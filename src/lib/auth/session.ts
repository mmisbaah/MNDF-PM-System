import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { ACCESS_COOKIE } from "./cookies";
import { verifyJwt } from "./jwt";
import { hasPermission, requiresMfa, type Permission } from "./rbac";
import { loadActiveRoles, sessionIsActive } from "./repository";
import type { AccessClaims, SessionPrincipal } from "./types";
import { requireAdministratorAuthorization } from "./administrator-authorization";

function sameOrigin(request: NextRequest): boolean {
  if (["GET", "HEAD", "OPTIONS"].includes(request.method)) return true;
  const origin = request.headers.get("origin");
  const host = request.headers.get("host");
  if (!origin || !host) return false;
  try {
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}

export async function authenticateRequest(request: NextRequest): Promise<SessionPrincipal> {
  if (!sameOrigin(request)) throw new AuthError(403, "Cross-origin request denied");
  const token = request.cookies.get(ACCESS_COOKIE)?.value;
  if (!token) throw new AuthError(401, "Authentication required");
  let claims: AccessClaims;
  try {
    claims = await verifyJwt<AccessClaims>(token, "access");
  } catch {
    throw new AuthError(401, "Session expired");
  }
  if (!(await sessionIsActive(claims.tenantId, claims.sub, claims.sessionId))) {
    throw new AuthError(401, "Session revoked or expired");
  }
  const activeRoles=await loadActiveRoles(claims.tenantId,claims.sub);
  if (!activeRoles.length) throw new AuthError(403, "No active access role");
  if (requiresMfa(activeRoles) && !claims.mfa) throw new AuthError(403, "Multi-factor authentication required");
  return {
    accountId: claims.sub,
    tenantId: claims.tenantId,
    sessionId: claims.sessionId,
    roles: activeRoles,
    mfa: claims.mfa,
  };
}

export async function authorizeRequest(request: NextRequest, permission: Permission): Promise<SessionPrincipal> {
  const principal = await authenticateRequest(request);
  await requireAdministratorAuthorization(principal);
  if (!hasPermission(principal, permission)) throw new AuthError(403, "Insufficient permission");
  return principal;
}

export class AuthError extends Error {
  constructor(public readonly status: 401 | 403, message: string) {
    super(message);
  }
}

export function authErrorResponse(error: unknown): NextResponse | null {
  if (!(error instanceof AuthError)) return null;
  return NextResponse.json({ success: false, error: error.message }, { status: error.status });
}
