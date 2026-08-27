import { randomUUID } from "node:crypto";
import { withTenantTransaction } from "@/lib/auth/repository";
import { resolveEvaluatorChain, type EvaluatorCandidate, type ExplicitAssignment, type OrganizationalNode } from "./chain-engine";
import { EvaluationDomainError } from "./errors";

type InitializationRow = {
  cycle_id: string;
  cycle_status: string;
  starts_on: string;
  personnel_category: string;
  appointment_type: string;
  appointment_id: string;
  node_id: string;
};

export async function initializeAppraisal(
  tenantId: string,
  accountId: string,
  cycleId: string,
  personnelId: string,
) {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const context = await client.query<InitializationRow>(
      `SELECT cy.id AS cycle_id, cy.status::text AS cycle_status, cy.starts_on::text,
              p.personnel_category, ap.appointment_type, ap.id AS appointment_id,
              ap.organizational_node_id AS node_id
       FROM evaluation_cycles cy
       JOIN personnel p ON p.tenant_id = cy.tenant_id AND p.id = $3
       JOIN personnel_appointments pa
         ON pa.tenant_id = p.tenant_id AND pa.personnel_id = p.id AND pa.is_primary
         AND pa.starts_on <= cy.starts_on AND (pa.ends_on IS NULL OR pa.ends_on >= cy.starts_on)
       JOIN appointments ap ON ap.tenant_id = pa.tenant_id AND ap.id = pa.appointment_id
       WHERE cy.tenant_id = $1 AND cy.id = $2
       ORDER BY pa.starts_on DESC LIMIT 1
       FOR UPDATE OF cy`,
      [tenantId, cycleId, personnelId],
    );
    const row = context.rows[0];
    if (!row) throw new EvaluationDomainError("Cycle, personnel, or effective primary appointment not found", 404, "APPRAISAL_CONTEXT_NOT_FOUND");
    if (row.cycle_status !== "OPEN") {
      throw new EvaluationDomainError("Appraisals can only be initialized in an open evaluation cycle", 409, "CYCLE_NOT_OPEN");
    }
    if (row.appointment_type === "COMPANY_COMMANDER") {
      throw new EvaluationDomainError("Company commanders are excluded from pilot evaluations", 422, "COMMANDER_EXCLUDED");
    }

    const existing = await client.query<{ id: string }>(
      "SELECT id FROM appraisals WHERE tenant_id = $1 AND cycle_id = $2 AND personnel_id = $3",
      [tenantId, cycleId, personnelId],
    );
    if (existing.rows[0]) throw new EvaluationDomainError("An appraisal already exists for this cycle and personnel", 409, "APPRAISAL_EXISTS");

    const explicitRows = await client.query<{
      evaluator_personnel_id: string;
      evaluator_account_id: string;
      sequence_no: number;
      assignment_kind: ExplicitAssignment["kind"];
    }>(
      `SELECT ea.evaluator_personnel_id, ac.id AS evaluator_account_id,
              ea.sequence_no, ea.assignment_kind
       FROM evaluator_assignments ea
       JOIN accounts ac ON ac.tenant_id = ea.tenant_id
         AND ac.personnel_id = ea.evaluator_personnel_id AND ac.is_active
       WHERE ea.tenant_id = $1 AND ea.appraisee_personnel_id = $2
         AND ea.starts_on <= $3::date AND (ea.ends_on IS NULL OR ea.ends_on >= $3::date)
       ORDER BY ea.sequence_no`,
      [tenantId, personnelId, row.starts_on],
    );

    const nodesResult = await client.query<{ id: string; parent_id: string | null }>(
      "SELECT id, parent_id FROM organizational_nodes WHERE tenant_id = $1 AND active",
      [tenantId],
    );
    const candidatesResult = await client.query<{
      personnel_id: string;
      account_id: string;
      appointment_type: string;
      node_id: string;
    }>(
      `SELECT pa.personnel_id, ac.id AS account_id, ap.appointment_type,
              ap.organizational_node_id AS node_id
       FROM personnel_appointments pa
       JOIN appointments ap ON ap.tenant_id = pa.tenant_id AND ap.id = pa.appointment_id AND ap.active
       JOIN personnel p ON p.tenant_id = pa.tenant_id AND p.id = pa.personnel_id AND p.status = 'ACTIVE'
       JOIN accounts ac ON ac.tenant_id = p.tenant_id AND ac.personnel_id = p.id AND ac.is_active
       WHERE pa.tenant_id = $1 AND pa.is_primary
         AND pa.starts_on <= $2::date AND (pa.ends_on IS NULL OR pa.ends_on >= $2::date)`,
      [tenantId, row.starts_on],
    );

    const explicitAssignments: ExplicitAssignment[] = explicitRows.rows.map((assignment) => ({
      evaluatorPersonnelId: assignment.evaluator_personnel_id,
      evaluatorAccountId: assignment.evaluator_account_id,
      sequenceNo: assignment.sequence_no,
      kind: assignment.assignment_kind,
    }));
    const nodes: OrganizationalNode[] = nodesResult.rows.map((node) => ({ id: node.id, parentId: node.parent_id }));
    const candidates: EvaluatorCandidate[] = candidatesResult.rows.map((candidate) => ({
      personnelId: candidate.personnel_id,
      accountId: candidate.account_id,
      appointmentType: candidate.appointment_type,
      nodeId: candidate.node_id,
    }));
    const chain = resolveEvaluatorChain({
      appraiseePersonnelId: personnelId,
      appraiseeAppointmentType: row.appointment_type,
      appraiseeNodeId: row.node_id,
      nodes,
      candidates,
      explicitAssignments: explicitAssignments.length ? explicitAssignments : undefined,
    });

    const appraisalId = randomUUID();
    const snapshotId = randomUUID();
    await client.query(
      `INSERT INTO appraisals
       (id, tenant_id, cycle_id, personnel_id, status, personnel_category_snapshot, appointment_type_snapshot)
       VALUES ($1,$2,$3,$4,'DRAFT',$5,$6)`,
      [appraisalId, tenantId, cycleId, personnelId, row.personnel_category, row.appointment_type],
    );
    await client.query(
      `INSERT INTO evaluator_chain_snapshots
       (id, tenant_id, appraisal_id, snapshot_version, is_active, created_by_account_id)
       VALUES ($1,$2,$3,1,true,$4)`,
      [snapshotId, tenantId, appraisalId, accountId],
    );
    for (const step of chain) {
      await client.query(
        `INSERT INTO evaluator_chain_steps
         (id, tenant_id, snapshot_id, evaluator_personnel_id, evaluator_account_id,
          sequence_no, step_kind, status)
         VALUES ($1,$2,$3,$4,$5,$6,$7,'PENDING')`,
        [randomUUID(), tenantId, snapshotId, step.evaluatorPersonnelId, step.evaluatorAccountId,
          step.sequenceNo, step.kind],
      );
    }
    return { appraisalId, snapshotId, personnelCategory: row.personnel_category, appointmentType: row.appointment_type, chain };
  });
}
