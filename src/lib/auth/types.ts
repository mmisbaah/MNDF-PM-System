export const SYSTEM_ROLES = [
  "APPRAISEE",
  "SQUAD_LEADER",
  "PLATOON_SERGEANT",
  "PLATOON_LEADER",
  "FIRST_SERGEANT",
  "EXECUTIVE_OFFICER",
  "COMPANY_COMMANDER",
  "AUTHORIZER_HANDOVER",
  "UNIT_ADMINISTRATOR",
  "GRIEVANCE_OFFICER",
  "AUDITOR",
  "TECHNICAL_OPERATOR",
] as const;

export type SystemRole = (typeof SYSTEM_ROLES)[number];

export type AccessClaims = {
  sub: string;
  tenantId: string;
  sessionId: string;
  roles: SystemRole[];
  mfa: boolean;
  purpose: "access";
  iat: number;
  exp: number;
  iss: "mndf-pms";
  aud: "mndf-pms-web";
};

export type MfaChallengeClaims = Omit<AccessClaims, "sessionId" | "mfa" | "purpose"> & {
  purpose: "mfa_challenge";
  passwordVerified: true;
};

export type AuthenticatedAccount = {
  accountId: string;
  tenantId: string;
  tenantCode: string;
  email: string;
  passwordHash: string;
  isActive: boolean;
  mfaEnabled: boolean;
  roles: SystemRole[];
};

export type SessionPrincipal = {
  accountId: string;
  tenantId: string;
  sessionId: string;
  roles: SystemRole[];
  mfa: boolean;
};
