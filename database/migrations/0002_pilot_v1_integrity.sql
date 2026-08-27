BEGIN;

CREATE OR REPLACE FUNCTION current_actor_account_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.account_id', true), '')::uuid
$$;

CREATE OR REPLACE FUNCTION write_audit_event(
  p_tenant_id uuid,
  p_action text,
  p_entity_table text,
  p_entity_id uuid,
  p_old_data jsonb,
  p_new_data jsonb,
  p_reason text DEFAULT NULL,
  p_appraisal_id uuid DEFAULT NULL,
  p_complaint_id uuid DEFAULT NULL,
  p_restricted_access boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_actor uuid := current_actor_account_id();
  v_personnel uuid;
BEGIN
  SELECT personnel_id INTO v_personnel
  FROM accounts WHERE tenant_id = p_tenant_id AND id = v_actor;

  INSERT INTO audit_logs (
    tenant_id, actor_account_id, actor_personnel_id, action, entity_table,
    entity_id, appraisal_id, complaint_id, restricted_access, reason,
    old_data, new_data, request_id
  ) VALUES (
    p_tenant_id, v_actor, v_personnel, p_action, p_entity_table,
    p_entity_id, p_appraisal_id, p_complaint_id, p_restricted_access, p_reason,
    p_old_data, p_new_data,
    NULLIF(current_setting('app.request_id', true), '')::uuid
  );
END;
$$;

CREATE OR REPLACE FUNCTION block_audit_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs is append-only';
END;
$$;

CREATE TRIGGER audit_logs_no_update_delete
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION block_audit_mutation();

CREATE OR REPLACE FUNCTION enforce_confirmed_activity_version_immutability()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.is_confirmed_version THEN
    RAISE EXCEPTION 'confirmed activity version % cannot be modified or deleted', OLD.id;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER activity_versions_immutable
BEFORE UPDATE OR DELETE ON activity_versions
FOR EACH ROW EXECUTE FUNCTION enforce_confirmed_activity_version_immutability();

CREATE OR REPLACE FUNCTION enforce_template_immutability()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_template_version_id uuid;
  v_tenant_id uuid;
  v_locked boolean;
BEGIN
  IF TG_TABLE_NAME = 'template_versions' THEN
    v_template_version_id := OLD.id;
    v_tenant_id := OLD.tenant_id;
  ELSE
    v_template_version_id := OLD.template_version_id;
    v_tenant_id := OLD.tenant_id;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM evaluation_cycles
    WHERE tenant_id = v_tenant_id
      AND template_version_id = v_template_version_id
      AND status <> 'DRAFT'
  ) INTO v_locked;

  IF v_locked THEN
    RAISE EXCEPTION 'template version % is immutable because an evaluation cycle has begun', v_template_version_id;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER template_versions_locked
BEFORE UPDATE OR DELETE ON template_versions
FOR EACH ROW EXECUTE FUNCTION enforce_template_immutability();
CREATE TRIGGER template_sections_locked
BEFORE UPDATE OR DELETE ON template_sections
FOR EACH ROW EXECUTE FUNCTION enforce_template_immutability();
CREATE TRIGGER criteria_locked
BEFORE UPDATE OR DELETE ON criteria
FOR EACH ROW EXECUTE FUNCTION enforce_template_immutability();

CREATE OR REPLACE FUNCTION enforce_extreme_rating_evidence()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_tenant_id uuid;
  v_rating_id uuid;
  v_rating smallint;
  v_justification text;
  v_evidence_count integer;
BEGIN
  IF TG_TABLE_NAME = 'appraisal_ratings' THEN
    v_tenant_id := COALESCE(NEW.tenant_id, OLD.tenant_id);
    v_rating_id := COALESCE(NEW.id, OLD.id);
  ELSE
    v_tenant_id := COALESCE(NEW.tenant_id, OLD.tenant_id);
    v_rating_id := COALESCE(NEW.rating_id, OLD.rating_id);
    IF v_rating_id IS NULL THEN RETURN NULL; END IF;
  END IF;

  SELECT rating, justification INTO v_rating, v_justification
  FROM appraisal_ratings
  WHERE tenant_id = v_tenant_id AND id = v_rating_id;

  IF NOT FOUND THEN RETURN NULL; END IF;

  IF v_rating IN (1,2,5) THEN
    SELECT count(*) INTO v_evidence_count
    FROM evidence_attachments
    WHERE tenant_id = v_tenant_id AND rating_id = v_rating_id;

    IF v_justification IS NULL OR btrim(v_justification) = '' OR v_evidence_count < 1 THEN
      RAISE EXCEPTION 'rating % requires a justification and one evidence attachment', v_rating;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER rating_requires_evidence
