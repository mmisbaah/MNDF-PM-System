"use client";

import React, { useState } from "react";
import { EvaluatorSession, MarineEvaluation, ScoreItem } from "@/types/mdu";
import {
  COMPETENCIES,
  CATEGORY_LABELS,
  SCORE_LABELS,
  EVIDENCE_TRIGGERS,
  getRankBadgeColor,
} from "@/lib/mduConstants";
import {
  ShieldCheck,
  AlertTriangle,
  CheckCircle2,
  RefreshCw,
  Award,
  FileText,
  UserCheck,
} from "lucide-react";

interface EvaluationFormProps {
  session: EvaluatorSession;
  onSubmitted: (newEvaluation: MarineEvaluation) => void;
  onSwitchTarget: () => void;
}

export function EvaluationForm({
  session,
  onSubmitted,
  onSwitchTarget,
}: EvaluationFormProps) {
  // Initialize scores state for all 18 parameters
  const [scores, setScores] = useState<Record<string, { score: number; evidence: string }>>(
    () => {
      const init: Record<string, { score: number; evidence: string }> = {};
      COMPETENCIES.forEach((c) => {
        init[c.id] = { score: 3, evidence: "" };
      });
      return init;
    }
  );

  const [declarationSigned, setDeclarationSigned] = useState<boolean>(false);
  const [errorMsg, setErrorMsg] = useState<string>("");
  const [successMsg, setSuccessMsg] = useState<string>("");
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);

  const handleScoreChange = (compId: string, val: number) => {
    setScores((prev) => ({
      ...prev,
      [compId]: {
        score: val,
        // Keep existing evidence if still required, or clear if switched to 3 or 4
        evidence: prev[compId]?.evidence || "",
      },
    }));
  };

  const handleEvidenceChange = (compId: string, text: string) => {
    setScores((prev) => ({
      ...prev,
      [compId]: {
        ...prev[compId],
        evidence: text,
      },
    }));
  };

  // Calculate current composite average
  const currentAvg = (() => {
    const vals = Object.values(scores);
    if (!vals.length) return 0;
    const sum = vals.reduce((acc, item) => acc + item.score, 0);
    return Number((sum / vals.length).toFixed(2));
  })();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg("");
    setSuccessMsg("");

    if (!declarationSigned) {
      setErrorMsg(
        "You must sign the Al-'Adl Integrity Declaration confirming impartiality before submitting."
      );
      return;
    }

    // Check Al-'Adl behavioral evidence safeguard
    const missingEvidenceItems: string[] = [];
    COMPETENCIES.forEach((c) => {
      const item = scores[c.id];
      if (EVIDENCE_TRIGGERS[item.score] && !item.evidence.trim()) {
        missingEvidenceItems.push(c.title);
      }
    });

    if (missingEvidenceItems.length > 0) {
      setErrorMsg(
        `AL-'ADL SAFEGUARD EXCEPTION: Written behavioral evidence is mandatory for scores 1, 2, and 5. Please provide objective evidence for: ${missingEvidenceItems
          .slice(0, 3)
          .join(", ")}${
          missingEvidenceItems.length > 3
            ? ` and ${missingEvidenceItems.length - 3} more`
            : ""
        }.`
      );
      return;
    }

    setIsSubmitting(true);
    try {
      const scoreEntries: ScoreItem[] = COMPETENCIES.map((c) => ({
        compId: c.id,
        score: scores[c.id].score,
        evidence: scores[c.id].evidence.trim(),
      }));

      const res = await fetch("/api/evaluations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          evaluatorRank: session.evaluatorRank,
          evaluatorName: session.evaluatorName,
          targetRank: session.targetRank,
          targetName: session.targetName,
          evalType: session.evalType,
          scoresJson: scoreEntries,
          compositeScore: currentAvg,
          declarationSigned: true,
        }),
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(
          data.error || "Failed to submit evaluation to server."
        );
      }

      setSuccessMsg(
        `Assessment successfully recorded for ${session.targetRank} ${session.targetName} with composite score ${currentAvg}.`
      );

      // Reset form
      const resetState: Record<string, { score: number; evidence: string }> = {};
      COMPETENCIES.forEach((c) => {
        resetState[c.id] = { score: 3, evidence: "" };
      });
      setScores(resetState);
      setDeclarationSigned(false);

      onSubmitted(data.evaluation);
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (err: any) {
      setErrorMsg(err.message || "An error occurred during submission.");
    } finally {
      setIsSubmitting(false);
    }
  };

  // Group competencies by category
  const categories = ["ethos", "leadership", "followership", "fitness", "training", "cohesion"];

  return (
    <div className="space-y-6">
      {/* Top Banner: Evaluator vs Target */}
      <div className="rounded-2xl bg-gradient-to-r from-slate-900 via-slate-800 to-slate-900 border border-slate-700/80 p-5 shadow-xl">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <span className="text-xs font-bold uppercase tracking-wider text-cyan-400">
                {session.mode === "self" ? "Self Assessment Mode" : "Personnel Evaluation Mode"}
              </span>
              <span className="rounded-full bg-cyan-950 px-2.5 py-0.5 text-[11px] font-semibold text-cyan-300 border border-cyan-800">
                {session.evalType} Perspective
              </span>
            </div>
            <h2 className="text-lg sm:text-xl font-black text-white flex items-center gap-2 flex-wrap">
              <span>Evaluating:</span>
              <span
                className={`inline-flex items-center rounded px-2 py-0.5 text-xs font-bold ${getRankBadgeColor(
                  session.targetRank
                )}`}
              >
                {session.targetRank}
              </span>
              <span className="text-cyan-200">{session.targetName}</span>
            </h2>
            <p className="text-xs text-slate-300">
              Evaluator: <strong className="text-slate-100">{session.evaluatorRank} {session.evaluatorName}</strong> • Real-time Composite Average:{" "}
              <strong className="text-cyan-400 text-sm font-bold">{currentAvg} / 5.00</strong>
            </p>
          </div>

          <button
            type="button"
            onClick={onSwitchTarget}
            className="flex items-center justify-center gap-1.5 rounded-xl bg-slate-800 border border-slate-600 px-4 py-2.5 text-xs font-semibold text-slate-200 hover:bg-slate-700 transition-colors shrink-0"
          >
            <RefreshCw className="h-4 w-4 text-cyan-400" />
            <span>Switch Target Marine</span>
          </button>
        </div>
      </div>

      {/* Success / Error notification */}
      {successMsg && (
        <div className="rounded-xl bg-emerald-950/80 border border-emerald-600 p-4 text-sm text-emerald-200 flex items-center gap-3 shadow-lg">
          <CheckCircle2 className="h-6 w-6 text-emerald-400 shrink-0" />
          <div>
            <p className="font-bold">{successMsg}</p>
            <p className="text-xs text-emerald-300/80">
              The record has been saved to the PostgreSQL database and added to the research dashboard.
            </p>
          </div>
        </div>
      )}

      {errorMsg && (
        <div className="rounded-xl bg-rose-950/80 border border-rose-700 p-4 text-sm text-rose-200 flex items-center gap-3 shadow-lg">
          <AlertTriangle className="h-6 w-6 text-rose-400 shrink-0" />
          <div>
            <p className="font-bold">Evaluation Submission Alert</p>
            <p className="text-xs text-rose-300/90">{errorMsg}</p>
          </div>
        </div>
      )}

      {/* Form with categories & 18 parameters */}
      <form onSubmit={handleSubmit} className="space-y-8">
        {categories.map((catId) => {
          const items = COMPETENCIES.filter((c) => c.category === catId);
          return (
            <div
              key={catId}
              className="rounded-2xl bg-slate-900/90 border border-slate-800/80 p-5 sm:p-6 shadow-xl space-y-5"
            >
              <div className="flex items-center justify-between border-b border-slate-800 pb-3">
                <div className="flex items-center gap-2.5">
                  <div className="h-2 w-2 rounded-full bg-cyan-400" />
                  <h3 className="text-sm sm:text-base font-extrabold uppercase tracking-wide text-cyan-400">
                    {CATEGORY_LABELS[catId]}
                  </h3>
                </div>
                <span className="text-[11px] font-semibold text-slate-400">
                  {items.length} Parameters
                </span>
              </div>

              <div className="space-y-6">
                {items.map((comp) => {
                  const currentItem = scores[comp.id];
                  const showEvidence = EVIDENCE_TRIGGERS[currentItem.score];

                  return (
                    <div
                      key={comp.id}
                      className="rounded-xl bg-slate-800/40 border border-slate-800 p-4 sm:p-5 transition-colors hover:border-slate-700"
                    >
                      <div className="flex flex-col md:flex-row md:items-start justify-between gap-3 mb-3">
                        <div className="space-y-1 max-w-xl">
                          <h4 className="text-sm sm:text-base font-bold text-white flex items-center gap-2">
                            <span>{comp.title}</span>
                          </h4>
                          <p className="text-xs text-slate-400 leading-relaxed">
                            {comp.desc}
                          </p>
                        </div>
                        <div className="shrink-0">
                          <span
                            className={`inline-flex items-center rounded-lg px-3 py-1 text-xs font-bold ${
                              currentItem.score >= 4
                                ? "bg-emerald-950/80 text-emerald-300 border border-emerald-700/60"
                                : currentItem.score === 3
                                ? "bg-cyan-950/80 text-cyan-300 border border-cyan-700/60"
                                : "bg-rose-950/80 text-rose-300 border border-rose-700/60"
                            }`}
                          >
                            Score: {currentItem.score} / 5
                          </span>
                        </div>
                      </div>

                      <div className="mt-3">
                        <label className="block text-[11px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                          Performance Rating Scale
                        </label>
                        <select
                          value={currentItem.score}
                          onChange={(e) =>
                            handleScoreChange(comp.id, parseInt(e.target.value, 10))
                          }
                          className="w-full rounded-lg bg-slate-900 border border-slate-700 px-3.5 py-2.5 text-sm font-medium text-slate-200 focus:border-cyan-500 focus:outline-none transition-colors"
                        >
                          {[5, 4, 3, 2, 1].map((num) => (
                            <option key={num} value={num}>
                              {SCORE_LABELS[num]}
                            </option>
                          ))}
                        </select>
                      </div>

                      {/* Al-'Adl safeguard textarea */}
                      {showEvidence && (
                        <div className="mt-3.5 rounded-xl bg-rose-950/60 border border-rose-800/80 p-3.5 animate-in fade-in duration-200 space-y-2">
                          <div className="flex items-center gap-2 text-rose-300">
                            <AlertTriangle className="h-4 w-4 shrink-0" />
                            <span className="text-xs font-bold uppercase tracking-wider">
                              Al-&lsquo;Adl Safeguard Triggered (Score {currentItem.score}): Mandatory Written Evidence Required
                            </span>
                          </div>
                          <p className="text-[11px] text-rose-200/80 leading-relaxed">
                            To prevent arbitrary bias or favoritism, scores of 1, 2, or 5 require specific observable incidents, deployment dates, or objective operational metrics.
                          </p>
                          <textarea
                            value={currentItem.evidence}
                            onChange={(e) =>
                              handleEvidenceChange(comp.id, e.target.value)
                            }
                            placeholder="Detail observable behaviors, dates, operational drills, or PET metrics supporting this rating..."
                            rows={3}
                            required
                            className="w-full rounded-lg bg-slate-900/90 border border-rose-700/60 p-2.5 text-xs text-slate-100 placeholder:text-slate-500 focus:border-rose-400 focus:outline-none"
                          />
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}

        {/* AL-'ADL INTEGRITY DECLARATION */}
        <div className="rounded-2xl bg-gradient-to-br from-slate-900 to-cyan-950/40 border border-cyan-800/60 p-5 sm:p-6 shadow-xl space-y-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-cyan-600/20 text-cyan-400 border border-cyan-600/40">
              <ShieldCheck className="h-6 w-6" />
            </div>
            <div>
              <h3 className="text-base font-bold text-white">
                Al-&lsquo;Adl (Justice) Integrity Declaration
              </h3>
              <p className="text-xs text-slate-400">
                Mandatory ethical oath before MNDF MDU command submission
              </p>
            </div>
          </div>

          <p className="text-xs sm:text-sm text-slate-300 bg-slate-900/80 p-4 rounded-xl border border-slate-800 italic leading-relaxed">
            &ldquo;I declare before Allah that this evaluation is based strictly on observable behaviors, objective duty execution, and professional military standards, free from personal bias, favor, or prejudice.&rdquo;
          </p>

          <label className="flex items-start gap-3 cursor-pointer pt-1">
            <input
              type="checkbox"
              checked={declarationSigned}
              onChange={(e) => setDeclarationSigned(e.target.checked)}
              className="mt-1 h-5 w-5 rounded border-slate-700 bg-slate-900 text-cyan-600 focus:ring-cyan-500 focus:ring-offset-slate-900 cursor-pointer"
            />
            <span className="text-sm font-semibold text-slate-200">
              I solemnly sign and confirm this Al-&lsquo;Adl Integrity Declaration as{" "}
              <strong className="text-cyan-400">
                {session.evaluatorRank} {session.evaluatorName}
              </strong>.
            </span>
          </label>
        </div>

        {/* Submit button */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-end gap-3 pt-2">
          <button
            type="button"
            onClick={() => {
              window.scrollTo({ top: 0, behavior: "smooth" });
            }}
            className="rounded-xl border border-slate-700 bg-slate-800/80 px-5 py-3 text-sm font-semibold text-slate-300 hover:bg-slate-700 transition-colors"
          >
            Review Scores ({currentAvg} Avg)
          </button>
          <button
            type="submit"
            disabled={isSubmitting}
            className="flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-cyan-600 to-blue-700 hover:from-cyan-500 hover:to-blue-600 px-8 py-3.5 text-sm sm:text-base font-bold text-white shadow-xl shadow-cyan-900/30 transition-all disabled:opacity-50"
          >
            <ShieldCheck className="h-5 w-5" />
            <span>
              {isSubmitting
                ? "Submitting Evaluation to PostgreSQL..."
                : `Submit Assessment for ${session.targetRank} ${session.targetName}`}
            </span>
          </button>
        </div>
      </form>
    </div>
  );
}
