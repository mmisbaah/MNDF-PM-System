import { randomUUID } from "node:crypto";
import { withTenantTransaction } from "@/lib/auth/repository";
import { BASELINE_TEMPLATE, BASELINE_CRITERIA_COUNT, type PersonnelCategory } from "./baseline-template";
import { EvaluationDomainError } from "./errors";

export async function provisionBaselineTemplate(tenantId: string, accountId: string) {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const existing = await client.query<{ template_id: string; version_id: string; version_no: number }>(
      `SELECT t.id AS template_id, v.id AS version_id, v.version_no
       FROM evaluation_templates t
       JOIN template_versions v ON v.tenant_id = t.tenant_id AND v.template_id = t.id
       WHERE t.tenant_id = $1 AND t.is_baseline
       ORDER BY v.version_no DESC LIMIT 1`,
      [tenantId],
    );
    if (existing.rows[0]) return { ...existing.rows[0], criteriaCount: BASELINE_CRITERIA_COUNT, created: false };

    const templateId = randomUUID();
    const versionId = randomUUID();
    await client.query(
      `INSERT INTO evaluation_templates (id, tenant_id, name, is_baseline, created_by_account_id)
       VALUES ($1, $2, $3, true, $4)`,
      [templateId, tenantId, BASELINE_TEMPLATE.name, accountId],
    );
    await client.query(
      `INSERT INTO template_versions
       (id, tenant_id, template_id, version_no, status, effective_from, published_at, created_by_account_id)
       VALUES ($1, $2, $3, $4, 'PUBLISHED', current_date, now(), $5)`,
      [versionId, tenantId, templateId, BASELINE_TEMPLATE.version, accountId],
    );

    for (const [sectionIndex, section] of BASELINE_TEMPLATE.sections.entries()) {
      const sectionId = randomUUID();
      await client.query(
        `INSERT INTO template_sections (id, tenant_id, template_version_id, name, display_order)
         VALUES ($1, $2, $3, $4, $5)`,
        [sectionId, tenantId, versionId, section.name, sectionIndex + 1],
      );
      for (const [criterionIndex, criterion] of section.criteria.entries()) {
        await client.query(
          `INSERT INTO criteria
           (id, tenant_id, template_version_id, section_id, code, name, description,
            display_order, is_unit_specific, applicable_categories, requires_rating)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, $9::text[], true)`,
          [randomUUID(), tenantId, versionId, sectionId, criterion.code, criterion.name,
            criterion.description, criterionIndex + 1, criterion.applicableCategories],
        );
      }
    }
    await client.query(
      `INSERT INTO template_reporting_details (tenant_id, template_version_id, updated_by_account_id)
       VALUES ($1, $2, $3)`,
      [tenantId, versionId, accountId],
    );
    return { template_id: templateId, version_id: versionId, version_no: 1, criteriaCount: BASELINE_CRITERIA_COUNT, created: true };
  });
}

export type UnitCategoryInput = {
  name: string;
  criteria: Array<{
    code: string;
    name: string;
    description: string;
    applicableCategories: PersonnelCategory[];
    applicableAppointmentTypes?: string[];
  }>;
};

