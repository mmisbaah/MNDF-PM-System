import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";
import {
  validateRatingEvidence,
  type EvidenceInput,
} from "@/lib/evaluation/evidence";

export async function flagAdministrativeError(
  tenantId: string,
  accountId: string,
  appraisalId: string,
  reason: string,
) {
  if (!reason.trim())
    throw new EvaluationDomainError(
      "Error reason is required",
      422,
      "ERROR_REASON_REQUIRED",
    );
  return withTenantTransaction(
    tenantId,
    accountId,
    async (c) =>
      (
        await c.query(
          `INSERT INTO appraisal_admin_error_flags(tenant_id,appraisal_id,reason,flagged_by_account_id) VALUES($1,$2,$3,$4) RETURNING *`,
          [tenantId, appraisalId, reason.trim(), accountId],
        )
      ).rows[0],
  );
}
export async function authorizeReopening(
  tenantId: string,
  commanderId: string,
  appraisalId: string,
  input: {
    complaintId?: string;
    adminErrorFlagId?: string;
    correctionOfficerAccountId?: string;
    reason: string;
  },
) {
  if (
    !input.reason?.trim() ||
    Boolean(input.complaintId) === Boolean(input.adminErrorFlagId)
  )
    throw new EvaluationDomainError(
      "Provide a reason and exactly one reopening basis",
      422,
      "REOPEN_BASIS_REQUIRED",
    );
  if (!input.correctionOfficerAccountId)
    throw new EvaluationDomainError(
      "A correction officer from the evaluator chain is required",
      422,
      "CORRECTION_OFFICER_REQUIRED",
    );
  return withTenantTransaction(tenantId, commanderId, async (client) => {
    const result = await client.query(
      `INSERT INTO appraisal_reopen_authorizations
      (tenant_id,appraisal_id,complaint_id,admin_error_flag_id,admin_flag_reason,requested_by_account_id,authorized_by_account_id,correction_officer_account_id,reason,expires_at)
      SELECT $1,a.id,c.id,f.id,f.reason,COALESCE(f.flagged_by_account_id,ca.id),$5,$6,$7,clock_timestamp()+interval '5 days'
      FROM appraisals a
      LEFT JOIN complaints c ON c.tenant_id=a.tenant_id AND c.appraisal_id=a.id AND c.id=$3
      LEFT JOIN accounts ca ON ca.tenant_id=c.tenant_id AND ca.personnel_id=c.complainant_personnel_id
      LEFT JOIN appraisal_admin_error_flags f ON f.tenant_id=a.tenant_id AND f.appraisal_id=a.id
        AND f.id=$4 AND f.withdrawn_at IS NULL
      WHERE a.tenant_id=$1 AND a.id=$2 AND a.status='CLOSED'
        AND (($3::uuid IS NOT NULL AND c.id IS NOT NULL) OR ($4::uuid IS NOT NULL AND f.id IS NOT NULL))
      RETURNING id,appraisal_id,authorized_at,expires_at`,
      [
        tenantId,
        appraisalId,
        input.complaintId ?? null,
        input.adminErrorFlagId ?? null,
        commanderId,
        input.correctionOfficerAccountId ?? null,
        input.reason.trim(),
      ],
    );
    if (!result.rows[0])
      throw new EvaluationDomainError(
        "Complaint or formal administrative flag not found",
        404,
        "REOPEN_BASIS_NOT_FOUND",
      );
    return result.rows[0];
  });
}

