BEGIN;
DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='mndf_pms_runtime')THEN CREATE ROLE mndf_pms_runtime NOLOGIN NOINHERIT NOBYPASSRLS;END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='mndf_pms_migration_owner')THEN CREATE ROLE mndf_pms_migration_owner NOLOGIN NOINHERIT NOBYPASSRLS;END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='mndf_pms_backup')THEN CREATE ROLE mndf_pms_backup NOLOGIN NOINHERIT NOBYPASSRLS;END IF;
END$$;
REVOKE ALL ON SCHEMA public FROM PUBLIC;GRANT USAGE ON SCHEMA public TO mndf_pms_runtime,mndf_pms_backup;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO mndf_pms_runtime;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO mndf_pms_runtime;
REVOKE INSERT,UPDATE,DELETE ON audit_logs FROM mndf_pms_runtime;
REVOKE ALL ON FUNCTION write_audit_event(uuid,text,text,uuid,jsonb,jsonb,text,uuid,uuid,boolean) FROM PUBLIC,mndf_pms_runtime;
REVOKE SELECT ON appraisal_comments FROM mndf_pms_runtime;
GRANT SELECT ON member_visible_appraisal_comments,official_appraisal_current_version,official_appraisal_current_ratings TO mndf_pms_runtime;
GRANT EXECUTE ON FUNCTION auth_lookup_login_account(text,text),record_operator_exception(uuid,uuid,text,text),read_restricted_comments_for_complaint(uuid,uuid,text),process_grievance_deadlines(uuid),refresh_tenant_recommendations(uuid) TO mndf_pms_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mndf_pms_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE mndf_pms_migration_owner IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO mndf_pms_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE mndf_pms_migration_owner IN SCHEMA public GRANT USAGE,SELECT ON SEQUENCES TO mndf_pms_runtime;
COMMIT;
