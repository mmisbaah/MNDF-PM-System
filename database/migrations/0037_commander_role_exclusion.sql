BEGIN;

UPDATE account_roles participant
SET valid_until=clock_timestamp()
WHERE participant.role IN('APPRAISEE','SQUAD_LEADER','PLATOON_SERGEANT','PLATOON_LEADER','FIRST_SERGEANT','EXECUTIVE_OFFICER','GRIEVANCE_OFFICER')
  AND participant.valid_from<clock_timestamp()
  AND(participant.valid_until IS NULL OR participant.valid_until>clock_timestamp())
  AND EXISTS(
    SELECT 1 FROM account_roles commander
    WHERE commander.tenant_id=participant.tenant_id
      AND commander.account_id=participant.account_id
      AND commander.role='COMPANY_COMMANDER'
      AND commander.valid_from<=clock_timestamp()
      AND(commander.valid_until IS NULL OR commander.valid_until>clock_timestamp())
  );

CREATE OR REPLACE FUNCTION prevent_commander_appraisal_role_overlap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=public,pg_temp
AS $$
DECLARE
  v_participant_roles constant system_role[]:=ARRAY[
    'APPRAISEE','SQUAD_LEADER','PLATOON_SERGEANT','PLATOON_LEADER',
    'FIRST_SERGEANT','EXECUTIVE_OFFICER','GRIEVANCE_OFFICER'
  ]::system_role[];
BEGIN
  IF NEW.role<>'COMPANY_COMMANDER' AND NOT(NEW.role=ANY(v_participant_roles)) THEN
    RETURN NEW;
  END IF;
  IF EXISTS(
    SELECT 1 FROM account_roles existing
    WHERE existing.tenant_id=NEW.tenant_id AND existing.account_id=NEW.account_id
      AND existing.id<>NEW.id
      AND (
        (NEW.role='COMPANY_COMMANDER' AND existing.role=ANY(v_participant_roles))
        OR(NEW.role=ANY(v_participant_roles) AND existing.role='COMPANY_COMMANDER')
      )
      AND tstzrange(existing.valid_from,COALESCE(existing.valid_until,'infinity'::timestamptz),'[)')
          && tstzrange(NEW.valid_from,COALESCE(NEW.valid_until,'infinity'::timestamptz),'[)')
  ) THEN
    RAISE EXCEPTION 'System Authorizer role cannot overlap ordinary appraisal-participant roles'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS commander_role_exclusion_guard ON account_roles;
CREATE TRIGGER commander_role_exclusion_guard
BEFORE INSERT OR UPDATE OF role,valid_from,valid_until ON account_roles
FOR EACH ROW EXECUTE FUNCTION prevent_commander_appraisal_role_overlap();

COMMIT;
