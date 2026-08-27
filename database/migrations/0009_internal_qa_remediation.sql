BEGIN;

DROP TABLE IF EXISTS mdu_system_feedback,mdu_unit_actions,mdu_evaluations,mdu_personnel CASCADE;

ALTER TABLE appraisal_reopen_authorizations
  ADD COLUMN correction_officer_account_id uuid,
  ADD FOREIGN KEY (tenant_id, correction_officer_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT;

CREATE TABLE correction_evidence_attachments (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  correction_rating_id uuid NOT NULL, storage_key text NOT NULL CHECK(btrim(storage_key)<>''),
  original_filename text NOT NULL CHECK(btrim(original_filename)<>''),
  mime_type text NOT NULL CHECK(mime_type IN('application/pdf','image/jpeg','image/png','image/webp')),
  byte_size integer NOT NULL CHECK(byte_size>0 AND byte_size<=5242880), page_count smallint NOT NULL CHECK(page_count=1),
  sha256_hex text NOT NULL CHECK(sha256_hex~'^[0-9a-fA-F]{64}$'), malware_status malware_scan_status NOT NULL DEFAULT 'PENDING',
  scanned_at timestamptz, uploaded_by_account_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(tenant_id,id), UNIQUE(tenant_id,correction_rating_id), UNIQUE(tenant_id,storage_key),
  FOREIGN KEY(tenant_id,correction_rating_id) REFERENCES appraisal_correction_ratings(tenant_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(tenant_id,uploaded_by_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT,
  CHECK((malware_status='PENDING' AND scanned_at IS NULL) OR (malware_status<>'PENDING' AND scanned_at IS NOT NULL))
);
ALTER TABLE correction_evidence_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE correction_evidence_attachments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON correction_evidence_attachments USING(tenant_id=current_tenant_id()) WITH CHECK(tenant_id=current_tenant_id());

CREATE OR REPLACE FUNCTION validate_correction_rating_scope() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_appraisal uuid; v_original record; BEGIN
  SELECT appraisal_id INTO v_appraisal FROM appraisal_correction_versions WHERE tenant_id=NEW.tenant_id AND id=NEW.correction_version_id;
  SELECT appraisal_id,criterion_id,is_final INTO v_original FROM appraisal_ratings WHERE tenant_id=NEW.tenant_id AND id=NEW.original_rating_id;
  IF v_appraisal IS NULL OR v_original.appraisal_id IS DISTINCT FROM v_appraisal OR v_original.criterion_id IS DISTINCT FROM NEW.criterion_id OR NOT v_original.is_final
    THEN RAISE EXCEPTION 'correction criterion and original rating must belong to the current final appraisal snapshot'; END IF;
  RETURN NEW; END $$;
CREATE TRIGGER correction_rating_scope BEFORE INSERT OR UPDATE ON appraisal_correction_ratings FOR EACH ROW EXECUTE FUNCTION validate_correction_rating_scope();

CREATE OR REPLACE FUNCTION validate_correction_submission() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_expected int;v_actual int;v_bad_evidence boolean; BEGIN
 IF NEW.status='AWAITING_APPROVAL' AND OLD.status='DRAFT' THEN
  SELECT count(*) INTO v_expected FROM appraisals a JOIN evaluation_cycles cy ON cy.tenant_id=a.tenant_id AND cy.id=a.cycle_id
   JOIN criteria cr ON cr.tenant_id=cy.tenant_id AND cr.template_version_id=cy.template_version_id
   WHERE a.tenant_id=NEW.tenant_id AND a.id=NEW.appraisal_id AND cr.requires_rating
    AND a.personnel_category_snapshot=ANY(cr.applicable_categories) AND(cr.applicable_appointment_types IS NULL OR a.appointment_type_snapshot=ANY(cr.applicable_appointment_types));
  SELECT count(*) INTO v_actual FROM appraisal_correction_ratings WHERE tenant_id=NEW.tenant_id AND correction_version_id=NEW.id;
  IF v_expected=0 OR v_actual<>v_expected THEN RAISE EXCEPTION 'correction requires exactly one rating for each of % applicable criteria; found %',v_expected,v_actual;END IF;
  SELECT EXISTS(SELECT 1 FROM appraisal_correction_ratings r LEFT JOIN correction_evidence_attachments e ON e.tenant_id=r.tenant_id AND e.correction_rating_id=r.id
    WHERE r.tenant_id=NEW.tenant_id AND r.correction_version_id=NEW.id AND r.rating IN(1,2,5)
      AND(r.justification IS NULL OR btrim(r.justification)='' OR e.id IS NULL)) INTO v_bad_evidence;
  IF v_bad_evidence THEN RAISE EXCEPTION 'correction ratings 1, 2, and 5 require justification and evidence';END IF;
 END IF;
 IF NEW.status='APPROVED' AND OLD.status='AWAITING_APPROVAL' AND EXISTS(SELECT 1 FROM appraisal_correction_ratings r
   JOIN correction_evidence_attachments e ON e.tenant_id=r.tenant_id AND e.correction_rating_id=r.id
   WHERE r.tenant_id=NEW.tenant_id AND r.correction_version_id=NEW.id AND e.malware_status<>'CLEAN')
   THEN RAISE EXCEPTION 'all correction evidence must pass malware scanning before approval';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER correction_submission_validate BEFORE UPDATE OF status ON appraisal_correction_versions FOR EACH ROW EXECUTE FUNCTION validate_correction_submission();

CREATE OR REPLACE FUNCTION guard_correction_evidence() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v_status correction_status;BEGIN
 SELECT cv.status INTO v_status FROM appraisal_correction_ratings r JOIN appraisal_correction_versions cv ON cv.tenant_id=r.tenant_id AND cv.id=r.correction_version_id
 WHERE r.tenant_id=COALESCE(NEW.tenant_id,OLD.tenant_id) AND r.id=COALESCE(NEW.correction_rating_id,OLD.correction_rating_id);
 IF v_status<>'DRAFT' AND NOT(TG_OP='UPDATE' AND OLD.malware_status='PENDING' AND NEW.malware_status IN('CLEAN','INFECTED','FAILED')) THEN RAISE EXCEPTION 'submitted correction evidence is immutable';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;END $$;
CREATE TRIGGER correction_evidence_guard BEFORE INSERT OR UPDATE OR DELETE ON correction_evidence_attachments FOR EACH ROW EXECUTE FUNCTION guard_correction_evidence();

CREATE OR REPLACE FUNCTION require_correction_officer() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.correction_officer_account_id IS NULL THEN RAISE EXCEPTION 'a correction officer must be formally assigned';END IF;
 IF NOT EXISTS(SELECT 1 FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps st ON st.tenant_id=sn.tenant_id AND st.snapshot_id=sn.id
  WHERE sn.tenant_id=NEW.tenant_id AND sn.appraisal_id=NEW.appraisal_id AND sn.is_active AND st.evaluator_account_id=NEW.correction_officer_account_id)
  THEN RAISE EXCEPTION 'correction officer must belong to the appraisal evaluator chain';END IF;RETURN NEW;END $$;
CREATE TRIGGER reopen_requires_correction_officer BEFORE INSERT ON appraisal_reopen_authorizations FOR EACH ROW EXECUTE FUNCTION require_correction_officer();

CREATE OR REPLACE FUNCTION enforce_appraisal_workflow() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v_now timestamptz:=clock_timestamp();BEGIN
 IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW;END IF;
 IF NOT((OLD.status IN('DRAFT','SELF_ASSESSMENT_SUBMITTED','RETURNED') AND NEW.status='IN_EVALUATION')
  OR(OLD.status='IN_EVALUATION' AND NEW.status='AWAITING_COMMANDER_APPROVAL')
  OR(OLD.status='AWAITING_COMMANDER_APPROVAL' AND NEW.status='APPROVED') OR(OLD.status='APPROVED' AND NEW.status='ACKNOWLEDGED')
  OR(OLD.status='ACKNOWLEDGED' AND NEW.status='CLOSED') OR(OLD.status IN('CLOSED','COMPLAINT_OPEN') AND NEW.status='REOPENED') OR(OLD.status='REOPENED' AND NEW.status='CLOSED'))
  THEN RAISE EXCEPTION 'invalid controlled appraisal transition: % -> %',OLD.status,NEW.status;END IF;
 IF NEW.status='APPROVED' THEN NEW.approved_by_account_id:=current_actor_account_id();NEW.approved_at:=v_now;NEW.available_to_member_at:=v_now;
 ELSIF NEW.status='ACKNOWLEDGED' THEN NEW.acknowledged_at:=v_now;
 ELSIF NEW.status='CLOSED' THEN NEW.closed_at:=v_now;END IF;
 NEW.updated_at:=v_now;NEW.row_version:=OLD.row_version+1;RETURN NEW;END $$;
CREATE TRIGGER appraisals_controlled_workflow BEFORE UPDATE OF status ON appraisals FOR EACH ROW EXECUTE FUNCTION enforce_appraisal_workflow();

CREATE OR REPLACE VIEW official_appraisal_current_version WITH(security_invoker=true) AS
SELECT a.tenant_id,a.id AS appraisal_id,a.personnel_id,a.cycle_id,
 COALESCE(cv.id,a.id) AS official_version_id,COALESCE(cv.version_no,0) AS correction_version_no,
 COALESCE(cv.total_points,a.total_points) AS total_points,COALESCE(cv.maximum_points,a.maximum_points) AS maximum_points,
 COALESCE(cv.score_percentage,a.score_percentage) AS score_percentage,cv.approved_at AS correction_approved_at
FROM appraisals a LEFT JOIN LATERAL(SELECT * FROM appraisal_correction_versions x WHERE x.tenant_id=a.tenant_id AND x.appraisal_id=a.id AND x.status='APPROVED' ORDER BY x.version_no DESC LIMIT 1)cv ON true;

CREATE OR REPLACE VIEW official_appraisal_current_ratings WITH(security_invoker=true) AS
SELECT o.tenant_id,o.appraisal_id,r.criterion_id,r.rating,r.justification,r.id AS source_rating_id,o.correction_version_no
FROM official_appraisal_current_version o JOIN appraisal_ratings r ON r.tenant_id=o.tenant_id AND r.appraisal_id=o.appraisal_id AND r.is_final
WHERE o.correction_version_no=0
UNION ALL
SELECT o.tenant_id,o.appraisal_id,r.criterion_id,r.rating,r.justification,r.id,o.correction_version_no
FROM official_appraisal_current_version o JOIN appraisal_correction_ratings r ON r.tenant_id=o.tenant_id AND r.correction_version_id=o.official_version_id
WHERE o.correction_version_no>0;

CREATE OR REPLACE VIEW member_visible_appraisal_comments WITH(security_barrier=true) AS
SELECT tenant_id,id,appraisal_id,evaluator_step_id,author_account_id,body,supersedes_comment_id,created_at
FROM appraisal_comments WHERE tenant_id=current_tenant_id() AND visibility='MEMBER_VISIBLE';

CREATE OR REPLACE FUNCTION recalculate_recommendations(p_tenant uuid,p_personnel uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_app record;v_bad boolean;v_open boolean;v_eligible boolean;v_type recommendation_type;BEGIN
 SELECT o.appraisal_id,o.score_percentage,p.unit_service_started_on INTO v_app FROM official_appraisal_current_version o
 JOIN appraisals a ON a.tenant_id=o.tenant_id AND a.id=o.appraisal_id JOIN evaluation_cycles cy ON cy.tenant_id=a.tenant_id AND cy.id=a.cycle_id AND cy.cycle_type='ANNUAL'
 JOIN personnel p ON p.tenant_id=a.tenant_id AND p.id=a.personnel_id WHERE o.tenant_id=p_tenant AND o.personnel_id=p_personnel AND a.status IN('APPROVED','ACKNOWLEDGED','CLOSED') ORDER BY cy.ends_on DESC LIMIT 1;
 IF NOT FOUND THEN RETURN;END IF;
 SELECT EXISTS(SELECT 1 FROM official_appraisal_current_ratings WHERE tenant_id=p_tenant AND appraisal_id=v_app.appraisal_id AND rating<3)INTO v_bad;
 SELECT EXISTS(SELECT 1 FROM disciplinary_matters WHERE tenant_id=p_tenant AND personnel_id=p_personnel AND status IN('ALLEGED','UNDER_REVIEW','CONFIRMED'))OR EXISTS(SELECT 1 FROM awol_incidents WHERE tenant_id=p_tenant AND personnel_id=p_personnel AND status IN('REPORTED','UNDER_REVIEW','CONFIRMED'))INTO v_open;
 v_eligible:=v_app.score_percentage>85.00 AND NOT v_bad AND NOT v_open AND clock_timestamp()>(v_app.unit_service_started_on::timestamp+interval '9 months');PERFORM set_config('app.eligibility_engine','true',true);
 FOREACH v_type IN ARRAY ARRAY['PROMOTION'::recommendation_type,'COMMENDATION'::recommendation_type] LOOP
  INSERT INTO recommendations(tenant_id,personnel_id,annual_appraisal_id,recommendation_type,status,eligibility_checked_at,annual_score_percentage,has_rating_below_three,has_unresolved_disciplinary_matter,unit_service_started_on,eligible)
  VALUES(p_tenant,p_personnel,v_app.appraisal_id,v_type,CASE WHEN v_eligible THEN'ELIGIBLE'ELSE'INELIGIBLE'END,clock_timestamp(),v_app.score_percentage,v_bad,v_open,v_app.unit_service_started_on,v_eligible)
  ON CONFLICT(tenant_id,personnel_id,annual_appraisal_id,recommendation_type)DO UPDATE SET eligibility_checked_at=EXCLUDED.eligibility_checked_at,annual_score_percentage=EXCLUDED.annual_score_percentage,has_rating_below_three=EXCLUDED.has_rating_below_three,has_unresolved_disciplinary_matter=EXCLUDED.has_unresolved_disciplinary_matter,unit_service_started_on=EXCLUDED.unit_service_started_on,eligible=EXCLUDED.eligible,status=CASE WHEN recommendations.status IN('ELIGIBLE','INELIGIBLE')THEN EXCLUDED.status WHEN NOT EXCLUDED.eligible THEN'INELIGIBLE'ELSE recommendations.status END;
  INSERT INTO recommendation_eligibility_assessments(tenant_id,recommendation_id,annual_score_percentage,has_rating_below_three,has_unresolved_disciplinary_matter,unit_service_started_on,service_threshold_at,eligible)
  SELECT p_tenant,id,v_app.score_percentage,v_bad,v_open,v_app.unit_service_started_on,v_app.unit_service_started_on::timestamp+interval'9 months',v_eligible FROM recommendations WHERE tenant_id=p_tenant AND personnel_id=p_personnel AND annual_appraisal_id=v_app.appraisal_id AND recommendation_type=v_type;
 END LOOP;END $$;

CREATE OR REPLACE FUNCTION apply_active_data_mode() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v_mode data_mode;BEGIN
 IF current_date NOT BETWEEN DATE '2026-12-01' AND DATE '2026-12-31' THEN NEW.data_mode:='PRODUCTION';RETURN NEW;END IF;
 SELECT active_data_mode INTO v_mode FROM tenant_runtime_settings WHERE tenant_id=NEW.tenant_id;NEW.data_mode:=COALESCE(v_mode,'PRODUCTION');RETURN NEW;END $$;

CREATE TRIGGER audit_correction_evidence AFTER INSERT OR UPDATE OR DELETE ON correction_evidence_attachments FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
COMMIT;
