\set ON_ERROR_STOP on

BEGIN;

-- Keep the table constraint aligned with the eligibility engine's exact
-- timestamp comparison. The original date casts could reject a valid result
-- reached later on the exact nine-month threshold date.
DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT con.conname
    INTO constraint_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace ns ON ns.oid = rel.relnamespace
   WHERE ns.nspname = 'public'
     AND rel.relname = 'recommendations'
     AND con.contype = 'c'
     AND pg_get_constraintdef(con.oid) ILIKE '%eligibility_checked_at%unit_service_started_on%9 months%';

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE recommendations DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

ALTER TABLE recommendations
  ADD CONSTRAINT recommendations_service_over_nine_months
  CHECK (
    NOT eligible
    OR eligibility_checked_at > unit_service_started_on::timestamp + interval '9 months'
  );

COMMIT;
