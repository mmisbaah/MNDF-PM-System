import { randomUUID } from "node:crypto";
import { withTenantTransaction } from "@/lib/auth/repository";
import { validateRatingEvidence, type EvidenceInput } from "./evidence";
import { EvaluationDomainError } from "./errors";

export type SubmitRatingInput = {
  criterionId: string;
  rating: number;
  justification?: string | null;
  evidence?: EvidenceInput;
};

export async function submitRating(
  tenantId: string,
  accountId: string,
  appraisalId: string,
  input: SubmitRatingInput,
) {
  validateRatingEvidence(
    input.rating,
    input.justification ?? null,
    input.evidence,
  );
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const context = await client.query<{
      appraisal_status: string;
      cycle_status: string;
      evaluator_step_id: string;
      step_kind: string;
      step_status: string;
      prior_steps_complete: boolean;
      applicable: boolean;
    }>(
      `SELECT a.status::text AS appraisal_status, cy.status::text AS cycle_status,
              step.id AS evaluator_step_id, step.step_kind,
              step.status::text AS step_status,
              NOT EXISTS (
                SELECT 1 FROM evaluator_chain_steps prior
                WHERE prior.tenant_id = step.tenant_id AND prior.snapshot_id = step.snapshot_id
                  AND prior.sequence_no < step.sequence_no AND prior.status <> 'SUBMITTED'
              ) AS prior_steps_complete,
              (a.personnel_category_snapshot = ANY(cr.applicable_categories)
               AND (cr.applicable_appointment_types IS NULL
                    OR a.appointment_type_snapshot = ANY(cr.applicable_appointment_types))) AS applicable
       FROM appraisals a
       JOIN evaluation_cycles cy ON cy.tenant_id = a.tenant_id AND cy.id = a.cycle_id
       JOIN criteria cr ON cr.tenant_id = cy.tenant_id
         AND cr.template_version_id = cy.template_version_id AND cr.id = $3
       JOIN evaluator_chain_snapshots snap ON snap.tenant_id = a.tenant_id
         AND snap.appraisal_id = a.id AND snap.is_active
       JOIN evaluator_chain_steps step ON step.tenant_id = snap.tenant_id
         AND step.snapshot_id = snap.id AND step.evaluator_account_id = $4
       WHERE a.tenant_id = $1 AND a.id = $2
       FOR UPDATE OF a`,
      [tenantId, appraisalId, input.criterionId, accountId],
    );
    const row = context.rows[0];
    if (!row)
      throw new EvaluationDomainError(
        "Appraisal, criterion, or assigned evaluator step not found",
        404,
        "RATING_CONTEXT_NOT_FOUND",
      );
    if (row.cycle_status === "CLOSED" || row.cycle_status === "ARCHIVED") {
      throw new EvaluationDomainError(
        "The appraisal cycle is closed and no longer accepts rating changes",
        409,
        "EVALUATION_CYCLE_CLOSED",
      );
    }
    if (
      ![
        "DRAFT",
        "SELF_ASSESSMENT_SUBMITTED",
        "IN_EVALUATION",
        "RETURNED",
        "REOPENED",
      ].includes(row.appraisal_status)
    ) {
      throw new EvaluationDomainError(
        "This appraisal cannot accept rating changes",
        409,
        "APPRAISAL_IMMUTABLE",
      );
    }
    if (row.step_kind === "COMMENT_ONLY")
      throw new EvaluationDomainError(
        "Comment-only evaluator steps cannot submit ratings",
        403,
        "COMMENT_ONLY_STEP",
      );
    if (row.step_status === "SUBMITTED" || row.step_status === "SKIPPED") {
      throw new EvaluationDomainError(
        "This evaluator step has already been finalized",
        409,
        "EVALUATOR_STEP_FINALIZED",
      );
    }
    if (!row.prior_steps_complete) {
      throw new EvaluationDomainError(
        "Earlier evaluator steps must be submitted first",
        409,
        "EVALUATOR_SEQUENCE_BLOCKED",
      );
    }
    if (!row.applicable)
      throw new EvaluationDomainError(
        "Criterion is not applicable to this personnel category or appointment",
        422,
        "CRITERION_NOT_APPLICABLE",
      );

    const previous = await client.query<{ id: string }>(
      `SELECT id FROM appraisal_ratings
       WHERE tenant_id = $1 AND appraisal_id = $2 AND criterion_id = $3 AND is_final
       FOR UPDATE`,
      [tenantId, appraisalId, input.criterionId],
    );
    const previousId = previous.rows[0]?.id ?? null;
    if (previousId) {
      await client.query(
        "UPDATE appraisal_ratings SET is_final = false, updated_at = now() WHERE tenant_id = $1 AND id = $2",
        [tenantId, previousId],
      );
    }

    const ratingId = randomUUID();
    await client.query(
      `INSERT INTO appraisal_ratings
       (id, tenant_id, appraisal_id, criterion_id, evaluator_step_id, rating, justification,
        is_final, supersedes_rating_id, created_by_account_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,true,$8,$9)`,
      [
        ratingId,
        tenantId,
        appraisalId,
        input.criterionId,
        row.evaluator_step_id,
        input.rating,
        input.justification?.trim() || null,
        previousId,
        accountId,
      ],
    );
    if (input.evidence) {
      const inserted = await client.query(
        `WITH claimed AS(UPDATE evidence_uploads SET consumed_at=clock_timestamp()
          WHERE tenant_id=$2 AND id=$4 AND uploaded_by_account_id=$9 AND consumed_at IS NULL RETURNING *)
         INSERT INTO evidence_attachments
         (id, tenant_id, rating_id, storage_key, original_filename, mime_type,
          byte_size, page_count, sha256_hex, malware_status, uploaded_by_account_id)
         SELECT $1,$2,$3,storage_key,original_filename,mime_type,byte_size,page_count,sha256_hex,malware_status,$9 FROM claimed RETURNING id`,
        [
          randomUUID(),
          tenantId,
          ratingId,
          input.evidence.uploadId,
          null,
          null,
          null,
          null,
          accountId,
        ],
      );
      if (!inserted.rowCount)
        throw new EvaluationDomainError(
          "Evidence upload is unavailable, belongs to another account, or was already used",
          409,
          "EVIDENCE_UPLOAD_UNAVAILABLE",
        );
    }
    await client.query(
      `UPDATE appraisals SET status = 'IN_EVALUATION', row_version = row_version + 1, updated_at = now()
       WHERE tenant_id = $1 AND id = $2 AND status IN ('DRAFT','SELF_ASSESSMENT_SUBMITTED','RETURNED')`,
      [tenantId, appraisalId],
    );
    return {
      ratingId,
      supersedesRatingId: previousId,
      evidenceStatus: input.evidence ? "PENDING" : null,
    };
  });
}

