BEGIN;

CREATE TYPE correction_status AS ENUM ('DRAFT', 'AWAITING_APPROVAL', 'APPROVED', 'REJECTED');

CREATE TABLE appraisal_admin_error_flags (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL, reason text NOT NULL CHECK (btrim(reason)<>''), flagged_by_account_id uuid NOT NULL,
  flagged_at timestamptz NOT NULL DEFAULT clock_timestamp(), withdrawn_at timestamptz,
  PRIMARY KEY(tenant_id,id), FOREIGN KEY(tenant_id,appraisal_id) REFERENCES appraisals(tenant_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(tenant_id,flagged_by_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT
);

ALTER TABLE appraisal_reopen_authorizations
  ADD COLUMN requested_by_account_id uuid,
  ADD COLUMN admin_error_flag_id uuid,
  ADD COLUMN requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ADD FOREIGN KEY (tenant_id, requested_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  ADD FOREIGN KEY (tenant_id, admin_error_flag_id) REFERENCES appraisal_admin_error_flags(tenant_id, id) ON DELETE RESTRICT;

CREATE TABLE appraisal_correction_versions (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL, authorization_id uuid NOT NULL, version_no integer NOT NULL CHECK (version_no > 0),
  status correction_status NOT NULL DEFAULT 'DRAFT', reason text NOT NULL CHECK (btrim(reason) <> ''),
  total_points numeric(10,2), maximum_points numeric(10,2), score_percentage numeric(5,2),
  created_by_account_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  submitted_at timestamptz, approved_by_account_id uuid, approved_at timestamptz,
  rejected_by_account_id uuid, rejected_at timestamptz, decision_reason text,
  PRIMARY KEY (tenant_id, id), UNIQUE (tenant_id, appraisal_id, version_no), UNIQUE (tenant_id, authorization_id),
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, authorization_id) REFERENCES appraisal_reopen_authorizations(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, created_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, approved_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, rejected_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (score_percentage IS NULL OR score_percentage BETWEEN 0 AND 100),
  CHECK ((status = 'APPROVED') = (approved_at IS NOT NULL)),
  CHECK ((status = 'REJECTED') = (rejected_at IS NOT NULL))
);

CREATE TABLE appraisal_correction_ratings (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  correction_version_id uuid NOT NULL, criterion_id uuid NOT NULL, original_rating_id uuid NOT NULL,
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5), justification text,
  correction_reason text NOT NULL CHECK (btrim(correction_reason) <> ''), created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (tenant_id, id), UNIQUE (tenant_id, correction_version_id, criterion_id),
  FOREIGN KEY (tenant_id, correction_version_id) REFERENCES appraisal_correction_versions(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, criterion_id) REFERENCES criteria(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, original_rating_id) REFERENCES appraisal_ratings(tenant_id, id) ON DELETE RESTRICT,
  CHECK (rating NOT IN (1,2,5) OR (justification IS NOT NULL AND btrim(justification) <> ''))
);

CREATE TABLE correction_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL, correction_version_id uuid NOT NULL, recipient_account_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('REOPEN_AUTHORIZED','CORRECTION_SUBMITTED','CORRECTION_APPROVED','CORRECTION_REJECTED')),
  message text NOT NULL CHECK (btrim(message) <> ''), created_at timestamptz NOT NULL DEFAULT clock_timestamp(), read_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE CASCADE,
  FOREIGN KEY (tenant_id, correction_version_id) REFERENCES appraisal_correction_versions(tenant_id, id) ON DELETE CASCADE,
  FOREIGN KEY (tenant_id, recipient_account_id) REFERENCES accounts(tenant_id, id) ON DELETE CASCADE
);

CREATE TABLE recommendation_eligibility_assessments (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  recommendation_id uuid NOT NULL, checked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  annual_score_percentage numeric(5,2) NOT NULL, has_rating_below_three boolean NOT NULL,
  has_unresolved_disciplinary_matter boolean NOT NULL, unit_service_started_on date NOT NULL,
  service_threshold_at timestamptz NOT NULL, eligible boolean NOT NULL,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,recommendation_id) REFERENCES recommendations(tenant_id,id) ON DELETE RESTRICT
);

