BEGIN;

CREATE TYPE mfa_factor_status AS ENUM ('PENDING', 'ACTIVE', 'DISABLED');

CREATE TABLE auth_sessions (
  id uuid NOT NULL,
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  account_id uuid NOT NULL,
  refresh_token_hash text NOT NULL CHECK (refresh_token_hash ~ '^[0-9a-f]{64}$'),
  ip_address inet NOT NULL,
  user_agent text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  rotated_at timestamptz,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE CASCADE,
  CHECK (expires_at > created_at),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);

CREATE TABLE account_mfa_factors (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  account_id uuid NOT NULL,
  encrypted_secret text NOT NULL CHECK (length(encrypted_secret) >= 40),
  status mfa_factor_status NOT NULL DEFAULT 'PENDING',
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, account_id),
  FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE CASCADE,
  CHECK ((status = 'ACTIVE') = (verified_at IS NOT NULL))
);

CREATE TABLE auth_login_events (
  id bigint GENERATED ALWAYS AS IDENTITY,
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  account_id uuid,
  normalized_email citext NOT NULL,
  ip_address inet NOT NULL,
  succeeded boolean NOT NULL,
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE SET NULL
);

CREATE TABLE operator_exception_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  operator_tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  operator_account_id uuid NOT NULL,
  target_account_id uuid,
  action text NOT NULL CHECK (action IN ('EMERGENCY_ACCOUNT_RECOVERY', 'SECURITY_INCIDENT_ACCESS')),
  reason text NOT NULL CHECK (length(btrim(reason)) >= 20),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (operator_tenant_id, operator_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, target_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_auth_sessions_account ON auth_sessions (tenant_id, account_id, expires_at) WHERE revoked_at IS NULL;
CREATE INDEX idx_auth_login_throttle ON auth_login_events (tenant_id, normalized_email, ip_address, occurred_at DESC) WHERE NOT succeeded;
CREATE INDEX idx_operator_exception_time ON operator_exception_requests (tenant_id, created_at DESC);

CREATE OR REPLACE FUNCTION enforce_technical_operator_separation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.role = 'TECHNICAL_OPERATOR' AND EXISTS (
    SELECT 1 FROM account_roles
    WHERE tenant_id = NEW.tenant_id AND account_id = NEW.account_id
      AND role <> 'TECHNICAL_OPERATOR'
      AND valid_from <= now() AND (valid_until IS NULL OR valid_until > now())
  ) THEN
    RAISE EXCEPTION 'technical operator accounts cannot hold ordinary unit roles';
  END IF;
  IF NEW.role <> 'TECHNICAL_OPERATOR' AND EXISTS (
    SELECT 1 FROM account_roles
    WHERE tenant_id = NEW.tenant_id AND account_id = NEW.account_id
      AND role = 'TECHNICAL_OPERATOR'
      AND valid_from <= now() AND (valid_until IS NULL OR valid_until > now())
  ) THEN
    RAISE EXCEPTION 'ordinary unit roles cannot be granted to technical operator accounts';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER account_roles_operator_separation
BEFORE INSERT OR UPDATE ON account_roles
FOR EACH ROW EXECUTE FUNCTION enforce_technical_operator_separation();

ALTER TABLE auth_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON auth_sessions
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

ALTER TABLE account_mfa_factors ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_mfa_factors FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON account_mfa_factors
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

ALTER TABLE auth_login_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_login_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON auth_login_events
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

ALTER TABLE operator_exception_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_exception_requests FORCE ROW LEVEL SECURITY;
CREATE POLICY target_tenant_isolation ON operator_exception_requests
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

-- Permits the security-definer login lookup to resolve only the exact supplied unit code.
CREATE POLICY tenant_login_lookup ON tenants FOR SELECT
  USING (code = NULLIF(current_setting('app.login_tenant_code', true), '')::citext);

CREATE OR REPLACE FUNCTION auth_lookup_login_account(p_tenant_code text, p_email text)
RETURNS TABLE (
  account_id uuid,
  tenant_id uuid,
  tenant_code text,
  email text,
  password_hash text,
  is_active boolean,
  mfa_enabled boolean,
  roles system_role[]
) LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp AS $$
DECLARE v_tenant_id uuid;
BEGIN
  PERFORM set_config('app.login_tenant_code', p_tenant_code, true);
  SELECT id INTO v_tenant_id FROM tenants WHERE code = p_tenant_code::citext;
  IF v_tenant_id IS NULL THEN RETURN; END IF;
  PERFORM set_config('app.tenant_id', v_tenant_id::text, true);

  RETURN QUERY
  SELECT a.id, a.tenant_id, t.code::text, a.email::text, a.password_hash,
         a.is_active AND t.status = 'ACTIVE', a.mfa_enabled,
         COALESCE(array_agg(ar.role) FILTER (WHERE ar.role IS NOT NULL), ARRAY[]::system_role[])
  FROM tenants t
  JOIN accounts a ON a.tenant_id = t.id
  LEFT JOIN account_roles ar
    ON ar.tenant_id = a.tenant_id AND ar.account_id = a.id
    AND ar.valid_from <= now() AND (ar.valid_until IS NULL OR ar.valid_until > now())
  WHERE t.id = v_tenant_id AND a.email = p_email::citext
  GROUP BY a.id, a.tenant_id, t.code, a.email, a.password_hash, a.is_active, t.status, a.mfa_enabled;
END
$$;

REVOKE ALL ON FUNCTION auth_lookup_login_account(text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION record_operator_exception(
  p_target_tenant_id uuid,
  p_target_account_id uuid,
  p_action text,
  p_reason text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_operator_tenant_id uuid := current_tenant_id();
  v_operator_account_id uuid := current_actor_account_id();
  v_request_id uuid;
BEGIN
  IF length(btrim(p_reason)) < 20 THEN RAISE EXCEPTION 'exception reason must contain at least 20 characters'; END IF;
  IF p_action NOT IN ('EMERGENCY_ACCOUNT_RECOVERY', 'SECURITY_INCIDENT_ACCESS') THEN RAISE EXCEPTION 'unsupported operator action'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM account_roles
    WHERE tenant_id = v_operator_tenant_id AND account_id = v_operator_account_id
      AND role = 'TECHNICAL_OPERATOR' AND valid_from <= now()
      AND (valid_until IS NULL OR valid_until > now())
  ) THEN RAISE EXCEPTION 'technical operator role required'; END IF;

  PERFORM set_config('app.tenant_id', p_target_tenant_id::text, true);
  INSERT INTO operator_exception_requests (
    tenant_id, operator_tenant_id, operator_account_id, target_account_id, action, reason
  ) VALUES (
    p_target_tenant_id, v_operator_tenant_id, v_operator_account_id, p_target_account_id, p_action, p_reason
  ) RETURNING id INTO v_request_id;

  PERFORM write_audit_event(
    p_target_tenant_id, 'TECHNICAL_OPERATOR_EXCEPTION_REQUEST', 'operator_exception_requests',
    v_request_id, NULL,
    jsonb_build_object('operator_tenant_id', v_operator_tenant_id, 'operator_account_id', v_operator_account_id,
                       'target_account_id', p_target_account_id, 'action', p_action),
    p_reason, NULL, NULL, true
  );
  RETURN v_request_id;
END;
$$;

REVOKE ALL ON FUNCTION record_operator_exception(uuid, uuid, text, text) FROM PUBLIC;

COMMIT;
