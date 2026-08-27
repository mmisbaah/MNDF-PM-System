\set ON_ERROR_STOP on

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