CREATE INDEX idx_correction_versions_appraisal ON appraisal_correction_versions(tenant_id, appraisal_id, version_no DESC);
CREATE INDEX idx_correction_notifications_recipient ON correction_notifications(tenant_id, recipient_account_id, created_at DESC);
CREATE INDEX idx_eligibility_assessments_history ON recommendation_eligibility_assessments(tenant_id,recommendation_id,checked_at DESC);

DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['appraisal_admin_error_flags','appraisal_correction_versions','appraisal_correction_ratings','correction_notifications','recommendation_eligibility_assessments'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t); EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
  EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())', t);
END LOOP; END $$;

CREATE OR REPLACE FUNCTION validate_reopen_authorization()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status appraisal_status; v_commander boolean; v_requester_allowed boolean;
BEGIN
  SELECT status INTO v_status FROM appraisals WHERE tenant_id=NEW.tenant_id AND id=NEW.appraisal_id;
  IF v_status <> 'CLOSED' THEN RAISE EXCEPTION 'only closed appraisals may be reopened'; END IF;
  NEW.authorized_at := clock_timestamp(); NEW.expires_at := NEW.authorized_at + interval '5 days';
  IF NEW.authorized_by_account_id IS DISTINCT FROM current_actor_account_id() THEN RAISE EXCEPTION 'commander authorization must be issued by acting account'; END IF;
  SELECT EXISTS(SELECT 1 FROM account_roles WHERE tenant_id=NEW.tenant_id AND account_id=NEW.authorized_by_account_id
    AND role='COMPANY_COMMANDER' AND valid_from<=clock_timestamp() AND (valid_until IS NULL OR valid_until>clock_timestamp())) INTO v_commander;
  IF NOT v_commander THEN RAISE EXCEPTION 'company commander authorization required'; END IF;
  IF NEW.complaint_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM complaints WHERE tenant_id=NEW.tenant_id AND id=NEW.complaint_id AND appraisal_id=NEW.appraisal_id)
    THEN RAISE EXCEPTION 'complaint does not belong to appraisal'; END IF;
  IF NEW.admin_flag_reason IS NOT NULL THEN
    IF NEW.admin_error_flag_id IS NULL THEN RAISE EXCEPTION 'formal administrative error flag is required'; END IF;
    IF NOT EXISTS(SELECT 1 FROM appraisal_admin_error_flags f WHERE f.tenant_id=NEW.tenant_id AND f.id=NEW.admin_error_flag_id
      AND f.appraisal_id=NEW.appraisal_id AND f.flagged_by_account_id=NEW.requested_by_account_id AND f.withdrawn_at IS NULL AND f.reason=NEW.admin_flag_reason)
      THEN RAISE EXCEPTION 'administrative error flag is invalid or withdrawn'; END IF;
    SELECT EXISTS(SELECT 1 FROM account_roles WHERE tenant_id=NEW.tenant_id AND account_id=NEW.requested_by_account_id
      AND role IN ('UNIT_ADMINISTRATOR','FIRST_SERGEANT','EXECUTIVE_OFFICER') AND valid_from<=clock_timestamp()
      AND (valid_until IS NULL OR valid_until>clock_timestamp())) INTO v_requester_allowed;
    IF NOT v_requester_allowed THEN RAISE EXCEPTION 'administrative error must be formally flagged by an administrative officer'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER reopen_authorization_validate BEFORE INSERT ON appraisal_reopen_authorizations
FOR EACH ROW EXECUTE FUNCTION validate_reopen_authorization();

CREATE OR REPLACE FUNCTION validate_admin_error_flag() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v_allowed boolean; BEGIN
  IF NEW.flagged_by_account_id IS DISTINCT FROM current_actor_account_id() THEN RAISE EXCEPTION 'error flag actor mismatch'; END IF;
  SELECT EXISTS(SELECT 1 FROM account_roles WHERE tenant_id=NEW.tenant_id AND account_id=NEW.flagged_by_account_id
    AND role IN('UNIT_ADMINISTRATOR','FIRST_SERGEANT','EXECUTIVE_OFFICER') AND valid_from<=clock_timestamp()
    AND (valid_until IS NULL OR valid_until>clock_timestamp())) INTO v_allowed;
  IF NOT v_allowed THEN RAISE EXCEPTION 'administrative officer role required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM appraisals WHERE tenant_id=NEW.tenant_id AND id=NEW.appraisal_id AND status='CLOSED') THEN RAISE EXCEPTION 'only closed appraisals can be flagged'; END IF;
  RETURN NEW; END $$;
