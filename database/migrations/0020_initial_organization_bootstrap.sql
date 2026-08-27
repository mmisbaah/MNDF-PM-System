\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS organization_level_definitions(
  id uuid NOT NULL DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  level_number smallint NOT NULL CHECK(level_number BETWEEN 1 AND 10),name text NOT NULL CHECK(btrim(name)<>''),
  code citext NOT NULL CHECK(btrim(code::text)<>''),active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(tenant_id,id),UNIQUE(tenant_id,level_number)
);

CREATE OR REPLACE FUNCTION bootstrap_single_organization(
  p_name text,
  p_code text,
  p_timezone text,
  p_nodes jsonb,
  p_authorizer_name text,
  p_authorizer_rank text,
  p_authorizer_appointment text,
  p_authorizer_login text,
  p_authorizer_password_hash text,
  p_admin_login text,
  p_admin_password_hash text
) RETURNS TABLE(tenant_id uuid, authorizer_account_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_tenant uuid:=gen_random_uuid();
  v_personnel uuid:=gen_random_uuid();
  v_authorizer uuid:=gen_random_uuid();
  v_root uuid:=gen_random_uuid();
  v_appointment uuid:=gen_random_uuid();
  v_item jsonb;
  v_role system_role;
  v_category text;
BEGIN
  PERFORM 1 FROM system_installation WHERE singleton FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM system_installation WHERE singleton AND installation_status='UNCONFIGURED') THEN
    RAISE EXCEPTION 'this installation is already configured';
  END IF;
  IF btrim(p_name)='' OR btrim(p_code)='' THEN RAISE EXCEPTION 'organization name and code are required'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_nodes,'[]'::jsonb)) item WHERE COALESCE((item->>'levelNumber')::integer,0) NOT BETWEEN 1 AND 10) THEN
    RAISE EXCEPTION 'organizational level numbers must be between 1 and 10';
  END IF;
  IF COALESCE(btrim(p_authorizer_appointment),'')='' THEN RAISE EXCEPTION 'system authorizer appointment is required'; END IF;

  PERFORM set_config('app.tenant_id',v_tenant::text,true);
  INSERT INTO tenants(id,code,name,status,timezone) VALUES(v_tenant,upper(btrim(p_code)),btrim(p_name),'ACTIVE',COALESCE(NULLIF(btrim(p_timezone),''),'Indian/Maldives'));
  v_category:='CIVILIAN';
  INSERT INTO personnel(id,tenant_id,personnel_code,full_name,rank_name,personnel_category,date_joined_service,unit_service_started_on)
  VALUES(v_personnel,v_tenant,'PILOT-AUTH-001',btrim(p_authorizer_name),btrim(p_authorizer_rank),v_category,current_date,current_date);
  INSERT INTO accounts(id,tenant_id,personnel_id,email,password_hash,is_active)
  VALUES(v_authorizer,v_tenant,v_personnel,lower(btrim(p_authorizer_login)),p_authorizer_password_hash,true);
  PERFORM set_config('app.account_id',v_authorizer::text,true);
  v_role:='COMPANY_COMMANDER';
  INSERT INTO account_roles(tenant_id,account_id,role,granted_by_account_id) VALUES(v_tenant,v_authorizer,v_role,v_authorizer);
  INSERT INTO account_roles(tenant_id,account_id,role,granted_by_account_id) VALUES(v_tenant,v_authorizer,'UNIT_ADMINISTRATOR',v_authorizer)
    ON CONFLICT DO NOTHING;

  INSERT INTO organizational_nodes(id,tenant_id,node_type,code,name,sort_order)
  VALUES(v_root,v_tenant,'ORGANIZATION',upper(btrim(p_code)),btrim(p_name),0);
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_nodes,'[]'::jsonb)) LOOP
    IF COALESCE(btrim(v_item->>'clientId'),'')='' OR COALESCE(btrim(v_item->>'name'),'')='' OR COALESCE(btrim(v_item->>'code'),'')='' THEN
      RAISE EXCEPTION 'each hierarchy entry requires an id, name, and code';
    END IF;
    INSERT INTO organization_level_definitions(tenant_id,level_number,name,code)
    VALUES(v_tenant,(v_item->>'levelNumber')::integer,btrim(v_item->>'name'),upper(btrim(v_item->>'code')));
  END LOOP;

  INSERT INTO appointments(id,tenant_id,organizational_node_id,appointment_type,title)
  VALUES(v_appointment,v_tenant,v_root,'OTHER',btrim(p_authorizer_appointment));
  INSERT INTO personnel_appointments(tenant_id,personnel_id,appointment_id,starts_on)
  VALUES(v_tenant,v_personnel,v_appointment,current_date);
  INSERT INTO accounts(tenant_id,email,password_hash,is_active)
  VALUES(v_tenant,lower(btrim(p_admin_login)),p_admin_password_hash,false);
  INSERT INTO account_roles(tenant_id,account_id,role,granted_by_account_id)
  SELECT v_tenant,a.id,'UNIT_ADMINISTRATOR',v_authorizer FROM accounts a WHERE a.tenant_id=v_tenant AND a.email=lower(btrim(p_admin_login))::citext;
  UPDATE system_installation SET tenant_id=v_tenant,installation_status='PENDING_ACTIVATION',configured_at=clock_timestamp(),activated_at=NULL WHERE singleton;
  RETURN QUERY SELECT v_tenant,v_authorizer;
END $$;

CREATE OR REPLACE FUNCTION activate_single_organization(p_tenant uuid,p_account uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM set_config('app.tenant_id',p_tenant::text,true);
  PERFORM set_config('app.account_id',p_account::text,true);
  IF NOT EXISTS(
    SELECT 1 FROM account_roles WHERE tenant_id=p_tenant AND account_id=p_account
      AND role IN('COMPANY_COMMANDER','EXECUTIVE_OFFICER','PLATOON_LEADER','FIRST_SERGEANT')
      AND valid_from<=clock_timestamp() AND(valid_until IS NULL OR valid_until>clock_timestamp())
  ) THEN RAISE EXCEPTION 'only the System Authorizer may activate this organization'; END IF;
  IF NOT EXISTS(SELECT 1 FROM accounts WHERE tenant_id=p_tenant AND id=p_account AND mfa_enabled) THEN
    RAISE EXCEPTION 'MFA enrollment is required before activation';
  END IF;
  UPDATE system_installation SET installation_status='ACTIVE',activated_at=clock_timestamp()
    WHERE singleton AND tenant_id=p_tenant AND installation_status='PENDING_ACTIVATION';
  IF NOT FOUND THEN RAISE EXCEPTION 'organization is not pending activation'; END IF;
  UPDATE accounts a SET is_active=true,updated_at=clock_timestamp()
    WHERE a.tenant_id=p_tenant AND a.personnel_id IS NULL
      AND EXISTS(SELECT 1 FROM account_roles r WHERE r.tenant_id=a.tenant_id AND r.account_id=a.id AND r.role='UNIT_ADMINISTRATOR');
END $$;

REVOKE ALL ON FUNCTION bootstrap_single_organization(text,text,text,jsonb,text,text,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION activate_single_organization(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bootstrap_single_organization(text,text,text,jsonb,text,text,text,text,text,text,text) TO mndf_pms_runtime;
GRANT EXECUTE ON FUNCTION activate_single_organization(uuid,uuid) TO mndf_pms_runtime;

COMMIT;
