import { cookies } from "next/headers";

export const ACCESS_COOKIE = "mndf_access";
export const REFRESH_COOKIE = "mndf_refresh";
export const MFA_COOKIE = "mndf_mfa_challenge";

const secure = process.env.NODE_ENV === "production";

export async function setAccessCookie(token: string): Promise<void> {
  (await cookies()).set(ACCESS_COOKIE, token, {
    httpOnly: true, secure, sameSite: "strict", path: "/", maxAge: 15 * 60,
  });
}

export async function setRefreshCookie(tenantId: string, token: string): Promise<void> {
  (await cookies()).set(REFRESH_COOKIE, `${tenantId}.${token}`, {
    httpOnly: true, secure, sameSite: "strict", path: "/api/auth", maxAge: 7 * 24 * 60 * 60,
  });
}

export async function setMfaChallengeCookie(token: string): Promise<void> {
  (await cookies()).set(MFA_COOKIE, token, {
    httpOnly: true, secure, sameSite: "strict", path: "/api/auth", maxAge: 10 * 60,
  });
}

export async function clearAuthCookies(): Promise<void> {
  const store = await cookies();
  store.delete(ACCESS_COOKIE);
  store.delete(REFRESH_COOKIE);
  store.delete(MFA_COOKIE);
}
