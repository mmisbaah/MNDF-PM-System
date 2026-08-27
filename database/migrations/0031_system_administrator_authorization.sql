BEGIN;

CREATE TABLE system_administrator_authorizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  administrator_account_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'PENDING' CHECK(status IN('PENDING','APPROVED','REJECTED','EXPIRED')),
  operator_personnel_ids uuid[] NOT NULL CHECK(cardinality(operator_personnel_ids)>0),
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  decided_by_account_id uuid,
  decided_at timestamptz,
  decision_reason text CHECK(decision_reason IS NULL OR length(decision_reason) BETWEEN 1 AND 1000),
  valid_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(tenant_id,administrator_account_id) REFERENCES accounts(tenant_id,id),
  FOREIGN KEY(tenant_id,decided_by_account_id) REFERENCES accounts(tenant_id,id),
  CHECK((status='PENDING' AND decided_at IS NULL AND valid_until IS NULL) OR
        (status='APPROVED' AND decided_at IS NOT NULL AND valid_until=decided_at+interval '7 days') OR
        (status IN('REJECTED','EXPIRED') AND decided_at IS NOT NULL))
);

CREATE UNIQUE INDEX one_open_system_administrator_authorization
  ON system_administrator_authorizations(tenant_id,administrator_account_id)
  WHERE status IN('PENDING','APPROVED');
CREATE INDEX system_administrator_authorization_queue
  ON system_administrator_authorizations(tenant_id,status,requested_at DESC);

ALTER TABLE system_administrator_authorizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_administrator_authorizations FORCE ROW LEVEL SECURITY;
CREATE POLICY system_administrator_authorization_tenant_isolation ON system_administrator_authorizations
  USING(tenant_id=current_setting('app.tenant_id',true)::uuid)
  WITH CHECK(tenant_id=current_setting('app.tenant_id',true)::uuid);

CREATE TRIGGER audit_system_administrator_authorizations
AFTER INSERT OR UPDATE OR DELETE ON system_administrator_authorizations
FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

COMMIT;
