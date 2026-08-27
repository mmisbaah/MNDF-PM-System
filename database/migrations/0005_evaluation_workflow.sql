BEGIN;

ALTER TABLE criteria
  ADD COLUMN applicable_appointment_types text[];

ALTER TABLE criteria
  ADD CONSTRAINT criteria_appointment_types_not_empty
  CHECK (applicable_appointment_types IS NULL OR cardinality(applicable_appointment_types) > 0);

ALTER TABLE appraisals
  ADD COLUMN personnel_category_snapshot text,
  ADD COLUMN appointment_type_snapshot text;

ALTER TABLE appraisals
  ADD CONSTRAINT appraisals_category_snapshot_valid
  CHECK (personnel_category_snapshot IS NULL OR personnel_category_snapshot IN ('OFFICER','NCO','PRIVATE','CIVILIAN'));

CREATE UNIQUE INDEX uq_one_baseline_template_per_tenant
  ON evaluation_templates (tenant_id)
  WHERE is_baseline;

CREATE TABLE template_reporting_details (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  template_version_id uuid NOT NULL,
  report_title text NOT NULL DEFAULT 'Performance Appraisal Report',
  commander_signature_label text NOT NULL DEFAULT 'Commanding Officer',
  include_score_percentage boolean NOT NULL DEFAULT true,
  include_eligibility_summary boolean NOT NULL DEFAULT true,
  footer_text text,
  updated_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, template_version_id),
  FOREIGN KEY (tenant_id, template_version_id) REFERENCES template_versions(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, updated_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_criteria_applicability
  ON criteria USING gin (applicable_categories, applicable_appointment_types);

ALTER TABLE template_reporting_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE template_reporting_details FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON template_reporting_details
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

CREATE OR REPLACE FUNCTION enforce_template_immutability()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_template_version_id uuid;
  v_tenant_id uuid;
  v_locked boolean;
BEGIN
  IF TG_TABLE_NAME = 'template_versions' THEN
    v_template_version_id := COALESCE(NEW.id, OLD.id);
    v_tenant_id := COALESCE(NEW.tenant_id, OLD.tenant_id);
  ELSE
    v_template_version_id := COALESCE(NEW.template_version_id, OLD.template_version_id);
    v_tenant_id := COALESCE(NEW.tenant_id, OLD.tenant_id);
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

DROP TRIGGER template_sections_locked ON template_sections;
CREATE TRIGGER template_sections_locked
BEFORE INSERT OR UPDATE OR DELETE ON template_sections
FOR EACH ROW EXECUTE FUNCTION enforce_template_immutability();

DROP TRIGGER criteria_locked ON criteria;
CREATE TRIGGER criteria_locked
BEFORE INSERT OR UPDATE OR DELETE ON criteria
FOR EACH ROW EXECUTE FUNCTION enforce_template_immutability();

CREATE TRIGGER template_reporting_details_locked
BEFORE INSERT OR UPDATE OR DELETE ON template_reporting_details
FOR EACH ROW EXECUTE FUNCTION enforce_template_immutability();

CREATE TRIGGER audit_template_reporting_details
AFTER INSERT OR UPDATE OR DELETE ON template_reporting_details
FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

CREATE OR REPLACE FUNCTION protect_baseline_template_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.is_baseline AND (TG_OP = 'DELETE' OR NOT NEW.is_baseline) THEN
    RAISE EXCEPTION 'the centrally defined baseline template cannot be deleted or converted';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER baseline_template_identity_immutable
BEFORE UPDATE OR DELETE ON evaluation_templates
FOR EACH ROW EXECUTE FUNCTION protect_baseline_template_identity();

CREATE OR REPLACE FUNCTION evaluator_snapshot_is_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'evaluator-chain snapshots are immutable after appraisal initialization';
END;
$$;

CREATE TRIGGER evaluator_chain_snapshots_immutable
BEFORE UPDATE OR DELETE ON evaluator_chain_snapshots
FOR EACH ROW EXECUTE FUNCTION evaluator_snapshot_is_immutable();

CREATE OR REPLACE FUNCTION evaluator_step_structure_is_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE'
     OR OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
     OR OLD.snapshot_id IS DISTINCT FROM NEW.snapshot_id
     OR OLD.evaluator_personnel_id IS DISTINCT FROM NEW.evaluator_personnel_id
     OR OLD.evaluator_account_id IS DISTINCT FROM NEW.evaluator_account_id
     OR OLD.sequence_no IS DISTINCT FROM NEW.sequence_no
     OR OLD.step_kind IS DISTINCT FROM NEW.step_kind
     OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'evaluator-chain step structure is immutable after appraisal initialization';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER evaluator_chain_steps_structure_immutable
BEFORE UPDATE OR DELETE ON evaluator_chain_steps
FOR EACH ROW EXECUTE FUNCTION evaluator_step_structure_is_immutable();

CREATE OR REPLACE FUNCTION guard_appraisal_content_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_tenant_id uuid := COALESCE(NEW.tenant_id, OLD.tenant_id);
  v_appraisal_id uuid := COALESCE(NEW.appraisal_id, OLD.appraisal_id);
  v_status appraisal_status;
  v_reopen_allowed boolean;
BEGIN
  SELECT status INTO v_status
  FROM appraisals
  WHERE tenant_id = v_tenant_id AND id = v_appraisal_id;

  IF v_status IN ('APPROVED','ACKNOWLEDGED','CLOSED') THEN
    RAISE EXCEPTION 'active or completed appraisal content cannot be modified';
  END IF;

  IF v_status = 'REOPENED' THEN
    SELECT EXISTS (
      SELECT 1 FROM appraisal_reopen_authorizations
      WHERE tenant_id = v_tenant_id AND appraisal_id = v_appraisal_id
        AND expires_at > now()
    ) INTO v_reopen_allowed;
    IF NOT v_reopen_allowed THEN
      RAISE EXCEPTION 'reopened appraisal requires an unexpired commander authorization';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER ratings_block_completed_mutation
BEFORE INSERT OR UPDATE OR DELETE ON appraisal_ratings
FOR EACH ROW EXECUTE FUNCTION guard_appraisal_content_mutation();

CREATE TRIGGER comments_block_completed_mutation
BEFORE INSERT OR UPDATE OR DELETE ON appraisal_comments
FOR EACH ROW EXECUTE FUNCTION guard_appraisal_content_mutation();

CREATE OR REPLACE FUNCTION guard_evidence_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_tenant_id uuid := COALESCE(NEW.tenant_id, OLD.tenant_id);
  v_rating_id uuid := COALESCE(NEW.rating_id, OLD.rating_id);
  v_status appraisal_status;
BEGIN
  IF TG_OP = 'UPDATE' AND (
    OLD.rating_id IS DISTINCT FROM NEW.rating_id
    OR OLD.activity_version_id IS DISTINCT FROM NEW.activity_version_id
    OR OLD.storage_key IS DISTINCT FROM NEW.storage_key
    OR OLD.sha256_hex IS DISTINCT FROM NEW.sha256_hex
    OR OLD.byte_size IS DISTINCT FROM NEW.byte_size
    OR OLD.mime_type IS DISTINCT FROM NEW.mime_type
  ) THEN
    RAISE EXCEPTION 'evidence identity and content metadata are immutable; upload a replacement under an authorized workflow';
  END IF;
  IF v_rating_id IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  SELECT a.status INTO v_status
  FROM appraisal_ratings r
  JOIN appraisals a ON a.tenant_id = r.tenant_id AND a.id = r.appraisal_id
  WHERE r.tenant_id = v_tenant_id AND r.id = v_rating_id;
  IF v_status IN ('APPROVED','ACKNOWLEDGED','CLOSED') THEN
    RAISE EXCEPTION 'evidence for an approved or completed appraisal cannot be modified';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER evidence_block_completed_mutation
BEFORE INSERT OR UPDATE OR DELETE ON evidence_attachments
FOR EACH ROW EXECUTE FUNCTION guard_evidence_mutation();

CREATE OR REPLACE FUNCTION validate_rating_applicability()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_applies boolean;
BEGIN
  SELECT a.personnel_category_snapshot = ANY(cr.applicable_categories)
         AND (cr.applicable_appointment_types IS NULL
              OR a.appointment_type_snapshot = ANY(cr.applicable_appointment_types))
  INTO v_applies
  FROM appraisals a
  JOIN criteria cr ON cr.tenant_id = a.tenant_id AND cr.id = NEW.criterion_id
  WHERE a.tenant_id = NEW.tenant_id AND a.id = NEW.appraisal_id;
  IF NOT COALESCE(v_applies, false) THEN
    RAISE EXCEPTION 'criterion is not applicable to the appraisal personnel category or appointment snapshot';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER ratings_validate_applicability
BEFORE INSERT OR UPDATE OF appraisal_id, criterion_id ON appraisal_ratings
FOR EACH ROW EXECUTE FUNCTION validate_rating_applicability();

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

  IF NEW.personnel_category_snapshot IS NULL OR NEW.appointment_type_snapshot IS NULL THEN
    RAISE EXCEPTION 'appraisal applicability snapshots are required before score finalization';
  END IF;

  SELECT count(*) INTO v_expected
  FROM evaluation_cycles cy
  JOIN criteria cr ON cr.tenant_id = cy.tenant_id AND cr.template_version_id = cy.template_version_id
  WHERE cy.tenant_id = NEW.tenant_id
    AND cy.id = NEW.cycle_id
    AND cr.requires_rating
    AND NEW.personnel_category_snapshot = ANY(cr.applicable_categories)
    AND (cr.applicable_appointment_types IS NULL OR NEW.appointment_type_snapshot = ANY(cr.applicable_appointment_types));

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

COMMIT;
