BEGIN;
CREATE TABLE appraisal_self_assessments(
 id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES tenants(id)ON DELETE CASCADE,
 appraisal_id uuid NOT NULL,criterion_id uuid NOT NULL,self_rating smallint CHECK(self_rating BETWEEN 1 AND 5),
 narrative text NOT NULL CHECK(btrim(narrative)<>''),created_by_account_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,id),UNIQUE(tenant_id,appraisal_id,criterion_id),
 FOREIGN KEY(tenant_id,appraisal_id)REFERENCES appraisals(tenant_id,id)ON DELETE RESTRICT,
 FOREIGN KEY(tenant_id,criterion_id)REFERENCES criteria(tenant_id,id)ON DELETE RESTRICT,
 FOREIGN KEY(tenant_id,created_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT
);
ALTER TABLE appraisal_self_assessments ENABLE ROW LEVEL SECURITY;ALTER TABLE appraisal_self_assessments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON appraisal_self_assessments USING(tenant_id=current_tenant_id())WITH CHECK(tenant_id=current_tenant_id());
CREATE OR REPLACE FUNCTION guard_self_assessment()RETURNS trigger LANGUAGE plpgsql AS $$DECLARE v_status appraisal_status;v_personnel uuid;BEGIN
 SELECT a.status,a.personnel_id INTO v_status,v_personnel FROM appraisals a WHERE a.tenant_id=COALESCE(NEW.tenant_id,OLD.tenant_id)AND a.id=COALESCE(NEW.appraisal_id,OLD.appraisal_id);
 IF v_status<>'DRAFT'THEN RAISE EXCEPTION'self-assessment is immutable after submission';END IF;
 IF TG_OP<>'DELETE'AND NOT EXISTS(SELECT 1 FROM accounts ac WHERE ac.tenant_id=NEW.tenant_id AND ac.id=current_actor_account_id()AND ac.personnel_id=v_personnel)THEN RAISE EXCEPTION'only the appraisee may record self-assessment';END IF;
 IF TG_OP='DELETE'THEN RETURN OLD;END IF;NEW.updated_at:=clock_timestamp();RETURN NEW;END$$;
CREATE TRIGGER self_assessment_guard BEFORE INSERT OR UPDATE OR DELETE ON appraisal_self_assessments FOR EACH ROW EXECUTE FUNCTION guard_self_assessment();
CREATE TRIGGER audit_self_assessments AFTER INSERT OR UPDATE OR DELETE ON appraisal_self_assessments FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

CREATE OR REPLACE FUNCTION enforce_appraisal_workflow()RETURNS trigger LANGUAGE plpgsql AS $$DECLARE v_now timestamptz:=clock_timestamp();BEGIN
 IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW;END IF;
 IF NOT((OLD.status='DRAFT'AND NEW.status='SELF_ASSESSMENT_SUBMITTED')
  OR(OLD.status IN('DRAFT','SELF_ASSESSMENT_SUBMITTED','RETURNED')AND NEW.status='IN_EVALUATION')
  OR(OLD.status='IN_EVALUATION'AND NEW.status='AWAITING_COMMANDER_APPROVAL')
  OR(OLD.status='AWAITING_COMMANDER_APPROVAL'AND NEW.status='APPROVED')OR(OLD.status='APPROVED'AND NEW.status='ACKNOWLEDGED')
  OR(OLD.status='ACKNOWLEDGED'AND NEW.status='CLOSED')OR(OLD.status IN('CLOSED','COMPLAINT_OPEN')AND NEW.status='REOPENED')OR(OLD.status='REOPENED'AND NEW.status='CLOSED'))
 THEN RAISE EXCEPTION'invalid controlled appraisal transition: % -> %',OLD.status,NEW.status;END IF;
 IF NEW.status='APPROVED'THEN NEW.approved_by_account_id:=current_actor_account_id();NEW.approved_at:=v_now;NEW.available_to_member_at:=v_now;
 ELSIF NEW.status='ACKNOWLEDGED'THEN NEW.acknowledged_at:=v_now;ELSIF NEW.status='CLOSED'THEN NEW.closed_at:=v_now;END IF;
 NEW.updated_at:=v_now;NEW.row_version:=OLD.row_version+1;RETURN NEW;END$$;

GRANT SELECT,INSERT,UPDATE,DELETE ON appraisal_self_assessments TO mndf_pms_runtime;
COMMIT;
