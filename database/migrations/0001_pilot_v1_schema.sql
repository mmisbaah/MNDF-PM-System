BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TYPE tenant_status AS ENUM ('PROVISIONING', 'ACTIVE', 'SUSPENDED', 'ARCHIVED', 'DELETION_PENDING');
CREATE TYPE personnel_status AS ENUM ('ACTIVE', 'POSTED_OUT', 'RETIRED', 'SEPARATED', 'SUSPENDED');
CREATE TYPE system_role AS ENUM (
  'APPRAISEE', 'SQUAD_LEADER', 'PLATOON_SERGEANT', 'PLATOON_LEADER',
  'FIRST_SERGEANT', 'EXECUTIVE_OFFICER', 'COMPANY_COMMANDER',
  'UNIT_ADMINISTRATOR', 'GRIEVANCE_OFFICER', 'AUDITOR', 'TECHNICAL_OPERATOR'
);
CREATE TYPE cycle_type AS ENUM ('QUARTERLY', 'HALF_YEAR', 'ANNUAL');
CREATE TYPE cycle_status AS ENUM ('DRAFT', 'OPEN', 'SELF_ASSESSMENT', 'EVALUATION', 'APPROVAL', 'CLOSED', 'ARCHIVED');
CREATE TYPE template_version_status AS ENUM ('DRAFT', 'PUBLISHED', 'RETIRED');
CREATE TYPE activity_status AS ENUM ('DRAFT', 'SUBMITTED', 'RETURNED', 'CONFIRMED', 'CORRECTION_REQUESTED', 'EDITABLE', 'UNCHANGED');
CREATE TYPE appraisal_status AS ENUM (
  'DRAFT', 'SELF_ASSESSMENT_SUBMITTED', 'IN_EVALUATION', 'RETURNED',
  'AWAITING_COMMANDER_APPROVAL', 'APPROVED', 'ACKNOWLEDGED',
  'COMPLAINT_OPEN', 'REOPENED', 'CLOSED'
);
CREATE TYPE evaluator_step_status AS ENUM ('PENDING', 'IN_PROGRESS', 'SUBMITTED', 'RETURNED', 'SKIPPED');
CREATE TYPE comment_visibility AS ENUM ('MEMBER_VISIBLE', 'RESTRICTED_SUPERVISORY');
CREATE TYPE malware_scan_status AS ENUM ('PENDING', 'CLEAN', 'INFECTED', 'FAILED');
CREATE TYPE complaint_status AS ENUM ('SUBMITTED', 'ACCEPTED', 'RETURNED', 'UNDER_REVIEW', 'DECIDED', 'CLOSED', 'OVERDUE');
CREATE TYPE complaint_decision AS ENUM ('UPHELD', 'PARTIALLY_UPHELD', 'REJECTED', 'WITHDRAWN');
CREATE TYPE recommendation_type AS ENUM ('PROMOTION', 'COMMENDATION');
CREATE TYPE recommendation_status AS ENUM ('INELIGIBLE', 'ELIGIBLE', 'NOMINATED', 'APPROVED', 'REJECTED', 'WITHDRAWN');
CREATE TYPE disciplinary_status AS ENUM ('ALLEGED', 'UNDER_REVIEW', 'CONFIRMED', 'RESOLVED', 'DISMISSED');
CREATE TYPE awol_status AS ENUM ('REPORTED', 'UNDER_REVIEW', 'CONFIRMED', 'RESOLVED', 'DISMISSED');
CREATE TYPE deletion_authorization_role AS ENUM ('UNIT_COMMANDER', 'SECOND_TIER_SUPERVISOR');

CREATE TABLE tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code citext NOT NULL UNIQUE,
  name text NOT NULL CHECK (btrim(name) <> ''),
  status tenant_status NOT NULL DEFAULT 'PROVISIONING',
  timezone text NOT NULL DEFAULT 'Indian/Maldives',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE personnel (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  personnel_code citext NOT NULL,
  full_name text NOT NULL CHECK (btrim(full_name) <> ''),
  rank_name text NOT NULL CHECK (btrim(rank_name) <> ''),
  personnel_category text NOT NULL CHECK (personnel_category IN ('OFFICER', 'NCO', 'PRIVATE', 'CIVILIAN')),
  date_joined_service date NOT NULL,
  unit_service_started_on date NOT NULL,
  email citext,
  phone text,
  status personnel_status NOT NULL DEFAULT 'ACTIVE',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, personnel_code),
  CHECK (unit_service_started_on >= date_joined_service)
);

