ALTER TYPE system_role ADD VALUE IF NOT EXISTS 'AUTHORIZER_HANDOVER';

BEGIN;

CREATE TABLE system_authorizer_transfers(
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  outgoing_account_id uuid NOT NULL,
  incoming_account_id uuid NOT NULL,
  initiated_by_account_id uuid NOT NULL,
  reason text NOT NULL CHECK(char_length(btrim(reason)) BETWEEN 1 AND 1000),
  transferred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  handover_expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(tenant_id,id),
  FOREIGN KEY(tenant_id,outgoing_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(tenant_id,incoming_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(tenant_id,initiated_by_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT,
  CHECK(outgoing_account_id<>incoming_account_id),
  CHECK(handover_expires_at=transferred_at+interval '3 days')
);

ALTER TABLE system_authorizer_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_authorizer_transfers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON system_authorizer_transfers USING(tenant_id=current_tenant_id()) WITH CHECK(tenant_id=current_tenant_id());
CREATE INDEX idx_authorizer_transfers_tenant_time ON system_authorizer_transfers(tenant_id,transferred_at DESC);
CREATE TRIGGER audit_system_authorizer_transfers AFTER INSERT OR UPDATE OR DELETE ON system_authorizer_transfers FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
GRANT SELECT,INSERT,UPDATE,DELETE ON system_authorizer_transfers TO mndf_pms_runtime;
GRANT SELECT ON system_authorizer_transfers TO mndf_pms_backup;

COMMIT;
