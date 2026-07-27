"use client";

import React, { useState } from "react";
import { UnitAction, EvaluatorSession } from "@/types/mdu";
import {
  MNDF_RANKS,
  ACTION_CATEGORIES,
  getRankBadgeColor,
} from "@/lib/mduConstants";
import {
  Award,
  PlusCircle,
  Trash2,
  CheckCircle2,
  Clock,
  AlertCircle,
  UserCheck,
} from "lucide-react";

interface UnitActionsTabProps {
  session: EvaluatorSession;
  actions: UnitAction[];
  onActionCreated: (newAction: UnitAction) => void;
  onActionUpdated: (updatedAction: UnitAction) => void;
  onActionDeleted: (id: number) => Promise<void>;
}

export function UnitActionsTab({
  session,
  actions,
  onActionCreated,
  onActionUpdated,
  onActionDeleted,
}: UnitActionsTabProps) {
  const [rank, setRank] = useState<string>("");
  const [name, setName] = useState<string>("");
  const [category, setCategory] = useState<string>(ACTION_CATEGORIES[0]);
  const [details, setDetails] = useState<string>("");
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [errorMsg, setErrorMsg] = useState<string>("");

  const handleCreateAction = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg("");

    if (!rank || !name.trim() || !details.trim()) {
      setErrorMsg("Please select a rank, enter a name, and provide justification notes.");
      return;
    }

    setIsSubmitting(true);
    try {
      const res = await fetch("/api/actions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          personnelRank: rank,
          personnelName: name.trim(),
          category,
          loggedBy: `${session.evaluatorRank} ${session.evaluatorName}`,
          details: details.trim(),
          status: "Active",
        }),
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || "Failed to log action.");
      }

      onActionCreated(data.action);
      setRank("");
      setName("");
      setDetails("");
    } catch (err: any) {
      setErrorMsg(err.message || "An error occurred.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleToggleStatus = async (action: UnitAction) => {
    const newStatus =
      action.status === "Active"
        ? "Completed"
        : action.status === "Completed"
        ? "Under Review"
        : "Active";

    try {
      const res = await fetch("/api/actions", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: action.id,
          status: newStatus,
        }),
      });
      const data = await res.json();
      if (res.ok && data.success) {
        onActionUpdated(data.action);
      }
    } catch (err) {
      console.error("Error updating status:", err);
    }
  };

  return (
    <div className="space-y-8">
      {/* Action form card */}
      <div className="rounded-2xl bg-slate-900 border border-slate-800 p-5 sm:p-6 shadow-xl space-y-5">
        <div className="flex items-center gap-3 border-b border-slate-800 pb-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-cyan-600/20 text-cyan-400 border border-cyan-700/60">
            <Award className="h-6 w-6" />
          </div>
          <div>
            <h2 className="text-base sm:text-lg font-black text-white">
              Log Unit Administrative Action or Recognition
            </h2>
            <p className="text-xs text-slate-400">
              Record internal MDU awards, Commando training slots, counseling, or corrective drill orders
            </p>
          </div>
        </div>

        {errorMsg && (
          <div className="rounded-xl bg-rose-950/80 border border-rose-700 p-3.5 text-xs text-rose-200">
            {errorMsg}
          </div>
        )}

        <form onSubmit={handleCreateAction} className="space-y-4">
          <div className="flex items-center justify-between">
            <label className="text-xs font-bold text-slate-300">
              Personnel Information
            </label>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-semibold text-slate-400 mb-1">
                Personnel Rank
              </label>
              <select
                value={rank}
                onChange={(e) => setRank(e.target.value)}
                className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3 py-2.5 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
                required
              >
                <option value="">-- Rank --</option>
                {MNDF_RANKS.map((r) => (
                  <option key={r.code} value={r.code}>
                    {r.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="sm:col-span-2">
              <label className="block text-xs font-semibold text-slate-400 mb-1">
                Personnel Name
              </label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="e.g. H. Ibrahim"
                className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3 py-2.5 text-sm text-slate-100 placeholder:text-slate-500 focus:border-cyan-500 focus:outline-none"
                required
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-400 mb-1">
              Action Category
            </label>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3 py-2.5 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
            >
              {ACTION_CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-400 mb-1">
              Justification &amp; Operational Notes
            </label>
            <textarea
              value={details}
              onChange={(e) => setDetails(e.target.value)}
              placeholder="Specify operational reasons, deployment drills, or scorecard metrics supporting this administrative order..."
              rows={3}
              required
              className="w-full rounded-lg bg-slate-950 border border-slate-700 p-3 text-xs sm:text-sm text-slate-100 placeholder:text-slate-500 focus:border-cyan-500 focus:outline-none"
            />
          </div>

          <div className="flex items-center justify-between pt-2">
            <span className="text-xs text-slate-400">
              Logged by:{" "}
              <strong className="text-cyan-400">
                {session.evaluatorRank} {session.evaluatorName}
              </strong>
            </span>
            <button
              type="submit"
              disabled={isSubmitting}
              className="flex items-center gap-2 rounded-xl bg-cyan-600 hover:bg-cyan-500 px-6 py-2.5 font-bold text-xs sm:text-sm text-white shadow-lg transition-colors disabled:opacity-50"
            >
              <PlusCircle className="h-4 w-4" />
              <span>{isSubmitting ? "Logging Action..." : "Log Action"}</span>
            </button>
          </div>
        </form>
      </div>

      {/* Logged actions history table */}
      <div className="rounded-2xl bg-slate-900 border border-slate-800 shadow-xl overflow-hidden">
        <div className="p-5 border-b border-slate-800">
          <h3 className="text-base sm:text-lg font-extrabold text-white">
            Unit Administrative Actions Log
          </h3>
          <p className="text-xs text-slate-400">
            Click status pill to cycle between Active, Completed, or Under Review
          </p>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse text-xs sm:text-sm">
            <thead>
              <tr className="border-b border-slate-800 bg-slate-950/60 text-slate-400 font-bold uppercase tracking-wider text-[11px]">
                <th className="py-3.5 px-4">Date</th>
                <th className="py-3.5 px-4">Personnel</th>
                <th className="py-3.5 px-4">Category</th>
                <th className="py-3.5 px-4">Logged By</th>
                <th className="py-3.5 px-4">Notes</th>
                <th className="py-3.5 px-4">Status</th>
                <th className="py-3.5 px-4 text-right">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60">
              {actions.length === 0 ? (
                <tr>
                  <td
                    colSpan={7}
                    className="py-10 text-center text-slate-500 text-xs font-medium"
                  >
                    No unit administrative actions logged yet.
                  </td>
                </tr>
              ) : (
                actions.map((act) => {
                  const isAward =
                    act.category.includes("Commendation") ||
                    act.category.includes("Award") ||
                    act.category.includes("Priority");
                  return (
                    <tr
                      key={act.id}
                      className="hover:bg-slate-800/40 transition-colors"
                    >
                      <td className="py-3 px-4 text-slate-400 whitespace-nowrap">
                        {new Date(act.createdAt).toLocaleDateString()}
                      </td>
                      <td className="py-3 px-4 whitespace-nowrap">
                        <span
                          className={`inline-flex items-center rounded px-2 py-0.5 text-xs font-bold mr-2 ${getRankBadgeColor(
                            act.personnelRank
                          )}`}
                        >
                          {act.personnelRank}
                        </span>
                        <span className="font-bold text-white">
                          {act.personnelName}
                        </span>
                      </td>
                      <td className="py-3 px-4">
                        <span
                          className={`inline-flex items-center rounded-full px-3 py-1 text-[11px] font-bold ${
                            isAward
                              ? "bg-emerald-950/80 text-emerald-300 border border-emerald-700"
                              : "bg-cyan-950/80 text-cyan-300 border border-cyan-700"
                          }`}
                        >
                          {act.category}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-slate-300 font-medium whitespace-nowrap">
                        {act.loggedBy}
                      </td>
                      <td className="py-3 px-4 text-slate-300 max-w-sm">
                        {act.details}
                      </td>
                      <td className="py-3 px-4 whitespace-nowrap">
                        <button
                          onClick={() => handleToggleStatus(act)}
                          className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-bold cursor-pointer transition-colors ${
                            act.status === "Completed"
                              ? "bg-emerald-950 text-emerald-300 border border-emerald-600 hover:bg-emerald-900"
                              : act.status === "Under Review"
                              ? "bg-amber-950 text-amber-300 border border-amber-600 hover:bg-amber-900"
                              : "bg-cyan-950 text-cyan-300 border border-cyan-600 hover:bg-cyan-900"
                          }`}
                          title="Click to change status"
                        >
                          {act.status === "Completed" && (
                            <CheckCircle2 className="h-3.5 w-3.5" />
                          )}
                          {act.status === "Active" && (
                            <Clock className="h-3.5 w-3.5" />
                          )}
                          {act.status === "Under Review" && (
                            <AlertCircle className="h-3.5 w-3.5" />
                          )}
                          <span>{act.status}</span>
                        </button>
                      </td>
                      <td className="py-3 px-4 text-right whitespace-nowrap">
                        <button
                          onClick={() => onActionDeleted(act.id)}
                          className="rounded-lg p-1.5 text-slate-400 hover:bg-rose-950 hover:text-rose-300 transition-colors"
                          title="Delete action record"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
