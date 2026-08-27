BEGIN;

-- Audited DML must not require the runtime role to call the low-level writer.
CREATE OR REPLACE FUNCTION audit_sensitive_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_tenant uuid:=COALESCE(NEW.tenant_id,OLD.tenant_id);v_id uuid:=COALESCE(NEW.id,OLD.id);
 v_action text:=TG_TABLE_NAME||'_'||TG_OP;v_appraisal uuid;v_complaint uuid;v_restricted boolean:=false;
BEGIN
 IF TG_TABLE_NAME='appraisal_ratings' THEN v_appraisal:=COALESCE(NEW.appraisal_id,OLD.appraisal_id);END IF;
 IF TG_TABLE_NAME='appraisal_comments' THEN v_appraisal:=COALESCE(NEW.appraisal_id,OLD.appraisal_id);v_restricted:=COALESCE(NEW.visibility,OLD.visibility)='RESTRICTED_SUPERVISORY';END IF;
 IF TG_TABLE_NAME='complaints' THEN v_appraisal:=COALESCE(NEW.appraisal_id,OLD.appraisal_id);v_complaint:=v_id;END IF;
 PERFORM write_audit_event(v_tenant,v_action,TG_TABLE_NAME,v_id,
  CASE WHEN TG_OP IN('UPDATE','DELETE')THEN to_jsonb(OLD)END,
  CASE WHEN TG_OP IN('INSERT','UPDATE')THEN to_jsonb(NEW)END,NULL,v_appraisal,v_complaint,
  v_restricted);
 IF TG_OP='DELETE'THEN RETURN OLD;END IF;RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION audit_sensitive_change() FROM PUBLIC,mndf_pms_runtime;

CREATE TABLE evidence_uploads(
 id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
 uploaded_by_account_id uuid NOT NULL,storage_key text NOT NULL,original_filename text NOT NULL,mime_type text NOT NULL,
 byte_size integer NOT NULL CHECK(byte_size>0 AND byte_size<=5242880),page_count smallint NOT NULL CHECK(page_count=1),
 sha256_hex text NOT NULL CHECK(sha256_hex~'^[0-9a-f]{64}$'),malware_status malware_scan_status NOT NULL DEFAULT'PENDING',
 scanned_at timestamptz,consumed_at timestamptz,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,id),UNIQUE(tenant_id,storage_key),
 FOREIGN KEY(tenant_id,uploaded_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 CHECK(mime_type IN('application/pdf','image/jpeg','image/png','image/webp')),
 CHECK((malware_status='PENDING'AND scanned_at IS NULL)OR(malware_status<>'PENDING'AND scanned_at IS NOT NULL))
);
ALTER TABLE evidence_uploads ENABLE ROW LEVEL SECURITY;ALTER TABLE evidence_uploads FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON evidence_uploads USING(tenant_id=current_tenant_id())WITH CHECK(tenant_id=current_tenant_id());

CREATE TABLE mfa_verification_attempts(
 id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES tenants(id)ON DELETE CASCADE,
 account_id uuid NOT NULL,succeeded boolean NOT NULL,occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,id),FOREIGN KEY(tenant_id,account_id)REFERENCES accounts(tenant_id,id)ON DELETE CASCADE
);
CREATE INDEX idx_mfa_attempts_recent ON mfa_verification_attempts(tenant_id,account_id,occurred_at DESC);
ALTER TABLE mfa_verification_attempts ENABLE ROW LEVEL SECURITY;ALTER TABLE mfa_verification_attempts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON mfa_verification_attempts USING(tenant_id=current_tenant_id())WITH CHECK(tenant_id=current_tenant_id());

CREATE OR REPLACE FUNCTION enforce_correction_actor()RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_officer uuid;BEGIN
 SELECT ra.correction_officer_account_id INTO v_officer FROM appraisal_correction_versions cv
 JOIN appraisal_reopen_authorizations ra ON ra.tenant_id=cv.tenant_id AND ra.id=cv.authorization_id
 WHERE cv.tenant_id=COALESCE(NEW.tenant_id,OLD.tenant_id)AND cv.id=COALESCE(NEW.correction_version_id,OLD.correction_version_id);
 IF current_actor_account_id()IS DISTINCT FROM v_officer THEN RAISE EXCEPTION'only the assigned correction officer may change correction ratings';END IF;
 IF TG_OP='DELETE'THEN RETURN OLD;END IF;RETURN NEW;
END $$;
CREATE TRIGGER correction_rating_actor BEFORE INSERT OR UPDATE OR DELETE ON appraisal_correction_ratings FOR EACH ROW EXECUTE FUNCTION enforce_correction_actor();

CREATE OR REPLACE FUNCTION enforce_correction_submitter()RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_officer uuid;BEGIN
 IF NEW.status='AWAITING_APPROVAL'AND OLD.status='DRAFT'THEN
  SELECT correction_officer_account_id INTO v_officer FROM appraisal_reopen_authorizations WHERE tenant_id=NEW.tenant_id AND id=NEW.authorization_id;
  IF current_actor_account_id()IS DISTINCT FROM v_officer THEN RAISE EXCEPTION'only the assigned correction officer may submit the correction';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER correction_submitter_guard BEFORE UPDATE OF status ON appraisal_correction_versions FOR EACH ROW EXECUTE FUNCTION enforce_correction_submitter();

CREATE OR REPLACE FUNCTION validate_activity_confirmer()RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_evaluator_personnel uuid;BEGIN
 IF NEW.status='CONFIRMED'AND OLD.status='SUBMITTED'THEN
  SELECT personnel_id INTO v_evaluator_personnel FROM accounts WHERE tenant_id=NEW.tenant_id AND id=current_actor_account_id();
  IF NOT EXISTS(SELECT 1 FROM evaluator_assignments ea WHERE ea.tenant_id=NEW.tenant_id
    AND ea.appraisee_personnel_id=NEW.personnel_id AND ea.evaluator_personnel_id=v_evaluator_personnel
    AND ea.starts_on<=NEW.activity_date AND(ea.ends_on IS NULL OR ea.ends_on>=NEW.activity_date))
  THEN RAISE EXCEPTION'activity confirmation requires an effective evaluator assignment';END IF;
 END IF;RETURN NEW;
END $$;
CREATE TRIGGER activity_confirmer_guard BEFORE UPDATE OF status ON activity_records FOR EACH ROW EXECUTE FUNCTION validate_activity_confirmer();

CREATE OR REPLACE FUNCTION validate_appraisal_closer()RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
 IF NEW.status='CLOSED'AND OLD.status='ACKNOWLEDGED'AND NOT EXISTS(
  SELECT 1 FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps st ON st.tenant_id=sn.tenant_id AND st.snapshot_id=sn.id
  WHERE sn.tenant_id=NEW.tenant_id AND sn.appraisal_id=NEW.id AND sn.is_active AND st.step_kind='FINAL_APPROVAL'
    AND st.evaluator_account_id=current_actor_account_id())THEN RAISE EXCEPTION'only the snapshotted final approver may close the appraisal';END IF;
 RETURN NEW;END $$;
CREATE TRIGGER appraisal_closer_guard BEFORE UPDATE OF status ON appraisals FOR EACH ROW EXECUTE FUNCTION validate_appraisal_closer();

CREATE TRIGGER audit_evidence_uploads AFTER INSERT OR UPDATE OR DELETE ON evidence_uploads FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

GRANT SELECT,INSERT,UPDATE,DELETE ON evidence_uploads,mfa_verification_attempts TO mndf_pms_runtime;

COMMIT;