CREATE TABLE accounts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  personnel_id uuid,
  email citext NOT NULL,
  password_hash text NOT NULL CHECK (length(password_hash) >= 20),
  is_active boolean NOT NULL DEFAULT true,
  mfa_enabled boolean NOT NULL DEFAULT false,
  password_changed_at timestamptz,
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, email),
  UNIQUE (tenant_id, personnel_id),
  FOREIGN KEY (tenant_id, personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE account_roles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  account_id uuid NOT NULL,
  role system_role NOT NULL,
  granted_by_account_id uuid,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, account_id, role, valid_from),
  FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE CASCADE,
  FOREIGN KEY (tenant_id, granted_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);

CREATE TABLE organizational_nodes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  parent_id uuid,
  node_type text NOT NULL CHECK (node_type IN ('COMPANY', 'HEADQUARTERS', 'PLATOON', 'SQUAD', 'OTHER')),
  code citext NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, code),
  FOREIGN KEY (tenant_id, parent_id) REFERENCES organizational_nodes(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE appointments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  organizational_node_id uuid NOT NULL,
  appointment_type text NOT NULL CHECK (appointment_type IN (
    'RIFLEMAN', 'SQUAD_LEADER', 'PLATOON_SERGEANT', 'PLATOON_LEADER',
    'FIRST_SERGEANT', 'EXECUTIVE_OFFICER', 'COMPANY_COMMANDER', 'OTHER'
  )),
  title text NOT NULL CHECK (btrim(title) <> ''),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, organizational_node_id) REFERENCES organizational_nodes(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE personnel_appointments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  personnel_id uuid NOT NULL,
  appointment_id uuid NOT NULL,
  starts_on date NOT NULL,
  ends_on date,
  is_primary boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, appointment_id) REFERENCES appointments(tenant_id, id) ON DELETE RESTRICT,
  CHECK (ends_on IS NULL OR ends_on >= starts_on)
);

CREATE TABLE evaluator_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisee_personnel_id uuid NOT NULL,
  evaluator_personnel_id uuid NOT NULL,
  sequence_no smallint NOT NULL CHECK (sequence_no BETWEEN 1 AND 10),
  assignment_kind text NOT NULL DEFAULT 'RATING' CHECK (assignment_kind IN ('RATING', 'COMMENT_ONLY', 'FINAL_APPROVAL')),
  starts_on date NOT NULL,
  ends_on date,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, appraisee_personnel_id, sequence_no, starts_on),
  FOREIGN KEY (tenant_id, appraisee_personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, evaluator_personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  CHECK (appraisee_personnel_id <> evaluator_personnel_id),
  CHECK (ends_on IS NULL OR ends_on >= starts_on)
);

CREATE TABLE evaluation_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (btrim(name) <> ''),
  is_baseline boolean NOT NULL DEFAULT false,
  created_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, created_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE template_versions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  template_id uuid NOT NULL,
  version_no integer NOT NULL CHECK (version_no > 0),
  status template_version_status NOT NULL DEFAULT 'DRAFT',
  effective_from date,
  published_at timestamptz,
  created_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, template_id, version_no),
  FOREIGN KEY (tenant_id, template_id) REFERENCES evaluation_templates(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, created_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK ((status = 'DRAFT') OR published_at IS NOT NULL)
);

CREATE TABLE template_sections (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  template_version_id uuid NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  display_order integer NOT NULL CHECK (display_order > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, template_version_id, display_order),
  FOREIGN KEY (tenant_id, template_version_id) REFERENCES template_versions(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE criteria (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  template_version_id uuid NOT NULL,
  section_id uuid NOT NULL,
  code citext NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  description text NOT NULL DEFAULT '',
  display_order integer NOT NULL CHECK (display_order > 0),
  is_unit_specific boolean NOT NULL DEFAULT false,
  applicable_categories text[] NOT NULL DEFAULT ARRAY['OFFICER','NCO','PRIVATE','CIVILIAN']::text[],
  requires_rating boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, template_version_id, code),
  UNIQUE (tenant_id, template_version_id, id),
  FOREIGN KEY (tenant_id, template_version_id) REFERENCES template_versions(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, section_id) REFERENCES template_sections(tenant_id, id) ON DELETE RESTRICT,
  CHECK (cardinality(applicable_categories) > 0),
  CHECK (applicable_categories <@ ARRAY['OFFICER','NCO','PRIVATE','CIVILIAN']::text[])
);

CREATE TABLE evaluation_cycles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  template_version_id uuid NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  cycle_type cycle_type NOT NULL,
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  status cycle_status NOT NULL DEFAULT 'DRAFT',
  opened_at timestamptz,
  closed_at timestamptz,
  created_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, name),
  FOREIGN KEY (tenant_id, template_version_id) REFERENCES template_versions(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, created_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (ends_on >= starts_on),
  CHECK ((status = 'DRAFT') OR opened_at IS NOT NULL)
);

