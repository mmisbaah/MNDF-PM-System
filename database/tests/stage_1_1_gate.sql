\set ON_ERROR_STOP on
DO $$DECLARE v_missing text;BEGIN
 SELECT string_agg(c.relname,', ')INTO v_missing FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public'AND c.relkind='r'AND c.relname<>'tenants'AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='tenant_id'AND NOT a.attisdropped);
 IF v_missing IS NOT NULL THEN RAISE EXCEPTION'operational tables without tenant_id: %',v_missing;END IF;
 SELECT string_agg(c.relname,', ')INTO v_missing FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public'AND c.relkind='r'AND c.relname NOT IN('schema_migrations','system_installation')AND(NOT c.relrowsecurity OR NOT c.relforcerowsecurity);
 IF v_missing IS NOT NULL THEN RAISE EXCEPTION'tables without forced RLS: %',v_missing;END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('mndf_pms_runtime','mndf_pms_migration_owner','mndf_pms_backup')AND rolbypassrls)THEN RAISE EXCEPTION'deployment role has BYPASSRLS';END IF;
 IF has_function_privilege('mndf_pms_runtime','write_audit_event(uuid,text,text,uuid,jsonb,jsonb,text,uuid,uuid,boolean)','EXECUTE')THEN RAISE EXCEPTION'runtime can directly write audit events';END IF;
 IF NOT(SELECT prosecdef FROM pg_proc WHERE oid='audit_sensitive_change()'::regprocedure)THEN RAISE EXCEPTION'audit trigger function is not SECURITY DEFINER';END IF;
 IF has_table_privilege('mndf_pms_runtime','appraisal_comments','SELECT')THEN RAISE EXCEPTION'runtime has direct comment-table read access';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='correction_rating_actor'AND NOT tgisinternal)THEN RAISE EXCEPTION'correction actor trigger missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='activity_confirmer_guard'AND NOT tgisinternal)THEN RAISE EXCEPTION'activity confirmer trigger missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='appraisal_closer_guard'AND NOT tgisinternal)THEN RAISE EXCEPTION'appraisal closer trigger missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint con JOIN pg_class rel ON rel.oid=con.conrelid JOIN pg_namespace ns ON ns.oid=rel.relnamespace
   WHERE ns.nspname='public'AND rel.relname='recommendations'AND con.conname='recommendations_service_over_nine_months'
   AND pg_get_constraintdef(con.oid)ILIKE'%eligibility_checked_at >%unit_service_started_on%'
   AND pg_get_constraintdef(con.oid)NOT ILIKE'%::date%')THEN RAISE EXCEPTION'recommendation service threshold must use exact timestamp precision';END IF;
 IF EXISTS(SELECT 1 FROM pg_constraint con JOIN pg_class rel ON rel.oid=con.conrelid JOIN pg_namespace ns ON ns.oid=rel.relnamespace
   WHERE ns.nspname='public'AND rel.relname='recommendations'AND con.contype='c'
   AND pg_get_constraintdef(con.oid)ILIKE'%eligibility_checked_at%unit_service_started_on%'
   AND pg_get_constraintdef(con.oid)ILIKE'%::date%')THEN RAISE EXCEPTION'legacy date-truncated recommendation threshold remains';END IF;
 IF pg_get_functiondef('recalculate_recommendations(uuid,uuid)'::regprocedure)NOT ILIKE'%(CASE WHEN v_eligible THEN ''ELIGIBLE'' ELSE ''INELIGIBLE'' END)::recommendation_status%'
   THEN RAISE EXCEPTION'recommendation engine must cast computed status to recommendation_status';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='operational_report_actor_guard'AND NOT tgisinternal)
   THEN RAISE EXCEPTION'operational report actor guard missing';END IF;
 IF pg_get_functiondef('enforce_operational_report_actor()'::regprocedure)NOT ILIKE'%only the creator may submit%'
   OR pg_get_functiondef('enforce_operational_report_actor()'::regprocedure)NOT ILIKE'%not authorized to confirm%'
   THEN RAISE EXCEPTION'operational report actor workflow enforcement is incomplete';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='commander_role_exclusion_guard'AND NOT tgisinternal)
   THEN RAISE EXCEPTION'commander role exclusion guard missing';END IF;
 IF EXISTS(
   SELECT 1 FROM account_roles commander JOIN account_roles participant
     ON participant.tenant_id=commander.tenant_id AND participant.account_id=commander.account_id
   WHERE commander.role='COMPANY_COMMANDER'
     AND participant.role IN('APPRAISEE','SQUAD_LEADER','PLATOON_SERGEANT','PLATOON_LEADER','FIRST_SERGEANT','EXECUTIVE_OFFICER','GRIEVANCE_OFFICER')
     AND commander.valid_from<=clock_timestamp() AND(commander.valid_until IS NULL OR commander.valid_until>clock_timestamp())
     AND participant.valid_from<=clock_timestamp() AND(participant.valid_until IS NULL OR participant.valid_until>clock_timestamp())
 ) THEN RAISE EXCEPTION'commander role overlaps ordinary appraisal-participant role';END IF;
END$$;
SELECT 'stage_1_1_database_gate_passed' AS result;
