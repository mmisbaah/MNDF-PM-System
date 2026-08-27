import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { synchronizeQuarterlyCycles } from "@/lib/evaluation/cycle-service";

export const runtime = "nodejs";

function authorized(request: NextRequest) {
  const expected = process.env.GRIEVANCE_CRON_SECRET;
  const supplied = request.headers.get("authorization")?.replace(/^Bearer /, "");
  if (!expected || !supplied) return false;
  const left = Buffer.from(expected);
  const right = Buffer.from(supplied);
  return left.length === right.length && timingSafeEqual(left, right);
}

export async function POST(request: NextRequest) {
  if (!authorized(request))
    return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
  const body = (await request.json()) as { tenantId?: string };
  if (!body.tenantId)
    return NextResponse.json(
      { success: false, error: "Tenant ID is required" },
      { status: 422 },
    );
  const cycles = await synchronizeQuarterlyCycles(body.tenantId, null);
  return NextResponse.json({ success: true, cycles });
}
