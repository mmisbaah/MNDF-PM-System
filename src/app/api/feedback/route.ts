import { NextRequest, NextResponse } from "next/server";
import { db } from "@/db";
import { systemFeedbackTable } from "@/db/schema";
import { desc, eq } from "drizzle-orm";

export async function GET() {
  try {
    const feedback = await db
      .select()
      .from(systemFeedbackTable)
      .orderBy(desc(systemFeedbackTable.createdAt));
    return NextResponse.json({ success: true, feedback });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to fetch feedback" },
      { status: 500 }
    );
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { submitterRank, submitterName, fairnessRating, evidenceSafeguardOpinion, comments } = body;

    if (!submitterRank || !fairnessRating) {
      return NextResponse.json(
        { success: false, error: "Missing required feedback fields." },
        { status: 400 }
      );
    }

    const [inserted] = await db
      .insert(systemFeedbackTable)
      .values({
        submitterRank,
        submitterName: submitterName || "Anonymized",
        fairnessRating: parseInt(String(fairnessRating), 10),
        evidenceSafeguardOpinion: evidenceSafeguardOpinion || "Neutral / Unsure",
        comments: comments || "N/A",
      })
      .returning();

    return NextResponse.json({ success: true, feedback: inserted });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to submit feedback" },
      { status: 500 }
    );
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const id = searchParams.get("id");
    if (!id) {
      return NextResponse.json({ success: false, error: "Missing feedback ID" }, { status: 400 });
    }

    await db.delete(systemFeedbackTable).where(eq(systemFeedbackTable.id, parseInt(id, 10)));
    return NextResponse.json({ success: true });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err.message || "Failed to delete feedback" },
      { status: 500 }
    );
  }
}
