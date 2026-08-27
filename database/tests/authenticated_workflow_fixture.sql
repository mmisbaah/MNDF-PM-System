\set ON_ERROR_STOP on

BEGIN;
CREATE TEMP TABLE regression_fixture_values(password_hash text NOT NULL) ON COMMIT DROP;
INSERT INTO regression_fixture_values VALUES (:'regression_password_hash');

DO $$
DECLARE
  v_tenant uuid := '860e116c-bdcf-412e-8498-689c0a65395a';
  v_commander_account uuid;
  v_rifleman uuid;
  v_rifleman_account uuid;
  v_squad_leader uuid;
  v_squad_account uuid;
  v_platoon_leader uuid;
  v_platoon_account uuid;
  v_template uuid;
  v_cycle uuid;
  v_appraisal uuid;
  v_snapshot uuid;
  v_hash text;
BEGIN
  SELECT password_hash INTO v_hash FROM regression_fixture_values;
  SELECT id INTO STRICT v_commander_account FROM accounts WHERE tenant_id=v_tenant AND email='commander02@pilot.test';
  SELECT id INTO STRICT v_rifleman FROM personnel WHERE tenant_id=v_tenant AND personnel_code='PTRIF001';
  SELECT id,personnel_id INTO STRICT v_squad_account,v_squad_leader FROM accounts WHERE tenant_id=v_tenant AND email='adminclerk@pilot.test';
  SELECT id,personnel_id INTO STRICT v_platoon_account,v_platoon_leader FROM accounts WHERE tenant_id=v_tenant AND email='adminincharge@pilot.test';
  SELECT tv.id INTO STRICT v_template FROM template_versions tv JOIN evaluation_templates et ON et.tenant_id=tv.tenant_id AND et.id=tv.template_id WHERE tv.tenant_id=v_tenant AND tv.status='PUBLISHED' AND et.is_baseline ORDER BY tv.version_no DESC LIMIT 1;

  UPDATE accounts SET password_hash=v_hash,must_change_password=false,password_changed_at=clock_timestamp(),updated_at=clock_timestamp()
    WHERE tenant_id=v_tenant AND id IN(v_squad_account,v_platoon_account,v_commander_account);
  SELECT id INTO v_rifleman_account FROM accounts WHERE tenant_id=v_tenant AND personnel_id=v_rifleman;
  IF v_rifleman_account IS NULL THEN
    v_rifleman_account:=gen_random_uuid();
    INSERT INTO accounts(id,tenant_id,personnel_id,email,password_hash,is_active,must_change_password)
      VALUES(v_rifleman_account,v_tenant,v_rifleman,'rifleman1@pilot.test',v_hash,true,false);
  ELSE
    UPDATE accounts SET password_hash=v_hash,is_active=true,must_change_password=false,password_changed_at=clock_timestamp(),updated_at=clock_timestamp()
      WHERE tenant_id=v_tenant AND id=v_rifleman_account;
  END IF;

  INSERT INTO account_roles(tenant_id,account_id,role,granted_by_account_id)
    SELECT v_tenant,x.account_id,x.role::system_role,v_commander_account
    FROM (VALUES(v_rifleman_account,'APPRAISEE'),(v_squad_account,'SQUAD_LEADER'),(v_platoon_account,'PLATOON_LEADER'))x(account_id,role)
    WHERE NOT EXISTS(SELECT 1 FROM account_roles ar WHERE ar.tenant_id=v_tenant AND ar.account_id=x.account_id AND ar.role=x.role::system_role AND(ar.valid_until IS NULL OR ar.valid_until>clock_timestamp()));

  SELECT id INTO v_cycle FROM evaluation_cycles WHERE tenant_id=v_tenant AND name='Authenticated Workflow Training';
  IF v_cycle IS NULL THEN
    v_cycle:=gen_random_uuid();
    INSERT INTO evaluation_cycles(id,tenant_id,template_version_id,name,cycle_type,starts_on,ends_on,status,opened_at,created_by_account_id,data_mode)
      VALUES(v_cycle,v_tenant,v_template,'Authenticated Workflow Training','QUARTERLY','2026-08-01','2026-08-31','OPEN',clock_timestamp(),v_commander_account,'TRAINING');
    UPDATE evaluation_cycles SET data_mode='TRAINING' WHERE tenant_id=v_tenant AND id=v_cycle;
  END IF;

  INSERT INTO evaluator_assignments(tenant_id,appraisee_personnel_id,evaluator_personnel_id,sequence_no,assignment_kind,starts_on,ends_on)
    SELECT v_tenant,v_rifleman,x.personnel_id,x.sequence_no,x.kind,'2026-08-01','2026-08-31'
    FROM (VALUES(v_squad_leader,1,'RATING'),(v_platoon_leader,2,'RATING'),((SELECT personnel_id FROM accounts WHERE tenant_id=v_tenant AND id=v_commander_account),3,'FINAL_APPROVAL'))x(personnel_id,sequence_no,kind)
    WHERE NOT EXISTS(SELECT 1 FROM evaluator_assignments ea WHERE ea.tenant_id=v_tenant AND ea.appraisee_personnel_id=v_rifleman AND ea.sequence_no=x.sequence_no AND ea.starts_on='2026-08-01');

  SELECT id INTO v_appraisal FROM appraisals WHERE tenant_id=v_tenant AND cycle_id=v_cycle AND personnel_id=v_rifleman;
  IF v_appraisal IS NULL THEN
    v_appraisal:=gen_random_uuid();v_snapshot:=gen_random_uuid();
    INSERT INTO appraisals(id,tenant_id,cycle_id,personnel_id,status,personnel_category_snapshot,appointment_type_snapshot)
      VALUES(v_appraisal,v_tenant,v_cycle,v_rifleman,'DRAFT','PRIVATE','RIFLEMAN');
    INSERT INTO evaluator_chain_snapshots(id,tenant_id,appraisal_id,snapshot_version,is_active,created_by_account_id)
      VALUES(v_snapshot,v_tenant,v_appraisal,1,true,v_commander_account);
    INSERT INTO evaluator_chain_steps(tenant_id,snapshot_id,evaluator_personnel_id,evaluator_account_id,sequence_no,step_kind,status)
      VALUES(v_tenant,v_snapshot,v_squad_leader,v_squad_account,1,'RATING','PENDING'),
            (v_tenant,v_snapshot,v_platoon_leader,v_platoon_account,2,'RATING','PENDING'),
            (v_tenant,v_snapshot,(SELECT personnel_id FROM accounts WHERE tenant_id=v_tenant AND id=v_commander_account),v_commander_account,3,'FINAL_APPROVAL','PENDING');
  END IF;
END $$;

SELECT 'authenticated_workflow_fixture_ready' AS result;
COMMIT;
