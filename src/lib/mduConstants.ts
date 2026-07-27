export interface RankInfo {
  code: string;
  label: string;
  order: number;
  color: string;
  shortLabel: string;
}

export const MNDF_RANKS: RankInfo[] = [
  { code: "Pte", label: "Private (Pte)", order: 1, color: "bg-slate-700 text-slate-100", shortLabel: "Private" },
  { code: "LCpl", label: "Lance Corporal (LCpl)", order: 2, color: "bg-slate-700 text-slate-100", shortLabel: "Lance Corporal" },
  { code: "Cpl", label: "Corporal (Cpl)", order: 3, color: "bg-slate-700 text-slate-100", shortLabel: "Corporal" },
  { code: "Sgt", label: "Sergeant (Sgt)", order: 4, color: "bg-emerald-800 text-emerald-100", shortLabel: "Sergeant" },
  { code: "SSgt", label: "Staff Sergeant (SSgt)", order: 5, color: "bg-emerald-800 text-emerald-100", shortLabel: "Staff Sergeant" },
  { code: "SFC", label: "Sergeant First Class (SFC)", order: 6, color: "bg-emerald-800 text-emerald-100", shortLabel: "SFC" },
  { code: "1SG", label: "First Sergeant (1SG)", order: 7, color: "bg-emerald-900 text-emerald-100", shortLabel: "1SG" },
  { code: "Lt", label: "Lieutenant (Lt)", order: 8, color: "bg-amber-700 text-amber-100", shortLabel: "Lieutenant" },
  { code: "FLt", label: "First Lieutenant (FLt)", order: 9, color: "bg-amber-700 text-amber-100", shortLabel: "First Lieutenant" },
  { code: "Cpt", label: "Captain (Cpt)", order: 10, color: "bg-amber-800 text-amber-100", shortLabel: "Captain" },
  { code: "Maj", label: "Major (Maj)", order: 11, color: "bg-rose-800 text-rose-100", shortLabel: "Major" },
];

export function getRankOrder(code: string): number {
  const r = MNDF_RANKS.find((x) => x.code === code);
  return r ? r.order : 0;
}

export function getRankLabel(code: string): string {
  const r = MNDF_RANKS.find((x) => x.code === code);
  return r ? r.label : code;
}

export function getRankBadgeColor(code: string): string {
  const r = MNDF_RANKS.find((x) => x.code === code);
  return r ? r.color : "bg-slate-700 text-slate-100";
}

export interface CompetencyItem {
  id: string;
  category: string;
  title: string;
  desc: string;
}

export const CATEGORY_LABELS: Record<string, string> = {
  ethos: "Military Discipline & Integrity",
  leadership: "Leadership & Command Presence",
  followership: "Followership & Chain of Command",
  fitness: "Physical & Mental Combat Fitness",
  training: "Training Proficiency & Skill Mastery",
  cohesion: "Unit Cohesion & Esprit de Corps",
};

