\set ON_ERROR_STOP on

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
  SELECT c.appraisal_id INTO v_appraisal FROM complaints c
  WHERE c.tenant_id = p_tenant_id AND c.id = p_complaint_id
    AND c.status IN ('ACCEPTED','UNDER_REVIEW','DECIDED');
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

  PERFORM write_audit_event(
    p_tenant_id, 'RESTRICTED_COMMENT_' || upper(p_action), 'complaints',
    p_complaint_id, NULL, NULL, 'case-scoped restricted comment list access',
    v_appraisal, p_complaint_id, true
  );

  FOR v_comment IN SELECT c.id, c.appraisal_id, c.author_account_id, c.body, c.created_at
    FROM appraisal_comments c WHERE c.tenant_id = p_tenant_id AND c.appraisal_id = v_appraisal
      AND c.visibility = 'RESTRICTED_SUPERVISORY' ORDER BY c.created_at
  LOOP
    comment_id := v_comment.id; appraisal_id := v_comment.appraisal_id;
    author_account_id := v_comment.author_account_id; body := v_comment.body; created_at := v_comment.created_at;
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION read_restricted_comments_for_complaint(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION read_restricted_comments_for_complaint(uuid, uuid, text) TO mndf_pms_runtime;
