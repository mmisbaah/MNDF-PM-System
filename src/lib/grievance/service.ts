import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";

type ComplaintRow = {
  id: string; appraisal_id: string; status: string; grounds: string;
  submitted_at: Date; submission_deadline_at: Date; acceptance_deadline_at: Date;
  accepted_at: Date | null; decision_deadline_at: Date | null; decided_at: Date | null;
  decision: string | null; decision_reason: string | null; return_reason: string | null;
  is_overdue: boolean; overdue_stage: string | null; overdue_since: Date | null;
};

const complaintSelect = `SELECT id, appraisal_id, status::text, grounds, submitted_at,
  submission_deadline_at, acceptance_deadline_at, accepted_at, decision_deadline_at,
  decided_at, decision::text, decision_reason, return_reason, is_overdue, overdue_stage, overdue_since
  FROM complaints`;

export async function submitComplaint(tenantId: string, accountId: string, appraisalId: string, grounds: string) {
  if (!grounds.trim()) throw new EvaluationDomainError("Complaint grounds are required", 422, "GROUNDS_REQUIRED");
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query<ComplaintRow>(
      `INSERT INTO complaints (tenant_id, appraisal_id, complainant_personnel_id, grounds, submission_deadline_at, acceptance_deadline_at)
       SELECT $1, a.id, ac.personnel_id, $3, a.available_to_member_at + interval '3 days', clock_timestamp() + interval '3 days'
       FROM appraisals a JOIN accounts ac ON ac.tenant_id = a.tenant_id AND ac.id = $2
       WHERE a.tenant_id = $1 AND a.id = $4 AND a.personnel_id = ac.personnel_id
         AND a.approved_at IS NOT NULL AND a.available_to_member_at IS NOT NULL
       RETURNING id, appraisal_id, status::text, grounds, submitted_at, submission_deadline_at,
         acceptance_deadline_at, accepted_at, decision_deadline_at, decided_at, decision::text,
         decision_reason, return_reason, is_overdue, overdue_stage, overdue_since`,
      [tenantId, accountId, grounds.trim(), appraisalId],
    );
    if (!result.rows[0]) throw new EvaluationDomainError("Approved appraisal is unavailable or does not belong to this account", 404, "APPRAISAL_NOT_AVAILABLE");
    return result.rows[0];
  });
}

export async function getComplaint(tenantId: string, accountId: string, complaintId: string, canManage: boolean) {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query<ComplaintRow>(
      `${complaintSelect} c WHERE c.tenant_id = $1 AND c.id = $2 AND ($3 OR EXISTS (
        SELECT 1 FROM accounts ac WHERE ac.tenant_id = c.tenant_id AND ac.id = $4
          AND ac.personnel_id = c.complainant_personnel_id))`,
      [tenantId, complaintId, canManage, accountId],
    );
    if (!result.rows[0]) throw new EvaluationDomainError("Complaint not found", 404, "COMPLAINT_NOT_FOUND");
    return result.rows[0];
  });
}

export async function transitionComplaint(
  tenantId: string, accountId: string, complaintId: string,
  action: "accept" | "return" | "review" | "decide" | "close",
  data: { reason?: string; decision?: "UPHELD" | "PARTIALLY_UPHELD" | "REJECTED" | "WITHDRAWN" } = {},
) {
  const targets = { accept: "ACCEPTED", return: "RETURNED", review: "UNDER_REVIEW", decide: "DECIDED", close: "CLOSED" } as const;
  if ((action === "return" || action === "decide") && !data.reason?.trim())
    throw new EvaluationDomainError("A reason is required", 422, "REASON_REQUIRED");
  if (action === "decide" && !data.decision)
    throw new EvaluationDomainError("A decision is required", 422, "DECISION_REQUIRED");

  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query<ComplaintRow>(
      `UPDATE complaints SET status = $3::complaint_status,
         return_reason = CASE WHEN $3 = 'RETURNED' THEN $4 ELSE return_reason END,
         decision = CASE WHEN $3 = 'DECIDED' THEN $5::complaint_decision ELSE decision END,
         decision_reason = CASE WHEN $3 = 'DECIDED' THEN $4 ELSE decision_reason END
       WHERE tenant_id = $1 AND id = $2
       RETURNING id, appraisal_id, status::text, grounds, submitted_at, submission_deadline_at,
         acceptance_deadline_at, accepted_at, decision_deadline_at, decided_at, decision::text,
         decision_reason, return_reason, is_overdue, overdue_stage, overdue_since`,
      [tenantId, complaintId, targets[action], data.reason?.trim() ?? null, data.decision ?? null],
    );
    if (!result.rows[0]) throw new EvaluationDomainError("Complaint not found", 404, "COMPLAINT_NOT_FOUND");
    return result.rows[0];
  });
}

