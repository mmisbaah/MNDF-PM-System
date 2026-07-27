import { NextRequest, NextResponse } from "next/server";
import { db } from "@/db";
import { evaluationsTable } from "@/db/schema";
import { desc, eq } from "drizzle-orm";
import { getRankOrder } from "@/lib/mduConstants";

export async function GET() {
  try {
    const evaluations = await db
      .select()
      .from(evaluationsTable)
      .orderBy(desc(evaluationsTable.createdAt));
    return NextResponse.json({ success: true, evaluations });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to fetch evaluations" },
      { status: 500 }
    );
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      evaluatorRank,
      evaluatorName,
      targetRank,
      targetName,
      evalType,
      scoresJson,
      compositeScore,
      declarationSigned,
    } = body;

    if (!evaluatorRank || !evaluatorName || !targetRank || !targetName) {
      return NextResponse.json(
        { success: false, error: "Missing required evaluator or target information." },
        { status: 400 }
      );
    }

    // Server-Side Military Hierarchy Check
    const evalOrder = getRankOrder(evaluatorRank);
    const targetOrder = getRankOrder(targetRank);

    if (evalOrder < targetOrder && evalType !== "Self") {
      return NextResponse.json(
        {
          success: false,
          error: `MILITARY HIERARCHY RESTRICTION: A junior rank (${evaluatorRank}) is restricted from evaluating a senior rank (${targetRank}). Evaluators must be of equal or senior rank.`,
        },
        { status: 403 }
      );
    }

    const [inserted] = await db
      .insert(evaluationsTable)
      .values({
        evaluatorRank,
        evaluatorName,
        targetRank,
        targetName,
        evalType: evalType || "Supervisor",
        scoresJson: typeof scoresJson === "string" ? scoresJson : JSON.stringify(scoresJson),
        compositeScore: typeof compositeScore === "number" ? compositeScore : parseFloat(compositeScore || "3.0"),
        declarationSigned: declarationSigned ?? true,
      })
      .returning();

    return NextResponse.json({ success: true, evaluation: inserted });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to create evaluation" },
      { status: 500 }
    );
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const id = searchParams.get("id");
    if (!id) {
      return NextResponse.json({ success: false, error: "Missing evaluation ID" }, { status: 400 });
    }

    await db.delete(evaluationsTable).where(eq(evaluationsTable.id, parseInt(id, 10)));
    return NextResponse.json({ success: true });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to delete evaluation" },
      { status: 500 }
    );
  }
}
