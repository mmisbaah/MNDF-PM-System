BEGIN;

ALTER TABLE complaints
  ADD COLUMN returned_at timestamptz,
  ADD COLUMN returned_by_account_id uuid,
  ADD COLUMN return_reason text,
  ADD COLUMN is_overdue boolean NOT NULL DEFAULT false,
  ADD COLUMN overdue_stage text,
  ADD COLUMN overdue_since timestamptz,
  ADD FOREIGN KEY (tenant_id, returned_by_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
  ADD CHECK ((returned_at IS NULL) = (returned_by_account_id IS NULL)),
  ADD CHECK (returned_at IS NULL OR (return_reason IS NOT NULL AND btrim(return_reason) <> '')),
  ADD CHECK (overdue_stage IS NULL OR overdue_stage IN ('ACCEPTANCE', 'DECISION')),
  ADD CHECK ((is_overdue AND overdue_stage IS NOT NULL AND overdue_since IS NOT NULL)
          OR (NOT is_overdue AND overdue_stage IS NULL AND overdue_since IS NULL));

CREATE TABLE grievance_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  recipient_account_id uuid NOT NULL,
  complaint_id uuid,
  appraisal_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN (
    'SUBMISSION_DUE_SOON', 'SUBMISSION_EXPIRED',
    'ACCEPTANCE_DUE_SOON', 'ACCEPTANCE_EXPIRED',
    'DECISION_DUE_SOON', 'DECISION_EXPIRED'
  )),
  title text NOT NULL CHECK (btrim(title) <> ''),
  body text NOT NULL CHECK (btrim(body) <> ''),
  deliver_at timestamptz NOT NULL,
  delivered_at timestamptz,
  read_at timestamptz,
  deduplication_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, deduplication_key),
  FOREIGN KEY (tenant_id, recipient_account_id) REFERENCES accounts(tenant_id, id) ON DELETE CASCADE,
  FOREIGN KEY (tenant_id, complaint_id) REFERENCES complaints(tenant_id, id) ON DELETE CASCADE,
  FOREIGN KEY (tenant_id, appraisal_id) REFERENCES appraisals(tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX idx_grievance_notifications_delivery
  ON grievance_notifications (tenant_id, deliver_at) WHERE delivered_at IS NULL;
CREATE INDEX idx_grievance_notifications_recipient
  ON grievance_notifications (tenant_id, recipient_account_id, created_at DESC);
CREATE INDEX idx_complaints_open_overdue
  ON complaints (tenant_id, is_overdue, overdue_since)
  WHERE status IN ('SUBMITTED', 'ACCEPTED', 'UNDER_REVIEW');

ALTER TABLE grievance_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE grievance_notifications FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON grievance_notifications
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

CREATE OR REPLACE FUNCTION enforce_complaint_state_machine()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_now timestamptz := clock_timestamp();
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.status := 'SUBMITTED';
    RETURN NEW;
  END IF;

  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF NOT ((OLD.status = 'SUBMITTED' AND NEW.status IN ('ACCEPTED', 'RETURNED')) OR
          (OLD.status = 'ACCEPTED' AND NEW.status IN ('UNDER_REVIEW', 'DECIDED')) OR
          (OLD.status = 'UNDER_REVIEW' AND NEW.status = 'DECIDED') OR
          (OLD.status = 'DECIDED' AND NEW.status = 'CLOSED')) THEN
    RAISE EXCEPTION 'invalid complaint transition: % -> %', OLD.status, NEW.status;
  END IF;

  IF NEW.status = 'ACCEPTED' THEN
    NEW.accepted_at := v_now;
    NEW.accepted_by_account_id := current_actor_account_id();
    NEW.decision_deadline_at := v_now + interval '5 days';
    NEW.is_overdue := false;
    NEW.overdue_stage := NULL;
    NEW.overdue_since := NULL;
  ELSIF NEW.status = 'RETURNED' THEN
    NEW.returned_at := v_now;
    NEW.returned_by_account_id := current_actor_account_id();
  ELSIF NEW.status = 'DECIDED' THEN
    NEW.decided_at := v_now;
    NEW.decided_by_account_id := current_actor_account_id();
  END IF;
  NEW.updated_at := v_now;
  RETURN NEW;
END;
$$;

CREATE TRIGGER complaints_state_machine
BEFORE INSERT OR UPDATE OF status ON complaints
FOR EACH ROW EXECUTE FUNCTION enforce_complaint_state_machine();

CREATE OR REPLACE FUNCTION derive_complaint_deadlines()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_available_at timestamptz;
BEGIN
  SELECT available_to_member_at INTO v_available_at FROM appraisals
  WHERE tenant_id = NEW.tenant_id AND id = NEW.appraisal_id AND personnel_id = NEW.complainant_personnel_id;
  IF v_available_at IS NULL THEN RAISE EXCEPTION 'complaint requires an appraisal made available to the same personnel'; END IF;
  IF TG_OP = 'INSERT' THEN NEW.submitted_at := clock_timestamp(); END IF;
  NEW.submission_deadline_at := v_available_at + interval '3 days';
  NEW.acceptance_deadline_at := NEW.submitted_at + interval '3 days';
  IF NEW.submitted_at > NEW.submission_deadline_at THEN RAISE EXCEPTION 'complaint submission deadline has passed'; END IF;
  NEW.decision_deadline_at := CASE WHEN NEW.accepted_at IS NULL THEN NULL ELSE NEW.accepted_at + interval '5 days' END;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION schedule_submission_notifications()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_account uuid; v_deadline timestamptz;
BEGIN
  IF NEW.available_to_member_at IS NULL OR NEW.available_to_member_at IS NOT DISTINCT FROM OLD.available_to_member_at THEN RETURN NEW; END IF;
  v_deadline := NEW.available_to_member_at + interval '3 days';
  SELECT id INTO v_account FROM accounts WHERE tenant_id = NEW.tenant_id AND personnel_id = NEW.personnel_id AND is_active;
  IF v_account IS NULL THEN RETURN NEW; END IF;
  INSERT INTO grievance_notifications
    (tenant_id, recipient_account_id, appraisal_id, event_type, title, body, deliver_at, deduplication_key)
  VALUES
    (NEW.tenant_id, v_account, NEW.id, 'SUBMISSION_DUE_SOON', 'Complaint submission deadline approaching',
     'The complaint window for appraisal ' || NEW.id || ' closes at ' || v_deadline::text,
     GREATEST(clock_timestamp(), v_deadline - interval '24 hours'), NEW.id || ':SUBMISSION:24H:' || v_account),
    (NEW.tenant_id, v_account, NEW.id, 'SUBMISSION_DUE_SOON', 'Complaint submission deadline approaching',
     'The complaint window for appraisal ' || NEW.id || ' closes at ' || v_deadline::text,
     GREATEST(clock_timestamp(), v_deadline - interval '1 hour'), NEW.id || ':SUBMISSION:1H:' || v_account),
    (NEW.tenant_id, v_account, NEW.id, 'SUBMISSION_EXPIRED', 'Complaint submission window expired',
     'The complaint window for appraisal ' || NEW.id || ' closed at ' || v_deadline::text,
     v_deadline, NEW.id || ':SUBMISSION:EXPIRED:' || v_account)
  ON CONFLICT (tenant_id, deduplication_key) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER appraisals_schedule_complaint_window_notifications
AFTER UPDATE OF available_to_member_at ON appraisals
FOR EACH ROW EXECUTE FUNCTION schedule_submission_notifications();

CREATE OR REPLACE FUNCTION schedule_grievance_notifications()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_account uuid;
  v_deadline timestamptz;
  v_stage text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_deadline := NEW.acceptance_deadline_at; v_stage := 'ACCEPTANCE';
  ELSIF NEW.status = 'ACCEPTED' AND OLD.status <> 'ACCEPTED' THEN
    v_deadline := NEW.decision_deadline_at; v_stage := 'DECISION';
  ELSE
    RETURN NEW;
  END IF;

  FOR v_account IN
    SELECT DISTINCT ar.account_id FROM account_roles ar
    WHERE ar.tenant_id = NEW.tenant_id
      AND ar.role IN ('FIRST_SERGEANT', 'EXECUTIVE_OFFICER', 'COMPANY_COMMANDER')
      AND ar.valid_from <= current_date AND (ar.valid_until IS NULL OR ar.valid_until > current_date)
    UNION
    SELECT cco.account_id FROM complaint_case_officers cco
    WHERE cco.tenant_id = NEW.tenant_id AND cco.complaint_id = NEW.id AND cco.removed_at IS NULL
  LOOP
    INSERT INTO grievance_notifications
      (tenant_id, recipient_account_id, complaint_id, appraisal_id, event_type, title, body, deliver_at, deduplication_key)
    VALUES
      (NEW.tenant_id, v_account, NEW.id, NEW.appraisal_id, v_stage || '_DUE_SOON',
       v_stage || ' deadline approaching', 'Complaint ' || NEW.id || ' is due at ' || v_deadline::text,
       GREATEST(clock_timestamp(), v_deadline - interval '24 hours'), NEW.id || ':' || v_stage || ':24H:' || v_account),
      (NEW.tenant_id, v_account, NEW.id, NEW.appraisal_id, v_stage || '_DUE_SOON',
       v_stage || ' deadline approaching', 'Complaint ' || NEW.id || ' is due at ' || v_deadline::text,
       GREATEST(clock_timestamp(), v_deadline - interval '1 hour'), NEW.id || ':' || v_stage || ':1H:' || v_account),
      (NEW.tenant_id, v_account, NEW.id, NEW.appraisal_id, v_stage || '_EXPIRED',
       v_stage || ' deadline expired', 'Complaint remains open and is overdue since ' || v_deadline::text,
       v_deadline, NEW.id || ':' || v_stage || ':EXPIRED:' || v_account)
    ON CONFLICT (tenant_id, deduplication_key) DO NOTHING;
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE TRIGGER complaints_schedule_notifications
AFTER INSERT OR UPDATE OF status ON complaints
FOR EACH ROW EXECUTE FUNCTION schedule_grievance_notifications();

CREATE OR REPLACE FUNCTION process_grievance_deadlines(p_tenant_id uuid)
RETURNS TABLE(marked_overdue integer, released_notifications integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_marked integer; v_released integer;
BEGIN
  IF p_tenant_id IS DISTINCT FROM current_tenant_id() THEN RAISE EXCEPTION 'tenant context mismatch'; END IF;
  WITH changed AS (
    UPDATE complaints c SET
      is_overdue = true,
      overdue_stage = CASE WHEN c.status = 'SUBMITTED' THEN 'ACCEPTANCE' ELSE 'DECISION' END,
      overdue_since = CASE WHEN c.status = 'SUBMITTED' THEN c.acceptance_deadline_at ELSE c.decision_deadline_at END,
      updated_at = clock_timestamp()
    WHERE c.tenant_id = p_tenant_id AND NOT c.is_overdue
      AND ((c.status = 'SUBMITTED' AND c.acceptance_deadline_at < clock_timestamp()) OR
           (c.status IN ('ACCEPTED','UNDER_REVIEW') AND c.decision_deadline_at < clock_timestamp()))
    RETURNING 1
  ) SELECT count(*)::integer INTO v_marked FROM changed;

  WITH changed AS (
    UPDATE grievance_notifications SET delivered_at = clock_timestamp()
    WHERE tenant_id = p_tenant_id AND delivered_at IS NULL AND deliver_at <= clock_timestamp()
    RETURNING 1
  ) SELECT count(*)::integer INTO v_released FROM changed;
  RETURN QUERY SELECT v_marked, v_released;
END;
$$;

CREATE OR REPLACE FUNCTION read_restricted_comments_for_complaint(
  p_tenant_id uuid, p_complaint_id uuid, p_action text DEFAULT 'VIEW'
) RETURNS TABLE (
  comment_id uuid, appraisal_id uuid, author_account_id uuid, body text, created_at timestamptz
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_actor uuid := current_actor_account_id(); v_appraisal uuid; v_comment record; v_allowed boolean;
BEGIN
  IF p_tenant_id IS DISTINCT FROM current_tenant_id() OR v_actor IS NULL THEN
    RAISE EXCEPTION 'authenticated tenant context required';
  END IF;
  SELECT appraisal_id INTO v_appraisal FROM complaints
  WHERE tenant_id = p_tenant_id AND id = p_complaint_id AND status IN ('ACCEPTED','UNDER_REVIEW','DECIDED');
  IF NOT FOUND THEN RAISE EXCEPTION 'accepted complaint not found'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM account_roles ar WHERE ar.tenant_id = p_tenant_id AND ar.account_id = v_actor
      AND ar.role IN ('FIRST_SERGEANT','EXECUTIVE_OFFICER','COMPANY_COMMANDER')
      AND ar.valid_from <= current_date AND (ar.valid_until IS NULL OR ar.valid_until > current_date)
    UNION ALL
    SELECT 1 FROM complaint_case_officers cco WHERE cco.tenant_id = p_tenant_id
      AND cco.complaint_id = p_complaint_id AND cco.account_id = v_actor AND cco.removed_at IS NULL
  ) INTO v_allowed;
  IF NOT v_allowed THEN RAISE EXCEPTION 'restricted comment access denied'; END IF;

  FOR v_comment IN SELECT c.id, c.appraisal_id, c.author_account_id, c.body, c.created_at
    FROM appraisal_comments c WHERE c.tenant_id = p_tenant_id AND c.appraisal_id = v_appraisal
      AND c.visibility = 'RESTRICTED_SUPERVISORY' ORDER BY c.created_at
  LOOP
    PERFORM write_audit_event(p_tenant_id, 'RESTRICTED_COMMENT_' || upper(p_action), 'appraisal_comments',
      v_comment.id, NULL, NULL, 'case-scoped grievance access', v_appraisal, p_complaint_id, true);
    comment_id := v_comment.id; appraisal_id := v_comment.appraisal_id;
    author_account_id := v_comment.author_account_id; body := v_comment.body; created_at := v_comment.created_at;
    RETURN NEXT;
  END LOOP;
END;
$$;

-- Disable the former evaluator-seniority access path; all grievance reads must be case-scoped.
DROP FUNCTION read_restricted_comment(uuid, uuid, uuid, text);
CREATE FUNCTION read_restricted_comment(p_tenant_id uuid,p_comment_id uuid,p_complaint_id uuid,p_reason text)
RETURNS TABLE (comment_id uuid, appraisal_id uuid, author_account_id uuid, body text, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN RAISE EXCEPTION 'use read_restricted_comments_for_complaint'; END;
$$;
REVOKE ALL ON FUNCTION read_restricted_comment(uuid, uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION read_restricted_comments_for_complaint(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION process_grievance_deadlines(uuid) FROM PUBLIC;

COMMIT;
