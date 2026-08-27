import { EvaluationDomainError } from "./errors";

export type StepKind = "RATING" | "COMMENT_ONLY" | "FINAL_APPROVAL";

export type OrganizationalNode = { id: string; parentId: string | null };
export type EvaluatorCandidate = {
  personnelId: string;
  accountId: string;
  appointmentType: string;
  nodeId: string;
};
export type ExplicitAssignment = {
  evaluatorPersonnelId: string;
  evaluatorAccountId: string;
  sequenceNo: number;
  kind: StepKind;
};
export type ResolvedChainStep = ExplicitAssignment & { source: "EXPLICIT" | "DEFAULT_RULE" };

const DEFAULT_RULES: Readonly<Record<string, readonly { appointmentType: string; kind: StepKind }[]>> = {
  RIFLEMAN: [
    { appointmentType: "SQUAD_LEADER", kind: "RATING" },
    { appointmentType: "PLATOON_SERGEANT", kind: "RATING" },
    { appointmentType: "PLATOON_LEADER", kind: "RATING" },
    { appointmentType: "COMPANY_COMMANDER", kind: "FINAL_APPROVAL" },
  ],
  SQUAD_LEADER: [
    { appointmentType: "PLATOON_SERGEANT", kind: "RATING" },
    { appointmentType: "PLATOON_LEADER", kind: "RATING" },
    { appointmentType: "COMPANY_COMMANDER", kind: "FINAL_APPROVAL" },
  ],
  PLATOON_SERGEANT: [
    { appointmentType: "PLATOON_LEADER", kind: "RATING" },
    { appointmentType: "COMPANY_COMMANDER", kind: "FINAL_APPROVAL" },
  ],
  PLATOON_LEADER: [
    { appointmentType: "EXECUTIVE_OFFICER", kind: "COMMENT_ONLY" },
    { appointmentType: "COMPANY_COMMANDER", kind: "FINAL_APPROVAL" },
  ],
  FIRST_SERGEANT: [
    { appointmentType: "EXECUTIVE_OFFICER", kind: "COMMENT_ONLY" },
    { appointmentType: "COMPANY_COMMANDER", kind: "FINAL_APPROVAL" },
  ],
  EXECUTIVE_OFFICER: [{ appointmentType: "COMPANY_COMMANDER", kind: "FINAL_APPROVAL" }],
};

export function resolveEvaluatorChain(input: {
  appraiseePersonnelId: string;
  appraiseeAppointmentType: string;
  appraiseeNodeId: string;
  nodes: readonly OrganizationalNode[];
  candidates: readonly EvaluatorCandidate[];
  explicitAssignments?: readonly ExplicitAssignment[];
}): ResolvedChainStep[] {
  if (input.appraiseeAppointmentType === "COMPANY_COMMANDER") {
    throw new EvaluationDomainError("Company commanders are excluded from pilot evaluations", 422, "COMMANDER_EXCLUDED");
  }

  if (input.explicitAssignments?.length) {
    return validateResolvedChain(
      input.explicitAssignments.map((assignment) => ({ ...assignment, source: "EXPLICIT" as const })),
      input.appraiseePersonnelId,
    );
  }

  const rule = DEFAULT_RULES[input.appraiseeAppointmentType];
  if (!rule) {
    throw new EvaluationDomainError(
      `No default evaluator rule exists for ${input.appraiseeAppointmentType}; configure an explicit chain`,
      422,
      "CHAIN_CONFIGURATION_REQUIRED",
    );
  }

  const ancestors = ancestorPath(input.appraiseeNodeId, input.nodes);
  const steps = rule.map((required, index): ResolvedChainStep => {
    const candidate = chooseCandidate(required.appointmentType, input.candidates, ancestors);
    if (!candidate) {
      throw new EvaluationDomainError(
        `No active ${required.appointmentType} account can be resolved for evaluator step ${index + 1}`,
        422,
        "EVALUATOR_NOT_FOUND",
      );
    }
    return {
      evaluatorPersonnelId: candidate.personnelId,
      evaluatorAccountId: candidate.accountId,
      sequenceNo: index + 1,
      kind: required.kind,
      source: "DEFAULT_RULE",
    };
  });
  return validateResolvedChain(steps, input.appraiseePersonnelId);
}

function ancestorPath(startNodeId: string, nodes: readonly OrganizationalNode[]): string[] {
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const result: string[] = [];
  const visited = new Set<string>();
  let current: string | null = startNodeId;
  while (current) {
    if (visited.has(current)) throw new EvaluationDomainError("Organizational hierarchy contains a cycle", 409, "INVALID_ORG_HIERARCHY");
    visited.add(current);
    result.push(current);
    current = byId.get(current)?.parentId ?? null;
  }
  return result;
}

function chooseCandidate(
  appointmentType: string,
  candidates: readonly EvaluatorCandidate[],
  ancestors: readonly string[],
): EvaluatorCandidate | undefined {
  const matching = candidates.filter((candidate) => candidate.appointmentType === appointmentType);
  const inChain = matching
    .map((candidate) => ({ candidate, distance: ancestors.indexOf(candidate.nodeId) }))
    .filter((item) => item.distance >= 0)
    .sort((left, right) => left.distance - right.distance);
  if (inChain[0]) return inChain[0].candidate;

  // Company headquarters appointments may be a sibling node rather than an ancestor.
  if (["COMPANY_COMMANDER", "EXECUTIVE_OFFICER", "FIRST_SERGEANT"].includes(appointmentType) && matching.length === 1) {
    return matching[0];
  }
  return undefined;
}

function validateResolvedChain(steps: ResolvedChainStep[], appraiseePersonnelId: string): ResolvedChainStep[] {
  const ordered = [...steps].sort((left, right) => left.sequenceNo - right.sequenceNo);
  if (ordered.length === 0) throw new EvaluationDomainError("An evaluator chain cannot be empty", 422, "EMPTY_EVALUATOR_CHAIN");
  const seen = new Set<string>();
  ordered.forEach((step, index) => {
    if (step.sequenceNo !== index + 1) throw new EvaluationDomainError("Evaluator sequence numbers must be continuous", 422, "INVALID_CHAIN_SEQUENCE");
    if (step.evaluatorPersonnelId === appraiseePersonnelId) throw new EvaluationDomainError("An appraisee cannot evaluate or approve themselves", 422, "SELF_EVALUATION_FORBIDDEN");
    if (seen.has(step.evaluatorPersonnelId)) throw new EvaluationDomainError("An evaluator cannot appear twice in one chain", 422, "DUPLICATE_EVALUATOR");
    seen.add(step.evaluatorPersonnelId);
  });
  if (ordered.at(-1)?.kind !== "FINAL_APPROVAL") {
    throw new EvaluationDomainError("The final evaluator-chain step must be final approval", 422, "FINAL_APPROVER_REQUIRED");
  }
  if (ordered.slice(0, -1).some((step) => step.kind === "FINAL_APPROVAL")) {
    throw new EvaluationDomainError("Only the last evaluator-chain step may grant final approval", 422, "INVALID_FINAL_APPROVER_POSITION");
  }
  return ordered;
}
