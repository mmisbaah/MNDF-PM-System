import { NextRequest, NextResponse } from "next/server";
import { db } from "@/db";
import { personnelTable } from "@/db/schema";
import { asc, eq } from "drizzle-orm";

export async function GET() {
  try {
    const personnel = await db
      .select()
      .from(personnelTable)
      .orderBy(asc(personnelTable.id));
    return NextResponse.json({ success: true, personnel });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to fetch personnel" },
      { status: 500 }
    );
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();

    // Support Batch CSV / CVS Import
    if (Array.isArray(body.batch)) {
      const insertedList = [];
      const errorsList = [];

      for (const item of body.batch) {
        const { serviceNo, rank, name, platoon, role } = item;
        if (!serviceNo || !rank || !name) {
          continue;
        }
        try {
          // Check if marine exists
          const existing = await db
            .select()
            .from(personnelTable)
            .where(eq(personnelTable.serviceNo, String(serviceNo).trim()));

          if (existing.length > 0) {
            // Update existing marine
            const [updated] = await db
              .update(personnelTable)
              .set({
                rank: String(rank).trim(),
                name: String(name).trim(),
                platoon: String(platoon || "MDU Command HQ").trim(),
                role: String(role || "Marine Rifleman").trim(),
              })
              .where(eq(personnelTable.serviceNo, String(serviceNo).trim()))
              .returning();
            if (updated) insertedList.push(updated);
          } else {
            // Insert new marine
            const [inserted] = await db
              .insert(personnelTable)
              .values({
                serviceNo: String(serviceNo).trim(),
                rank: String(rank).trim(),
                name: String(name).trim(),
                platoon: String(platoon || "MDU Command HQ").trim(),
                role: String(role || "Marine Rifleman").trim(),
              })
              .returning();
            if (inserted) insertedList.push(inserted);
          }
        } catch (e: any) {
          errorsList.push({ serviceNo, error: e.message });
        }
      }

      const updatedRoster = await db
        .select()
        .from(personnelTable)
        .orderBy(asc(personnelTable.id));

      return NextResponse.json({
        success: true,
        importedCount: insertedList.length,
        personnel: updatedRoster,
        errors: errorsList,
      });
    }

    // Single marine insert
    const { serviceNo, rank, name, platoon, role } = body;
    if (!serviceNo || !rank || !name || !platoon || !role) {
      return NextResponse.json(
        { success: false, error: "All personnel fields are required." },
        { status: 400 }
      );
    }

    const [inserted] = await db
      .insert(personnelTable)
      .values({ serviceNo, rank, name, platoon, role })
      .returning();

    return NextResponse.json({ success: true, marine: inserted });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to add marine to roster" },
      { status: 500 }
    );
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const id = searchParams.get("id");
    if (!id) {
      return NextResponse.json({ success: false, error: "Missing personnel ID" }, { status: 400 });
    }

    await db.delete(personnelTable).where(eq(personnelTable.id, parseInt(id, 10)));
    return NextResponse.json({ success: true });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to delete marine" },
      { status: 500 }
    );
  }
}
