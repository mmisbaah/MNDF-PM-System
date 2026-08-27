import type { AccessClaims, MfaChallengeClaims } from "./types";

type JwtClaims = AccessClaims | MfaChallengeClaims;

function base64UrlEncode(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function base64UrlDecode(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "="));
  return new TextDecoder().decode(Uint8Array.from(binary, (char) => char.charCodeAt(0)));
}

async function signingKey(): Promise<CryptoKey> {
  const secret = process.env.AUTH_JWT_SECRET;
  if (!secret || secret.length < 32) throw new Error("AUTH_JWT_SECRET must contain at least 32 characters");
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function signJwt<T extends JwtClaims>(claims: T): Promise<string> {
  const header = base64UrlEncode(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = base64UrlEncode(JSON.stringify(claims));
  const unsigned = `${header}.${payload}`;
  const signature = await crypto.subtle.sign("HMAC", await signingKey(), new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64UrlEncode(signature)}`;
}

export async function verifyJwt<T extends JwtClaims>(token: string, purpose: T["purpose"]): Promise<T> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Invalid token");
  const [header, payload, signature] = parts;
  const decodedHeader = JSON.parse(base64UrlDecode(header)) as { alg?: string; typ?: string };
  if (decodedHeader.alg !== "HS256" || decodedHeader.typ !== "JWT") throw new Error("Unsupported token header");
  const valid = await crypto.subtle.verify(
    "HMAC",
    await signingKey(),
    Uint8Array.from(atob(signature.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(signature.length / 4) * 4, "=")), (char) => char.charCodeAt(0)),
    new TextEncoder().encode(`${header}.${payload}`),
  );
  if (!valid) throw new Error("Invalid token signature");

  const claims = JSON.parse(base64UrlDecode(payload)) as T;
  const now = Math.floor(Date.now() / 1000);
  if (claims.exp <= now || claims.iat > now + 30) throw new Error("Expired token");
  if (claims.iss !== "mndf-pms" || claims.aud !== "mndf-pms-web" || claims.purpose !== purpose) {
    throw new Error("Invalid token claims");
  }
  if (!claims.sub || !claims.tenantId || !Array.isArray(claims.roles)) throw new Error("Incomplete token claims");
  return claims;
}

export function buildClaimsBase(accountId: string, tenantId: string, roles: AccessClaims["roles"], ttlSeconds: number) {
  const iat = Math.floor(Date.now() / 1000);
  return { sub: accountId, tenantId, roles, iat, exp: iat + ttlSeconds, iss: "mndf-pms" as const, aud: "mndf-pms-web" as const };
}
