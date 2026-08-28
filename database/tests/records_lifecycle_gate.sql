\set ON_ERROR_STOP on
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['retention_policy_versions','legal_holds','controlled_export_requests','record_disposal_requests','record_disposal_approvals']LOOP
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public'AND table_name=t AND column_name='tenant_id')THEN RAISE EXCEPTION'% lacks tenant_id',t;END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=('public.'||t)::regclass AND relrowsecurity AND relforcerowsecurity)THEN RAISE EXCEPTION'% lacks forced RLS',t;END IF;
 END LOOP;
 IF has_table_privilege('mndf_pms_runtime','retention_policy_versions','DELETE')THEN RAISE EXCEPTION'runtime may delete retention policy';END IF;
 IF has_table_privilege('mndf_pms_runtime','legal_holds','DELETE')THEN RAISE EXCEPTION'runtime may delete legal hold';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='record_disposal_approvals'::regclass AND tgname='disposal_approval_validate'AND tgenabled<>'D')THEN RAISE EXCEPTION'disposal approval validation missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='uq_retention_policy_approved')THEN RAISE EXCEPTION'one-approved-policy constraint missing';END IF;
END$$;
SELECT'records_lifecycle_gate_passed' result;