export async function submitEvaluatorStep(
  tenantId: string,
  accountId: string,
  appraisalId: string,
) {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const context = await client.query<{
      step_id: string;
      step_kind: string;
      step_status: string;
      expected_ratings: number;
      submitted_ratings: number;
      prior_steps_complete: boolean;
      evidence_clean: boolean;
    }>(
      `SELECT step.id AS step_id, step.step_kind, step.status::text AS step_status,
              (SELECT count(*) FROM criteria cr
               JOIN evaluation_cycles cy ON cy.tenant_id = cr.tenant_id AND cy.template_version_id = cr.template_version_id
               WHERE cy.tenant_id = a.tenant_id AND cy.id = a.cycle_id AND cr.requires_rating
                 AND a.personnel_category_snapshot = ANY(cr.applicable_categories)
                 AND (cr.applicable_appointment_types IS NULL
                      OR a.appointment_type_snapshot = ANY(cr.applicable_appointment_types)))::int AS expected_ratings,
              (SELECT count(*) FROM appraisal_ratings r
               WHERE r.tenant_id = a.tenant_id AND r.appraisal_id = a.id
                 AND r.evaluator_step_id = step.id AND r.is_final)::int AS submitted_ratings,
              NOT EXISTS (
                SELECT 1 FROM evaluator_chain_steps prior
                WHERE prior.tenant_id = step.tenant_id AND prior.snapshot_id = step.snapshot_id
                  AND prior.sequence_no < step.sequence_no AND prior.status <> 'SUBMITTED'
              ) AS prior_steps_complete,
              NOT EXISTS (
                SELECT 1 FROM appraisal_ratings r
                LEFT JOIN evidence_attachments e
                  ON e.tenant_id = r.tenant_id AND e.rating_id = r.id
                WHERE r.tenant_id = a.tenant_id AND r.appraisal_id = a.id
                  AND r.evaluator_step_id = step.id AND r.is_final
                  AND r.rating IN (1,2,5)
                  AND (e.id IS NULL OR e.malware_status <> 'CLEAN')
              ) AS evidence_clean
       FROM appraisals a
       JOIN evaluation_cycles cycle ON cycle.tenant_id = a.tenant_id AND cycle.id = a.cycle_id
       JOIN evaluator_chain_snapshots snap ON snap.tenant_id = a.tenant_id
         AND snap.appraisal_id = a.id AND snap.is_active
       JOIN evaluator_chain_steps step ON step.tenant_id = snap.tenant_id
         AND step.snapshot_id = snap.id AND step.evaluator_account_id = $3
       WHERE a.tenant_id = $1 AND a.id = $2
         AND cycle.status NOT IN ('CLOSED','ARCHIVED')
         AND a.status IN ('DRAFT','SELF_ASSESSMENT_SUBMITTED','IN_EVALUATION','RETURNED','REOPENED')
       FOR UPDATE OF a, step`,
      [tenantId, appraisalId, accountId],
    );
    const row = context.rows[0];
    if (!row)
      throw new EvaluationDomainError(
        "Assigned evaluator step not found or appraisal is immutable",
        404,
        "EVALUATOR_STEP_NOT_FOUND",
      );
    if (row.step_status === "SUBMITTED" || row.step_status === "SKIPPED") {
      throw new EvaluationDomainError(
        "Evaluator step is already finalized",
        409,
        "EVALUATOR_STEP_FINALIZED",
      );
    }
    if (!row.prior_steps_complete)
      throw new EvaluationDomainError(
        "Earlier evaluator steps must be submitted first",
        409,
        "EVALUATOR_SEQUENCE_BLOCKED",
      );
    if (
      row.step_kind === "RATING" &&
      row.submitted_ratings !== row.expected_ratings
    ) {
      throw new EvaluationDomainError(
        `Evaluator step requires ${row.expected_ratings} applicable ratings; found ${row.submitted_ratings}`,
        422,
        "INCOMPLETE_EVALUATOR_RATINGS",
      );
    }
    if (!row.evidence_clean) {
      throw new EvaluationDomainError(
        "Required evidence must pass malware scanning before evaluator submission",
        422,
        "EVIDENCE_NOT_CLEAN",
      );
    }
    await client.query(
      `WITH final_score AS (
         SELECT sum(r.rating)::numeric(10,2) AS total_points,
                (count(*) * 5)::numeric(10,2) AS maximum_points
         FROM appraisal_ratings r
         WHERE r.tenant_id = $1 AND r.appraisal_id = $2 AND r.is_final
       )
       UPDATE appraisals a
       SET total_points = final_score.total_points,
           maximum_points = final_score.maximum_points,
           score_percentage = round(
             final_score.total_points / final_score.maximum_points * 100,
             2
           ),
           row_version = row_version + 1,
           updated_at = clock_timestamp()
       FROM final_score
       WHERE a.tenant_id = $1 AND a.id = $2
         AND final_score.maximum_points > 0`,
      [tenantId, appraisalId],
    );
    await client.query(
      `UPDATE evaluator_chain_steps SET status = 'SUBMITTED', submitted_at = now()
       WHERE tenant_id = $1 AND id = $2`,
      [tenantId, row.step_id],
    );
    await client.query(
      `UPDATE appraisals a SET status='AWAITING_COMMANDER_APPROVAL'
      WHERE a.tenant_id=$1 AND a.id=$2 AND a.status='IN_EVALUATION' AND NOT EXISTS(
        SELECT 1 FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps pending ON pending.tenant_id=sn.tenant_id AND pending.snapshot_id=sn.id
        WHERE sn.tenant_id=a.tenant_id AND sn.appraisal_id=a.id AND sn.is_active AND pending.step_kind<>'FINAL_APPROVAL' AND pending.status<>'SUBMITTED')`,
      [tenantId, appraisalId],
    );
    return { stepId: row.step_id, status: "SUBMITTED" as const };
  });
}
