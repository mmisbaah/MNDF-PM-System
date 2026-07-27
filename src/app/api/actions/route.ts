import { NextRequest, NextResponse } from "next/server";
import { db } from "@/db";
import { unitActionsTable } from "@/db/schema";
import { desc, eq } from "drizzle-orm";

export async function GET() {
  try {
    const actions = await db
      .select()
      .from(unitActionsTable)
      .orderBy(desc(unitActionsTable.createdAt));
    return NextResponse.json({ success: true, actions });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to fetch unit actions" },
      { status: 500 }
    );
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { personnelRank, personnelName, category, loggedBy, details, status } = body;

    if (!personnelRank || !personnelName || !category || !details) {
      return NextResponse.json(
        { success: false, error: "Missing required action fields." },
        { status: 400 }
      );
    }

    const [inserted] = await db
      .insert(unitActionsTable)
      .values({
        personnelRank,
        personnelName,
        category,
        loggedBy: loggedBy || "MDU Command",
        details,
        status: status || "Active",
      })
      .returning();

    return NextResponse.json({ success: true, action: inserted });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to log unit action" },
      { status: 500 }
    );
  }
}

export async function PUT(req: NextRequest) {
  try {
    const body = await req.json();
    const { id, status, details } = body;
    if (!id) {
      return NextResponse.json({ success: false, error: "Missing action ID" }, { status: 400 });
    }

    const updateData: Record<string, any> = {};
    if (status) updateData.status = status;
    if (details) updateData.details = details;

    const [updated] = await db
      .update(unitActionsTable)
      .set(updateData)
      .where(eq(unitActionsTable.id, parseInt(id, 10)))
      .returning();

    return NextResponse.json({ success: true, action: updated });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to update action" },
      { status: 500 }
    );
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const id = searchParams.get("id");
    if (!id) {
      return NextResponse.json({ success: false, error: "Missing action ID" }, { status: 400 });
    }

    await db.delete(unitActionsTable).where(eq(unitActionsTable.id, parseInt(id, 10)));
    return NextResponse.json({ success: true });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to delete action" },
      { status: 500 }
    );
  }
}
