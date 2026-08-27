import type { SessionPrincipal, SystemRole } from "./types";

export const PERMISSIONS = [
  "personnel.read",
  "personnel.manage",
  "conduct.manage",
  "accounts.provision",
  "organization.manage",
  "activity.self.manage",
  "activity.confirm",
  "appraisal.self_assess",
  "appraisal.evaluate",
  "appraisal.comment",
  "appraisal.approve",
  "appraisal.score_adjust",
  "appraisal.correction_authorize",
  "appraisal.initialize",
  "template.manage",
  "grievance.participate",
  "grievance.manage",
  "report.read",
  "tenant.export_approve",
  "tenant.closure_approve",
  "audit.read",
  "handover.read",
  "handover.export",
  "operations.backup",
  "operations.deploy",
  "operations.incident_response",
  "operations.emergency_account_recovery",
] as const;

export type Permission = (typeof PERMISSIONS)[number];

const EVALUATOR_PERMISSIONS: Permission[] = [
  "personnel.read",
  "activity.confirm",
  "appraisal.evaluate",
  "appraisal.comment",
  "report.read",
];

export const ROLE_PERMISSIONS: Readonly<Record<SystemRole, readonly Permission[]>> = {
  APPRAISEE: ["activity.self.manage", "appraisal.self_assess", "report.read"],
  SQUAD_LEADER: EVALUATOR_PERMISSIONS,
  PLATOON_SERGEANT: EVALUATOR_PERMISSIONS,
  PLATOON_LEADER: EVALUATOR_PERMISSIONS,
  FIRST_SERGEANT: [
    ...EVALUATOR_PERMISSIONS,
    "personnel.manage",
    "conduct.manage",
    "grievance.participate",
    "grievance.manage",
    "appraisal.initialize",
  ],
  EXECUTIVE_OFFICER: [
    ...EVALUATOR_PERMISSIONS,
    "personnel.manage",
    "conduct.manage",
    "grievance.participate",
    "grievance.manage",
    "appraisal.initialize",
  ],
  COMPANY_COMMANDER: [
    "personnel.read",
    "appraisal.comment",
    "report.read",
    "personnel.manage",
    "conduct.manage",
    "organization.manage",
    "appraisal.approve",
    "appraisal.score_adjust",
    "appraisal.correction_authorize",
    "appraisal.initialize",
    "template.manage",
    "grievance.participate",
    "grievance.manage",
    "tenant.export_approve",
    "tenant.closure_approve",
    "audit.read",
  ],
  AUTHORIZER_HANDOVER: ["personnel.read", "report.read", "audit.read", "handover.read", "handover.export"],
  // The dedicated Administrator account is intentionally non-supervisory.
  // Organization design and appraisal initialization remain Authorizer duties.
  UNIT_ADMINISTRATOR: ["personnel.read", "personnel.manage", "accounts.provision", "report.read"],
  GRIEVANCE_OFFICER: ["personnel.read", "grievance.participate", "grievance.manage", "report.read"],
  AUDITOR: ["personnel.read", "report.read", "audit.read"],
  TECHNICAL_OPERATOR: [
    "organization.manage",
    "operations.backup",
    "operations.deploy",
    "operations.incident_response",
    "operations.emergency_account_recovery",
  ],
};

export const MFA_REQUIRED_ROLES = new Set<SystemRole>([
  "COMPANY_COMMANDER",
  "EXECUTIVE_OFFICER",
  "FIRST_SERGEANT",
  "UNIT_ADMINISTRATOR",
  "TECHNICAL_OPERATOR",
]);

export function hasPermission(principal: SessionPrincipal, permission: Permission): boolean {
  return principal.roles.some((role) => ROLE_PERMISSIONS[role].includes(permission));
}

export function requiresMfa(roles: readonly SystemRole[]): boolean {
  return roles.some((role) => MFA_REQUIRED_ROLES.has(role));
}

export function isTechnicalOperatorOnly(roles: readonly SystemRole[]): boolean {
  return roles.length > 0 && roles.every((role) => role === "TECHNICAL_OPERATOR");
}
