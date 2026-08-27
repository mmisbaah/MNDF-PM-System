BEGIN;

CREATE OR REPLACE FUNCTION compute_audit_chain_hash(p_previous text,p_row audit_logs)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,pg_temp AS $$
 SELECT encode(digest(COALESCE(p_previous,'')||'|'||jsonb_build_object(
  'id',p_row.id,'tenantId',p_row.tenant_id,'occurredAt',p_row.occurred_at,
  'actorAccountId',p_row.actor_account_id,'actorPersonnelId',p_row.actor_personnel_id,
  'action',p_row.action,'entityTable',p_row.entity_table,'entityId',p_row.entity_id,
  'appraisalId',p_row.appraisal_id,'complaintId',p_row.complaint_id,
  'restrictedAccess',p_row.restricted_access,'reason',p_row.reason,
  'oldData',p_row.old_data,'newData',p_row.new_data,'requestId',p_row.request_id,
  'sourceIp',p_row.source_ip,'userAgent',p_row.user_agent)::text,'sha256'),'hex')
$$;

CREATE OR REPLACE FUNCTION seal_audit_insert()RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE v_previous text;BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.tenant_id::text,8041039));
 SELECT hash_chain_value INTO v_previous FROM audit_logs WHERE tenant_id=NEW.tenant_id ORDER BY id DESC LIMIT 1;
 NEW.hash_chain_value:=compute_audit_chain_hash(v_previous,NEW);RETURN NEW;
END$$;

DROP TRIGGER IF EXISTS audit_logs_seal_insert ON audit_logs;
CREATE TRIGGER audit_logs_seal_insert BEFORE INSERT ON audit_logs FOR EACH ROW EXECUTE FUNCTION seal_audit_insert();

ALTER TABLE audit_logs DISABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs DISABLE TRIGGER audit_logs_no_update_delete;
DO $$DECLARE v_tenant uuid;v_previous text;v_row audit_logs%ROWTYPE;BEGIN
 FOR v_tenant IN SELECT DISTINCT tenant_id FROM audit_logs ORDER BY tenant_id LOOP
  v_previous:=NULL;
  FOR v_row IN SELECT * FROM audit_logs WHERE tenant_id=v_tenant ORDER BY id LOOP
   v_previous:=compute_audit_chain_hash(v_previous,v_row);
   UPDATE audit_logs SET hash_chain_value=v_previous WHERE id=v_row.id;
  END LOOP;
 END LOOP;
END$$;
ALTER TABLE audit_logs ENABLE TRIGGER audit_logs_no_update_delete;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ALTER COLUMN hash_chain_value SET NOT NULL;

CREATE OR REPLACE FUNCTION verify_audit_hash_chain(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(valid boolean,bad_audit_id bigint) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_row audit_logs%ROWTYPE;v_tenant uuid;v_previous text;v_expected text;BEGIN
 FOR v_row IN SELECT * FROM audit_logs WHERE p_tenant_id IS NULL OR tenant_id=p_tenant_id ORDER BY tenant_id,id LOOP
  IF v_tenant IS DISTINCT FROM v_row.tenant_id THEN v_tenant:=v_row.tenant_id;v_previous:=NULL;END IF;
  v_expected:=compute_audit_chain_hash(v_previous,v_row);
  IF v_row.hash_chain_value IS DISTINCT FROM v_expected THEN valid:=false;bad_audit_id:=v_row.id;RETURN NEXT;RETURN;END IF;
  v_previous:=v_row.hash_chain_value;
 END LOOP;
 valid:=true;bad_audit_id:=NULL;RETURN NEXT;
END$$;
REVOKE ALL ON FUNCTION compute_audit_chain_hash(text,audit_logs),seal_audit_insert(),verify_audit_hash_chain(uuid) FROM PUBLIC,mndf_pms_runtime;
GRANT EXECUTE ON FUNCTION verify_audit_hash_chain(uuid) TO mndf_pms_backup;

COMMIT;
