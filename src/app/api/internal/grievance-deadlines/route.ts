import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { processDeadlines } from "@/lib/grievance/service";
export const runtime = "nodejs";
function authorized(request: NextRequest) {
  const expected = process.env.GRIEVANCE_CRON_SECRET; const supplied = request.headers.get("authorization")?.replace(/^Bearer /, "");
  if (!expected || !supplied) return false;
  const a = Buffer.from(expected); const b = Buffer.from(supplied); return a.length === b.length && timingSafeEqual(a, b);
}
export async function POST(request: NextRequest) {
  if (!authorized(request)) return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
  const body = await request.json() as { tenantId?: string };
  if (!body.tenantId) return NextResponse.json({ success: false, error: "Tenant ID is required" }, { status: 422 });
  const result = await processDeadlines(body.tenantId);
  return NextResponse.json({ success: true, ...result });
}
