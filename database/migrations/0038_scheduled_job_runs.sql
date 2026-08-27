BEGIN;
CREATE TABLE scheduled_job_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  job_type text NOT NULL CHECK (job_type IN ('GRIEVANCE_DEADLINES','CYCLE_LIFECYCLE','RECOMMENDATION_ELIGIBILITY')),
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at timestamptz,
  succeeded boolean,
  result jsonb,
  error_message text,
  PRIMARY KEY (tenant_id,id),
  CHECK ((finished_at IS NULL AND succeeded IS NULL) OR (finished_at IS NOT NULL AND succeeded IS NOT NULL)),
  CHECK (NOT COALESCE(succeeded,false) OR error_message IS NULL)
);
CREATE INDEX idx_scheduled_job_runs_recent ON scheduled_job_runs(tenant_id,job_type,started_at DESC);
ALTER TABLE scheduled_job_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE scheduled_job_runs FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON scheduled_job_runs USING(tenant_id=current_tenant_id()) WITH CHECK(tenant_id=current_tenant_id());
CREATE TRIGGER audit_scheduled_job_runs AFTER INSERT OR UPDATE OR DELETE ON scheduled_job_runs FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();
GRANT SELECT,INSERT,UPDATE ON scheduled_job_runs TO mndf_pms_runtime;
GRANT SELECT ON scheduled_job_runs TO mndf_pms_backup;
COMMIT;