export async function createCorrectionVersion(
  tenantId: string,
  accountId: string,
  authorizationId: string,
  reason: string,
) {
  if (!reason.trim())
    throw new EvaluationDomainError(
      "Correction reason is required",
      422,
      "CORRECTION_REASON_REQUIRED",
    );
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const auth = await client.query<{ appraisal_id: string }>(
      `UPDATE appraisal_reopen_authorizations SET used_at=clock_timestamp()
      WHERE tenant_id=$1 AND id=$2 AND correction_officer_account_id=$3 AND used_at IS NULL AND expires_at>=clock_timestamp() RETURNING appraisal_id`,
      [tenantId, authorizationId, accountId],
    );
    if (!auth.rows[0])
      throw new EvaluationDomainError(
        "Reopening authorization is missing, expired, or already used",
        409,
        "AUTHORIZATION_UNAVAILABLE",
      );
    const appraisalId = auth.rows[0].appraisal_id;
    const version = await client.query<{ id: string; version_no: number }>(
      `INSERT INTO appraisal_correction_versions
      (tenant_id,appraisal_id,authorization_id,version_no,reason,created_by_account_id)
      SELECT $1,$2,$3,COALESCE(max(version_no),0)+1,$4,$5 FROM appraisal_correction_versions WHERE tenant_id=$1 AND appraisal_id=$2
      RETURNING id,version_no`,
      [tenantId, appraisalId, authorizationId, reason.trim(), accountId],
    );
    await client.query(
      `INSERT INTO appraisal_correction_ratings(tenant_id,correction_version_id,criterion_id,original_rating_id,rating,justification,correction_reason)
      SELECT r.tenant_id,$3,r.criterion_id,r.id,r.rating,r.justification,$4 FROM appraisal_ratings r
      WHERE r.tenant_id=$1 AND r.appraisal_id=$2 AND r.is_final`,
      [
        tenantId,
        appraisalId,
        version.rows[0].id,
        "Original approved rating snapshot",
      ],
    );
    await client.query(
      `INSERT INTO correction_evidence_attachments(tenant_id,correction_rating_id,storage_key,original_filename,mime_type,byte_size,page_count,sha256_hex,malware_status,scanned_at,uploaded_by_account_id)
      SELECT ce.tenant_id,cr.id,ce.storage_key,ce.original_filename,ce.mime_type,ce.byte_size,ce.page_count,ce.sha256_hex,ce.malware_status,ce.scanned_at,$3
      FROM appraisal_correction_ratings cr JOIN evidence_attachments ce ON ce.tenant_id=cr.tenant_id AND ce.rating_id=cr.original_rating_id
      WHERE cr.tenant_id=$1 AND cr.correction_version_id=$2`,
      [tenantId, version.rows[0].id, accountId],
    );
    const reopened = await client.query(
      "UPDATE appraisals SET status='REOPENED',updated_at=clock_timestamp() WHERE tenant_id=$1 AND id=$2 AND status='CLOSED' RETURNING id",
      [tenantId, appraisalId],
    );
    if (!reopened.rows[0])
      throw new EvaluationDomainError(
        "Only a closed appraisal may be reopened",
        409,
        "APPRAISAL_NOT_CLOSED",
      );
    await client.query(
      `INSERT INTO correction_notifications(tenant_id,appraisal_id,correction_version_id,recipient_account_id,event_type,message)
      SELECT $1,$2,$3,ac.id,'REOPEN_AUTHORIZED',$4 FROM appraisals a JOIN accounts ac ON ac.tenant_id=a.tenant_id AND ac.personnel_id=a.personnel_id
      WHERE a.tenant_id=$1 AND a.id=$2`,
      [
        tenantId,
        appraisalId,
        version.rows[0].id,
        `A correction was authorized for appraisal ${appraisalId}`,
      ],
    );
    return { ...version.rows[0], appraisalId };
  });
}

