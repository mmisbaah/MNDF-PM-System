import {
  pgTable,
  serial,
  text,
  integer,
  real,
  boolean,
  timestamp,
} from "drizzle-orm/pg-core";

// Personnel directory for the MNDF Marine Deployment Unit (MDU)
export const personnelTable = pgTable("mdu_personnel", {
  id: serial("id").primaryKey(),
  serviceNo: text("service_no").notNull().unique(),
  rank: text("rank").notNull(),
  name: text("name").notNull(),
  platoon: text("platoon").notNull(),
  role: text("role").notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

// Evaluations submitted by evaluators for themselves or target personnel
export const evaluationsTable = pgTable("mdu_evaluations", {
  id: serial("id").primaryKey(),
  evaluatorRank: text("evaluator_rank").notNull(),
  evaluatorName: text("evaluator_name").notNull(),
  targetRank: text("target_rank").notNull(),
  targetName: text("target_name").notNull(),
  evalType: text("eval_type").notNull(), // "Self", "Supervisor", "Peer"
  scoresJson: text("scores_json").notNull(), // JSON string: Array<{ compId: string, score: number, evidence: string }>
  compositeScore: real("composite_score").notNull(),
  declarationSigned: boolean("declaration_signed").default(true).notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

// Administrative unit actions (commendations, course slots, counseling, retraining)
export const unitActionsTable = pgTable("mdu_unit_actions", {
  id: serial("id").primaryKey(),
  personnelRank: text("personnel_rank").notNull(),
  personnelName: text("personnel_name").notNull(),
  category: text("category").notNull(),
  loggedBy: text("logged_by").notNull(),
  details: text("details").notNull(),
  status: text("status").default("Active").notNull(), // "Active", "Completed", "Under Review"
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

// System feedback from personnel regarding Al-'Adl safeguard and fairness
export const systemFeedbackTable = pgTable("mdu_system_feedback", {
  id: serial("id").primaryKey(),
  submitterRank: text("submitter_rank").notNull(),
  submitterName: text("submitter_name").notNull(),
  fairnessRating: integer("fairness_rating").notNull(), // 1 to 5
  evidenceSafeguardOpinion: text("evidence_safeguard_opinion").notNull(),
  comments: text("comments").notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});
