"use client";

import React, { useState } from "react";
import { SystemFeedback, EvaluatorSession } from "@/types/mdu";
import { MNDF_RANKS, getRankBadgeColor } from "@/lib/mduConstants";
import {
  MessageSquare,
  Send,
  Trash2,
  CheckCircle2,
  HelpCircle,
  Star,
} from "lucide-react";

interface SystemFeedbackTabProps {
  session: EvaluatorSession;
  feedbackList: SystemFeedback[];
  onFeedbackCreated: (item: SystemFeedback) => void;
  onFeedbackDeleted: (id: number) => Promise<void>;
}

export function SystemFeedbackTab({
  session,
  feedbackList,
  onFeedbackCreated,
  onFeedbackDeleted,
}: SystemFeedbackTabProps) {
  const [fairness, setFairness] = useState<number>(5);
  const [safeguardOpinion, setSafeguardOpinion] = useState<string>(
    "Yes - Significantly reduces arbitrary ratings"
  );
  const [comments, setComments] = useState<string>("");
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [errorMsg, setErrorMsg] = useState<string>("");

  const handleSubmitFeedback = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg("");

    setIsSubmitting(true);
    try {
      const res = await fetch("/api/feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          submitterRank: session.evaluatorRank,
          submitterName: session.evaluatorName,
          fairnessRating: fairness,
          evidenceSafeguardOpinion: safeguardOpinion,
          comments: comments.trim() || "N/A",
        }),
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || "Failed to submit feedback.");
      }

      onFeedbackCreated(data.feedback);
      setComments("");
      setFairness(5);
    } catch (err: any) {
      setErrorMsg(err.message || "An error occurred.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="space-y-8">
      {/* Feedback submission form */}
      <div className="rounded-2xl bg-slate-900 border border-slate-800 p-5 sm:p-6 shadow-xl space-y-5">
        <div className="flex items-center gap-3 border-b border-slate-800 pb-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-amber-500/20 text-amber-400 border border-amber-500/30">
            <MessageSquare className="h-6 w-6" />
          </div>
          <div>
            <h2 className="text-base sm:text-lg font-black text-white">
              PDS Multi-Rater Tool vs. Legacy System Feedback
            </h2>
            <p className="text-xs text-slate-400">
              Contribute anonymized perception data on Al-&lsquo;Adl safeguard fairness &amp; system effectiveness
            </p>
          </div>
        </div>

        {errorMsg && (
          <div className="rounded-xl bg-rose-950/80 border border-rose-700 p-3.5 text-xs text-rose-200">
            {errorMsg}
          </div>
        )}

        <form onSubmit={handleSubmitFeedback} className="space-y-5">
          <div>
            <label className="block text-xs font-bold text-slate-300 mb-2">
              1. Compared to legacy annual paper appraisals, how fair and objective is this multi-rater PDS tool?
            </label>
            <select
              value={fairness}
              onChange={(e) => setFairness(parseInt(e.target.value, 10))}
              className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3.5 py-2.5 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
            >
              <option value="5">
                5 - Much More Fair &amp; Transparent (60% Sup / 25% Self / 15% Peer)
              </option>
              <option value="4">4 - Slightly More Fair</option>
              <option value="3">3 - About the Same as Legacy System</option>
              <option value="2">2 - Less Fair / Administrative Friction</option>
              <option value="1">1 - Biased / Unfair</option>
            </select>
          </div>

          <div>
            <label className="block text-xs font-bold text-slate-300 mb-2">
              2. Does the requirement for written behavioral evidence (Al-&lsquo;Adl Safeguard) improve supervisor accountability?
            </label>
            <select
              value={safeguardOpinion}
              onChange={(e) => setSafeguardOpinion(e.target.value)}
              className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3.5 py-2.5 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
            >
              <option value="Yes - Significantly reduces arbitrary ratings">
                Yes - Significantly reduces arbitrary ratings &amp; favoritism
              </option>
              <option value="Neutral / Unsure">
                Neutral / Unsure of operational impact
              </option>
              <option value="No - Creates extra administrative burden">
                No - Creates extra administrative burden
              </option>
            </select>
          </div>

          <div>
            <label className="block text-xs font-bold text-slate-300 mb-2">
              3. Qualitative Feedback &amp; Suggestions for System Improvement
            </label>
            <textarea
              value={comments}
              onChange={(e) => setComments(e.target.value)}
              placeholder="Share thoughts on deployment applicability, drill metrics, or weight adjustments..."
              rows={3}
              className="w-full rounded-lg bg-slate-950 border border-slate-700 p-3 text-xs sm:text-sm text-slate-100 placeholder:text-slate-500 focus:border-cyan-500 focus:outline-none"
            />
          </div>

          <div className="flex items-center justify-between pt-2">
            <span className="text-xs text-slate-400">
              Submitting as:{" "}
              <strong className="text-cyan-400">
                {session.evaluatorRank} ({session.evaluatorName})
              </strong>
            </span>
            <button
              type="submit"
              disabled={isSubmitting}
              className="flex items-center gap-2 rounded-xl bg-amber-600 hover:bg-amber-500 px-6 py-2.5 font-bold text-xs sm:text-sm text-white shadow-lg transition-colors disabled:opacity-50"
            >
              <Send className="h-4 w-4" />
              <span>{isSubmitting ? "Submitting..." : "Submit Feedback"}</span>
            </button>
          </div>
        </form>
      </div>

      {/* Collected feedback log table */}
      <div className="rounded-2xl bg-slate-900 border border-slate-800 shadow-xl overflow-hidden">
        <div className="p-5 border-b border-slate-800">
          <h3 className="text-base sm:text-lg font-extrabold text-white">
            Collected Personnel Feedback Log
          </h3>
          <p className="text-xs text-slate-400">
            Anonymized system perception responses stored in PostgreSQL
          </p>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse text-xs sm:text-sm">
            <thead>
              <tr className="border-b border-slate-800 bg-slate-950/60 text-slate-400 font-bold uppercase tracking-wider text-[11px]">
                <th className="py-3.5 px-4">Date</th>
                <th className="py-3.5 px-4">Rank Role</th>
                <th className="py-3.5 px-4">Fairness Rating</th>
                <th className="py-3.5 px-4">Al-&lsquo;Adl Safeguard Impact</th>
                <th className="py-3.5 px-4">Comments</th>
                <th className="py-3.5 px-4 text-right">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60">
              {feedbackList.length === 0 ? (
                <tr>
                  <td
                    colSpan={6}
                    className="py-10 text-center text-slate-500 text-xs font-medium"
                  >
                    No feedback responses submitted yet.
                  </td>
                </tr>
              ) : (
                feedbackList.map((fb) => (
                  <tr
                    key={fb.id}
                    className="hover:bg-slate-800/40 transition-colors"
                  >
                    <td className="py-3 px-4 text-slate-400 whitespace-nowrap">
                      {new Date(fb.createdAt).toLocaleDateString()}
                    </td>
                    <td className="py-3 px-4 whitespace-nowrap">
                      <span
                        className={`inline-flex items-center rounded px-2 py-0.5 text-xs font-bold ${getRankBadgeColor(
                          fb.submitterRank
                        )}`}
                      >
                        {fb.submitterRank}
                      </span>
                    </td>
                    <td className="py-3 px-4">
                      <span className="inline-flex items-center gap-1 font-bold text-amber-400">
                        <Star className="h-4 w-4 fill-amber-400" />
                        <span>{fb.fairnessRating} / 5</span>
                      </span>
                    </td>
                    <td className="py-3 px-4 text-slate-300 font-medium">
                      {fb.evidenceSafeguardOpinion}
                    </td>
                    <td className="py-3 px-4 text-slate-300 max-w-sm">
                      {fb.comments}
                    </td>
                    <td className="py-3 px-4 text-right whitespace-nowrap">
                      <button
                        onClick={() => onFeedbackDeleted(fb.id)}
                        className="rounded-lg p-1.5 text-slate-400 hover:bg-rose-950 hover:text-rose-300 transition-colors"
                        title="Delete feedback entry"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
