import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";
import { buildPrintablePdf } from "./pdf";
export type OperationalPeriod =
  "WEEKLY" | "TWICE_MONTHLY" | "MONTHLY" | "EVERY_TWO_MONTHS";
const operationalPeriods = new Set<OperationalPeriod>([
  "WEEKLY", "TWICE_MONTHLY", "MONTHLY", "EVERY_TWO_MONTHS",
]);
export async function createOperationalReport(
  tenantId: string,
  accountId: string,
  input: {
    personnelId: string;
    periodType: OperationalPeriod;
    periodStart: string;
    periodEnd: string;
    progress: string;
    supervisorFeedback: string;
    challenges: string;
    trainingRequirements: string;
    activityIds: string[];
  },
) {
  if (!operationalPeriods.has(input.periodType))
    throw new EvaluationDomainError("Valid operational report period required",422,"REPORT_PERIOD_REQUIRED");
  const start = new Date(`${input.periodStart}T00:00:00Z`);
  const end = new Date(`${input.periodEnd}T00:00:00Z`);
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end < start)
    throw new EvaluationDomainError("Valid report start and end dates are required",422,"REPORT_DATES_INVALID");
  const narratives = [input.progress,input.supervisorFeedback,input.challenges,input.trainingRequirements];
  if (narratives.some((value)=>!value?.trim()))
    throw new EvaluationDomainError("All operational report narrative fields are required",422,"REPORT_NARRATIVE_REQUIRED");
  return withTenantTransaction(tenantId, accountId, async (c) => {
    const authorized = await c.query(
      `SELECT EXISTS(
         SELECT 1
         FROM accounts actor
         WHERE actor.tenant_id=$1 AND actor.id=$2 AND actor.is_active
           AND (
             EXISTS(
               SELECT 1 FROM evaluator_assignments assignment
               WHERE assignment.tenant_id=$1
                 AND assignment.evaluator_personnel_id=actor.personnel_id
                 AND assignment.appraisee_personnel_id=$3
                 AND daterange(assignment.starts_on,COALESCE(assignment.ends_on,'infinity'::date),'[]')
                     && daterange($4::date,$5::date,'[]')
             )
             OR EXISTS(
               SELECT 1 FROM account_roles role
               WHERE role.tenant_id=$1 AND role.account_id=$2
                 AND role.role IN('FIRST_SERGEANT','EXECUTIVE_OFFICER','COMPANY_COMMANDER')
                 AND role.valid_from<=clock_timestamp()
                 AND(role.valid_until IS NULL OR role.valid_until>clock_timestamp())
             )
           )
       ) AS allowed`,
      [tenantId,accountId,input.personnelId,input.periodStart,input.periodEnd],
    );
    if(!authorized.rows[0]?.allowed)
      throw new EvaluationDomainError("You are not assigned to report on this person",403,"REPORT_ACCESS_DENIED");
    const r = await c.query<{ id: string }>(
      `INSERT INTO operational_reports(tenant_id,personnel_id,period_type,period_start,period_end,progress,supervisor_feedback,challenges,training_requirements,created_by_account_id)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
      [
        tenantId,
        input.personnelId,
        input.periodType,
        input.periodStart,
        input.periodEnd,
        input.progress.trim(),
        input.supervisorFeedback.trim(),
        input.challenges.trim(),
        input.trainingRequirements.trim(),
        accountId,
      ],
    );
    if (input.activityIds?.length)
      await c.query(
        `INSERT INTO operational_report_activities(tenant_id,operational_report_id,activity_record_id)
 SELECT $1,$2,id FROM activity_records WHERE tenant_id=$1 AND id=ANY($3::uuid[]) AND data_mode=(SELECT data_mode FROM operational_reports WHERE tenant_id=$1 AND id=$2)`,
        [tenantId, r.rows[0].id, input.activityIds],
      );
    return r.rows[0];
  });
}

export async function transitionOperationalReport(
  tenantId:string,
  accountId:string,
  id:string,
  action:"submit"|"confirm",
){
  const status=action==="submit"?"SUBMITTED":"CONFIRMED";
  return withTenantTransaction(tenantId,accountId,async(c)=>{
    const result=action==="submit"
      ?await c.query(
        `UPDATE operational_reports
         SET status='SUBMITTED'
         WHERE tenant_id=$1 AND id=$2 AND status='DRAFT' AND created_by_account_id=$3
         RETURNING *`,
        [tenantId,id,accountId],
      )
      :await c.query(
        `UPDATE operational_reports report
         SET status='CONFIRMED'
         WHERE report.tenant_id=$1 AND report.id=$2 AND report.status='SUBMITTED'
           AND EXISTS(
             SELECT 1 FROM accounts actor
             WHERE actor.tenant_id=report.tenant_id AND actor.id=$3 AND actor.is_active
               AND (
                 EXISTS(
                   SELECT 1 FROM evaluator_assignments assignment
                   WHERE assignment.tenant_id=report.tenant_id
                     AND assignment.evaluator_personnel_id=actor.personnel_id
                     AND assignment.appraisee_personnel_id=report.personnel_id
                     AND daterange(assignment.starts_on,COALESCE(assignment.ends_on,'infinity'::date),'[]')
                         && daterange(report.period_start,report.period_end,'[]')
                 )
                 OR EXISTS(
                   SELECT 1 FROM account_roles role
                   WHERE role.tenant_id=report.tenant_id AND role.account_id=actor.id
                     AND role.role IN('FIRST_SERGEANT','EXECUTIVE_OFFICER','COMPANY_COMMANDER')
                     AND role.valid_from<=clock_timestamp()
                     AND(role.valid_until IS NULL OR role.valid_until>clock_timestamp())
                 )
               )
           )
         RETURNING report.*`,
        [tenantId,id,accountId],
      );
    if(!result.rows[0])throw new EvaluationDomainError("Report action is not permitted or its state has changed",403,"REPORT_ACTION_DENIED");
    return result.rows[0];
  });
}

export async function getOperationalReport(
  tenantId: string,
  accountId: string,
  id: string,
) {
  return withTenantTransaction(tenantId, accountId, async (c) => {
    const r = await c.query(
      `SELECT r.id,r.period_type,r.period_start,r.period_end,r.status,r.data_mode,r.progress,r.supervisor_feedback,r.challenges,r.training_requirements,
 p.personnel_code,p.full_name,(SELECT count(*)::int FROM activity_records pending WHERE pending.tenant_id=r.tenant_id AND pending.personnel_id=r.personnel_id AND pending.activity_date BETWEEN r.period_start AND r.period_end AND pending.data_mode=r.data_mode AND pending.status<>'CONFIRMED') AS pending_confirmations,
 COALESCE(jsonb_agg(jsonb_build_object('date',ar.activity_date,'title',av.title,'description',av.description,'outcome',av.outcome)) FILTER(WHERE ar.id IS NOT NULL),'[]') AS activities
 FROM operational_reports r JOIN personnel p ON p.tenant_id=r.tenant_id AND p.id=r.personnel_id
 LEFT JOIN operational_report_activities ora ON ora.tenant_id=r.tenant_id AND ora.operational_report_id=r.id LEFT JOIN activity_records ar ON ar.tenant_id=ora.tenant_id AND ar.id=ora.activity_record_id
 LEFT JOIN activity_versions av ON av.tenant_id=ar.tenant_id AND av.activity_record_id=ar.id AND av.is_confirmed_version
 WHERE r.tenant_id=$1 AND r.id=$2 AND r.data_mode=(CASE WHEN current_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31' THEN COALESCE((SELECT active_data_mode FROM tenant_runtime_settings WHERE tenant_id=$1),'PRODUCTION'::data_mode) ELSE 'PRODUCTION'::data_mode END) AND (r.created_by_account_id=$3 OR EXISTS(SELECT 1 FROM accounts ac WHERE ac.tenant_id=r.tenant_id AND ac.id=$3 AND ac.personnel_id=r.personnel_id)
 OR EXISTS(SELECT 1 FROM account_roles ar WHERE ar.tenant_id=r.tenant_id AND ar.account_id=$3 AND ar.role IN('FIRST_SERGEANT','EXECUTIVE_OFFICER','COMPANY_COMMANDER') AND ar.valid_from<=current_date AND(ar.valid_until IS NULL OR ar.valid_until>current_date)))
 GROUP BY r.id,p.personnel_code,p.full_name`,
      [tenantId, id, accountId],
    );
    if (!r.rows[0])
      throw new EvaluationDomainError(
        "Operational report not found",
        404,
        "REPORT_NOT_FOUND",
      );
    return r.rows[0];
  });
}

export async function getFormalReport(
  tenantId: string,
  accountId: string,
  appraisalId: string,
) {
  return withTenantTransaction(tenantId, accountId, async (c) => {
    const r = await c.query(
      `SELECT a.id,a.status,o.total_points,o.maximum_points,o.score_percentage,a.approved_at,a.acknowledged_at,a.closed_at,
 cy.name AS cycle_name,cy.cycle_type,cy.starts_on,cy.ends_on,cy.data_mode,p.personnel_code,p.full_name,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('criterion',cr.name,'rating',rt.rating,'justification',rt.justification) ORDER BY cr.display_order)
   FROM official_appraisal_current_ratings rt JOIN criteria cr ON cr.tenant_id=rt.tenant_id AND cr.id=rt.criterion_id WHERE rt.tenant_id=a.tenant_id AND rt.appraisal_id=a.id),'[]') ratings,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('body',cm.body,'createdAt',cm.created_at) ORDER BY cm.created_at)
   FROM member_visible_appraisal_comments cm WHERE cm.tenant_id=a.tenant_id AND cm.appraisal_id=a.id),'[]') public_comments,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('sequence',s.sequence_no,'kind',s.step_kind,'status',s.status,'evaluator',ep.full_name) ORDER BY s.sequence_no)
   FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps s ON s.tenant_id=sn.tenant_id AND s.snapshot_id=sn.id JOIN personnel ep ON ep.tenant_id=s.tenant_id AND ep.id=s.evaluator_personnel_id
   WHERE sn.tenant_id=a.tenant_id AND sn.appraisal_id=a.id AND sn.is_active),'[]') evaluation_chain,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('achievement',av.outcome,'developmentRequirement',av.lessons_learned,'challenge',av.challenges))
   FROM activity_records ar JOIN activity_versions av ON av.tenant_id=ar.tenant_id AND av.activity_record_id=ar.id AND av.is_confirmed_version
   WHERE ar.tenant_id=a.tenant_id AND ar.personnel_id=a.personnel_id AND ar.data_mode='PRODUCTION' AND ar.activity_date BETWEEN cy.starts_on AND cy.ends_on),'[]') development,
 (SELECT cp.status::text FROM complaints cp WHERE cp.tenant_id=a.tenant_id AND cp.appraisal_id=a.id ORDER BY cp.submitted_at DESC LIMIT 1) complaint_status
 FROM appraisals a JOIN official_appraisal_current_version o ON o.tenant_id=a.tenant_id AND o.appraisal_id=a.id JOIN evaluation_cycles cy ON cy.tenant_id=a.tenant_id AND cy.id=a.cycle_id JOIN personnel p ON p.tenant_id=a.tenant_id AND p.id=a.personnel_id
 WHERE a.tenant_id=$1 AND a.id=$2 AND cy.data_mode='PRODUCTION' AND (EXISTS(SELECT 1 FROM accounts ac WHERE ac.tenant_id=a.tenant_id AND ac.id=$3 AND ac.personnel_id=a.personnel_id)
 OR EXISTS(SELECT 1 FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps st ON st.tenant_id=sn.tenant_id AND st.snapshot_id=sn.id WHERE sn.tenant_id=a.tenant_id AND sn.appraisal_id=a.id AND st.evaluator_account_id=$3)
 OR EXISTS(SELECT 1 FROM account_roles ar WHERE ar.tenant_id=a.tenant_id AND ar.account_id=$3 AND ar.role IN('FIRST_SERGEANT','EXECUTIVE_OFFICER','COMPANY_COMMANDER') AND ar.valid_from<=clock_timestamp() AND(ar.valid_until IS NULL OR ar.valid_until>clock_timestamp())))`,
      [tenantId, appraisalId, accountId],
    );
    if (!r.rows[0])
      throw new EvaluationDomainError(
        "Production formal report not found or access denied",
        404,
        "REPORT_NOT_FOUND",
      );
    return r.rows[0];
  });
}

export async function exportQuarterlyPdf(
  tenantId: string,
  accountId: string,
  appraisalId: string,
) {
  const report = (await getFormalReport(
    tenantId,
    accountId,
    appraisalId,
  )) as any;
  if (report.cycle_type !== "QUARTERLY")
    throw new EvaluationDomainError(
      "PDF export is available for quarterly reports",
      422,
      "QUARTERLY_REQUIRED",
    );
  const ratings = (
    report.ratings as Array<{
      criterion: string;
      rating: number;
      justification?: string;
    }>
  ).map(
    (r) =>
      `${r.criterion}: ${r.rating}/5${r.justification ? ` - ${r.justification}` : ""}`,
  );
  const comments = (report.public_comments as Array<{ body: string }>).map(
    (c) => c.body,
  );
  const chain = (
    report.evaluation_chain as Array<{
      sequence: number;
      evaluator: string;
      kind: string;
      status: string;
    }>
  ).map((s) => `${s.sequence}. ${s.evaluator} - ${s.kind} - ${s.status}`);
  const development = (
    report.development as Array<{
      achievement?: string;
      developmentRequirement?: string;
      challenge?: string;
    }>
  ).flatMap((d) => [
    `Achievement: ${d.achievement ?? "None"}`,
    `Development requirement: ${d.developmentRequirement ?? d.challenge ?? "None"}`,
  ]);
  const pdf = buildPrintablePdf(
    "Performance Tracker Quarterly Performance Report",
    `${report.full_name} (${report.personnel_code}) | ${report.cycle_name}`,
    [
      {
        heading: "Score:",
        lines: [
          `${report.total_points} / ${report.maximum_points} (${report.score_percentage}%)`,
        ],
      },
      { heading: "Ratings:", lines: ratings },
      { heading: "Achievements and development:", lines: development },
      { heading: "Member-visible comments:", lines: comments },
      { heading: "Evaluation chain:", lines: chain },
      {
        heading: "Approval and acknowledgement:",
        lines: [
          `Approved: ${report.approved_at ?? "Pending"}`,
          `Acknowledged: ${report.acknowledged_at ?? "Pending"}`,
          `Complaint: ${report.complaint_status ?? "None"}`,
        ],
      },
    ],
  );
  await withTenantTransaction(tenantId, accountId, (c) =>
    c
      .query(
        "INSERT INTO report_exports(tenant_id,appraisal_id,format,data_mode,exported_by_account_id) VALUES($1,$2,'PDF','PRODUCTION',$3)",
        [tenantId, appraisalId, accountId],
      )
      .then(() => undefined),
  );
  return pdf;
}

export async function setTrainingMode(
  tenantId: string,
  accountId: string,
  enabled: boolean,
) {
  return withTenantTransaction(
    tenantId,
    accountId,
    async (c) =>
      (
        await c.query(
          `INSERT INTO tenant_runtime_settings(tenant_id,active_data_mode,changed_by_account_id) VALUES($1,$2,$3)
 ON CONFLICT(tenant_id) DO UPDATE SET active_data_mode=EXCLUDED.active_data_mode,changed_by_account_id=EXCLUDED.changed_by_account_id RETURNING active_data_mode,changed_at`,
          [tenantId, enabled ? "TRAINING" : "PRODUCTION", accountId],
        )
      ).rows[0],
  );
}
export async function getTrainingMode(tenantId: string, accountId: string) {
  return withTenantTransaction(
    tenantId,
    accountId,
    async (c) =>
      (
        await c.query<{ active_data_mode: string }>(
          "SELECT CASE WHEN current_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31' THEN active_data_mode ELSE 'PRODUCTION'::data_mode END AS active_data_mode FROM tenant_runtime_settings WHERE tenant_id=$1",
          [tenantId],
        )
      ).rows[0]?.active_data_mode ?? "PRODUCTION",
  );
}
