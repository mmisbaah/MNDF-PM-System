BEGIN;

CREATE TYPE data_mode AS ENUM ('PRODUCTION','TRAINING');
CREATE TYPE operational_report_period AS ENUM ('WEEKLY','TWICE_MONTHLY','MONTHLY','EVERY_TWO_MONTHS');
CREATE TYPE operational_report_status AS ENUM ('DRAFT','SUBMITTED','CONFIRMED');

CREATE TABLE tenant_runtime_settings (
  tenant_id uuid PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  active_data_mode data_mode NOT NULL DEFAULT 'PRODUCTION',
  changed_by_account_id uuid NOT NULL, changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(tenant_id,changed_by_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT
);

ALTER TABLE evaluation_cycles ADD COLUMN data_mode data_mode NOT NULL DEFAULT 'PRODUCTION';
ALTER TABLE activity_records ADD COLUMN data_mode data_mode NOT NULL DEFAULT 'PRODUCTION';

CREATE TABLE operational_reports (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  personnel_id uuid NOT NULL, period_type operational_report_period NOT NULL, period_start date NOT NULL, period_end date NOT NULL,
  data_mode data_mode NOT NULL DEFAULT 'PRODUCTION', status operational_report_status NOT NULL DEFAULT 'DRAFT',
  progress text NOT NULL DEFAULT '', supervisor_feedback text NOT NULL DEFAULT '', challenges text NOT NULL DEFAULT '',
  training_requirements text NOT NULL DEFAULT '', created_by_account_id uuid NOT NULL,
  submitted_at timestamptz, confirmed_by_account_id uuid, confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(tenant_id,id), UNIQUE(tenant_id,personnel_id,period_type,period_start,data_mode),
  FOREIGN KEY(tenant_id,personnel_id) REFERENCES personnel(tenant_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(tenant_id,created_by_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(tenant_id,confirmed_by_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT,
  CHECK(period_end>=period_start), CHECK((status='CONFIRMED')=(confirmed_at IS NOT NULL))
);

CREATE TABLE operational_report_activities (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  operational_report_id uuid NOT NULL, activity_record_id uuid NOT NULL,
  PRIMARY KEY(tenant_id,id), UNIQUE(tenant_id,operational_report_id,activity_record_id),
  FOREIGN KEY(tenant_id,operational_report_id) REFERENCES operational_reports(tenant_id,id) ON DELETE CASCADE,
  FOREIGN KEY(tenant_id,activity_record_id) REFERENCES activity_records(tenant_id,id) ON DELETE RESTRICT
);

CREATE TABLE report_exports (
  id uuid NOT NULL DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL, format text NOT NULL CHECK(format IN('PDF','JSON')), data_mode data_mode NOT NULL,
  exported_by_account_id uuid NOT NULL, exported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(tenant_id,id), FOREIGN KEY(tenant_id,appraisal_id) REFERENCES appraisals(tenant_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(tenant_id,exported_by_account_id) REFERENCES accounts(tenant_id,id) ON DELETE RESTRICT
);

CREATE INDEX idx_operational_reports_period ON operational_reports(tenant_id,data_mode,period_start,period_end);
CREATE INDEX idx_cycles_reporting_mode ON evaluation_cycles(tenant_id,data_mode,cycle_type,ends_on);
CREATE INDEX idx_activities_reporting_mode ON activity_records(tenant_id,data_mode,activity_date);

DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['tenant_runtime_settings','operational_reports','operational_report_activities','report_exports'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t); EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id=current_tenant_id()) WITH CHECK (tenant_id=current_tenant_id())',t);
END LOOP; END $$;

CREATE OR REPLACE FUNCTION apply_active_data_mode() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v_mode data_mode; BEGIN
  SELECT active_data_mode INTO v_mode FROM tenant_runtime_settings WHERE tenant_id=NEW.tenant_id;
  NEW.data_mode:=COALESCE(v_mode,'PRODUCTION'); RETURN NEW; END $$;
CREATE TRIGGER cycles_apply_data_mode BEFORE INSERT ON evaluation_cycles FOR EACH ROW EXECUTE FUNCTION apply_active_data_mode();
CREATE TRIGGER activities_apply_data_mode BEFORE INSERT ON activity_records FOR EACH ROW EXECUTE FUNCTION apply_active_data_mode();
CREATE TRIGGER operational_reports_apply_data_mode BEFORE INSERT ON operational_reports FOR EACH ROW EXECUTE FUNCTION apply_active_data_mode();

CREATE OR REPLACE FUNCTION validate_training_mode_toggle() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  IF NEW.active_data_mode='TRAINING' AND NOT (current_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31') THEN
    RAISE EXCEPTION 'pilot training mode is available only during December 2026'; END IF;
  NEW.changed_at:=clock_timestamp(); NEW.changed_by_account_id:=current_actor_account_id(); RETURN NEW; END $$;
CREATE TRIGGER training_mode_toggle_validate BEFORE INSERT OR UPDATE ON tenant_runtime_settings FOR EACH ROW EXECUTE FUNCTION validate_training_mode_toggle();

CREATE OR REPLACE FUNCTION immutable_confirmed_operational_report() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  IF OLD.status='CONFIRMED' THEN RAISE EXCEPTION 'confirmed operational reports are immutable'; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  IF NEW.status='CONFIRMED' AND OLD.status='SUBMITTED' THEN NEW.confirmed_at:=clock_timestamp();NEW.confirmed_by_account_id:=current_actor_account_id();
  ELSIF NEW.status='SUBMITTED' AND OLD.status='DRAFT' THEN NEW.submitted_at:=clock_timestamp();
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN RAISE EXCEPTION 'invalid operational report transition'; END IF;
  NEW.updated_at:=clock_timestamp(); RETURN NEW; END $$;
CREATE TRIGGER operational_report_guard BEFORE UPDATE OR DELETE ON operational_reports FOR EACH ROW EXECUTE FUNCTION immutable_confirmed_operational_report();

CREATE TRIGGER audit_operational_reports AFTER INSERT OR UPDATE OR DELETE ON operational_reports FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
CREATE TRIGGER audit_report_exports AFTER INSERT OR UPDATE OR DELETE ON report_exports FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

COMMIT;
