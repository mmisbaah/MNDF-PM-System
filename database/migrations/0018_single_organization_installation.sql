\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE system_installation (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  tenant_id uuid UNIQUE REFERENCES tenants(id) ON DELETE RESTRICT,
  installation_status text NOT NULL CHECK (installation_status IN ('UNCONFIGURED','PENDING_ACTIVATION','ACTIVE')),
  configured_at timestamptz,
  activated_at timestamptz,
  CHECK ((installation_status='UNCONFIGURED')=(tenant_id IS NULL)),
  CHECK (configured_at IS NOT NULL OR installation_status='UNCONFIGURED')
);

INSERT INTO system_installation(singleton,tenant_id,installation_status,configured_at,activated_at)
SELECT true,id,CASE WHEN status='ACTIVE' THEN 'ACTIVE' ELSE 'PENDING_ACTIVATION' END,clock_timestamp(),
       CASE WHEN status='ACTIVE' THEN clock_timestamp() ELSE NULL END
FROM tenants ORDER BY created_at LIMIT 1;
INSERT INTO system_installation(singleton,tenant_id,installation_status)
SELECT true,NULL,'UNCONFIGURED' WHERE NOT EXISTS(SELECT 1 FROM system_installation);

REVOKE ALL ON system_installation FROM PUBLIC,mndf_pms_runtime;

CREATE OR REPLACE FUNCTION read_installation_identity()
RETURNS TABLE(configured boolean,installation_status text,tenant_id uuid,organization_name text,organization_code text)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
DECLARE v_tenant uuid;
BEGIN
  SELECT si.tenant_id INTO v_tenant FROM system_installation si WHERE si.singleton;
  IF v_tenant IS NOT NULL THEN PERFORM set_config('app.tenant_id',v_tenant::text,true); END IF;
  RETURN QUERY SELECT si.tenant_id IS NOT NULL,si.installation_status,si.tenant_id,t.name,t.code::text
  FROM system_installation si LEFT JOIN tenants t ON t.id=si.tenant_id WHERE si.singleton;
END
$$;
REVOKE ALL ON FUNCTION read_installation_identity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION read_installation_identity() TO mndf_pms_runtime;

CREATE OR REPLACE FUNCTION auth_lookup_login_account(p_tenant_code text,p_email text)
RETURNS TABLE(account_id uuid,tenant_id uuid,tenant_code text,email text,password_hash text,is_active boolean,mfa_enabled boolean,roles system_role[])
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
DECLARE v_tenant_id uuid;
BEGIN
  IF NULLIF(btrim(p_tenant_code),'') IS NULL THEN
    SELECT si.tenant_id INTO v_tenant_id FROM system_installation si WHERE si.singleton AND si.installation_status IN('PENDING_ACTIVATION','ACTIVE');
  ELSE
    SELECT id INTO v_tenant_id FROM tenants WHERE code=p_tenant_code::citext;
  END IF;
  IF v_tenant_id IS NULL THEN RETURN; END IF;
  PERFORM set_config('app.tenant_id',v_tenant_id::text,true);
  RETURN QUERY SELECT a.id,a.tenant_id,t.code::text,a.email::text,a.password_hash,
    a.is_active AND t.status='ACTIVE',a.mfa_enabled,
    COALESCE(array_agg(ar.role) FILTER(WHERE ar.role IS NOT NULL),ARRAY[]::system_role[])
  FROM tenants t JOIN accounts a ON a.tenant_id=t.id
  LEFT JOIN account_roles ar ON ar.tenant_id=a.tenant_id AND ar.account_id=a.id
    AND ar.valid_from<=now() AND(ar.valid_until IS NULL OR ar.valid_until>now())
  WHERE t.id=v_tenant_id AND a.email=p_email::citext
  GROUP BY a.id,a.tenant_id,t.code,a.email,a.password_hash,a.is_active,t.status,a.mfa_enabled;
END $$;
REVOKE ALL ON FUNCTION auth_lookup_login_account(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_lookup_login_account(text,text) TO mndf_pms_runtime;

COMMIT;
