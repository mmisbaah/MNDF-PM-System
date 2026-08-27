import { withTenantTransaction } from "@/lib/auth/repository";
import { hasPermission } from "@/lib/auth/rbac";
import type { SessionPrincipal } from "@/lib/auth/types";
export async function loadWorkspace(p: SessionPrincipal) {
  const manage = hasPermission(p, "personnel.manage"),
    initialize = hasPermission(p, "appraisal.initialize"),
    evaluate = hasPermission(p, "appraisal.evaluate"),
    confirm = hasPermission(p, "activity.confirm"),
    selfAssess = hasPermission(p, "appraisal.self_assess"),
    grievanceManage = hasPermission(p, "grievance.manage"),
    correctionAuthorize = hasPermission(p, "appraisal.correction_authorize");
  const organizationManage = hasPermission(p, "organization.manage");
  const accountProvision = hasPermission(p, "accounts.provision");
  const recordsManage = hasPermission(p, "conduct.manage");
  const handoverRead = hasPermission(p,"handover.read");
  const readinessView = hasPermission(p,"audit.read") || hasPermission(p,"tenant.closure_approve");
  return withTenantTransaction(p.tenantId, p.accountId, async (c) => {
    const profile =
      (
        await c.query(
          `SELECT ac.id account_id,ac.personnel_id,ac.email::text account_login,ac.mfa_enabled,pe.personnel_code,pe.full_name,pe.rank_name,
                  COALESCE(pe.full_name,ac.email::text) display_name,
                  COALESCE(current_appointment.title,'System Administrator') appointment_title,
                  current_appointment.organizational_node_id
           FROM accounts ac
           LEFT JOIN personnel pe ON pe.tenant_id=ac.tenant_id AND pe.id=ac.personnel_id
           LEFT JOIN LATERAL(
             SELECT ap.title,ap.organizational_node_id FROM personnel_appointments pa
             JOIN appointments ap ON ap.tenant_id=pa.tenant_id AND ap.id=pa.appointment_id
             WHERE pa.tenant_id=ac.tenant_id AND pa.personnel_id=ac.personnel_id
               AND pa.starts_on<=current_date AND(pa.ends_on IS NULL OR pa.ends_on>=current_date)
             ORDER BY pa.is_primary DESC,pa.starts_on DESC LIMIT 1
           )current_appointment ON true
           WHERE ac.tenant_id=$1 AND ac.id=$2`,
          [p.tenantId, p.accountId],
        )
      ).rows[0] ?? null;
    const personnel =
      manage || initialize || evaluate
        ? (
            await c.query(
              `SELECT pe.id,pe.personnel_code,pe.full_name,pe.rank_name,pe.personnel_category,pe.status,pe.rank_precedence,pe.date_of_rank,pe.manual_precedence,pe.date_joined_service,pe.unit_service_started_on,
                      pa.id personnel_appointment_id,pa.role_description,ap.id appointment_id,ap.title appointment_title,atype.role_description appointment_role_description,ap.organizational_node_id,onode.name organizational_node_name,
                      login_account.id account_id,login_account.email::text account_login,login_account.is_active account_active,login_account.must_change_password,login_account.mfa_enabled
               FROM personnel pe
               LEFT JOIN LATERAL(SELECT * FROM personnel_appointments x WHERE x.tenant_id=pe.tenant_id AND x.personnel_id=pe.id AND x.is_primary AND x.ends_on IS NULL ORDER BY x.starts_on DESC LIMIT 1)pa ON true
               LEFT JOIN appointments ap ON ap.tenant_id=pa.tenant_id AND ap.id=pa.appointment_id
               LEFT JOIN appointment_types atype ON atype.tenant_id=ap.tenant_id AND atype.id=ap.appointment_type_id
               LEFT JOIN organizational_nodes onode ON onode.tenant_id=ap.tenant_id AND onode.id=ap.organizational_node_id
               LEFT JOIN accounts login_account ON login_account.tenant_id=pe.tenant_id AND login_account.personnel_id=pe.id
               WHERE pe.tenant_id=$1 AND($2::boolean OR pe.status='ACTIVE')ORDER BY pe.rank_name,pe.full_name`,
              [p.tenantId,manage],
            )
          ).rows
        : profile?.personnel_id
          ? (
              await c.query(
                `SELECT id,personnel_code,full_name,rank_name,personnel_category,status FROM personnel WHERE tenant_id=$1 AND id=$2`,
                [p.tenantId, profile.personnel_id],
              )
            ).rows
          : [];
    const organizationLevelDefinitions = (await c.query(`SELECT id,level_number,name,code,active FROM organization_level_definitions WHERE tenant_id=$1 AND active ORDER BY level_number`,[p.tenantId])).rows;
    const organizationalNodes = (
      await c.query(
        `WITH RECURSIVE tree AS (
           SELECT n.id,n.parent_id,n.node_type,n.code,n.name,n.description,n.sort_order,n.active,n.level_definition_id,d.level_number,d.name level_name,d.code level_code,
                  0 AS depth,n.name::text AS path
           FROM organizational_nodes n LEFT JOIN organization_level_definitions d ON d.tenant_id=n.tenant_id AND d.id=n.level_definition_id WHERE n.tenant_id=$1 AND n.parent_id IS NULL
           UNION ALL
           SELECT child.id,child.parent_id,child.node_type,child.code,child.name,child.description,child.sort_order,child.active,child.level_definition_id,d.level_number,d.name level_name,d.code level_code,
                  tree.depth+1,tree.path||' / '||child.name
           FROM organizational_nodes child JOIN tree ON child.tenant_id=$1 AND child.parent_id=tree.id LEFT JOIN organization_level_definitions d ON d.tenant_id=child.tenant_id AND d.id=child.level_definition_id
         ) SELECT * FROM tree WHERE active OR $2::boolean ORDER BY path,sort_order,name`,
        [p.tenantId, organizationManage],
      )
    ).rows;
    const appointmentTypes = manage || organizationManage
      ? (await c.query(`SELECT id,name,role_description,leadership_priority,system_administrator_operator,active FROM appointment_types WHERE tenant_id=$1 AND(active OR $2::boolean) ORDER BY name`,[p.tenantId,organizationManage])).rows
      : [];
    const leadershipSuccession = manage || organizationManage || handoverRead
      ? (await c.query(
          `SELECT row_number() OVER(ORDER BY type.leadership_priority,pe.rank_precedence NULLS LAST,pe.date_of_rank NULLS LAST,pe.unit_service_started_on,pe.manual_precedence NULLS LAST,pe.full_name) succession_order,
                  pe.id personnel_id,pe.full_name,pe.rank_name,pe.rank_precedence,pe.date_of_rank,pe.unit_service_started_on,pe.manual_precedence,
                  type.name appointment_type,type.leadership_priority,n.name organizational_node_name,ac.id account_id,ac.email::text account_login,ac.mfa_enabled
           FROM personnel pe
           JOIN personnel_appointments pa ON pa.tenant_id=pe.tenant_id AND pa.personnel_id=pe.id AND pa.is_primary AND pa.starts_on<=current_date AND(pa.ends_on IS NULL OR pa.ends_on>=current_date)
           JOIN appointments ap ON ap.tenant_id=pa.tenant_id AND ap.id=pa.appointment_id AND ap.active
           JOIN appointment_types type ON type.tenant_id=ap.tenant_id AND type.id=ap.appointment_type_id AND type.active AND type.leadership_priority IS NOT NULL
           JOIN organizational_nodes n ON n.tenant_id=ap.tenant_id AND n.id=ap.organizational_node_id AND n.active
           LEFT JOIN accounts ac ON ac.tenant_id=pe.tenant_id AND ac.personnel_id=pe.id AND ac.is_active
           WHERE pe.tenant_id=$1 AND pe.status='ACTIVE'
           ORDER BY succession_order`,[p.tenantId])).rows
      : [];
    const authorizerTransfers = manage || organizationManage || handoverRead
      ? (await c.query(`SELECT transfer.id,transfer.reason,transfer.transferred_at,transfer.handover_expires_at,outgoing.email::text outgoing_login,incoming.email::text incoming_login,outgoing_person.full_name outgoing_name,incoming_person.full_name incoming_name FROM system_authorizer_transfers transfer JOIN accounts outgoing ON outgoing.tenant_id=transfer.tenant_id AND outgoing.id=transfer.outgoing_account_id JOIN accounts incoming ON incoming.tenant_id=transfer.tenant_id AND incoming.id=transfer.incoming_account_id LEFT JOIN personnel outgoing_person ON outgoing_person.tenant_id=outgoing.tenant_id AND outgoing_person.id=outgoing.personnel_id LEFT JOIN personnel incoming_person ON incoming_person.tenant_id=incoming.tenant_id AND incoming_person.id=incoming.personnel_id WHERE transfer.tenant_id=$1 ORDER BY transfer.transferred_at DESC LIMIT 20`,[p.tenantId])).rows
      : [];
    const administratorAuthorizations=hasPermission(p,"tenant.closure_approve")
      ?(await c.query(`SELECT admin_auth.id,admin_auth.status,admin_auth.requested_at,admin_auth.decided_at,admin_auth.decision_reason,admin_auth.valid_until,
        administrator.email::text administrator_login,
        ARRAY(SELECT pe.full_name FROM personnel pe WHERE pe.tenant_id=admin_auth.tenant_id AND pe.id=ANY(admin_auth.operator_personnel_ids) ORDER BY pe.full_name) operator_names
        FROM system_administrator_authorizations admin_auth JOIN accounts administrator ON administrator.tenant_id=admin_auth.tenant_id AND administrator.id=admin_auth.administrator_account_id
        WHERE admin_auth.tenant_id=$1 ORDER BY admin_auth.requested_at DESC LIMIT 20`,[p.tenantId])).rows:[];
    const appointmentDefinitions = manage || organizationManage
      ? (await c.query(
          `SELECT ap.id,ap.organizational_node_id,ap.appointment_type_id,type.name title,type.role_description,ap.active,n.name organizational_node_name
           FROM appointments ap JOIN organizational_nodes n ON n.tenant_id=ap.tenant_id AND n.id=ap.organizational_node_id
           JOIN appointment_types type ON type.tenant_id=ap.tenant_id AND type.id=ap.appointment_type_id
           WHERE ap.tenant_id=$1 AND(ap.active OR $2::boolean)
           ORDER BY ap.title,n.name`,
          [p.tenantId,organizationManage],
        )).rows
      : [];
    const cycles = initialize
      ? (
          await c.query(
            `SELECT id,name,cycle_type,starts_on,ends_on,status FROM evaluation_cycles WHERE tenant_id=$1 AND status='OPEN' ORDER BY starts_on DESC`,
            [p.tenantId],
          )
        ).rows
      : [];
    const cycleSchedule = correctionAuthorize
      ? (
          await c.query(
            `SELECT id,name,cycle_type,starts_on,ends_on,closure_due_on,status,opened_at,closed_at
             FROM evaluation_cycles WHERE tenant_id=$1
             ORDER BY starts_on DESC`,
            [p.tenantId],
          )
        ).rows
      : [];
    const appraisals = (
      await c.query(
        `SELECT a.id,a.personnel_id,a.status,a.total_points,a.score_percentage,a.maximum_points,a.approved_at,a.available_to_member_at,a.acknowledged_at,a.closed_at,a.personnel_category_snapshot,a.appointment_type_snapshot,pe.full_name,pe.personnel_code,cy.name cycle_name,cy.cycle_type,cy.data_mode,
 (SELECT st.id FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps st ON st.tenant_id=sn.tenant_id AND st.snapshot_id=sn.id WHERE sn.tenant_id=a.tenant_id AND sn.appraisal_id=a.id AND sn.is_active AND st.evaluator_account_id=$2 AND st.status NOT IN('SUBMITTED','SKIPPED') ORDER BY st.sequence_no LIMIT 1) current_evaluator_step_id,
 EXISTS(SELECT 1 FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps st ON st.tenant_id=sn.tenant_id AND st.snapshot_id=sn.id WHERE sn.tenant_id=a.tenant_id AND sn.appraisal_id=a.id AND sn.is_active AND st.evaluator_account_id=$2 AND st.step_kind<>'FINAL_APPROVAL' AND st.status NOT IN('SUBMITTED','SKIPPED'))can_evaluate,
 EXISTS(SELECT 1 FROM accounts me WHERE me.tenant_id=a.tenant_id AND me.id=$2 AND me.personnel_id=a.personnel_id)can_acknowledge,
 (a.status='DRAFT'AND EXISTS(SELECT 1 FROM accounts me WHERE me.tenant_id=a.tenant_id AND me.id=$2 AND me.personnel_id=a.personnel_id)AND $4::boolean)can_self_assess,
 EXISTS(SELECT 1 FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps st ON st.tenant_id=sn.tenant_id AND st.snapshot_id=sn.id WHERE sn.tenant_id=a.tenant_id AND sn.appraisal_id=a.id AND sn.is_active AND st.step_kind='FINAL_APPROVAL'AND st.evaluator_account_id=$2)final_approver
 FROM appraisals a JOIN personnel pe ON pe.tenant_id=a.tenant_id AND pe.id=a.personnel_id JOIN evaluation_cycles cy ON cy.tenant_id=a.tenant_id AND cy.id=a.cycle_id
 WHERE a.tenant_id=$1 AND(EXISTS(SELECT 1 FROM accounts me WHERE me.tenant_id=a.tenant_id AND me.id=$2 AND me.personnel_id=a.personnel_id)OR EXISTS(SELECT 1 FROM evaluator_chain_snapshots sn JOIN evaluator_chain_steps st ON st.tenant_id=sn.tenant_id AND st.snapshot_id=sn.id WHERE sn.tenant_id=a.tenant_id AND sn.appraisal_id=a.id AND sn.is_active AND st.evaluator_account_id=$2)OR $3::boolean)ORDER BY cy.starts_on DESC,pe.full_name`,
        [p.tenantId, p.accountId, manage, selfAssess],
      )
    ).rows;
    const ids = appraisals.map((x) => x.id);
    const criteria = ids.length
      ? (
          await c.query(
            `SELECT a.id appraisal_id,cr.id criterion_id,sec.name section_name,cr.code,cr.name,cr.description,cr.display_order FROM appraisals a JOIN evaluation_cycles cy ON cy.tenant_id=a.tenant_id AND cy.id=a.cycle_id JOIN criteria cr ON cr.tenant_id=cy.tenant_id AND cr.template_version_id=cy.template_version_id JOIN template_sections sec ON sec.tenant_id=cr.tenant_id AND sec.id=cr.section_id WHERE a.tenant_id=$1 AND a.id=ANY($2::uuid[])AND cr.requires_rating AND a.personnel_category_snapshot=ANY(cr.applicable_categories)AND(cr.applicable_appointment_types IS NULL OR a.appointment_type_snapshot=ANY(cr.applicable_appointment_types))ORDER BY a.id,sec.display_order,cr.display_order`,
            [p.tenantId, ids],
          )
        ).rows
      : [];
    const ratings = ids.length
      ? (
          await c.query(
            `SELECT appraisal_id,criterion_id,rating,justification,evaluator_step_id FROM appraisal_ratings WHERE tenant_id=$1 AND appraisal_id=ANY($2::uuid[])AND is_final`,
            [p.tenantId, ids],
          )
        ).rows
      : [];
    const comments = ids.length
      ? (
          await c.query(
            `SELECT appraisal_id,body,created_at,author_account_id FROM member_visible_appraisal_comments WHERE tenant_id=$1 AND appraisal_id=ANY($2::uuid[])ORDER BY created_at`,
            [p.tenantId, ids],
          )
        ).rows
      : [];
    const selfAssessments = ids.length
      ? (
          await c.query(
            `SELECT appraisal_id,criterion_id,self_rating,narrative,updated_at FROM appraisal_self_assessments WHERE tenant_id=$1 AND appraisal_id=ANY($2::uuid[])`,
            [p.tenantId, ids],
          )
        ).rows
      : [];
    const activities = profile?.personnel_id
      ? (
          await c.query(
            `SELECT ar.id,ar.personnel_id,ar.activity_date,ar.status,ar.confirmed_at,pe.full_name,av.title,av.description,av.outcome,av.challenges,av.lessons_learned,(ar.personnel_id=$3)own_record FROM activity_records ar JOIN personnel pe ON pe.tenant_id=ar.tenant_id AND pe.id=ar.personnel_id JOIN LATERAL(SELECT * FROM activity_versions v WHERE v.tenant_id=ar.tenant_id AND v.activity_record_id=ar.id ORDER BY version_no DESC LIMIT 1)av ON true WHERE ar.tenant_id=$1 AND ar.data_mode=(CASE WHEN current_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31' THEN COALESCE((SELECT active_data_mode FROM tenant_runtime_settings WHERE tenant_id=$1),'PRODUCTION'::data_mode) ELSE 'PRODUCTION'::data_mode END) AND(ar.personnel_id=$3 OR($4::boolean AND EXISTS(SELECT 1 FROM accounts ac JOIN evaluator_assignments ea ON ea.tenant_id=ac.tenant_id AND ea.evaluator_personnel_id=ac.personnel_id WHERE ac.tenant_id=ar.tenant_id AND ac.id=$2 AND ea.appraisee_personnel_id=ar.personnel_id AND ea.starts_on<=ar.activity_date AND(ea.ends_on IS NULL OR ea.ends_on>=ar.activity_date))))ORDER BY ar.activity_date DESC LIMIT 100`,
            [p.tenantId, p.accountId, profile.personnel_id, confirm],
          )
        ).rows
      : [];
    const awol = manage
      ? (
          await c.query(
            `SELECT aw.id,aw.personnel_id,pe.full_name,pe.personnel_code,aw.started_at,aw.ended_at,aw.status,aw.reference,aw.resolution FROM awol_incidents aw JOIN personnel pe ON pe.tenant_id=aw.tenant_id AND pe.id=aw.personnel_id WHERE aw.tenant_id=$1 ORDER BY aw.started_at DESC LIMIT 100`,
            [p.tenantId],
          )
        ).rows
      : [];
    const discipline = manage
      ? (
          await c.query(
            `SELECT dm.id,dm.personnel_id,pe.full_name,pe.personnel_code,dm.reference_code,dm.occurred_on,dm.status,dm.summary,dm.resolved_at FROM disciplinary_matters dm JOIN personnel pe ON pe.tenant_id=dm.tenant_id AND pe.id=dm.personnel_id WHERE dm.tenant_id=$1 ORDER BY dm.created_at DESC LIMIT 100`,
            [p.tenantId],
          )
        ).rows
      : [];
    const complaints = (
      await c.query(
        `SELECT co.id,co.appraisal_id,co.status,co.grounds,co.submitted_at,
                co.submission_deadline_at,co.acceptance_deadline_at,co.accepted_at,
                co.decision_deadline_at,co.decided_at,co.decision,
                co.decision_reason,co.return_reason,co.is_overdue,
                co.overdue_stage,co.overdue_since,pe.full_name,pe.personnel_code
         FROM complaints co
         JOIN personnel pe ON pe.tenant_id=co.tenant_id
           AND pe.id=co.complainant_personnel_id
         WHERE co.tenant_id=$1 AND (
           $3::boolean OR EXISTS(
             SELECT 1 FROM accounts ac
             WHERE ac.tenant_id=co.tenant_id AND ac.id=$2
               AND ac.personnel_id=co.complainant_personnel_id
           )
         )
         ORDER BY co.submitted_at DESC`,
        [p.tenantId, p.accountId, grievanceManage],
      )
    ).rows;
    const correctionOfficers = correctionAuthorize
      ? (
          await c.query(
            `SELECT DISTINCT sn.appraisal_id,ac.id account_id,pe.full_name,pe.rank_name
             FROM evaluator_chain_snapshots sn
             JOIN evaluator_chain_steps st ON st.tenant_id=sn.tenant_id AND st.snapshot_id=sn.id
             JOIN accounts ac ON ac.tenant_id=st.tenant_id AND ac.id=st.evaluator_account_id AND ac.is_active
             LEFT JOIN personnel pe ON pe.tenant_id=ac.tenant_id AND pe.id=ac.personnel_id
             WHERE sn.tenant_id=$1 AND sn.is_active AND st.step_kind='RATING'
             ORDER BY pe.full_name`,
            [p.tenantId],
          )
        ).rows
      : [];
    const adminErrorFlags =
      manage || correctionAuthorize
        ? (
            await c.query(
              `SELECT id,appraisal_id,reason,flagged_at,withdrawn_at
             FROM appraisal_admin_error_flags WHERE tenant_id=$1
             ORDER BY flagged_at DESC`,
              [p.tenantId],
            )
          ).rows
        : [];
    const reopenAuthorizations = (
      await c.query(
        `SELECT ra.id,ra.appraisal_id,ra.complaint_id,ra.admin_error_flag_id,ra.reason,
                ra.correction_officer_account_id,ra.authorized_at,ra.expires_at,ra.used_at,
                pe.full_name correction_officer_name,
                (ra.correction_officer_account_id=$2) is_assigned_officer
         FROM appraisal_reopen_authorizations ra
         LEFT JOIN accounts ac ON ac.tenant_id=ra.tenant_id AND ac.id=ra.correction_officer_account_id
         LEFT JOIN personnel pe ON pe.tenant_id=ac.tenant_id AND pe.id=ac.personnel_id
         WHERE ra.tenant_id=$1 AND (
           $3::boolean OR ra.correction_officer_account_id=$2
         ) ORDER BY ra.authorized_at DESC`,
        [p.tenantId, p.accountId, correctionAuthorize],
      )
    ).rows;
    const correctionVersions = (
      await c.query(
        `SELECT cv.id,cv.appraisal_id,cv.authorization_id,cv.version_no,cv.status,
                cv.reason,cv.total_points,cv.maximum_points,cv.score_percentage,
                cv.created_at,cv.submitted_at,cv.approved_at,cv.rejected_at,cv.decision_reason
         FROM appraisal_correction_versions cv
         JOIN appraisal_reopen_authorizations ra ON ra.tenant_id=cv.tenant_id AND ra.id=cv.authorization_id
         WHERE cv.tenant_id=$1 AND (
           $3::boolean OR ra.correction_officer_account_id=$2
         ) ORDER BY cv.created_at DESC`,
        [p.tenantId, p.accountId, correctionAuthorize],
      )
    ).rows;
    const correctionVersionIds = correctionVersions.map(
      (version) => version.id,
    );
    const correctionRatings = correctionVersionIds.length
      ? (
          await c.query(
            `SELECT cr.id,cr.correction_version_id,cr.criterion_id,cr.original_rating_id,
                    cr.rating,cr.justification,cr.correction_reason,orig.rating original_rating,
                    orig.justification original_justification,sec.name section_name,c.name criterion_name,
                    c.description
             FROM appraisal_correction_ratings cr
             JOIN appraisal_ratings orig ON orig.tenant_id=cr.tenant_id AND orig.id=cr.original_rating_id
             JOIN criteria c ON c.tenant_id=cr.tenant_id AND c.id=cr.criterion_id
             JOIN template_sections sec ON sec.tenant_id=c.tenant_id AND sec.id=c.section_id
             WHERE cr.tenant_id=$1 AND cr.correction_version_id=ANY($2::uuid[])
             ORDER BY cr.correction_version_id,sec.display_order,c.display_order`,
            [p.tenantId, correctionVersionIds],
          )
        ).rows
      : [];
    const recommendations = (
      await c.query(
        `SELECT r.id,r.personnel_id,r.annual_appraisal_id,r.recommendation_type,r.status,
                r.eligibility_checked_at,r.annual_score_percentage,r.has_rating_below_three,
                r.has_unresolved_disciplinary_matter,r.unit_service_started_on,r.eligible,
                r.nomination_reason,r.nominated_at,r.decision_reason,r.decided_at,
                pe.full_name,pe.personnel_code,latest.service_threshold_at
         FROM recommendations r
         JOIN personnel pe ON pe.tenant_id=r.tenant_id AND pe.id=r.personnel_id
         JOIN appraisals recommendation_appraisal
           ON recommendation_appraisal.tenant_id=r.tenant_id
          AND recommendation_appraisal.id=r.annual_appraisal_id
         JOIN evaluation_cycles recommendation_cycle
           ON recommendation_cycle.tenant_id=recommendation_appraisal.tenant_id
          AND recommendation_cycle.id=recommendation_appraisal.cycle_id
         LEFT JOIN LATERAL (
           SELECT ea.service_threshold_at FROM recommendation_eligibility_assessments ea
           WHERE ea.tenant_id=r.tenant_id AND ea.recommendation_id=r.id
           ORDER BY ea.checked_at DESC LIMIT 1
         ) latest ON true
         WHERE r.tenant_id=$1 AND recommendation_cycle.data_mode=(CASE WHEN current_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31' THEN COALESCE((SELECT active_data_mode FROM tenant_runtime_settings WHERE tenant_id=$1),'PRODUCTION'::data_mode) ELSE 'PRODUCTION'::data_mode END) AND (
           $3::boolean OR EXISTS(
             SELECT 1 FROM accounts ac WHERE ac.tenant_id=r.tenant_id
               AND ac.id=$2 AND ac.personnel_id=r.personnel_id
           )
         ) ORDER BY pe.full_name,r.recommendation_type`,
        [p.tenantId, p.accountId, manage],
      )
    ).rows;
    const operationalReports = (
      await c.query(
        `SELECT r.id,r.personnel_id,r.period_type,r.period_start,r.period_end,r.status,
                r.data_mode,r.progress,r.supervisor_feedback,r.challenges,
                r.training_requirements,r.created_at,pe.full_name,pe.personnel_code
         FROM operational_reports r
         JOIN personnel pe ON pe.tenant_id=r.tenant_id AND pe.id=r.personnel_id
         WHERE r.tenant_id=$1 AND (
           r.created_by_account_id=$2 OR $3::boolean OR EXISTS(
             SELECT 1 FROM accounts ac WHERE ac.tenant_id=r.tenant_id
               AND ac.id=$2 AND ac.personnel_id=r.personnel_id
           )
         ) ORDER BY r.period_end DESC,r.created_at DESC LIMIT 100`,
        [p.tenantId, p.accountId, manage],
      )
    ).rows;
    const runtimeSettings = (
      await c.query(
        `SELECT active_data_mode,changed_at FROM tenant_runtime_settings WHERE tenant_id=$1`,
        [p.tenantId],
      )
    ).rows[0] ?? { active_data_mode: "PRODUCTION", changed_at: null };
    const readinessAccounts = readinessView
      ? (await c.query(
          `SELECT ac.id,ac.email::text account_login,ac.is_active,ac.mfa_enabled,
                  COALESCE(pe.full_name,'Dedicated System Administrator') display_name,
                  COALESCE(pe.rank_name,'Administrative account') rank_name,
                  COALESCE(array_agg(DISTINCT ar.role::text) FILTER(WHERE ar.role IS NOT NULL),'{}') roles
           FROM accounts ac
           LEFT JOIN personnel pe ON pe.tenant_id=ac.tenant_id AND pe.id=ac.personnel_id
           LEFT JOIN account_roles ar ON ar.tenant_id=ac.tenant_id AND ar.account_id=ac.id
             AND ar.valid_from<=clock_timestamp() AND(ar.valid_until IS NULL OR ar.valid_until>clock_timestamp())
           WHERE ac.tenant_id=$1
           GROUP BY ac.tenant_id,ac.id,ac.email,ac.is_active,ac.mfa_enabled,
                    pe.full_name,pe.rank_name
           ORDER BY ac.is_active DESC,display_name`,
          [p.tenantId],
        )).rows
      : [];
    const privilegedRoles=new Set(["COMPANY_COMMANDER","EXECUTIVE_OFFICER","FIRST_SERGEANT","UNIT_ADMINISTRATOR","TECHNICAL_OPERATOR"]);
    const activeReadinessAccounts=readinessAccounts.filter((account:any)=>account.is_active);
    const readinessChecks=readinessView?[
      {code:"ORGANIZATION",label:"Organization hierarchy configured",passed:organizationalNodes.some((node:any)=>node.active)},
      {code:"APPOINTMENTS",label:"Appointment catalog configured",passed:appointmentDefinitions.some((appointment:any)=>appointment.active)},
      {code:"AUTHORIZER",label:"Active System Authorizer account",passed:activeReadinessAccounts.some((account:any)=>account.roles.includes("COMPANY_COMMANDER"))},
      {code:"COMMANDER_EXCLUSION",label:"System Authorizer excluded from ordinary appraisal roles",passed:activeReadinessAccounts.filter((account:any)=>account.roles.includes("COMPANY_COMMANDER")).every((account:any)=>!account.roles.some((role:string)=>["APPRAISEE","SQUAD_LEADER","PLATOON_SERGEANT","PLATOON_LEADER","FIRST_SERGEANT","EXECUTIVE_OFFICER","GRIEVANCE_OFFICER"].includes(role)))},
      {code:"ADMINISTRATOR",label:"Active dedicated Administrator account",passed:activeReadinessAccounts.some((account:any)=>account.roles.includes("UNIT_ADMINISTRATOR"))},
      {code:"APPRAISEE",label:"At least one active appraisee",passed:activeReadinessAccounts.some((account:any)=>account.roles.includes("APPRAISEE"))},
      {code:"EVALUATOR",label:"At least one active evaluator",passed:activeReadinessAccounts.some((account:any)=>account.roles.some((role:string)=>["SQUAD_LEADER","PLATOON_SERGEANT","PLATOON_LEADER","FIRST_SERGEANT","EXECUTIVE_OFFICER"].includes(role)))},
      {code:"MFA",label:"MFA enrolled for every privileged account",passed:activeReadinessAccounts.filter((account:any)=>account.roles.some((role:string)=>privilegedRoles.has(role))).every((account:any)=>account.mfa_enabled)},
      {code:"ADMIN_AUTHORIZATION",label:"Administrator has a current approved authorization",passed:administratorAuthorizations.some((authorization:any)=>authorization.status==="APPROVED"&&authorization.valid_until&&new Date(authorization.valid_until)>new Date())},
    ]:[];
    return {
      profile,
      permissions: {
        manage,
        initialize,
        evaluate,
        confirm,
        selfAssess,
        approve: hasPermission(p, "appraisal.approve"),
        comment: hasPermission(p, "appraisal.comment"),
        selfActivity: hasPermission(p, "activity.self.manage"),
        grievanceManage,
        correctionAuthorize,
        templateManage: hasPermission(p, "template.manage"),
        organizationManage,
        accountProvision,
        recordsManage,
        authorizerTransfer: hasPermission(p,"tenant.closure_approve"),
        handoverRead,
        readinessView,
      },
      personnel,
      organizationalNodes,
      organizationLevelDefinitions,
      appointmentTypes,
      appointmentDefinitions,
      leadershipSuccession,
      authorizerTransfers,
      administratorAuthorizations,
      cycles,
      cycleSchedule,
      appraisals,
      criteria,
      ratings,
      comments,
      selfAssessments,
      activities,
      awol,
      discipline,
      complaints,
      correctionOfficers,
      adminErrorFlags,
      reopenAuthorizations,
      correctionVersions,
      correctionRatings,
      recommendations,
      operationalReports,
      runtimeSettings,
      readinessAccounts,
      readinessChecks,
    };
  });
}
