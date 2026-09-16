\set ON_ERROR_STOP on
INSERT INTO tenants(id,code,name,status)VALUES
 ('10000000-0000-0000-0000-000000000001','STAGE11-A','Stage 1.1 Tenant A','ACTIVE'),
 ('20000000-0000-0000-0000-000000000002','STAGE11-B','Stage 1.1 Tenant B','ACTIVE') ON CONFLICT(id) DO NOTHING;
INSERT INTO accounts(id,tenant_id,email,password_hash,is_active)VALUES
 ('11000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','admin-a@example.test','not-a-real-password-hash-stage11-a',true),
 ('22000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','admin-b@example.test','not-a-real-password-hash-stage11-b',true) ON CONFLICT(tenant_id,id) DO NOTHING;

SET SESSION AUTHORIZATION mndf_pms_app;
BEGIN;
SELECT set_config('app.tenant_id','10000000-0000-0000-0000-000000000001',true);
SELECT set_config('app.account_id','11000000-0000-0000-0000-000000000001',true);
SELECT set_config('app.request_id','13000000-0000-0000-0000-000000000003',true);
DO $$DECLARE v_count integer;v_blocked boolean:=false;BEGIN
 SELECT count(*)INTO v_count FROM tenants;IF v_count<>1 THEN RAISE EXCEPTION'RLS tenant visibility failed: % rows',v_count;END IF;
 BEGIN
  INSERT INTO evaluation_templates(id,tenant_id,name,is_baseline,created_by_account_id)VALUES
   ('23000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000002','Cross tenant write',false,'22000000-0000-0000-0000-000000000002');
 EXCEPTION WHEN insufficient_privilege THEN v_blocked:=true;END;
 IF NOT v_blocked THEN RAISE EXCEPTION'cross-tenant write was not blocked by RLS';END IF;
END$$;
INSERT INTO evaluation_templates(id,tenant_id,name,is_baseline,created_by_account_id)VALUES
 ('14000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','Audit smoke template',false,'11000000-0000-0000-0000-000000000001');
INSERT INTO template_versions(id,tenant_id,template_id,version_no,status,created_by_account_id)VALUES
 ('15000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','14000000-0000-0000-0000-000000000004',1,'DRAFT','11000000-0000-0000-0000-000000000001');
DO $$BEGIN IF NOT EXISTS(SELECT 1 FROM audit_logs WHERE tenant_id='10000000-0000-0000-0000-000000000001'AND entity_table='template_versions'AND entity_id='15000000-0000-0000-0000-000000000005')THEN RAISE EXCEPTION'audited runtime write did not create an audit record';END IF;END$$;
ROLLBACK;
RESET SESSION AUTHORIZATION;
SELECT 'runtime_rls_and_audit_smoke_passed'AS result;