export async function assignCaseOfficer(tenantId: string, accountId: string, complaintId: string, officerAccountId: string) {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query<{ id: string }>(
      `INSERT INTO complaint_case_officers (tenant_id, complaint_id, account_id, assigned_by_account_id)
       SELECT $1, c.id, ac.id, $2 FROM complaints c JOIN accounts ac ON ac.tenant_id = c.tenant_id AND ac.id = $4 AND ac.is_active
       WHERE c.tenant_id = $1 AND c.id = $3 AND c.status IN ('ACCEPTED','UNDER_REVIEW')
       ON CONFLICT (tenant_id, complaint_id, account_id) DO UPDATE SET removed_at = NULL, assigned_at = clock_timestamp(), assigned_by_account_id = EXCLUDED.assigned_by_account_id
       RETURNING id`, [tenantId, accountId, complaintId, officerAccountId]);
    if (!result.rows[0]) throw new EvaluationDomainError("Accepted complaint or active officer account not found", 404, "CASE_ASSIGNMENT_INVALID");
    return result.rows[0];
  });
}

export async function readRestrictedComments(tenantId: string, accountId: string, complaintId: string, action = "VIEW") {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query(
      "SELECT * FROM read_restricted_comments_for_complaint($1, $2, $3)",
      [tenantId, complaintId, action],
    );
    return result.rows;
  });
}

export async function processDeadlines(tenantId: string) {
  return withTenantTransaction(tenantId, null, async (client) => {
    const result = await client.query<{ marked_overdue: number; released_notifications: number }>(
      "SELECT * FROM process_grievance_deadlines($1)", [tenantId]);
    return result.rows[0];
  });
}

export async function listNotifications(tenantId: string, accountId: string) {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query(
      `SELECT * FROM (
         SELECT 'GRIEVANCE' source,id,complaint_id,appraisal_id,event_type,title,body,
                deliver_at,delivered_at,read_at
         FROM grievance_notifications WHERE tenant_id=$1 AND recipient_account_id=$2 AND delivered_at IS NOT NULL
         UNION ALL
         SELECT 'CORRECTION' source,id,NULL::uuid complaint_id,appraisal_id,event_type,
                'Appraisal correction update' title,message body,created_at deliver_at,created_at delivered_at,read_at
         FROM correction_notifications WHERE tenant_id=$1 AND recipient_account_id=$2
       ) notifications ORDER BY deliver_at DESC LIMIT 100`, [tenantId, accountId]);
    return result.rows;
  });
}

export async function markNotificationRead(tenantId:string,accountId:string,id:string,source:"GRIEVANCE"|"CORRECTION"){
 return withTenantTransaction(tenantId,accountId,async client=>{
  const table=source==="GRIEVANCE"?"grievance_notifications":"correction_notifications";
  const result=await client.query(`UPDATE ${table} SET read_at=COALESCE(read_at,clock_timestamp()) WHERE tenant_id=$1 AND id=$2 AND recipient_account_id=$3 RETURNING id,read_at`,[tenantId,id,accountId]);
  if(!result.rows[0])throw new EvaluationDomainError("Notification not found",404,"NOTIFICATION_NOT_FOUND");
  return result.rows[0];
 });
}