CREATE TRIGGER admin_error_flag_validate BEFORE INSERT ON appraisal_admin_error_flags FOR EACH ROW EXECUTE FUNCTION validate_admin_error_flag();
CREATE TRIGGER audit_admin_error_flags AFTER INSERT OR UPDATE OR DELETE ON appraisal_admin_error_flags FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

CREATE OR REPLACE FUNCTION guard_correction_version()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_now timestamptz:=clock_timestamp(); v_actor uuid:=current_actor_account_id(); v_commander boolean;
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'correction versions are immutable'; END IF;
  IF TG_OP='UPDATE' AND OLD.status IN ('APPROVED','REJECTED') THEN RAISE EXCEPTION 'decided correction versions are immutable'; END IF;
  IF TG_OP='UPDATE' AND (OLD.appraisal_id IS DISTINCT FROM NEW.appraisal_id OR OLD.authorization_id IS DISTINCT FROM NEW.authorization_id
    OR OLD.version_no IS DISTINCT FROM NEW.version_no OR OLD.reason IS DISTINCT FROM NEW.reason OR OLD.created_by_account_id IS DISTINCT FROM NEW.created_by_account_id)
    THEN RAISE EXCEPTION 'correction version identity and reason are immutable'; END IF;
  IF TG_OP='UPDATE' AND NEW.status='AWAITING_APPROVAL' AND OLD.status='DRAFT' THEN NEW.submitted_at:=v_now;
  ELSIF TG_OP='UPDATE' AND NEW.status='APPROVED' AND OLD.status='AWAITING_APPROVAL' THEN
    SELECT EXISTS(SELECT 1 FROM account_roles WHERE tenant_id=NEW.tenant_id AND account_id=v_actor AND role='COMPANY_COMMANDER'
      AND valid_from<=v_now AND (valid_until IS NULL OR valid_until>v_now)) INTO v_commander;
    IF NOT v_commander THEN RAISE EXCEPTION 'company commander approval required'; END IF;
    NEW.approved_at:=v_now; NEW.approved_by_account_id:=v_actor;
  ELSIF TG_OP='UPDATE' AND NEW.status='REJECTED' AND OLD.status='AWAITING_APPROVAL' THEN
    SELECT EXISTS(SELECT 1 FROM account_roles WHERE tenant_id=NEW.tenant_id AND account_id=v_actor AND role='COMPANY_COMMANDER'
      AND valid_from<=v_now AND (valid_until IS NULL OR valid_until>v_now)) INTO v_commander;
    IF NOT v_commander THEN RAISE EXCEPTION 'company commander review required'; END IF;
    NEW.rejected_at:=v_now; NEW.rejected_by_account_id:=v_actor;
  ELSIF TG_OP='UPDATE' AND NEW.status<>OLD.status THEN RAISE EXCEPTION 'invalid correction transition: % -> %',OLD.status,NEW.status; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER correction_version_guard BEFORE UPDATE OR DELETE ON appraisal_correction_versions FOR EACH ROW EXECUTE FUNCTION guard_correction_version();

CREATE OR REPLACE FUNCTION guard_correction_rating()
RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v_status correction_status; BEGIN
  SELECT status INTO v_status FROM appraisal_correction_versions WHERE tenant_id=COALESCE(NEW.tenant_id,OLD.tenant_id) AND id=COALESCE(NEW.correction_version_id,OLD.correction_version_id);
  IF v_status<>'DRAFT' THEN RAISE EXCEPTION 'submitted correction ratings are immutable'; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW; END $$;
CREATE TRIGGER correction_rating_guard BEFORE INSERT OR UPDATE OR DELETE ON appraisal_correction_ratings FOR EACH ROW EXECUTE FUNCTION guard_correction_rating();

