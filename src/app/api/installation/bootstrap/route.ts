import { NextRequest, NextResponse } from "next/server";
import { pool } from "@/db";
import { hashPassword } from "@/lib/auth/password";

export const runtime = "nodejs";

function isLocalSetupRequest(request: NextRequest) {
  const host = request.nextUrl.hostname.toLowerCase();
  return host === "localhost" || host === "127.0.0.1" || host === "::1" || host === "[::1]" || host.startsWith("192.168.") || host.startsWith("10.");
}

export async function POST(request: NextRequest) {
  try {
    if (!isLocalSetupRequest(request)) return NextResponse.json({ success: false, error: "Initial setup is only available from the host computer or private network" }, { status: 403 });
    const body = await request.json();
    const required = [body.organizationName, body.organizationCode, body.authorizerName, body.authorizerRank, body.authorizerLogin, body.authorizerPassword, body.adminLogin, body.adminPassword];
    if (required.some((value) => typeof value !== "string" || !value.trim())) return NextResponse.json({ success: false, error: "Complete all required setup fields" }, { status: 422 });
    if (body.authorizerLogin.trim().toLowerCase() === body.adminLogin.trim().toLowerCase()) return NextResponse.json({ success: false, error: "Authorizer and Administrator must have different login IDs" }, { status: 422 });
    const authorizerHash = await hashPassword(body.authorizerPassword);
    const adminHash = await hashPassword(body.adminPassword);
    const result = await pool.query(
      "SELECT * FROM bootstrap_single_organization($1,$2,$3,$4::jsonb,$5,$6,$7,$8,$9,$10,$11)",
      [body.organizationName, body.organizationCode, body.timezone || "Indian/Maldives", JSON.stringify(Array.isArray(body.nodes) ? body.nodes : []), body.authorizerName, body.authorizerRank, body.authorizerAppointment, body.authorizerLogin, authorizerHash, body.adminLogin, adminHash],
    );
    return NextResponse.json({ success: true, tenantId: result.rows[0]?.tenant_id, next: "AUTHORIZE_AND_ACTIVATE" }, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Organization setup failed";
    return NextResponse.json({ success: false, error: message.includes("already configured") ? message : "Organization setup failed. Check codes, hierarchy parents, and password length." }, { status: message.includes("already configured") ? 409 : 422 });
  }
}
