import { NextRequest, NextResponse } from "next/server";
import { operationsHealth, validMonitorSecret } from "@/lib/operations/health";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  if (!validMonitorSecret(request.headers.get("authorization"))) return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
  try {
    const health = await operationsHealth();
    return NextResponse.json({ success: health.status !== "CRITICAL", ...health }, { status: health.status === "CRITICAL" ? 503 : 200, headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ success: false, status: "CRITICAL", error: "Operations health check failed" }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
}