CREATE OR REPLACE FUNCTION finalize_correction_score()
RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v_count integer; v_total numeric; BEGIN
  IF NEW.status='AWAITING_APPROVAL' AND OLD.status='DRAFT' THEN
    SELECT count(*),sum(rating) INTO v_count,v_total FROM appraisal_correction_ratings WHERE tenant_id=NEW.tenant_id AND correction_version_id=NEW.id;
    IF v_count=0 THEN RAISE EXCEPTION 'correction version has no rating snapshot'; END IF;
    NEW.total_points:=v_total; NEW.maximum_points:=v_count*5; NEW.score_percentage:=round(v_total/(v_count*5)*100,2);
  END IF; RETURN NEW; END $$;
CREATE TRIGGER correction_finalize_score BEFORE UPDATE OF status ON appraisal_correction_versions FOR EACH ROW EXECUTE FUNCTION finalize_correction_score();

DROP TRIGGER recommendations_validate_eligibility ON recommendations;
CREATE OR REPLACE FUNCTION guard_recommendation_workflow()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_engine boolean:=COALESCE(NULLIF(current_setting('app.eligibility_engine',true),''),'false')::boolean; v_actor uuid:=current_actor_account_id(); v_commander boolean;
BEGIN
  IF TG_OP='INSERT' AND NOT v_engine THEN RAISE EXCEPTION 'recommendations must originate from the eligibility engine'; END IF;
  IF TG_OP='UPDATE' AND NOT v_engine AND (OLD.eligible IS DISTINCT FROM NEW.eligible OR OLD.annual_score_percentage IS DISTINCT FROM NEW.annual_score_percentage
    OR OLD.has_rating_below_three IS DISTINCT FROM NEW.has_rating_below_three OR OLD.has_unresolved_disciplinary_matter IS DISTINCT FROM NEW.has_unresolved_disciplinary_matter
    OR OLD.unit_service_started_on IS DISTINCT FROM NEW.unit_service_started_on OR OLD.eligibility_checked_at IS DISTINCT FROM NEW.eligibility_checked_at)
    THEN RAISE EXCEPTION 'eligibility facts may only be changed by the eligibility engine'; END IF;
  IF NEW.status='NOMINATED' AND OLD.status='ELIGIBLE' THEN NEW.nominated_by_account_id:=v_actor; NEW.nominated_at:=clock_timestamp();
    IF NEW.nomination_reason IS NULL OR btrim(NEW.nomination_reason)='' THEN RAISE EXCEPTION 'nomination reason is required'; END IF;
  ELSIF NEW.status IN ('APPROVED','REJECTED') AND OLD.status='NOMINATED' THEN
    SELECT EXISTS(SELECT 1 FROM account_roles WHERE tenant_id=NEW.tenant_id AND account_id=v_actor AND role='COMPANY_COMMANDER'
      AND valid_from<=clock_timestamp() AND (valid_until IS NULL OR valid_until>clock_timestamp())) INTO v_commander;
    IF NOT v_commander THEN RAISE EXCEPTION 'company commander review is required'; END IF;
    IF NEW.decision_reason IS NULL OR btrim(NEW.decision_reason)='' THEN RAISE EXCEPTION 'commander decision reason is required'; END IF;
    NEW.decided_by_account_id:=v_actor; NEW.decided_at:=clock_timestamp();
  ELSIF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status AND NOT v_engine THEN RAISE EXCEPTION 'invalid recommendation transition: % -> %',OLD.status,NEW.status; END IF;
  IF NEW.status IN ('ELIGIBLE','NOMINATED','APPROVED') AND NOT NEW.eligible THEN RAISE EXCEPTION 'ineligible recommendation cannot advance'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recommendations_workflow_guard BEFORE INSERT OR UPDATE ON recommendations FOR EACH ROW EXECUTE FUNCTION guard_recommendation_workflow();