AFTER INSERT OR UPDATE ON appraisal_ratings
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_extreme_rating_evidence();

CREATE CONSTRAINT TRIGGER evidence_delete_rechecks_rating
AFTER UPDATE OR DELETE ON evidence_attachments
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_extreme_rating_evidence();

CREATE OR REPLACE FUNCTION enforce_clean_evidence_before_appraisal_progress()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('AWAITING_COMMANDER_APPROVAL', 'APPROVED', 'ACKNOWLEDGED', 'CLOSED')
     AND OLD.status IS DISTINCT FROM NEW.status
     AND EXISTS (
       SELECT 1
       FROM appraisal_ratings r
       JOIN evidence_attachments e
         ON e.tenant_id = r.tenant_id AND e.rating_id = r.id
       WHERE r.tenant_id = NEW.tenant_id
         AND r.appraisal_id = NEW.id
         AND e.malware_status <> 'CLEAN'
     ) THEN
    RAISE EXCEPTION 'appraisal % has evidence that has not passed malware scanning', NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER appraisals_require_clean_evidence
BEFORE UPDATE OF status ON appraisals
FOR EACH ROW EXECUTE FUNCTION enforce_clean_evidence_before_appraisal_progress();

CREATE OR REPLACE FUNCTION enforce_commander_not_self_approve()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_approver_personnel_id uuid;
  v_is_commander boolean;
BEGIN
  IF NEW.approved_by_account_id IS NULL THEN RETURN NEW; END IF;

  SELECT a.personnel_id,
         EXISTS (
           SELECT 1 FROM account_roles ar
           WHERE ar.tenant_id = a.tenant_id
             AND ar.account_id = a.id
             AND ar.role = 'COMPANY_COMMANDER'
             AND ar.valid_from <= now()
             AND (ar.valid_until IS NULL OR ar.valid_until > now())
         )
  INTO v_approver_personnel_id, v_is_commander
  FROM accounts a
  WHERE a.tenant_id = NEW.tenant_id AND a.id = NEW.approved_by_account_id;

  IF NOT v_is_commander THEN
    RAISE EXCEPTION 'final appraisal approval requires an active company commander role';
  END IF;
  IF v_approver_personnel_id = NEW.personnel_id THEN
    RAISE EXCEPTION 'commander accounts cannot approve their own appraisal';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER commander_cannot_self_approve
BEFORE INSERT OR UPDATE OF approved_by_account_id ON appraisals
FOR EACH ROW EXECUTE FUNCTION enforce_commander_not_self_approve();

CREATE OR REPLACE FUNCTION validate_rating_scope()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_expected_template uuid;
  v_criterion_template uuid;
  v_step_appraisal uuid;
BEGIN
  SELECT c.template_version_id INTO v_expected_template
  FROM appraisals a
  JOIN evaluation_cycles c ON c.tenant_id = a.tenant_id AND c.id = a.cycle_id
  WHERE a.tenant_id = NEW.tenant_id AND a.id = NEW.appraisal_id;

  SELECT template_version_id INTO v_criterion_template
  FROM criteria WHERE tenant_id = NEW.tenant_id AND id = NEW.criterion_id;

  SELECT snap.appraisal_id INTO v_step_appraisal
  FROM evaluator_chain_steps step
  JOIN evaluator_chain_snapshots snap
    ON snap.tenant_id = step.tenant_id AND snap.id = step.snapshot_id
  WHERE step.tenant_id = NEW.tenant_id AND step.id = NEW.evaluator_step_id;

  IF v_expected_template IS DISTINCT FROM v_criterion_template THEN
    RAISE EXCEPTION 'rating criterion is not part of the appraisal template version';
  END IF;
  IF v_step_appraisal IS DISTINCT FROM NEW.appraisal_id THEN
    RAISE EXCEPTION 'rating evaluator step is not part of the appraisal chain snapshot';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER ratings_validate_scope
