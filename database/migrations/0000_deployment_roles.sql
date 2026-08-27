BEGIN;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mndf_pms_runtime') THEN
    CREATE ROLE mndf_pms_runtime NOLOGIN NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mndf_pms_migration_owner') THEN
    CREATE ROLE mndf_pms_migration_owner NOLOGIN NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mndf_pms_backup') THEN
    CREATE ROLE mndf_pms_backup NOLOGIN NOINHERIT NOBYPASSRLS;
  END IF;
END $$;

GRANT USAGE, CREATE ON SCHEMA public TO mndf_pms_migration_owner;
DO $$BEGIN EXECUTE format('GRANT CREATE ON DATABASE %I TO mndf_pms_migration_owner',current_database());END$$;

COMMIT;
