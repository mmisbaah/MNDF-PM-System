import { withTenantTransaction } from "@/lib/auth/repository";
import { computeAppraisalScore, type FinalRating, type ScoreableCriterion } from "./score";
import { EvaluationDomainError } from "./errors";

export async function calculateAppraisalScore(tenantId: string, accountId: string, appraisalId: string) {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const appraisal = await client.query<{
      personnel_category_snapshot: string;
      appointment_type_snapshot: string;
      template_version_id: string;
    }>(
      `SELECT a.personnel_category_snapshot, a.appointment_type_snapshot, cy.template_version_id
       FROM appraisals a
       JOIN evaluation_cycles cy ON cy.tenant_id = a.tenant_id AND cy.id = a.cycle_id
       WHERE a.tenant_id = $1 AND a.id = $2`,
      [tenantId, appraisalId],
    );
    const context = appraisal.rows[0];
    if (!context) throw new EvaluationDomainError("Appraisal not found", 404, "APPRAISAL_NOT_FOUND");

    const criteriaResult = await client.query<{
      id: string;
      applicable_categories: string[];
      applicable_appointment_types: string[] | null;
    }>(
      `SELECT id, applicable_categories, applicable_appointment_types
       FROM criteria WHERE tenant_id = $1 AND template_version_id = $2 AND requires_rating`,
      [tenantId, context.template_version_id],
    );
    const ratingsResult = await client.query<{ criterion_id: string; rating: number }>(
      `SELECT criterion_id, rating FROM appraisal_ratings
       WHERE tenant_id = $1 AND appraisal_id = $2 AND is_final`,
      [tenantId, appraisalId],
    );
    const criteria: ScoreableCriterion[] = criteriaResult.rows.map((row) => ({
      id: row.id,
      applicableCategories: row.applicable_categories,
      applicableAppointmentTypes: row.applicable_appointment_types,
    }));
    const ratings: FinalRating[] = ratingsResult.rows.map((row) => ({ criterionId: row.criterion_id, rating: row.rating }));
    return computeAppraisalScore(
      criteria,
      ratings,
      context.personnel_category_snapshot,
      context.appointment_type_snapshot,
    );
  });
}
