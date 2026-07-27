export interface MarinePersonnel {
  id: number;
  serviceNo: string;
  rank: string;
  name: string;
  platoon: string;
  role: string;
  createdAt: string;
}

export interface ScoreItem {
  compId: string;
  score: number;
  evidence: string;
}

export interface MarineEvaluation {
  id: number;
  evaluatorRank: string;
  evaluatorName: string;
  targetRank: string;
  targetName: string;
  evalType: "Self" | "Supervisor" | "Peer";
  scoresJson: string; // JSON string of ScoreItem[]
  compositeScore: number;
  declarationSigned: boolean;
  createdAt: string;
}

export interface UnitAction {
  id: number;
  personnelRank: string;
  personnelName: string;
  category: string;
  loggedBy: string;
  details: string;
  status: string;
  createdAt: string;
}

export interface SystemFeedback {
  id: number;
  submitterRank: string;
  submitterName: string;
  fairnessRating: number;
  evidenceSafeguardOpinion: string;
  comments: string;
  createdAt: string;
}

export interface EvaluatorSession {
  evaluatorRank: string;
  evaluatorName: string;
  targetRank: string;
  targetName: string;
  evalType: "Self" | "Supervisor" | "Peer";
  mode: "self" | "other";
}
