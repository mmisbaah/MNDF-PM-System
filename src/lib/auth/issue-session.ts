import { setAccessCookie, setRefreshCookie } from "./cookies";
import { buildClaimsBase, signJwt } from "./jwt";
import { createSession, newRefreshToken } from "./repository";
import type { SystemRole } from "./types";

export async function issueSession(input: {
  accountId: string;
  tenantId: string;
  roles: SystemRole[];
  mfa: boolean;
  ipAddress: string;
  userAgent: string;
}): Promise<void> {
  const refresh = newRefreshToken();
  await createSession(input, refresh.hash, refresh.sessionId, input.ipAddress, input.userAgent);
  const access = await signJwt({
    ...buildClaimsBase(input.accountId, input.tenantId, input.roles, 15 * 60),
    sessionId: refresh.sessionId,
    mfa: input.mfa,
    purpose: "access" as const,
  });
  await setAccessCookie(access);
  await setRefreshCookie(input.tenantId, refresh.token);
}
