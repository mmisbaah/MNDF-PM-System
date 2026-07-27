import { db } from "@/db";
import {
  personnelTable,
  evaluationsTable,
  unitActionsTable,
  systemFeedbackTable,
} from "@/db/schema";
import { count } from "drizzle-orm";

export async function ensureSeedData() {
  try {
    const personnelCountRes = await db.select({ value: count() }).from(personnelTable);
    const countVal = personnelCountRes[0]?.value ?? 0;

    if (countVal > 0) {
      return { seeded: false, message: "Database already seeded." };
    }

    // 1. Seed MNDF Marine Deployment Unit Personnel
    await db.insert(personnelTable).values([
      {
        serviceNo: "MNDF-7102",
        rank: "Maj",
        name: "R. Shiham",
        platoon: "MDU Command HQ",
        role: "Marine Deployment Unit Commander",
      },
      {
        serviceNo: "MNDF-7340",
        rank: "Cpt",
        name: "M. Fazeel",
        platoon: "Alpha Platoon - MDU",
        role: "Platoon Commander",
      },
      {
        serviceNo: "MNDF-7512",
        rank: "FLt",
        name: "A. Zameer",
        platoon: "Bravo Platoon - MDU",
        role: "Platoon Commander",
      },
      {
        serviceNo: "MNDF-7801",
        rank: "1SG",
        name: "M. Nabeel",
        platoon: "MDU Command HQ",
        role: "Company First Sergeant",
      },
      {
        serviceNo: "MNDF-8114",
        rank: "SFC",
        name: "H. Rasheed",
        platoon: "Alpha Platoon - MDU",
        role: "Platoon Sergeant",
      },
      {
        serviceNo: "MNDF-8309",
        rank: "SSgt",
        name: "T. Moosa",
        platoon: "Bravo Platoon - MDU",
        role: "Platoon Sergeant",
      },
      {
        serviceNo: "MNDF-8542",
        rank: "Sgt",
        name: "M. Misbaah",
        platoon: "Alpha Platoon - MDU",
        role: "Section Commander",
      },
      {
        serviceNo: "MNDF-8890",
        rank: "Cpl",
        name: "A. Naseer",
        platoon: "Alpha Platoon - MDU",
        role: "Team Leader",
      },
      {
        serviceNo: "MNDF-9120",
        rank: "LCpl",
        name: "H. Ibrahim",
        platoon: "Alpha Platoon - MDU",
        role: "Assault Rifleman",
      },
      {
        serviceNo: "MNDF-9415",
        rank: "Pte",
        name: "S. Shaheem",
        platoon: "Bravo Platoon - MDU",
        role: "Marine Rifleman",
      },
    ]);

    // 2. Seed Evaluations
    const defaultScoresIbrahimSup = [
      { compId: "discipline_regulations", score: 4, evidence: "" },
      { compId: "moral_integrity", score: 4, evidence: "" },
      { compId: "leading_by_example", score: 4, evidence: "" },
      { compId: "command_presence", score: 3, evidence: "" },
      { compId: "decision_making", score: 3, evidence: "" },
      { compId: "subordinate_mentorship", score: 3, evidence: "" },
      { compId: "chain_of_command", score: 4, evidence: "" },
      { compId: "rules_sop_compliance", score: 4, evidence: "" },
      { compId: "accountability_ownership", score: 4, evidence: "" },
      { compId: "pet_endurance", score: 5, evidence: "Completed 12km load-carrying amphibious march in record time, leading section by example." },
      { compId: "mental_resilience", score: 4, evidence: "" },
      { compId: "military_bearing", score: 4, evidence: "" },
      { compId: "drill_tactical_mastery", score: 4, evidence: "" },
      { compId: "self_improvement", score: 4, evidence: "" },
      { compId: "initiative_adaptability", score: 3, evidence: "" },
      { compId: "mdu_teamwork", score: 4, evidence: "" },
      { compId: "punctuality_readiness", score: 4, evidence: "" },
      { compId: "mutual_respect", score: 4, evidence: "" },
    ];

    const defaultScoresIbrahimSelf = [
      { compId: "discipline_regulations", score: 3, evidence: "" },
      { compId: "moral_integrity", score: 4, evidence: "" },
      { compId: "leading_by_example", score: 3, evidence: "" },
      { compId: "command_presence", score: 3, evidence: "" },
      { compId: "decision_making", score: 3, evidence: "" },
      { compId: "subordinate_mentorship", score: 3, evidence: "" },
      { compId: "chain_of_command", score: 4, evidence: "" },
      { compId: "rules_sop_compliance", score: 4, evidence: "" },
      { compId: "accountability_ownership", score: 3, evidence: "" },
      { compId: "pet_endurance", score: 4, evidence: "" },
      { compId: "mental_resilience", score: 4, evidence: "" },
      { compId: "military_bearing", score: 3, evidence: "" },
      { compId: "drill_tactical_mastery", score: 4, evidence: "" },
      { compId: "self_improvement", score: 4, evidence: "" },
      { compId: "initiative_adaptability", score: 3, evidence: "" },
      { compId: "mdu_teamwork", score: 4, evidence: "" },
      { compId: "punctuality_readiness", score: 4, evidence: "" },
      { compId: "mutual_respect", score: 4, evidence: "" },
    ];

    const defaultScoresNaseerSup = [
      { compId: "discipline_regulations", score: 5, evidence: "Exemplary adherence to weapons safety and MDU field barracks regulations throughout deployment." },
      { compId: "moral_integrity", score: 4, evidence: "" },
      { compId: "leading_by_example", score: 4, evidence: "" },
      { compId: "command_presence", score: 4, evidence: "" },
      { compId: "decision_making", score: 4, evidence: "" },
      { compId: "subordinate_mentorship", score: 4, evidence: "" },
      { compId: "chain_of_command", score: 5, evidence: "Unswerving loyalty and rapid execution of platoon commander orders during live tactical exercise." },
      { compId: "rules_sop_compliance", score: 4, evidence: "" },
      { compId: "accountability_ownership", score: 4, evidence: "" },
      { compId: "pet_endurance", score: 4, evidence: "" },
      { compId: "mental_resilience", score: 4, evidence: "" },
      { compId: "military_bearing", score: 4, evidence: "" },
      { compId: "drill_tactical_mastery", score: 4, evidence: "" },
      { compId: "self_improvement", score: 4, evidence: "" },
      { compId: "initiative_adaptability", score: 4, evidence: "" },
      { compId: "mdu_teamwork", score: 5, evidence: "Volunteered for double watch shift to relieve injured comrade during field deployment." },
      { compId: "punctuality_readiness", score: 4, evidence: "" },
      { compId: "mutual_respect", score: 4, evidence: "" },
    ];

    await db.insert(evaluationsTable).values([
      {
        evaluatorRank: "Sgt",
        evaluatorName: "M. Misbaah",
        targetRank: "LCpl",
        targetName: "H. Ibrahim",
        evalType: "Supervisor",
        scoresJson: JSON.stringify(defaultScoresIbrahimSup),
        compositeScore: 3.83,
        declarationSigned: true,
      },
      {
        evaluatorRank: "LCpl",
        evaluatorName: "H. Ibrahim",
        targetRank: "LCpl",
        targetName: "H. Ibrahim",
        evalType: "Self",
        scoresJson: JSON.stringify(defaultScoresIbrahimSelf),
        compositeScore: 3.56,
        declarationSigned: true,
      },
      {
        evaluatorRank: "SFC",
        evaluatorName: "H. Rasheed",
        targetRank: "Cpl",
        targetName: "A. Naseer",
        evalType: "Supervisor",
        scoresJson: JSON.stringify(defaultScoresNaseerSup),
        compositeScore: 4.22,
        declarationSigned: true,
      },
      {
        evaluatorRank: "Cpt",
        evaluatorName: "M. Fazeel",
        targetRank: "Sgt",
        targetName: "M. Misbaah",
        evalType: "Supervisor",
        scoresJson: JSON.stringify(
          defaultScoresNaseerSup.map((item) =>
            item.compId === "command_presence"
              ? {
                  compId: "command_presence",
                  score: 5,
                  evidence:
                    "Flawlessly directed night tactical maneuver under severe weather conditions.",
                }
              : item
          )
        ),
        compositeScore: 4.28,
        declarationSigned: true,
      },
    ]);

    // 3. Seed Unit Actions
    await db.insert(unitActionsTable).values([
      {
        personnelRank: "LCpl",
        personnelName: "H. Ibrahim",
        category: "Commendation / Unit Award",
        loggedBy: "Sgt M. Misbaah",
        details:
          "Awarded MDU Monthly Commendation for outstanding marksmanship and fitness during field deployment drills.",
        status: "Active",
      },
      {
        personnelRank: "Cpl",
        personnelName: "A. Naseer",
        category: "Priority Advanced Commando Course Slot",
        loggedBy: "Cpt M. Fazeel",
        details:
          "Nominated for priority Commando selection course based on exemplary leadership and discipline evaluation.",
        status: "Completed",
      },
      {
        personnelRank: "Pte",
        personnelName: "S. Shaheem",
        category: "Corrective Drill / Retraining Order",
        loggedBy: "Sgt M. Misbaah",
        details:
          "Assigned 3 days of extra weapons maintenance and drill retraining following minor equipment inspection issue.",
        status: "Active",
      },
    ]);

    // 4. Seed System Feedback
    await db.insert(systemFeedbackTable).values([
      {
        submitterRank: "Sgt",
        submitterName: "M. Misbaah",
        fairnessRating: 5,
        evidenceSafeguardOpinion: "Yes - Significantly reduces arbitrary ratings",
        comments:
          "The Al-'Adl safeguard requiring written evidence for 1s, 2s, and 5s prevents favoritism and keeps evaluations honest before Allah and command.",
      },
      {
        submitterRank: "1SG",
        submitterName: "M. Nabeel",
        fairnessRating: 5,
        evidenceSafeguardOpinion: "Yes - Significantly reduces arbitrary ratings",
        comments:
          "Much better than legacy annual paper appraisals. Multi-rater composite (60/25/15) gives a fair and holistic view of our soldiers.",
      },
    ]);

    return { seeded: true, message: "Database successfully seeded with MNDF MDU demo data." };
  } catch (err) {
    console.error("Seed error:", err);
    throw err;
  }
}