export async function addUnitSpecificCategory(
  tenantId: string,
  accountId: string,
  templateVersionId: string,
  input: UnitCategoryInput,
) {
  validateUnitCategory(input);
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const version = await client.query<{ is_baseline: boolean; locked: boolean; next_order: number }>(
      `SELECT t.is_baseline,
         EXISTS (SELECT 1 FROM evaluation_cycles cy
                 WHERE cy.tenant_id = v.tenant_id AND cy.template_version_id = v.id AND cy.status <> 'DRAFT') AS locked,
         COALESCE((SELECT max(display_order) + 1 FROM template_sections s
                   WHERE s.tenant_id = v.tenant_id AND s.template_version_id = v.id), 1)::int AS next_order
       FROM template_versions v
       JOIN evaluation_templates t ON t.tenant_id = v.tenant_id AND t.id = v.template_id
       WHERE v.tenant_id = $1 AND v.id = $2
       FOR UPDATE OF v`,
      [tenantId, templateVersionId],
    );
    const row = version.rows[0];
    if (!row) throw new EvaluationDomainError("Template version not found", 404, "TEMPLATE_NOT_FOUND");
    if (!row.is_baseline) throw new EvaluationDomainError("Unit additions must extend the pilot baseline template", 422, "BASELINE_REQUIRED");
    if (row.locked) throw new EvaluationDomainError("Template is immutable because an evaluation cycle has begun", 409, "TEMPLATE_LOCKED");

    const sectionId = randomUUID();
    await client.query(
      `INSERT INTO template_sections (id, tenant_id, template_version_id, name, display_order)
       VALUES ($1, $2, $3, $4, $5)`,
      [sectionId, tenantId, templateVersionId, input.name.trim(), row.next_order],
    );
    for (const [index, criterion] of input.criteria.entries()) {
      await client.query(
        `INSERT INTO criteria
         (id, tenant_id, template_version_id, section_id, code, name, description, display_order,
          is_unit_specific, applicable_categories, applicable_appointment_types, requires_rating)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true,$9::text[],$10::text[],true)`,
        [randomUUID(), tenantId, templateVersionId, sectionId, criterion.code.trim().toUpperCase(),
          criterion.name.trim(), criterion.description.trim(), index + 1, criterion.applicableCategories,
          criterion.applicableAppointmentTypes?.length ? criterion.applicableAppointmentTypes : null],
      );
    }
    return { sectionId, criteriaAdded: input.criteria.length };
  });
}

function validateUnitCategory(input: UnitCategoryInput): void {
  if (!input.name?.trim() || !Array.isArray(input.criteria) || input.criteria.length === 0) {
    throw new EvaluationDomainError("A unit category requires a name and at least one criterion", 422, "INVALID_UNIT_CATEGORY");
  }
  const codes = new Set<string>();
  for (const criterion of input.criteria) {
    const code = criterion.code?.trim().toUpperCase();
    if (!/^[A-Z0-9_-]{2,20}$/.test(code)) throw new EvaluationDomainError("Criterion codes must use 2-20 letters, numbers, underscores, or hyphens", 422, "INVALID_CRITERION_CODE");
    if (codes.has(code)) throw new EvaluationDomainError("Criterion codes must be unique within the category", 409, "DUPLICATE_CRITERION_CODE");
    codes.add(code);
    if (!criterion.name?.trim() || !criterion.description?.trim()) throw new EvaluationDomainError("Every criterion requires a name and description", 422, "INCOMPLETE_CRITERION");
    if (!criterion.applicableCategories?.length) throw new EvaluationDomainError("Every criterion requires at least one personnel category", 422, "CRITERION_APPLICABILITY_REQUIRED");
  }
}

export type ReportingDetailsInput = {
  reportTitle: string;
  commanderSignatureLabel: string;
  includeScorePercentage: boolean;
  includeEligibilitySummary: boolean;
  footerText?: string | null;
};

export async function configureReportingDetails(
  tenantId: string,
  accountId: string,
  templateVersionId: string,
  input: ReportingDetailsInput,
) {
  if (!input.reportTitle?.trim() || !input.commanderSignatureLabel?.trim()) {
    throw new EvaluationDomainError("Report title and commander signature label are required", 422, "INVALID_REPORTING_DETAILS");
  }
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query<{ id: string }>(
      `INSERT INTO template_reporting_details
       (tenant_id, template_version_id, report_title, commander_signature_label,
        include_score_percentage, include_eligibility_summary, footer_text, updated_by_account_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (tenant_id, template_version_id) DO UPDATE SET
         report_title = EXCLUDED.report_title,
         commander_signature_label = EXCLUDED.commander_signature_label,
         include_score_percentage = EXCLUDED.include_score_percentage,
         include_eligibility_summary = EXCLUDED.include_eligibility_summary,
         footer_text = EXCLUDED.footer_text,
         updated_by_account_id = EXCLUDED.updated_by_account_id,
         updated_at = now()
       RETURNING id`,
      [tenantId, templateVersionId, input.reportTitle.trim(), input.commanderSignatureLabel.trim(),
        input.includeScorePercentage, input.includeEligibilitySummary, input.footerText?.trim() || null, accountId],
    );
    return { reportingDetailsId: result.rows[0].id };
  });
}
