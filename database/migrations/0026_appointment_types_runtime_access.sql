BEGIN;

ALTER TABLE appointment_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_types FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON appointment_types
  USING (tenant_id=current_tenant_id())
  WITH CHECK (tenant_id=current_tenant_id());

GRANT SELECT,INSERT,UPDATE,DELETE ON appointment_types TO mndf_pms_runtime;
GRANT SELECT ON appointment_types TO mndf_pms_backup;

COMMIT;
