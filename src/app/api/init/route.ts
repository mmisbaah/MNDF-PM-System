import { NextResponse } from "next/server";
import { db } from "@/db";
import {
  personnelTable,
  evaluationsTable,
  unitActionsTable,
  systemFeedbackTable,
} from "@/db/schema";
import { ensureSeedData } from "@/lib/mduSeed";
import { desc } from "drizzle-orm";

export async function GET() {
  try {
    const seedResult = await ensureSeedData();

    const [personnel, evaluations, unitActions, feedback] = await Promise.all([
      db.select().from(personnelTable).orderBy(personnelTable.id),
      db.select().from(evaluationsTable).orderBy(desc(evaluationsTable.createdAt)),
      db.select().from(unitActionsTable).orderBy(desc(unitActionsTable.createdAt)),
      db.select().from(systemFeedbackTable).orderBy(desc(systemFeedbackTable.createdAt)),
    ]);

    return NextResponse.json({
      success: true,
      seedResult,
      personnel,
      evaluations,
      unitActions,
      feedback,
    });
  } catch (error: any) {
    console.error("API /api/init error:", error);
    return NextResponse.json(
      { success: false, error: error.message || "Failed to initialize data" },
      { status: 500 }
    );
  }
}
