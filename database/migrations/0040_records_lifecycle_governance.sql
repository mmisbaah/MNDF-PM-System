\set ON_ERROR_STOP on
BEGIN;

CREATE TABLE retention_policy_versions(
 id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
 record_class text NOT NULL CHECK(record_class IN('PERSONNEL','PERFORMANCE','ACTIVITY','GRIEVANCE','EVIDENCE','DISCIPLINE','AUDIT','SECURITY_TELEMETRY','EXPORT_PACKAGE','BACKUP')),
 version_no integer NOT NULL CHECK(version_no>0),status text NOT NULL DEFAULT'DRAFT' CHECK(status IN('DRAFT','APPROVED','RETIRED')),
 retain_indefinitely boolean NOT NULL DEFAULT true,retention_days integer CHECK(retention_days BETWEEN 1 AND 36500),
 policy_reason text NOT NULL CHECK(btrim(policy_reason)<>''),created_by_account_id uuid NOT NULL,approved_by_account_id uuid,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),approved_at timestamptz,retired_at timestamptz,
 PRIMARY KEY(tenant_id,id),UNIQUE(tenant_id,record_class,version_no),
 FOREIGN KEY(tenant_id,created_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 FOREIGN KEY(tenant_id,approved_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 CHECK(retain_indefinitely=(retention_days IS NULL)),
 CHECK((status='DRAFT'AND approved_by_account_id IS NULL AND approved_at IS NULL AND retired_at IS NULL)
    OR(status='APPROVED'AND approved_by_account_id IS NOT NULL AND approved_at IS NOT NULL AND retired_at IS NULL)
    OR(status='RETIRED'AND approved_by_account_id IS NOT NULL AND approved_at IS NOT NULL AND retired_at IS NOT NULL))
);
CREATE UNIQUE INDEX uq_retention_policy_approved ON retention_policy_versions(tenant_id,record_class)WHERE status='APPROVED';

CREATE TABLE legal_holds(
 id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES tenants(id)ON DELETE CASCADE,
 scope_type text NOT NULL CHECK(scope_type IN('TENANT','PERSONNEL','APPRAISAL','COMPLAINT','EVIDENCE')),
 scope_id uuid,reason text NOT NULL CHECK(btrim(reason)<>''),created_by_account_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 released_by_account_id uuid,released_at timestamptz,release_reason text,
 PRIMARY KEY(tenant_id,id),FOREIGN KEY(tenant_id,created_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 FOREIGN KEY(tenant_id,released_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 CHECK((scope_type='TENANT'AND scope_id IS NULL)OR(scope_type<>'TENANT'AND scope_id IS NOT NULL)),
 CHECK((released_at IS NULL AND released_by_account_id IS NULL AND release_reason IS NULL)
    OR(released_at IS NOT NULL AND released_by_account_id IS NOT NULL AND btrim(release_reason)<>''))
);
CREATE INDEX idx_legal_holds_active ON legal_holds(tenant_id,scope_type,scope_id)WHERE released_at IS NULL;

CREATE TABLE controlled_export_requests(
 id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES tenants(id)ON DELETE CASCADE,
 export_scope text NOT NULL CHECK(export_scope IN('PERSONNEL_RECORD','APPRAISAL','GRIEVANCE_CASE','AUDIT_LEDGER','TENANT_ARCHIVE')),
 scope_id uuid,purpose text NOT NULL CHECK(btrim(purpose)<>''),status text NOT NULL DEFAULT'REQUESTED' CHECK(status IN('REQUESTED','APPROVED','REJECTED','COMPLETED','EXPIRED')),
 requested_by_account_id uuid NOT NULL,requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 decided_by_account_id uuid,decided_at timestamptz,decision_reason text,expires_at timestamptz,
 completed_at timestamptz,encrypted_manifest_sha256 text,
 PRIMARY KEY(tenant_id,id),FOREIGN KEY(tenant_id,requested_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 FOREIGN KEY(tenant_id,decided_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 CHECK((status='REQUESTED'AND decided_at IS NULL)OR(status<>'REQUESTED'AND decided_at IS NOT NULL)),
 CHECK(encrypted_manifest_sha256 IS NULL OR encrypted_manifest_sha256~'^[0-9a-f]{64}$'),
 CHECK(completed_at IS NULL OR(status='COMPLETED'AND encrypted_manifest_sha256 IS NOT NULL))
);

CREATE TABLE record_disposal_requests(
 id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES tenants(id)ON DELETE CASCADE,
 record_class text NOT NULL CHECK(record_class IN('PERSONNEL','PERFORMANCE','ACTIVITY','GRIEVANCE','EVIDENCE','DISCIPLINE','AUDIT','SECURITY_TELEMETRY','EXPORT_PACKAGE','BACKUP')),cutoff_at timestamptz NOT NULL,reason text NOT NULL CHECK(btrim(reason)<>''),
 status text NOT NULL DEFAULT'REQUESTED' CHECK(status IN('REQUESTED','AUTHORIZED','CANCELLED','VERIFIED_COMPLETE')),
 requested_by_account_id uuid NOT NULL,requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 cancelled_by_account_id uuid,cancelled_at timestamptz,cancellation_reason text,
 completed_by_account_id uuid,completed_at timestamptz,disposal_manifest_sha256 text,disposed_record_count bigint CHECK(disposed_record_count>=0),
 PRIMARY KEY(tenant_id,id),FOREIGN KEY(tenant_id,requested_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 FOREIGN KEY(tenant_id,cancelled_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 FOREIGN KEY(tenant_id,completed_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT,
 CHECK(disposal_manifest_sha256 IS NULL OR disposal_manifest_sha256~'^[0-9a-f]{64}$'),
 CHECK(status<>'VERIFIED_COMPLETE'OR(completed_at IS NOT NULL AND completed_by_account_id IS NOT NULL AND disposal_manifest_sha256 IS NOT NULL AND disposed_record_count IS NOT NULL))
);
CREATE TABLE record_disposal_approvals(
 id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL,disposal_request_id uuid NOT NULL,
 authority_role text NOT NULL CHECK(authority_role IN('SYSTEM_AUTHORIZER','SECOND_TIER_AUTHORITY')),
 approved_by_account_id uuid NOT NULL,approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),reason text NOT NULL CHECK(btrim(reason)<>''),
 PRIMARY KEY(tenant_id,id),UNIQUE(tenant_id,disposal_request_id,authority_role),UNIQUE(tenant_id,disposal_request_id,approved_by_account_id),
 FOREIGN KEY(tenant_id,disposal_request_id)REFERENCES record_disposal_requests(tenant_id,id)ON DELETE CASCADE,
 FOREIGN KEY(tenant_id,approved_by_account_id)REFERENCES accounts(tenant_id,id)ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION lifecycle_actor_has_role(p_tenant uuid,p_account uuid,p_role system_role)RETURNS boolean
LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$SELECT EXISTS(SELECT 1 FROM account_roles WHERE tenant_id=p_tenant AND account_id=p_account AND role=p_role AND valid_from<=clock_timestamp()AND(valid_until IS NULL OR valid_until>clock_timestamp()))$$;

CREATE OR REPLACE FUNCTION guard_retention_policy()RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$BEGIN
 IF TG_OP='DELETE'THEN RAISE EXCEPTION'policy versions cannot be deleted';END IF;
 IF TG_OP='INSERT'THEN IF NEW.created_by_account_id<>current_actor_account_id()THEN RAISE EXCEPTION'policy creator must be the acting account';END IF;RETURN NEW;END IF;
 IF OLD.status='RETIRED'THEN RAISE EXCEPTION'retired policies are immutable';END IF;
 IF OLD.status='APPROVED'THEN
  IF NOT lifecycle_actor_has_role(NEW.tenant_id,current_actor_account_id(),'COMPANY_COMMANDER')THEN RAISE EXCEPTION'only the System Authorizer may retire retention policy';END IF;
  IF NEW.status<>'RETIRED'OR NEW.retired_at IS NULL OR ROW(NEW.tenant_id,NEW.id,NEW.record_class,NEW.version_no,NEW.retain_indefinitely,NEW.retention_days,NEW.policy_reason,NEW.created_by_account_id,NEW.approved_by_account_id,NEW.created_at,NEW.approved_at)
   IS DISTINCT FROM ROW(OLD.tenant_id,OLD.id,OLD.record_class,OLD.version_no,OLD.retain_indefinitely,OLD.retention_days,OLD.policy_reason,OLD.created_by_account_id,OLD.approved_by_account_id,OLD.created_at,OLD.approved_at)THEN RAISE EXCEPTION'approved policies may only be retired';END IF;
 ELSIF NEW.status='APPROVED'THEN
  IF NOT lifecycle_actor_has_role(NEW.tenant_id,current_actor_account_id(),'COMPANY_COMMANDER')THEN RAISE EXCEPTION'only the System Authorizer may approve retention policy';END IF;
  NEW.approved_by_account_id:=current_actor_account_id();NEW.approved_at:=clock_timestamp();
 END IF;RETURN NEW;
END$$;
CREATE TRIGGER retention_policy_guard BEFORE INSERT OR UPDATE OR DELETE ON retention_policy_versions FOR EACH ROW EXECUTE FUNCTION guard_retention_policy();

CREATE OR REPLACE FUNCTION guard_legal_hold()RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$BEGIN
 IF TG_OP='DELETE'THEN RAISE EXCEPTION'legal holds cannot be deleted';END IF;
 IF TG_OP='INSERT'THEN IF NEW.created_by_account_id<>current_actor_account_id()THEN RAISE EXCEPTION'hold creator must be acting account';END IF;RETURN NEW;END IF;
 IF OLD.released_at IS NOT NULL THEN RAISE EXCEPTION'released legal holds are immutable';END IF;
 IF NEW.released_at IS NULL OR NEW.released_by_account_id<>current_actor_account_id()OR btrim(NEW.release_reason)=''THEN RAISE EXCEPTION'legal hold release requires acting account and reason';END IF;
 IF ROW(NEW.tenant_id,NEW.id,NEW.scope_type,NEW.scope_id,NEW.reason,NEW.created_by_account_id,NEW.created_at)IS DISTINCT FROM ROW(OLD.tenant_id,OLD.id,OLD.scope_type,OLD.scope_id,OLD.reason,OLD.created_by_account_id,OLD.created_at)THEN RAISE EXCEPTION'legal hold scope is immutable';END IF;RETURN NEW;
END$$;
CREATE TRIGGER legal_hold_guard BEFORE INSERT OR UPDATE OR DELETE ON legal_holds FOR EACH ROW EXECUTE FUNCTION guard_legal_hold();

CREATE OR REPLACE FUNCTION guard_controlled_export()RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$BEGIN
 IF TG_OP='DELETE'THEN RAISE EXCEPTION'controlled export records cannot be deleted';END IF;
 IF TG_OP='INSERT'THEN IF NEW.requested_by_account_id<>current_actor_account_id()THEN RAISE EXCEPTION'export requester must be acting account';END IF;RETURN NEW;END IF;
 IF OLD.status='REQUESTED'AND NEW.status IN('APPROVED','REJECTED')THEN
  IF NEW.decided_by_account_id<>current_actor_account_id()OR NEW.decided_by_account_id=OLD.requested_by_account_id OR NOT lifecycle_actor_has_role(NEW.tenant_id,NEW.decided_by_account_id,'COMPANY_COMMANDER')THEN RAISE EXCEPTION'export decision requires a different System Authorizer account';END IF;
 ELSIF OLD.status='APPROVED'AND NEW.status='COMPLETED'THEN
  IF OLD.expires_at<=clock_timestamp()OR NEW.completed_at IS NULL OR NEW.encrypted_manifest_sha256 IS NULL THEN RAISE EXCEPTION'export completion requires current approval and encrypted manifest';END IF;
 ELSIF OLD.status='APPROVED'AND NEW.status='EXPIRED'THEN NULL;
 ELSE RAISE EXCEPTION'invalid controlled export transition';END IF;RETURN NEW;
END$$;
CREATE TRIGGER controlled_export_guard BEFORE INSERT OR UPDATE OR DELETE ON controlled_export_requests FOR EACH ROW EXECUTE FUNCTION guard_controlled_export();

CREATE OR REPLACE FUNCTION guard_disposal_request()RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$BEGIN
 IF TG_OP='DELETE'THEN RAISE EXCEPTION'disposal records cannot be deleted';END IF;
 IF TG_OP='INSERT'THEN IF NEW.requested_by_account_id<>current_actor_account_id()THEN RAISE EXCEPTION'disposal requester must be acting account';END IF;RETURN NEW;END IF;
 IF OLD.status='REQUESTED'AND NEW.status='AUTHORIZED'THEN RETURN NEW;END IF;
 IF OLD.status IN('REQUESTED','AUTHORIZED')AND NEW.status='CANCELLED'AND NEW.cancelled_by_account_id=current_actor_account_id()AND btrim(NEW.cancellation_reason)<>''THEN RETURN NEW;END IF;
 IF OLD.status='AUTHORIZED'AND NEW.status='VERIFIED_COMPLETE'AND current_setting('app.verified_disposal_executor',true)='true'AND NEW.completed_by_account_id=current_actor_account_id()THEN RETURN NEW;END IF;
 RAISE EXCEPTION'invalid disposal transition';
END$$;
CREATE TRIGGER disposal_request_guard BEFORE INSERT OR UPDATE OR DELETE ON record_disposal_requests FOR EACH ROW EXECUTE FUNCTION guard_disposal_request();

CREATE OR REPLACE FUNCTION validate_disposal_approval()RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$DECLARE v_class text;v_role system_role;BEGIN
 IF NEW.approved_by_account_id<>current_actor_account_id()THEN RAISE EXCEPTION'disposal approval must be acting account';END IF;
 v_role:=CASE NEW.authority_role WHEN'SYSTEM_AUTHORIZER'THEN'COMPANY_COMMANDER'::system_role ELSE'EXECUTIVE_OFFICER'::system_role END;
 IF NOT lifecycle_actor_has_role(NEW.tenant_id,NEW.approved_by_account_id,v_role)THEN RAISE EXCEPTION'account lacks required disposal authority';END IF;
 SELECT record_class INTO STRICT v_class FROM record_disposal_requests WHERE tenant_id=NEW.tenant_id AND id=NEW.disposal_request_id AND status='REQUESTED';
 IF NOT EXISTS(SELECT 1 FROM retention_policy_versions WHERE tenant_id=NEW.tenant_id AND record_class=v_class AND status='APPROVED'AND NOT retain_indefinitely)THEN RAISE EXCEPTION'approved finite retention policy is required';END IF;
 IF EXISTS(SELECT 1 FROM legal_holds WHERE tenant_id=NEW.tenant_id AND released_at IS NULL)THEN RAISE EXCEPTION'active legal hold blocks disposal';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER disposal_approval_validate BEFORE INSERT ON record_disposal_approvals FOR EACH ROW EXECUTE FUNCTION validate_disposal_approval();
CREATE OR REPLACE FUNCTION refresh_disposal_authorization()RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$BEGIN
 UPDATE record_disposal_requests SET status='AUTHORIZED'WHERE tenant_id=NEW.tenant_id AND id=NEW.disposal_request_id AND status='REQUESTED'AND(SELECT count(*)FROM record_disposal_approvals WHERE tenant_id=NEW.tenant_id AND disposal_request_id=NEW.disposal_request_id)=2;RETURN NEW;END$$;
CREATE TRIGGER disposal_authorization_refresh AFTER INSERT ON record_disposal_approvals FOR EACH ROW EXECUTE FUNCTION refresh_disposal_authorization();

DO $$DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['retention_policy_versions','legal_holds','controlled_export_requests','record_disposal_requests','record_disposal_approvals']LOOP
 EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY tenant_isolation ON %I USING(tenant_id=current_tenant_id())WITH CHECK(tenant_id=current_tenant_id())',t);
 EXECUTE format('CREATE TRIGGER audit_%I AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change()',t,t);
END LOOP;END$$;
REVOKE ALL ON FUNCTION lifecycle_actor_has_role(uuid,uuid,system_role),guard_retention_policy(),guard_legal_hold(),guard_controlled_export(),guard_disposal_request(),validate_disposal_approval(),refresh_disposal_authorization()FROM PUBLIC;
GRANT SELECT,INSERT,UPDATE ON retention_policy_versions,legal_holds,controlled_export_requests,record_disposal_requests TO mndf_pms_runtime;
GRANT SELECT,INSERT ON record_disposal_approvals TO mndf_pms_runtime;
REVOKE DELETE ON retention_policy_versions,legal_holds,controlled_export_requests,record_disposal_requests,record_disposal_approvals FROM mndf_pms_runtime;
COMMIT;