CREATE TABLE activity_records (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  personnel_id uuid NOT NULL,
  activity_date date NOT NULL,
  status activity_status NOT NULL DEFAULT 'DRAFT',
  confirmed_by_account_id uuid,
  confirmed_at timestamptz,
  correction_authorized_by_account_id uuid,
  correction_authorized_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, confirmed_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, correction_authorized_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK ((status <> 'CONFIRMED') OR (confirmed_by_account_id IS NOT NULL AND confirmed_at IS NOT NULL)),
  CHECK (correction_authorized_until IS NULL OR correction_authorized_by_account_id IS NOT NULL)
);

CREATE TABLE activity_versions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  activity_record_id uuid NOT NULL,
  version_no integer NOT NULL CHECK (version_no > 0),
  title text NOT NULL CHECK (btrim(title) <> ''),
  description text NOT NULL CHECK (btrim(description) <> ''),
  outcome text,
  challenges text,
  lessons_learned text,
  is_confirmed_version boolean NOT NULL DEFAULT false,
  created_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, activity_record_id, version_no),
  FOREIGN KEY (tenant_id, activity_record_id) REFERENCES activity_records(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, created_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE disciplinary_matters (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  personnel_id uuid NOT NULL,
  reference_code text NOT NULL,
  occurred_on date,
  status disciplinary_status NOT NULL,
  summary text NOT NULL,
  resolved_at timestamptz,
  created_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, reference_code),
  FOREIGN KEY (tenant_id, personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, created_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK ((status NOT IN ('RESOLVED', 'DISMISSED')) OR resolved_at IS NOT NULL)
);

CREATE TABLE awol_incidents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  personnel_id uuid NOT NULL,
  status awol_status NOT NULL DEFAULT 'REPORTED',
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  reporting_authority_account_id uuid NOT NULL,
  reference text,
  resolution text,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, reporting_authority_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  CHECK ((status NOT IN ('RESOLVED', 'DISMISSED')) OR resolved_at IS NOT NULL)
);

CREATE TABLE awol_incident_criteria (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  awol_incident_id uuid NOT NULL,
  criterion_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, awol_incident_id, criterion_id),
  FOREIGN KEY (tenant_id, awol_incident_id) REFERENCES awol_incidents(tenant_id, id) ON DELETE CASCADE,
  FOREIGN KEY (tenant_id, criterion_id) REFERENCES criteria(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE appraisals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  cycle_id uuid NOT NULL,
  personnel_id uuid NOT NULL,
  status appraisal_status NOT NULL DEFAULT 'DRAFT',
  total_points numeric(10,2),
  maximum_points numeric(10,2),
  score_percentage numeric(5,2),
  available_to_member_at timestamptz,
  approved_by_account_id uuid,
  approved_at timestamptz,
  acknowledged_at timestamptz,
  closed_at timestamptz,
  row_version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, cycle_id, personnel_id),
  FOREIGN KEY (tenant_id, cycle_id) REFERENCES evaluation_cycles(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, approved_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (maximum_points IS NULL OR maximum_points > 0),
  CHECK (score_percentage IS NULL OR score_percentage BETWEEN 0 AND 100),
  CHECK ((approved_at IS NULL) = (approved_by_account_id IS NULL)),
  CHECK (available_to_member_at IS NULL OR approved_at IS NOT NULL)
);

CREATE TABLE evaluator_chain_snapshots (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL,
  snapshot_version integer NOT NULL CHECK (snapshot_version > 0),
  is_active boolean NOT NULL DEFAULT true,
  created_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  deactivated_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, appraisal_id, snapshot_version),
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, created_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK ((is_active AND deactivated_at IS NULL) OR (NOT is_active AND deactivated_at IS NOT NULL))
);

