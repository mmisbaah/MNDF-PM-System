import type { NextRequest } from "next/server";

export function requestIp(request: NextRequest): string {
  const candidate = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    ?? request.headers.get("x-real-ip")?.trim()
    ?? "127.0.0.1";
  return /^[0-9a-fA-F:.]+$/.test(candidate) ? candidate : "127.0.0.1";
}

export function requestUserAgent(request: NextRequest): string {
  return (request.headers.get("user-agent") ?? "unknown").slice(0, 500);
}

export function isSameOrigin(request: NextRequest): boolean {
  const origin = request.headers.get("origin");
  const host = request.headers.get("host");
  if (!origin || !host) return false;
  try {
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}