BEFORE INSERT OR UPDATE OF appraisal_id, criterion_id, evaluator_step_id
ON appraisal_ratings
FOR EACH ROW EXECUTE FUNCTION validate_rating_scope();

CREATE OR REPLACE FUNCTION preserve_rating_content()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.appraisal_id IS DISTINCT FROM NEW.appraisal_id
     OR OLD.criterion_id IS DISTINCT FROM NEW.criterion_id
     OR OLD.evaluator_step_id IS DISTINCT FROM NEW.evaluator_step_id
     OR OLD.rating IS DISTINCT FROM NEW.rating
     OR OLD.justification IS DISTINCT FROM NEW.justification
     OR OLD.created_by_account_id IS DISTINCT FROM NEW.created_by_account_id
     OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'rating content is immutable; create a replacement rating and score adjustment';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER ratings_preserve_original_content
BEFORE UPDATE ON appraisal_ratings
FOR EACH ROW EXECUTE FUNCTION preserve_rating_content();

CREATE OR REPLACE FUNCTION validate_score_adjustment()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_original appraisal_ratings%ROWTYPE;
  v_replacement appraisal_ratings%ROWTYPE;
  v_is_commander boolean;
BEGIN
  SELECT * INTO v_original FROM appraisal_ratings
  WHERE tenant_id = NEW.tenant_id AND id = NEW.original_rating_id;
  SELECT * INTO v_replacement FROM appraisal_ratings
  WHERE tenant_id = NEW.tenant_id AND id = NEW.replacement_rating_id;

  IF v_original.appraisal_id IS DISTINCT FROM NEW.appraisal_id
     OR v_replacement.appraisal_id IS DISTINCT FROM NEW.appraisal_id
     OR v_original.criterion_id IS DISTINCT FROM NEW.criterion_id
     OR v_replacement.criterion_id IS DISTINCT FROM NEW.criterion_id
     OR v_replacement.supersedes_rating_id IS DISTINCT FROM v_original.id THEN
    RAISE EXCEPTION 'score adjustment ratings must belong to the same appraisal and criterion and form a supersession chain';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM account_roles
    WHERE tenant_id = NEW.tenant_id
      AND account_id = NEW.adjusted_by_account_id
      AND role = 'COMPANY_COMMANDER'
      AND valid_from <= now()
      AND (valid_until IS NULL OR valid_until > now())
  ) INTO v_is_commander;
  IF NOT v_is_commander THEN
    RAISE EXCEPTION 'only an active company commander may create a score adjustment';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER score_adjustments_validate
BEFORE INSERT OR UPDATE ON score_adjustments
FOR EACH ROW EXECUTE FUNCTION validate_score_adjustment();

CREATE OR REPLACE FUNCTION finalize_appraisal_scores()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_expected integer;
  v_actual integer;
  v_total numeric(10,2);
BEGIN
  IF NEW.status NOT IN ('AWAITING_COMMANDER_APPROVAL','APPROVED','ACKNOWLEDGED','CLOSED')
     OR OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_expected
  FROM evaluation_cycles cy
  JOIN personnel p ON p.tenant_id = NEW.tenant_id AND p.id = NEW.personnel_id
  JOIN criteria cr ON cr.tenant_id = cy.tenant_id AND cr.template_version_id = cy.template_version_id
  WHERE cy.tenant_id = NEW.tenant_id
    AND cy.id = NEW.cycle_id
    AND cr.requires_rating
    AND p.personnel_category = ANY(cr.applicable_categories);

  SELECT count(*), COALESCE(sum(rating), 0) INTO v_actual, v_total
  FROM appraisal_ratings
  WHERE tenant_id = NEW.tenant_id AND appraisal_id = NEW.id AND is_final;

  IF v_actual <> v_expected OR v_expected = 0 THEN
    RAISE EXCEPTION 'appraisal requires exactly one final rating for each of % applicable criteria; found %', v_expected, v_actual;
  END IF;

  NEW.total_points := v_total;
  NEW.maximum_points := v_expected * 5;
  NEW.score_percentage := round((v_total / (v_expected * 5)) * 100, 2);
  RETURN NEW;
END;
$$;

