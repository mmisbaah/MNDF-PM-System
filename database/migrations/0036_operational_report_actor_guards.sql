BEGIN;

CREATE OR REPLACE FUNCTION operational_report_actor_is_supervisor(
  p_tenant uuid,
  p_account uuid,
  p_personnel uuid,
  p_period_start date,
  p_period_end date
) RETURNS boolean
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS(
    SELECT 1
    FROM accounts actor
    WHERE actor.tenant_id=p_tenant AND actor.id=p_account AND actor.is_active
      AND (
        EXISTS(
          SELECT 1 FROM evaluator_assignments assignment
          WHERE assignment.tenant_id=p_tenant
            AND assignment.evaluator_personnel_id=actor.personnel_id
            AND assignment.appraisee_personnel_id=p_personnel
            AND daterange(assignment.starts_on,COALESCE(assignment.ends_on,'infinity'::date),'[]')
                && daterange(p_period_start,p_period_end,'[]')
        )
        OR EXISTS(
          SELECT 1 FROM account_roles role
          WHERE role.tenant_id=p_tenant AND role.account_id=p_account
            AND role.role IN('FIRST_SERGEANT','EXECUTIVE_OFFICER','COMPANY_COMMANDER')
            AND role.valid_from<=clock_timestamp()
            AND(role.valid_until IS NULL OR role.valid_until>clock_timestamp())
        )
      )
  )
$$;

CREATE OR REPLACE FUNCTION enforce_operational_report_actor()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid := current_actor_account_id();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'operational report action requires an authenticated actor' USING ERRCODE='42501';
  END IF;

  IF TG_OP='INSERT' THEN
    IF NEW.created_by_account_id<>v_actor OR NOT operational_report_actor_is_supervisor(
      NEW.tenant_id,v_actor,NEW.personnel_id,NEW.period_start,NEW.period_end
    ) THEN
      RAISE EXCEPTION 'actor is not authorized to create this operational report' USING ERRCODE='42501';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP='DELETE' THEN
    IF OLD.status<>'DRAFT' OR OLD.created_by_account_id<>v_actor THEN
      RAISE EXCEPTION 'only the creator may delete a draft operational report' USING ERRCODE='42501';
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status='SUBMITTED' AND OLD.status='DRAFT' THEN
      IF OLD.created_by_account_id<>v_actor THEN
        RAISE EXCEPTION 'only the creator may submit an operational report' USING ERRCODE='42501';
      END IF;
    ELSIF NEW.status='CONFIRMED' AND OLD.status='SUBMITTED' THEN
      IF NOT operational_report_actor_is_supervisor(
        OLD.tenant_id,v_actor,OLD.personnel_id,OLD.period_start,OLD.period_end
      ) THEN
        RAISE EXCEPTION 'actor is not authorized to confirm this operational report' USING ERRCODE='42501';
      END IF;
    ELSE
      RAISE EXCEPTION 'invalid operational report transition' USING ERRCODE='23514';
    END IF;
  ELSIF OLD.status<>'DRAFT' OR OLD.created_by_account_id<>v_actor THEN
    RAISE EXCEPTION 'only the creator may edit a draft operational report' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS operational_report_actor_guard ON operational_reports;
CREATE TRIGGER operational_report_actor_guard
BEFORE INSERT OR UPDATE OR DELETE ON operational_reports
FOR EACH ROW EXECUTE FUNCTION enforce_operational_report_actor();

COMMIT;
