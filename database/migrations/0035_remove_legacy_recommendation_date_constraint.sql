\set ON_ERROR_STOP on

BEGIN;

-- Remove every legacy service-duration check that truncates timestamps to
-- dates. The named timestamp-precision constraint from 0033 remains active.
DO $$
DECLARE
  legacy record;
BEGIN
  FOR legacy IN
    SELECT con.conname
      FROM pg_constraint con
      JOIN pg_class rel ON rel.oid=con.conrelid
      JOIN pg_namespace ns ON ns.oid=rel.relnamespace
     WHERE ns.nspname='public'
       AND rel.relname='recommendations'
       AND con.contype='c'
       AND con.conname<>'recommendations_service_over_nine_months'
       AND pg_get_constraintdef(con.oid) ILIKE '%eligibility_checked_at%unit_service_started_on%'
       AND pg_get_constraintdef(con.oid) ILIKE '%::date%'
  LOOP
    EXECUTE format('ALTER TABLE recommendations DROP CONSTRAINT %I',legacy.conname);
  END LOOP;
END $$;

COMMIT;