CREATE TRIGGER appraisals_finalize_scores
BEFORE UPDATE OF status ON appraisals
FOR EACH ROW EXECUTE FUNCTION finalize_appraisal_scores();

CREATE OR REPLACE FUNCTION validate_recommendation_eligibility()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_score numeric(5,2);
  v_started date;
  v_cycle_type cycle_type;
  v_bad_rating boolean;
  v_open_discipline boolean;
BEGIN
  SELECT a.score_percentage, p.unit_service_started_on, c.cycle_type
  INTO v_score, v_started, v_cycle_type
  FROM appraisals a
  JOIN personnel p ON p.tenant_id = a.tenant_id AND p.id = a.personnel_id
  JOIN evaluation_cycles c ON c.tenant_id = a.tenant_id AND c.id = a.cycle_id
  WHERE a.tenant_id = NEW.tenant_id
    AND a.id = NEW.annual_appraisal_id
    AND a.personnel_id = NEW.personnel_id
    AND a.status IN ('APPROVED', 'ACKNOWLEDGED', 'CLOSED');

  IF NOT FOUND OR v_cycle_type <> 'ANNUAL' THEN
    RAISE EXCEPTION 'recommendation requires an approved annual appraisal for the same personnel';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM appraisal_ratings
    WHERE tenant_id = NEW.tenant_id
      AND appraisal_id = NEW.annual_appraisal_id
      AND is_final AND rating < 3
  ) INTO v_bad_rating;

  SELECT EXISTS (
    SELECT 1 FROM disciplinary_matters
    WHERE tenant_id = NEW.tenant_id
      AND personnel_id = NEW.personnel_id
      AND status IN ('ALLEGED', 'UNDER_REVIEW', 'CONFIRMED')
  ) OR EXISTS (
    SELECT 1 FROM awol_incidents
    WHERE tenant_id = NEW.tenant_id
      AND personnel_id = NEW.personnel_id
      AND status IN ('REPORTED', 'UNDER_REVIEW', 'CONFIRMED')
  ) INTO v_open_discipline;

  NEW.annual_score_percentage := v_score;
  NEW.has_rating_below_three := v_bad_rating;
  NEW.has_unresolved_disciplinary_matter := v_open_discipline;
  NEW.unit_service_started_on := v_started;
  NEW.eligible := v_score > 85
                  AND NOT v_bad_rating
                  AND NOT v_open_discipline
                  AND NEW.eligibility_checked_at::date > (v_started + interval '9 months')::date;

  IF NEW.status = 'ELIGIBLE' AND NOT NEW.eligible THEN
    NEW.status := 'INELIGIBLE';
  END IF;

  IF NEW.status IN ('ELIGIBLE', 'NOMINATED', 'APPROVED') AND NOT NEW.eligible THEN
    RAISE EXCEPTION 'personnel does not satisfy all recommendation eligibility requirements';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER recommendations_validate_eligibility
BEFORE INSERT OR UPDATE OF personnel_id, annual_appraisal_id, eligibility_checked_at, status
ON recommendations
FOR EACH ROW EXECUTE FUNCTION validate_recommendation_eligibility();

CREATE OR REPLACE FUNCTION derive_complaint_deadlines()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_available_at timestamptz;
BEGIN
  SELECT available_to_member_at INTO v_available_at
  FROM appraisals
  WHERE tenant_id = NEW.tenant_id
    AND id = NEW.appraisal_id
    AND personnel_id = NEW.complainant_personnel_id;

  IF v_available_at IS NULL THEN
    RAISE EXCEPTION 'complaint requires an appraisal made available to the same personnel';
  END IF;

  NEW.submission_deadline_at := v_available_at + interval '3 days';
  NEW.acceptance_deadline_at := NEW.submitted_at + interval '3 days';
  IF NEW.submitted_at > NEW.submission_deadline_at THEN
    RAISE EXCEPTION 'complaint submission deadline has passed';
  END IF;
  IF NEW.accepted_at IS NOT NULL THEN
    NEW.decision_deadline_at := NEW.accepted_at + interval '5 days';
  ELSE
    NEW.decision_deadline_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER complaints_derive_deadlines
BEFORE INSERT OR UPDATE OF submitted_at, accepted_at, appraisal_id, complainant_personnel_id
ON complaints
FOR EACH ROW EXECUTE FUNCTION derive_complaint_deadlines();