CREATE OR REPLACE FUNCTION recalculate_recommendations(p_tenant uuid,p_personnel uuid)
RETURNS void LANGUAGE plpgsql AS $$ DECLARE v_app record; v_score numeric; v_bad boolean; v_open boolean; v_eligible boolean; v_type recommendation_type; BEGIN
  SELECT a.id,a.score_percentage,p.unit_service_started_on INTO v_app FROM appraisals a
    JOIN evaluation_cycles cy ON cy.tenant_id=a.tenant_id AND cy.id=a.cycle_id AND cy.cycle_type='ANNUAL'
    JOIN personnel p ON p.tenant_id=a.tenant_id AND p.id=a.personnel_id
    WHERE a.tenant_id=p_tenant AND a.personnel_id=p_personnel AND a.status IN ('APPROVED','ACKNOWLEDGED','CLOSED')
    ORDER BY cy.ends_on DESC LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT COALESCE(cv.score_percentage,v_app.score_percentage) INTO v_score FROM (SELECT 1) x LEFT JOIN LATERAL(
    SELECT score_percentage FROM appraisal_correction_versions WHERE tenant_id=p_tenant AND appraisal_id=v_app.id AND status='APPROVED' ORDER BY version_no DESC LIMIT 1) cv ON true;
  IF EXISTS(SELECT 1 FROM appraisal_correction_versions WHERE tenant_id=p_tenant AND appraisal_id=v_app.id AND status='APPROVED') THEN
    SELECT EXISTS(SELECT 1 FROM appraisal_correction_ratings cr JOIN appraisal_correction_versions cv ON cv.tenant_id=cr.tenant_id AND cv.id=cr.correction_version_id
      WHERE cv.tenant_id=p_tenant AND cv.appraisal_id=v_app.id AND cv.status='APPROVED' AND cv.version_no=(SELECT max(version_no) FROM appraisal_correction_versions WHERE tenant_id=p_tenant AND appraisal_id=v_app.id AND status='APPROVED') AND cr.rating<3) INTO v_bad;
  ELSE SELECT EXISTS(SELECT 1 FROM appraisal_ratings WHERE tenant_id=p_tenant AND appraisal_id=v_app.id AND is_final AND rating<3) INTO v_bad; END IF;
  SELECT EXISTS(SELECT 1 FROM disciplinary_matters WHERE tenant_id=p_tenant AND personnel_id=p_personnel AND status IN ('ALLEGED','UNDER_REVIEW','CONFIRMED'))
    OR EXISTS(SELECT 1 FROM awol_incidents WHERE tenant_id=p_tenant AND personnel_id=p_personnel AND status IN ('REPORTED','UNDER_REVIEW','CONFIRMED')) INTO v_open;
  v_eligible:=v_score>85.00 AND NOT v_bad AND NOT v_open AND clock_timestamp() > (v_app.unit_service_started_on::timestamp + interval '9 months');
  PERFORM set_config('app.eligibility_engine','true',true);
  FOREACH v_type IN ARRAY ARRAY['PROMOTION'::recommendation_type,'COMMENDATION'::recommendation_type] LOOP
    INSERT INTO recommendations(tenant_id,personnel_id,annual_appraisal_id,recommendation_type,status,eligibility_checked_at,annual_score_percentage,has_rating_below_three,has_unresolved_disciplinary_matter,unit_service_started_on,eligible)
    VALUES(p_tenant,p_personnel,v_app.id,v_type,CASE WHEN v_eligible THEN 'ELIGIBLE' ELSE 'INELIGIBLE' END,clock_timestamp(),v_score,v_bad,v_open,v_app.unit_service_started_on,v_eligible)
    ON CONFLICT(tenant_id,personnel_id,annual_appraisal_id,recommendation_type) DO UPDATE SET eligibility_checked_at=EXCLUDED.eligibility_checked_at,
      annual_score_percentage=EXCLUDED.annual_score_percentage,has_rating_below_three=EXCLUDED.has_rating_below_three,
      has_unresolved_disciplinary_matter=EXCLUDED.has_unresolved_disciplinary_matter,unit_service_started_on=EXCLUDED.unit_service_started_on,eligible=EXCLUDED.eligible,
      status=CASE WHEN recommendations.status IN ('ELIGIBLE','INELIGIBLE') THEN EXCLUDED.status WHEN NOT EXCLUDED.eligible THEN 'INELIGIBLE' ELSE recommendations.status END;
    INSERT INTO recommendation_eligibility_assessments(tenant_id,recommendation_id,annual_score_percentage,has_rating_below_three,
      has_unresolved_disciplinary_matter,unit_service_started_on,service_threshold_at,eligible)
    SELECT p_tenant,id,v_score,v_bad,v_open,v_app.unit_service_started_on,v_app.unit_service_started_on::timestamp+interval '9 months',v_eligible
    FROM recommendations WHERE tenant_id=p_tenant AND personnel_id=p_personnel AND annual_appraisal_id=v_app.id AND recommendation_type=v_type;
  END LOOP; END $$;