export async function addCorrectedRating(
  tenantId: string,
  accountId: string,
  versionId: string,
  input: {
    criterionId: string;
    originalRatingId: string;
    rating: number;
    justification?: string;
    reason: string;
    evidence?: EvidenceInput;
  },
) {
  if (!input.reason?.trim())
    throw new EvaluationDomainError(
      "Per-rating correction reason is required",
      422,
      "RATING_REASON_REQUIRED",
    );
  validateRatingEvidence(
    input.rating,
    input.justification ?? null,
    input.evidence,
  );
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const ownership = await client.query(
      `SELECT 1 FROM appraisal_correction_versions cv JOIN appraisal_reopen_authorizations ra ON ra.tenant_id=cv.tenant_id AND ra.id=cv.authorization_id WHERE cv.tenant_id=$1 AND cv.id=$2 AND cv.status='DRAFT'AND ra.correction_officer_account_id=$3`,
      [tenantId, versionId, accountId],
    );
    if (!ownership.rowCount)
      throw new EvaluationDomainError(
        "Only the assigned correction officer may edit this draft correction",
        403,
        "CORRECTION_OFFICER_REQUIRED",
      );
    await client.query(
      `DELETE FROM correction_evidence_attachments WHERE tenant_id=$1 AND correction_rating_id IN(SELECT id FROM appraisal_correction_ratings WHERE tenant_id=$1 AND correction_version_id=$2 AND criterion_id=$3)`,
      [tenantId, versionId, input.criterionId],
    );
    await client.query(
      "DELETE FROM appraisal_correction_ratings WHERE tenant_id=$1 AND correction_version_id=$2 AND criterion_id=$3",
      [tenantId, versionId, input.criterionId],
    );
    const result = await client.query<{ id: string }>(
      `INSERT INTO appraisal_correction_ratings(tenant_id,correction_version_id,criterion_id,original_rating_id,rating,justification,correction_reason)
      VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [
        tenantId,
        versionId,
        input.criterionId,
        input.originalRatingId,
        input.rating,
        input.justification ?? null,
        input.reason.trim(),
      ],
    );
    if (input.evidence) {
      const attached = await client.query(
        `WITH claimed AS(UPDATE evidence_uploads SET consumed_at=clock_timestamp()WHERE tenant_id=$1 AND id=$3 AND uploaded_by_account_id=$4 AND consumed_at IS NULL RETURNING *)
      INSERT INTO correction_evidence_attachments(tenant_id,correction_rating_id,storage_key,original_filename,mime_type,byte_size,page_count,sha256_hex,malware_status,scanned_at,uploaded_by_account_id)
      SELECT $1,$2,storage_key,original_filename,mime_type,byte_size,page_count,sha256_hex,malware_status,scanned_at,$4 FROM claimed RETURNING id`,
        [tenantId, result.rows[0].id, input.evidence.uploadId, accountId],
      );
      if (!attached.rowCount)
        throw new EvaluationDomainError(
          "Evidence upload is unavailable, belongs to another account, or was already used",
          409,
          "EVIDENCE_UPLOAD_UNAVAILABLE",
        );
    }
    return result.rows[0];
  });
}

export async function transitionCorrection(
  tenantId: string,
  accountId: string,
  versionId: string,
  action: "submit" | "approve" | "reject",
  reason?: string,
) {
  if ((action === "approve" || action === "reject") && !reason?.trim())
    throw new EvaluationDomainError(
      "Decision reason is required",
      422,
      "DECISION_REASON_REQUIRED",
    );
  const status = {
    submit: "AWAITING_APPROVAL",
    approve: "APPROVED",
    reject: "REJECTED",
  }[action];
  return withTenantTransaction(tenantId, accountId, async (client) => {
    if (action === "submit") {
      const ownership = await client.query(
        `SELECT 1 FROM appraisal_correction_versions cv JOIN appraisal_reopen_authorizations ra ON ra.tenant_id=cv.tenant_id AND ra.id=cv.authorization_id WHERE cv.tenant_id=$1 AND cv.id=$2 AND cv.status='DRAFT'AND ra.correction_officer_account_id=$3`,
        [tenantId, versionId, accountId],
      );
      if (!ownership.rowCount)
        throw new EvaluationDomainError(
          "Only the assigned correction officer may submit this correction",
          403,
          "CORRECTION_OFFICER_REQUIRED",
        );
      const changed = await client.query(
        `SELECT 1 FROM appraisal_correction_ratings cr
         JOIN appraisal_ratings original ON original.tenant_id=cr.tenant_id AND original.id=cr.original_rating_id
         WHERE cr.tenant_id=$1 AND cr.correction_version_id=$2
           AND (cr.rating IS DISTINCT FROM original.rating
             OR COALESCE(cr.justification,'') IS DISTINCT FROM COALESCE(original.justification,''))
         LIMIT 1`,
        [tenantId, versionId],
      );
      if (!changed.rowCount)
        throw new EvaluationDomainError(
          "At least one rating or justification must be changed before submission",
          422,
          "CORRECTION_HAS_NO_CHANGES",
        );
    }
    const result = await client.query<{
      id: string;
      appraisal_id: string;
      status: string;
    }>(
      `UPDATE appraisal_correction_versions SET status=$3::correction_status,decision_reason=COALESCE($4,decision_reason)
      WHERE tenant_id=$1 AND id=$2 RETURNING id,appraisal_id,status::text`,
      [tenantId, versionId, status, reason?.trim() ?? null],
    );
    if (!result.rows[0])
      throw new EvaluationDomainError(
        "Correction version not found",
        404,
        "CORRECTION_NOT_FOUND",
      );
    if (action === "approve")
      await client.query(
        `UPDATE appraisals a SET status='CLOSED',total_points=cv.total_points,maximum_points=cv.maximum_points,
      score_percentage=cv.score_percentage,closed_at=clock_timestamp(),updated_at=clock_timestamp() FROM appraisal_correction_versions cv
      WHERE a.tenant_id=$1 AND a.id=cv.appraisal_id AND cv.id=$2`,
        [tenantId, versionId],
      );
    await client.query(
      `INSERT INTO correction_notifications(tenant_id,appraisal_id,correction_version_id,recipient_account_id,event_type,message)
      SELECT $1,$2,$3,ac.id,$4,$5 FROM appraisals a JOIN accounts ac ON ac.tenant_id=a.tenant_id AND ac.personnel_id=a.personnel_id
      WHERE a.tenant_id=$1 AND a.id=$2`,
      [
        tenantId,
        result.rows[0].appraisal_id,
        versionId,
        action === "submit"
          ? "CORRECTION_SUBMITTED"
          : action === "approve"
            ? "CORRECTION_APPROVED"
            : "CORRECTION_REJECTED",
        `Correction ${action} for appraisal ${result.rows[0].appraisal_id}`,
      ],
    );
    return result.rows[0];
  });
}
