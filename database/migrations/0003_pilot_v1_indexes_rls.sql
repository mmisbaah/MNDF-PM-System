BEGIN;

CREATE INDEX idx_personnel_status ON personnel (tenant_id, status);
CREATE INDEX idx_personnel_name ON personnel (tenant_id, lower(full_name));
CREATE INDEX idx_account_roles_active ON account_roles (tenant_id, account_id, role, valid_until);
CREATE INDEX idx_org_nodes_parent ON organizational_nodes (tenant_id, parent_id);
CREATE INDEX idx_personnel_appointments_current ON personnel_appointments (tenant_id, personnel_id, starts_on, ends_on);
CREATE UNIQUE INDEX uq_primary_appointment_start ON personnel_appointments (tenant_id, personnel_id, starts_on) WHERE is_primary;
CREATE INDEX idx_evaluator_assignments_active ON evaluator_assignments (tenant_id, appraisee_personnel_id, starts_on, ends_on, sequence_no);
CREATE INDEX idx_cycles_period ON evaluation_cycles (tenant_id, starts_on, ends_on, status);
CREATE INDEX idx_activity_person_date ON activity_records (tenant_id, personnel_id, activity_date DESC);
CREATE INDEX idx_activity_status ON activity_records (tenant_id, status, activity_date);
CREATE INDEX idx_disciplinary_open ON disciplinary_matters (tenant_id, personnel_id, status) WHERE status IN ('ALLEGED','UNDER_REVIEW','CONFIRMED');
CREATE INDEX idx_awol_open ON awol_incidents (tenant_id, personnel_id, status) WHERE status IN ('REPORTED','UNDER_REVIEW','CONFIRMED');
CREATE INDEX idx_appraisals_assignee_status ON appraisals (tenant_id, personnel_id, status);
CREATE INDEX idx_appraisals_cycle_status ON appraisals (tenant_id, cycle_id, status);
CREATE INDEX idx_chain_steps_evaluator ON evaluator_chain_steps (tenant_id, evaluator_account_id, status);
CREATE INDEX idx_ratings_appraisal_final ON appraisal_ratings (tenant_id, appraisal_id, criterion_id) WHERE is_final;
CREATE INDEX idx_score_adjustments_appraisal ON score_adjustments (tenant_id, appraisal_id, criterion_id, created_at);
CREATE INDEX idx_comments_appraisal_visibility ON appraisal_comments (tenant_id, appraisal_id, visibility, created_at);
CREATE INDEX idx_complaints_deadlines ON complaints (tenant_id, status, acceptance_deadline_at, decision_deadline_at);
CREATE INDEX idx_case_officers_account ON complaint_case_officers (tenant_id, account_id, complaint_id) WHERE removed_at IS NULL;
CREATE INDEX idx_recommendations_personnel ON recommendations (tenant_id, personnel_id, status);
CREATE INDEX idx_audit_tenant_time ON audit_logs (tenant_id, occurred_at DESC);
CREATE INDEX idx_audit_entity ON audit_logs (tenant_id, entity_table, entity_id, occurred_at DESC);
CREATE INDEX idx_audit_appraisal ON audit_logs (tenant_id, appraisal_id, occurred_at DESC) WHERE appraisal_id IS NOT NULL;
CREATE INDEX idx_audit_restricted ON audit_logs (tenant_id, complaint_id, occurred_at DESC) WHERE restricted_access;

-- Application transactions must set: SET LOCAL app.tenant_id = '<tenant uuid>'
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid
$$;

DO $enable_rls$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'personnel','accounts','account_roles','organizational_nodes','appointments',
    'personnel_appointments','evaluator_assignments','evaluation_templates','template_versions',
    'template_sections','criteria','evaluation_cycles','activity_records','activity_versions',
    'disciplinary_matters','awol_incidents','awol_incident_criteria','appraisals',
    'evaluator_chain_snapshots','evaluator_chain_steps','appraisal_ratings','score_adjustments','evidence_attachments',
    'appraisal_comments','complaints','complaint_case_officers','appraisal_reopen_authorizations',
    'recommendations','tenant_deletion_authorizations','audit_logs'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %I USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())', t
    );
  END LOOP;
END
$enable_rls$;

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_self_isolation ON tenants
  USING (id = current_tenant_id())
  WITH CHECK (id = current_tenant_id());

-- The application role must not own these tables or use BYPASSRLS.
-- Grant column/table privileges to a separate NOINHERIT/NOBYPASSRLS runtime role during deployment.

COMMIT;
