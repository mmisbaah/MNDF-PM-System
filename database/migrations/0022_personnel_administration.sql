\set ON_ERROR_STOP on
BEGIN;

ALTER TABLE personnel_appointments ADD COLUMN role_description text NOT NULL DEFAULT '';

CREATE TRIGGER audit_personnel AFTER INSERT OR UPDATE OR DELETE ON personnel FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_appointments AFTER INSERT OR UPDATE OR DELETE ON appointments FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_personnel_appointments AFTER INSERT OR UPDATE OR DELETE ON personnel_appointments FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

COMMIT;