CREATE OR REPLACE FUNCTION guard_tenant_deletion()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_roles integer;
  v_approvers integer;
BEGIN
  SELECT count(DISTINCT authorization_role), count(DISTINCT requested_by_account_id)
  INTO v_roles, v_approvers
  FROM tenant_deletion_authorizations
  WHERE tenant_id = OLD.id
    AND revoked_at IS NULL
    AND consumed_at IS NULL
    AND authorized_at >= now() - interval '30 days';

  IF v_roles < 2 OR v_approvers < 2 THEN
    RAISE EXCEPTION 'permanent tenant deletion requires two current authorizations from distinct people and required authority roles';
  END IF;

  UPDATE tenant_deletion_authorizations
  SET consumed_at = now()
  WHERE tenant_id = OLD.id AND revoked_at IS NULL AND consumed_at IS NULL;

  PERFORM write_audit_event(OLD.id, 'TENANT_PERMANENT_DELETE', 'tenants', OLD.id,
    to_jsonb(OLD), NULL, 'dual authorization satisfied');
  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION validate_tenant_deletion_authorization()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_required_role system_role;
  v_has_role boolean;
BEGIN
  IF NEW.requested_by_account_id IS DISTINCT FROM current_actor_account_id() THEN
    RAISE EXCEPTION 'deletion authorization must be recorded by the acting account';
  END IF;

  v_required_role := CASE NEW.authorization_role
    WHEN 'UNIT_COMMANDER' THEN 'COMPANY_COMMANDER'::system_role
    WHEN 'SECOND_TIER_SUPERVISOR' THEN 'EXECUTIVE_OFFICER'::system_role
  END;

  SELECT EXISTS (
    SELECT 1 FROM account_roles
    WHERE tenant_id = NEW.tenant_id
      AND account_id = NEW.requested_by_account_id
      AND role = v_required_role
      AND valid_from <= now()
      AND (valid_until IS NULL OR valid_until > now())
  ) INTO v_has_role;

  IF NOT v_has_role THEN
    RAISE EXCEPTION 'account lacks the active role required for this deletion authorization';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tenant_deletion_authorization_validate
BEFORE INSERT OR UPDATE ON tenant_deletion_authorizations
FOR EACH ROW EXECUTE FUNCTION validate_tenant_deletion_authorization();

CREATE TRIGGER tenants_dual_authorization_delete
BEFORE DELETE ON tenants
FOR EACH ROW EXECUTE FUNCTION guard_tenant_deletion();

CREATE OR REPLACE FUNCTION audit_sensitive_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_tenant uuid := COALESCE(NEW.tenant_id, OLD.tenant_id);
  v_id uuid := COALESCE(NEW.id, OLD.id);
  v_action text := TG_TABLE_NAME || '_' || TG_OP;
  v_appraisal uuid;
  v_complaint uuid;
BEGIN
  IF TG_TABLE_NAME = 'appraisal_ratings' THEN v_appraisal := COALESCE(NEW.appraisal_id, OLD.appraisal_id); END IF;
  IF TG_TABLE_NAME = 'appraisal_comments' THEN v_appraisal := COALESCE(NEW.appraisal_id, OLD.appraisal_id); END IF;
  IF TG_TABLE_NAME = 'complaints' THEN
    v_appraisal := COALESCE(NEW.appraisal_id, OLD.appraisal_id);
    v_complaint := v_id;
  END IF;
  PERFORM write_audit_event(v_tenant, v_action, TG_TABLE_NAME, v_id,
    CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) END,
    NULL, v_appraisal, v_complaint,
    TG_TABLE_NAME = 'appraisal_comments' AND COALESCE(NEW.visibility, OLD.visibility) = 'RESTRICTED_SUPERVISORY');
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER audit_template_versions AFTER INSERT OR UPDATE OR DELETE ON template_versions FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_template_sections AFTER INSERT OR UPDATE OR DELETE ON template_sections FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_criteria AFTER INSERT OR UPDATE OR DELETE ON criteria FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_ratings AFTER INSERT OR UPDATE OR DELETE ON appraisal_ratings FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_score_adjustments AFTER INSERT OR UPDATE OR DELETE ON score_adjustments FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_comments AFTER INSERT OR UPDATE OR DELETE ON appraisal_comments FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_complaints AFTER INSERT OR UPDATE OR DELETE ON complaints FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_reopens AFTER INSERT OR UPDATE OR DELETE ON appraisal_reopen_authorizations FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