CREATE UNIQUE INDEX uq_one_active_evaluator_chain_per_appraisal
  ON evaluator_chain_snapshots (tenant_id, appraisal_id)
  WHERE is_active;

CREATE TABLE evaluator_chain_steps (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  snapshot_id uuid NOT NULL,
  evaluator_personnel_id uuid NOT NULL,
  evaluator_account_id uuid NOT NULL,
  sequence_no smallint NOT NULL CHECK (sequence_no BETWEEN 1 AND 10),
  step_kind text NOT NULL CHECK (step_kind IN ('RATING', 'COMMENT_ONLY', 'FINAL_APPROVAL')),
  status evaluator_step_status NOT NULL DEFAULT 'PENDING',
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, snapshot_id, sequence_no),
  FOREIGN KEY (tenant_id, snapshot_id) REFERENCES evaluator_chain_snapshots(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, evaluator_personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, evaluator_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE appraisal_ratings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL,
  criterion_id uuid NOT NULL,
  evaluator_step_id uuid NOT NULL,
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  justification text,
  is_final boolean NOT NULL DEFAULT false,
  supersedes_rating_id uuid,
  created_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, appraisal_id, criterion_id, evaluator_step_id),
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, criterion_id) REFERENCES criteria(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, evaluator_step_id) REFERENCES evaluator_chain_steps(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, supersedes_rating_id) REFERENCES appraisal_ratings(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, created_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (rating NOT IN (1,2,5) OR (justification IS NOT NULL AND btrim(justification) <> ''))
);

CREATE UNIQUE INDEX uq_final_rating_per_criterion
  ON appraisal_ratings (tenant_id, appraisal_id, criterion_id)
  WHERE is_final;

CREATE TABLE score_adjustments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL,
  criterion_id uuid NOT NULL,
  original_rating_id uuid NOT NULL,
  replacement_rating_id uuid NOT NULL,
  adjusted_by_account_id uuid NOT NULL,
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, replacement_rating_id),
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, criterion_id) REFERENCES criteria(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, original_rating_id) REFERENCES appraisal_ratings(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, replacement_rating_id) REFERENCES appraisal_ratings(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, adjusted_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (original_rating_id <> replacement_rating_id)
);

CREATE TABLE evidence_attachments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  rating_id uuid,
  activity_version_id uuid,
  storage_key text NOT NULL CHECK (btrim(storage_key) <> ''),
  original_filename text NOT NULL CHECK (btrim(original_filename) <> ''),
  mime_type text NOT NULL CHECK (mime_type IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')),
  byte_size integer NOT NULL CHECK (byte_size > 0 AND byte_size <= 5242880),
  page_count smallint NOT NULL DEFAULT 1 CHECK (page_count = 1),
  sha256_hex text NOT NULL CHECK (sha256_hex ~ '^[0-9a-fA-F]{64}$'),
  malware_status malware_scan_status NOT NULL DEFAULT 'PENDING',
  scanned_at timestamptz,
  uploaded_by_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, storage_key),
  UNIQUE (tenant_id, rating_id),
  FOREIGN KEY (tenant_id, rating_id) REFERENCES appraisal_ratings(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, activity_version_id) REFERENCES activity_versions(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, uploaded_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (num_nonnulls(rating_id, activity_version_id) = 1),
  CHECK ((malware_status = 'PENDING' AND scanned_at IS NULL) OR (malware_status <> 'PENDING' AND scanned_at IS NOT NULL))
);

