import { NextRequest, NextResponse } from "next/server";
import { verifyJwt } from "@/lib/auth/jwt";
import type { AccessClaims } from "@/lib/auth/types";
import { hasPermission, requiresMfa, type Permission } from "@/lib/auth/rbac";

const ACCESS_COOKIE = "mndf_access";
export async function proxy(request: NextRequest) {
  const token = request.cookies.get(ACCESS_COOKIE)?.value;
  if (!token) return unauthorized(request);
  try {
    const claims = await verifyJwt<AccessClaims>(token, "access");
    if (requiresMfa(claims.roles) && !claims.mfa) {
      return NextResponse.json({ success: false, error: "Multi-factor authentication required" }, { status: 403 });
    }
    const required = requiredPermission(request.nextUrl.pathname, request.method);
    if (required && !hasPermission({
      accountId: claims.sub,
      tenantId: claims.tenantId,
      sessionId: claims.sessionId,
      roles: claims.roles,
      mfa: claims.mfa,
    }, required)) {
      return NextResponse.json({ success: false, error: "Insufficient permission" }, { status: 403 });
    }
    const headers = new Headers(request.headers);
    headers.set("x-mndf-tenant-id", claims.tenantId);
    headers.set("x-mndf-account-id", claims.sub);
    return NextResponse.next({ request: { headers } });
  } catch {
    return unauthorized(request);
  }
}

function requiredPermission(pathname: string, method: string): Permission | null {
  if(pathname==="/api/activities"&&method==="POST")return"activity.self.manage";
  if(pathname.endsWith("/submit")&&pathname.startsWith("/api/activities/"))return"activity.self.manage";
  if(pathname.endsWith("/confirm")&&pathname.startsWith("/api/activities/"))return"activity.confirm";
  if(pathname.startsWith("/api/evidence"))return"appraisal.evaluate";
  if(pathname.startsWith("/api/awol")||pathname.startsWith("/api/discipline"))return"personnel.manage";
  if(pathname.startsWith("/api/personnel"))return"personnel.manage";
  if(pathname.startsWith("/api/organization"))return"organization.manage";
  if(pathname==="/api/appraisals/initialize")return"appraisal.initialize";
  if(pathname.includes("/ratings")||pathname.includes("/steps/submit"))return"appraisal.evaluate";
  if(pathname.includes("/self-assessment"))return"appraisal.self_assess";
  if(pathname.includes("/approve")||pathname.includes("/close"))return"appraisal.approve";
  if(pathname.includes("/comments"))return"appraisal.comment";
  if(pathname.includes("/reopen-authorizations"))return"appraisal.correction_authorize";
  if(pathname.startsWith("/api/templates"))return"template.manage";
  if(pathname.startsWith("/api/reports")&&method==="GET")return"report.read";
  if(pathname.startsWith("/api/records-governance")&&method==="GET")return"audit.read";
  if(pathname.includes("/api/reports/operational/")&&pathname.endsWith("/transition")&&method==="POST")return null;
  if(pathname.startsWith("/api/corrections")&&pathname.endsWith("/transition"))return null;
  if(pathname.startsWith("/api/corrections"))return"appraisal.evaluate";
  if(pathname.startsWith("/api/recommendations/recalculate"))return"personnel.manage";
  return null;
}

function unauthorized(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith("/api/")) {
    return NextResponse.json({ success: false, error: "Authentication required" }, { status: 401 });
  }
  const url = request.nextUrl.clone();
  url.pathname = "/";
  url.searchParams.set("login", "required");
  return NextResponse.redirect(url);
}

export const config = {
  matcher: ["/api/((?!auth|health|internal|installation).*)", "/dashboard/:path*", "/admin/:path*"],
};