export const COMPETENCIES: CompetencyItem[] = [
  // 1. Military Discipline & Integrity
  {
    id: "discipline_regulations",
    category: "ethos",
    title: "Adherence to MNDF Regulations & Discipline",
    desc: "Unquestioned adherence to MNDF standing orders, barracks conduct, and field regulations on and off deployment.",
  },
  {
    id: "moral_integrity",
    category: "ethos",
    title: "Moral Integrity & Honest Reporting",
    desc: "Uncompromising truthfulness, transparency in operational reporting, and ethical accountability.",
  },
  {
    id: "leading_by_example",
    category: "ethos",
    title: "Leading by Example",
    desc: "Consistently modeling military standards, work ethic, and moral conduct to inspire peers and subordinates.",
  },

  // 2. Leadership & Command Presence
  {
    id: "command_presence",
    category: "leadership",
    title: "Command Presence & Clear Communication",
    desc: "Vocal projection, concise briefing, and calm composure under operational and training stress.",
  },
  {
    id: "decision_making",
    category: "leadership",
    title: "Tactical Decision-Making Under Pressure",
    desc: "Sound, timely judgment during high-stress deployment scenarios, ambiguity, or time-critical missions.",
  },
  {
    id: "subordinate_mentorship",
    category: "leadership",
    title: "Subordinate Development & Welfare",
    desc: "Active coaching, drill training, and personal welfare oversight of junior soldiers to build discipline and morale.",
  },

  // 3. Followership & Chain of Command
  {
    id: "chain_of_command",
    category: "followership",
    title: "Loyalty to Chain of Command",
    desc: "Prompt, willing receipt and execution of orders from superiors without hesitation or resistance.",
  },
  {
    id: "rules_sop_compliance",
    category: "followership",
    title: "Strict SOP & Safety Adherence",
    desc: "Rigorous compliance with weapons handling, field safety, barracks orders, and unit standard operating procedures.",
  },
  {
    id: "accountability_ownership",
    category: "followership",
    title: "Personal Accountability & Ownership",
    desc: "Taking full responsibility for actions, decisions, equipment care, and duty execution without deflecting blame.",
  },

  // 4. Physical & Mental Combat Fitness
  {
    id: "pet_endurance",
    category: "fitness",
    title: "Physical Efficiency Test (PET) & Endurance",
    desc: "Achieving high PET scores, load-bearing endurance, and sustained physical readiness for rigorous MDU duties.",
  },
  {
    id: "mental_resilience",
    category: "fitness",
    title: "Mental Resilience & Composure Under Stress",
    desc: "Composure, emotional stability, and mental fortitude during fatigue, sleep deprivation, and deployment adversity.",
  },
  {
    id: "military_bearing",
    category: "fitness",
    title: "Military Bearing & Uniform Grooming",
    desc: "Pristine uniform cleanliness, sharp grooming, proud posture, and exemplary military bearing.",
  },

  // 5. Training Proficiency & Skill Mastery
  {
    id: "drill_tactical_mastery",
    category: "training",
    title: "Infantry Drill & Tactical Skill Mastery",
    desc: "Demonstrated competence in infantry formations, marksmanship, fieldcraft, and MDU tactical maneuvers.",
  },
  {
    id: "self_improvement",
    category: "training",
    title: "Proactive Self-Improvement & Learning",
    desc: "Continuously pursuing professional military education, fitness milestones, and specialized qualification courses.",
  },
  {
    id: "initiative_adaptability",
    category: "training",
    title: "Initiative & Field Adaptability",
    desc: "Proactively taking constructive action without constant supervision and adapting quickly to unexpected mission changes.",
  },

  // 6. Unit Cohesion & Esprit de Corps
  {
    id: "mdu_teamwork",
    category: "cohesion",
    title: "MDU Teamwork & Camaraderie",
    desc: "Fostering esprit de corps, supporting comrades, and prioritizing squad and platoon mission success above self.",
  },
  {
    id: "punctuality_readiness",
    category: "cohesion",
    title: "Operational Reliability & Punctuality",
    desc: "Unfailing punctuality for formations, watch duties, equipment inspections, and deployment readiness drills.",
  },
  {
    id: "mutual_respect",
    category: "cohesion",
    title: "Respect Across Ranks",
    desc: "Treating fellow soldiers with respect, maintaining military courtesy, and strengthening unit trust.",
  },
];

export const SCORE_LABELS: Record<number, string> = {
  1: "1 - Unsatisfactory (Mandatory Written Evidence Required)",
  2: "2 - Below Standard / Needs Improvement (Mandatory Written Evidence)",
  3: "3 - Satisfactory (MNDF Standard Baseline)",
  4: "4 - Very Good / Commendable Performance",
  5: "5 - Outstanding Excellence (Mandatory Written Evidence Required)",
};

export const EVIDENCE_TRIGGERS: Record<number, boolean> = {
  1: true,
  2: true,
  5: true,
};

export const ACTION_CATEGORIES = [
  "Commendation / Unit Award",
  "Priority Advanced Commando Course Slot",
  "Internal Leadership Assignment",
  "Special Duty / Honor Guard Nomination",
  "Formal Performance Counseling",
  "Corrective Drill / Retraining Order",
];