CREATE OR REPLACE FUNCTION trigger_recalculate_recommendations() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  PERFORM recalculate_recommendations(COALESCE(NEW.tenant_id,OLD.tenant_id),COALESCE(NEW.personnel_id,OLD.personnel_id)); RETURN COALESCE(NEW,OLD); END $$;
CREATE TRIGGER discipline_recalculate AFTER INSERT OR UPDATE OF status ON disciplinary_matters FOR EACH ROW EXECUTE FUNCTION trigger_recalculate_recommendations();
CREATE TRIGGER awol_recalculate AFTER INSERT OR UPDATE OF status ON awol_incidents FOR EACH ROW EXECUTE FUNCTION trigger_recalculate_recommendations();

CREATE OR REPLACE FUNCTION correction_approved_recalculate() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v_personnel uuid; BEGIN
  IF NEW.status='APPROVED' AND OLD.status<>'APPROVED' THEN SELECT personnel_id INTO v_personnel FROM appraisals WHERE tenant_id=NEW.tenant_id AND id=NEW.appraisal_id;
    PERFORM recalculate_recommendations(NEW.tenant_id,v_personnel); END IF; RETURN NEW; END $$;
CREATE TRIGGER correction_approved_refresh AFTER UPDATE OF status ON appraisal_correction_versions FOR EACH ROW EXECUTE FUNCTION correction_approved_recalculate();

CREATE OR REPLACE FUNCTION appraisal_annual_recalculate() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  IF NEW.status IN ('APPROVED','ACKNOWLEDGED','CLOSED') AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM recalculate_recommendations(NEW.tenant_id,NEW.personnel_id); END IF; RETURN NEW; END $$;
CREATE TRIGGER appraisal_annual_refresh AFTER UPDATE OF status ON appraisals FOR EACH ROW EXECUTE FUNCTION appraisal_annual_recalculate();

CREATE OR REPLACE FUNCTION refresh_tenant_recommendations(p_tenant uuid) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_personnel uuid; v_count integer:=0; BEGIN
  IF p_tenant IS DISTINCT FROM current_tenant_id() THEN RAISE EXCEPTION 'tenant context mismatch'; END IF;
  FOR v_personnel IN SELECT DISTINCT a.personnel_id FROM appraisals a JOIN evaluation_cycles cy ON cy.tenant_id=a.tenant_id AND cy.id=a.cycle_id
    WHERE a.tenant_id=p_tenant AND cy.cycle_type='ANNUAL' AND a.status IN ('APPROVED','ACKNOWLEDGED','CLOSED')
  LOOP PERFORM recalculate_recommendations(p_tenant,v_personnel); v_count:=v_count+1; END LOOP; RETURN v_count; END $$;

CREATE TRIGGER audit_correction_versions AFTER INSERT OR UPDATE OR DELETE ON appraisal_correction_versions FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_correction_ratings AFTER INSERT OR UPDATE OR DELETE ON appraisal_correction_ratings FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_recommendations AFTER INSERT OR UPDATE OR DELETE ON recommendations FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

CREATE OR REPLACE FUNCTION immutable_eligibility_assessment() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  RAISE EXCEPTION 'eligibility assessment history is immutable'; END $$;
CREATE TRIGGER eligibility_assessment_immutable BEFORE UPDATE OR DELETE ON recommendation_eligibility_assessments
FOR EACH ROW EXECUTE FUNCTION immutable_eligibility_assessment();

REVOKE ALL ON FUNCTION refresh_tenant_recommendations(uuid) FROM PUBLIC;

COMMIT;