CREATE TABLE appraisal_comments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL,
  evaluator_step_id uuid,
  author_account_id uuid NOT NULL,
  visibility comment_visibility NOT NULL,
  body text NOT NULL CHECK (btrim(body) <> ''),
  supersedes_comment_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, evaluator_step_id) REFERENCES evaluator_chain_steps(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, author_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, supersedes_comment_id) REFERENCES appraisal_comments(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE complaints (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL,
  complainant_personnel_id uuid NOT NULL,
  status complaint_status NOT NULL DEFAULT 'SUBMITTED',
  grounds text NOT NULL CHECK (btrim(grounds) <> ''),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  submission_deadline_at timestamptz NOT NULL,
  acceptance_deadline_at timestamptz NOT NULL,
  accepted_at timestamptz,
  accepted_by_account_id uuid,
  decision_deadline_at timestamptz,
  decided_at timestamptz,
  decided_by_account_id uuid,
  decision complaint_decision,
  decision_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, complainant_personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, accepted_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, decided_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (submitted_at <= submission_deadline_at),
  CHECK (acceptance_deadline_at = submitted_at + interval '3 days'),
  CHECK ((accepted_at IS NULL) = (accepted_by_account_id IS NULL)),
  CHECK (decision_deadline_at IS NULL OR decision_deadline_at = accepted_at + interval '5 days'),
  CHECK ((decided_at IS NULL) = (decision IS NULL)),
  CHECK (decision IS NULL OR (decided_by_account_id IS NOT NULL AND decision_reason IS NOT NULL AND btrim(decision_reason) <> ''))
);

CREATE TABLE complaint_case_officers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  complaint_id uuid NOT NULL,
  account_id uuid NOT NULL,
  assigned_by_account_id uuid NOT NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, complaint_id, account_id),
  FOREIGN KEY (tenant_id, complaint_id) REFERENCES complaints(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, assigned_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE appraisal_reopen_authorizations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appraisal_id uuid NOT NULL,
  complaint_id uuid,
  admin_flag_reason text,
  authorized_by_account_id uuid NOT NULL,
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  authorized_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  PRIMARY KEY (tenant_id, id),
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, complaint_id) REFERENCES complaints(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, authorized_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (num_nonnulls(complaint_id, admin_flag_reason) = 1),
  CHECK (expires_at = authorized_at + interval '5 days')
);

CREATE TABLE recommendations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  personnel_id uuid NOT NULL,
  annual_appraisal_id uuid NOT NULL,
  recommendation_type recommendation_type NOT NULL,
  status recommendation_status NOT NULL DEFAULT 'ELIGIBLE',
  eligibility_checked_at timestamptz NOT NULL DEFAULT now(),
  annual_score_percentage numeric(5,2) NOT NULL,
  has_rating_below_three boolean NOT NULL,
  has_unresolved_disciplinary_matter boolean NOT NULL,
  unit_service_started_on date NOT NULL,
  eligible boolean NOT NULL,
  nominated_by_account_id uuid,
  nomination_reason text,
  nominated_at timestamptz,
  decided_by_account_id uuid,
  decision_reason text,
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, personnel_id, annual_appraisal_id, recommendation_type),
  FOREIGN KEY (tenant_id, personnel_id) REFERENCES personnel(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, annual_appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, nominated_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, decided_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  CHECK (annual_score_percentage > 85 OR NOT eligible),
  CHECK (NOT eligible OR NOT has_rating_below_three),
  CHECK (NOT eligible OR NOT has_unresolved_disciplinary_matter),
  CHECK (NOT eligible OR eligibility_checked_at::date > (unit_service_started_on + interval '9 months')::date),
  CHECK ((status NOT IN ('NOMINATED', 'APPROVED')) OR (nominated_by_account_id IS NOT NULL AND nomination_reason IS NOT NULL)),
  CHECK ((status NOT IN ('APPROVED', 'REJECTED')) OR (decided_by_account_id IS NOT NULL AND decided_at IS NOT NULL AND decision_reason IS NOT NULL))
);

-- Retained independently of tenant deletion so the dual authorization record survives.
CREATE TABLE tenant_deletion_authorizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  tenant_code_snapshot text NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  requested_by_account_id uuid NOT NULL,
  authorization_role deletion_authorization_role NOT NULL,
  authorized_at timestamptz NOT NULL DEFAULT now(),
  authorization_reason text NOT NULL CHECK (btrim(authorization_reason) <> ''),
  revoked_at timestamptz,
  consumed_at timestamptz,
  UNIQUE (tenant_id, requested_by_account_id, authorization_role, requested_at)
);

-- Append-only and retained independently of tenant deletion.
CREATE TABLE audit_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_account_id uuid,
  actor_personnel_id uuid,
  action text NOT NULL CHECK (btrim(action) <> ''),
  entity_table text NOT NULL CHECK (btrim(entity_table) <> ''),
  entity_id uuid,
  appraisal_id uuid,
  complaint_id uuid,
  restricted_access boolean NOT NULL DEFAULT false,
  reason text,
  old_data jsonb,
  new_data jsonb,
  request_id uuid,
  source_ip inet,
  user_agent text,
  hash_chain_value text,
  CHECK (old_data IS NOT NULL OR new_data IS NOT NULL OR reason IS NOT NULL)
);

COMMIT;