CREATE OR REPLACE FUNCTION log_restricted_comment_access(
  p_tenant_id uuid,
  p_comment_id uuid,
  p_complaint_id uuid,
  p_reason text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_appraisal uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM complaint_case_officers cco
    WHERE cco.tenant_id = p_tenant_id
      AND cco.complaint_id = p_complaint_id
      AND cco.account_id = current_actor_account_id()
      AND cco.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'account is not assigned to this grievance case';
  END IF;

  SELECT appraisal_id INTO v_appraisal FROM appraisal_comments
  WHERE tenant_id = p_tenant_id AND id = p_comment_id
    AND visibility = 'RESTRICTED_SUPERVISORY';
  IF NOT FOUND THEN RAISE EXCEPTION 'restricted comment not found'; END IF;

  PERFORM write_audit_event(p_tenant_id, 'RESTRICTED_COMMENT_READ', 'appraisal_comments',
    p_comment_id, NULL, NULL, p_reason, v_appraisal, p_complaint_id, true);
END;
$$;

CREATE OR REPLACE FUNCTION read_restricted_comment(
  p_tenant_id uuid,
  p_comment_id uuid,
  p_complaint_id uuid DEFAULT NULL,
  p_reason text DEFAULT 'authorized supervisory access'
) RETURNS TABLE (
  comment_id uuid,
  appraisal_id uuid,
  author_account_id uuid,
  body text,
  created_at timestamptz
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_actor uuid := current_actor_account_id();
  v_appraisal uuid;
  v_author_step smallint;
  v_reader_step smallint;
  v_case_access boolean := false;
BEGIN
  SELECT c.appraisal_id, author_step.sequence_no
  INTO v_appraisal, v_author_step
  FROM appraisal_comments c
  LEFT JOIN evaluator_chain_steps author_step
    ON author_step.tenant_id = c.tenant_id AND author_step.id = c.evaluator_step_id
  WHERE c.tenant_id = p_tenant_id
    AND c.id = p_comment_id
    AND c.visibility = 'RESTRICTED_SUPERVISORY';
  IF NOT FOUND THEN RAISE EXCEPTION 'restricted comment not found'; END IF;

  IF p_complaint_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM complaint_case_officers cco
      JOIN complaints cp
        ON cp.tenant_id = cco.tenant_id AND cp.id = cco.complaint_id
      WHERE cco.tenant_id = p_tenant_id
        AND cco.complaint_id = p_complaint_id
        AND cco.account_id = v_actor
        AND cco.removed_at IS NULL
        AND cp.appraisal_id = v_appraisal
        AND cp.status IN ('ACCEPTED', 'UNDER_REVIEW', 'DECIDED')
    ) INTO v_case_access;
  END IF;

  SELECT reader_step.sequence_no INTO v_reader_step
  FROM evaluator_chain_steps reader_step
  JOIN evaluator_chain_snapshots snap
    ON snap.tenant_id = reader_step.tenant_id AND snap.id = reader_step.snapshot_id
  WHERE reader_step.tenant_id = p_tenant_id
    AND reader_step.evaluator_account_id = v_actor
    AND snap.appraisal_id = v_appraisal
    AND snap.is_active
  ORDER BY reader_step.sequence_no DESC
  LIMIT 1;

  IF NOT v_case_access AND (v_author_step IS NULL OR v_reader_step IS NULL OR v_reader_step <= v_author_step) THEN
    RAISE EXCEPTION 'restricted comment access denied';
  END IF;

  PERFORM write_audit_event(p_tenant_id, 'RESTRICTED_COMMENT_READ', 'appraisal_comments',
    p_comment_id, NULL, NULL, p_reason, v_appraisal, p_complaint_id, true);

  RETURN QUERY
  SELECT c.id, c.appraisal_id, c.author_account_id, c.body, c.created_at
  FROM appraisal_comments c
  WHERE c.tenant_id = p_tenant_id AND c.id = p_comment_id;
END;
$$;

COMMIT;
