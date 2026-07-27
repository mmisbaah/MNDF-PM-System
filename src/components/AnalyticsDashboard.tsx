"use client";

import React, { useState } from "react";
import { MarineEvaluation } from "@/types/mdu";
import {
  MNDF_RANKS,
  getRankBadgeColor,
  SCORE_LABELS,
  COMPETENCIES,
} from "@/lib/mduConstants";
import {
  BarChart3,
  Download,
  Search,
  Filter,
  Trash2,
  FileText,
  AlertTriangle,
  Award,
  ChevronDown,
  ChevronUp,
} from "lucide-react";

interface AnalyticsDashboardProps {
  evaluations: MarineEvaluation[];
  onDeleteEvaluation: (id: number) => Promise<void>;
}

export function AnalyticsDashboard({
  evaluations,
  onDeleteEvaluation,
}: AnalyticsDashboardProps) {
  const [searchTerm, setSearchTerm] = useState("");
  const [rankFilter, setRankFilter] = useState("");
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);

  // Parse all score items once for quick stats
  let totalSafeguardTriggers = 0;
  evaluations.forEach((ev) => {
    try {
      const scores = JSON.parse(ev.scoresJson);
      if (Array.isArray(scores)) {
        scores.forEach((s: { score: number; evidence: string }) => {
          if (s.score === 1 || s.score === 2 || s.score === 5) {
            totalSafeguardTriggers++;
          }
        });
      }
    } catch (e) {}
  });

  // Build target personnel analytics scorecard (Supervisor 60%, Self 25%, Peer 15%)
  interface MarineStat {
    rank: string;
    name: string;
    supScores: number[];
    selfScores: number[];
    peerScores: number[];
  }
  const targetMap: Record<string, MarineStat> = {};
  evaluations.forEach((ev) => {
    const key = `${ev.targetRank}||${ev.targetName.trim().toLowerCase()}`;
    if (!targetMap[key]) {
      targetMap[key] = {
        rank: ev.targetRank,
        name: ev.targetName,
        supScores: [],
        selfScores: [],
        peerScores: [],
      };
    }
    if (ev.evalType === "Supervisor") {
      targetMap[key].supScores.push(ev.compositeScore);
    } else if (ev.evalType === "Self") {
      targetMap[key].selfScores.push(ev.compositeScore);
    } else if (ev.evalType === "Peer") {
      targetMap[key].peerScores.push(ev.compositeScore);
    }
  });

  const rosterStats = Object.values(targetMap).map((m) => {
    const avgSup = m.supScores.length
      ? m.supScores.reduce((a, b) => a + b, 0) / m.supScores.length
      : 0;
    const avgSelf = m.selfScores.length
      ? m.selfScores.reduce((a, b) => a + b, 0) / m.selfScores.length
      : 0;
    const avgPeer = m.peerScores.length
      ? m.peerScores.reduce((a, b) => a + b, 0) / m.peerScores.length
      : 0;

    let composite = 0;
    let totalWeight = 0;
    if (avgSup > 0) {
      composite += avgSup * 0.6;
      totalWeight += 0.6;
    }
    if (avgSelf > 0) {
      composite += avgSelf * 0.25;
      totalWeight += 0.25;
    }
    if (avgPeer > 0) {
      composite += avgPeer * 0.15;
      totalWeight += 0.15;
    }

    const finalComposite = totalWeight > 0 ? (composite / totalWeight).toFixed(2) : "N/A";
    const gap =
      avgSup > 0 && avgSelf > 0
        ? Math.abs(avgSelf - avgSup).toFixed(2)
        : "N/A";

    return {
      rank: m.rank,
      name: m.name,
      avgSup,
      avgSelf,
      avgPeer,
      finalComposite,
      gap,
    };
  });

  const gapVals = rosterStats
    .map((r) => r.gap)
    .filter((g) => g !== "N/A")
    .map(Number);
  const avgGap = gapVals.length
    ? (gapVals.reduce((a, b) => a + b, 0) / gapVals.length).toFixed(2)
    : "0.00";

  // Filter evaluations list
  const filteredEvals = evaluations.filter((ev) => {
    const matchesSearch =
      ev.targetName.toLowerCase().includes(searchTerm.toLowerCase()) ||
      ev.evaluatorName.toLowerCase().includes(searchTerm.toLowerCase()) ||
      ev.targetRank.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesRank = !rankFilter || ev.targetRank === rankFilter;
    return matchesSearch && matchesRank;
  });

  const handleExportCSV = () => {
    if (!evaluations.length) return;
    const headers = [
      "Assessment_ID",
      "Timestamp",
      "Evaluator_Rank",
      "Evaluator_Name",
      "Target_Rank",
      "Target_Name",
      "Role_Type",
      "Composite_Score",
      "Competency_ID",
      "Competency_Score",
      "Evidence_Notes",
    ];

    let csvContent = headers.join(",") + "\n";
    evaluations.forEach((ev) => {
      let scores = [];
      try {
        scores = JSON.parse(ev.scoresJson);
      } catch (e) {}

      if (Array.isArray(scores)) {
        scores.forEach((s: { compId: string; score: number; evidence: string }) => {
          const cleanEvidence = `"${(s.evidence || "").replace(/"/g, '""')}"`;
          const row = [
            ev.id,
            ev.createdAt,
            ev.evaluatorRank,
            `"${ev.evaluatorName}"`,
            ev.targetRank,
            `"${ev.targetName}"`,
            ev.evalType,
            ev.compositeScore,
            s.compId,
            s.score,
            cleanEvidence,
          ];
          csvContent += row.join(",") + "\n";
        });
      }
    });

    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.setAttribute(
      "download",
      `MNDF_MDU_Research_Data_${new Date().toISOString().slice(0, 10)}.csv`
    );
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  const handleDeleteClick = async (id: number) => {
    if (deletingId === id) {
      await onDeleteEvaluation(id);
      setDeletingId(null);
    } else {
      setDeletingId(id);
      setTimeout(() => setDeletingId(null), 4000);
    }
  };

  return (
    <div className="space-y-6">
      {/* KPI Stats Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="rounded-2xl bg-slate-900 border border-slate-800 p-5 shadow-lg flex items-center justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-wider text-slate-400">
              Total Assessments
            </p>
            <p className="text-3xl font-black text-white mt-1">
              {evaluations.length}
            </p>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-cyan-950 border border-cyan-800 text-cyan-400">
            <BarChart3 className="h-6 w-6" />
          </div>
        </div>

        <div className="rounded-2xl bg-slate-900 border border-slate-800 p-5 shadow-lg flex items-center justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-wider text-slate-400">
              Evaluated Marines
            </p>
            <p className="text-3xl font-black text-white mt-1">
              {rosterStats.length}
            </p>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-blue-950 border border-blue-800 text-blue-400">
            <Award className="h-6 w-6" />
          </div>
        </div>

        <div className="rounded-2xl bg-slate-900 border border-slate-800 p-5 shadow-lg flex items-center justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-wider text-slate-400">
              Avg Sup-Self Gap
            </p>
            <p className="text-3xl font-black text-cyan-400 mt-1">
              {avgGap}
            </p>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-cyan-950 border border-cyan-800 text-cyan-400">
            <BarChart3 className="h-6 w-6" />
          </div>
        </div>

        <div className="rounded-2xl bg-slate-900 border border-slate-800 p-5 shadow-lg flex items-center justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-wider text-slate-400">
              Al-&lsquo;Adl Triggers
            </p>
            <p className="text-3xl font-black text-rose-400 mt-1">
              {totalSafeguardTriggers}
            </p>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-rose-950 border border-rose-800 text-rose-400">
            <AlertTriangle className="h-6 w-6" />
          </div>
        </div>
      </div>

      {/* Multi-Rater Scorecard Card */}
      <div className="rounded-2xl bg-slate-900 border border-slate-800 shadow-xl overflow-hidden">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-5 border-b border-slate-800">
          <div>
            <h3 className="text-base sm:text-lg font-extrabold text-white">
              Compiled Multi-Rater Performance Scorecard
            </h3>
            <p className="text-xs text-slate-400 mt-0.5">
              Weighted composite distribution: Supervisor (60%), Self (25%), Peer (15%)
            </p>
          </div>
          <button
            onClick={handleExportCSV}
            disabled={!evaluations.length}
            className="flex items-center justify-center gap-1.5 rounded-xl bg-cyan-600 hover:bg-cyan-500 text-white font-bold px-4 py-2 text-xs transition-colors shadow-lg disabled:opacity-50"
          >
            <Download className="h-4 w-4" />
            <span>Export CSV Dataset</span>
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse text-xs sm:text-sm">
            <thead>
              <tr className="border-b border-slate-800 bg-slate-950/60 text-slate-400 font-bold uppercase tracking-wider text-[11px]">
                <th className="py-3.5 px-4">Personnel Name</th>
                <th className="py-3.5 px-4">Rank</th>
                <th className="py-3.5 px-4">Supervisor (60%)</th>
                <th className="py-3.5 px-4">Self (25%)</th>
                <th className="py-3.5 px-4">Peer (15%)</th>
                <th className="py-3.5 px-4 text-cyan-400">Composite</th>
                <th className="py-3.5 px-4">Perception Gap</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60">
              {rosterStats.length === 0 ? (
                <tr>
                  <td
                    colSpan={7}
                    className="py-10 text-center text-slate-500 text-xs font-medium"
                  >
                    No assessments recorded in the PostgreSQL database yet.
                  </td>
                </tr>
              ) : (
                rosterStats.map((r, i) => {
                  const isHighGap =
                    r.gap !== "N/A" && parseFloat(r.gap) >= 1.0;
                  return (
                    <tr
                      key={i}
                      className="hover:bg-slate-800/40 transition-colors"
                    >
                      <td className="py-3 px-4 font-bold text-white">
                        {r.name}
                      </td>
                      <td className="py-3 px-4">
                        <span
                          className={`inline-flex items-center rounded px-2 py-0.5 text-xs font-bold ${getRankBadgeColor(
                            r.rank
                          )}`}
                        >
                          {r.rank}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-slate-300">
                        {r.avgSup > 0 ? r.avgSup.toFixed(2) : "—"}
                      </td>
                      <td className="py-3 px-4 text-slate-300">
                        {r.avgSelf > 0 ? r.avgSelf.toFixed(2) : "—"}
                      </td>
                      <td className="py-3 px-4 text-slate-300">
                        {r.avgPeer > 0 ? r.avgPeer.toFixed(2) : "—"}
                      </td>
                      <td className="py-3 px-4 font-black text-cyan-400 text-base">
                        {r.finalComposite}
                      </td>
                      <td className="py-3 px-4">
                        <span
                          className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold ${
                            isHighGap
                              ? "bg-amber-950 text-amber-300 border border-amber-600"
                              : "bg-slate-800 text-slate-300 border border-slate-700"
                          }`}
                        >
                          {r.gap}
                        </span>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Individual Evaluation Log Section */}
      <div className="rounded-2xl bg-slate-900 border border-slate-800 shadow-xl p-5 space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800 pb-4">
          <div>
            <h3 className="text-base sm:text-lg font-extrabold text-white">
              Individual Assessment Log History
            </h3>
            <p className="text-xs text-slate-400">
              Inspect full score breakdowns and Al-&lsquo;Adl evidence notes
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-500" />
              <input
                type="text"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="Search marine or evaluator..."
                className="rounded-lg bg-slate-950 border border-slate-700 pl-8 pr-3 py-1.5 text-xs text-slate-200 placeholder:text-slate-500 focus:outline-none focus:border-cyan-500"
              />
            </div>

            <select
              value={rankFilter}
              onChange={(e) => setRankFilter(e.target.value)}
              className="rounded-lg bg-slate-950 border border-slate-700 px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-cyan-500"
            >
              <option value="">All Ranks</option>
              {MNDF_RANKS.map((r) => (
                <option key={r.code} value={r.code}>
                  {r.label}
                </option>
              ))}
            </select>
          </div>
        </div>

        {filteredEvals.length === 0 ? (
          <div className="py-12 text-center text-slate-500 text-xs">
            No matching assessment records found.
          </div>
        ) : (
          <div className="space-y-3">
            {filteredEvals.map((ev) => {
              const isExpanded = expandedId === ev.id;
              let parsedScores: { compId: string; score: number; evidence: string }[] = [];
              try {
                parsedScores = JSON.parse(ev.scoresJson);
              } catch (e) {}

              const evidenceCount = parsedScores.filter(
                (s) => s.evidence && s.evidence.trim().length > 0
              ).length;

              return (
                <div
                  key={ev.id}
                  className="rounded-xl bg-slate-800/40 border border-slate-800 overflow-hidden transition-colors"
                >
                  <div className="flex items-center justify-between p-4 gap-4">
                    <div className="flex items-center gap-3">
                      <span
                        className={`inline-flex items-center rounded px-2 py-0.5 text-xs font-bold ${getRankBadgeColor(
                          ev.targetRank
                        )}`}
                      >
                        {ev.targetRank}
                      </span>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-white text-sm">
                            {ev.targetName}
                          </span>
                          <span className="rounded-full bg-slate-700/80 px-2 py-0.5 text-[10px] font-semibold text-slate-300">
                            {ev.evalType}
                          </span>
                        </div>
                        <p className="text-[11px] text-slate-400 mt-0.5">
                          Evaluated by <strong>{ev.evaluatorRank} {ev.evaluatorName}</strong> • {new Date(ev.createdAt).toLocaleDateString()}
                        </p>
                      </div>
                    </div>

                    <div className="flex items-center gap-3">
                      <div className="text-right">
                        <span className="text-xs text-slate-400 block">
                          Composite Score
                        </span>
                        <span className="text-base font-black text-cyan-400">
                          {ev.compositeScore} / 5
                        </span>
                      </div>

                      <button
                        onClick={() =>
                          setExpandedId(isExpanded ? null : ev.id)
                        }
                        className="rounded-lg p-2 text-slate-400 hover:bg-slate-700 hover:text-white transition-colors"
                        title={isExpanded ? "Collapse details" : "Expand details"}
                      >
                        {isExpanded ? (
                          <ChevronUp className="h-5 w-5" />
                        ) : (
                          <ChevronDown className="h-5 w-5" />
                        )}
                      </button>

                      <button
                        onClick={() => handleDeleteClick(ev.id)}
                        className={`rounded-lg px-2.5 py-1.5 text-xs font-semibold transition-colors ${
                          deletingId === ev.id
                            ? "bg-rose-600 text-white"
                            : "bg-slate-800 text-slate-400 hover:bg-rose-950 hover:text-rose-300 border border-slate-700"
                        }`}
                        title="Delete assessment record"
                      >
                        <Trash2 className="h-4 w-4 inline mr-1" />
                        <span>{deletingId === ev.id ? "Confirm?" : "Delete"}</span>
                      </button>
                    </div>
                  </div>

                  {/* Expanded view showing individual parameter scores & evidence */}
                  {isExpanded && (
                    <div className="border-t border-slate-800 bg-slate-950/60 p-4 space-y-3">
                      <div className="flex items-center justify-between text-xs text-slate-400 border-b border-slate-800 pb-2">
                        <span>
                          Al-&lsquo;Adl Declaration Signed:{" "}
                          <strong className="text-emerald-400">Yes</strong>
                        </span>
                        <span>
                          Written Evidence Provided:{" "}
                          <strong className="text-cyan-400">
                            {evidenceCount} parameters
                          </strong>
                        </span>
                      </div>

                      <div className="grid grid-cols-1 md:grid-cols-2 gap-3 pt-1">
                        {parsedScores.map((s, idx) => {
                          const comp = COMPETENCIES.find((c) => c.id === s.compId);
                          return (
                            <div
                              key={idx}
                              className="rounded-lg bg-slate-900 border border-slate-800 p-3 text-xs space-y-1"
                            >
                              <div className="flex items-center justify-between">
                                <span className="font-bold text-slate-200">
                                  {comp ? comp.title : s.compId}
                                </span>
                                <span
                                  className={`rounded px-2 py-0.5 font-bold ${
                                    s.score >= 4
                                      ? "bg-emerald-950 text-emerald-300"
                                      : s.score === 3
                                      ? "bg-cyan-950 text-cyan-300"
                                      : "bg-rose-950 text-rose-300"
                                  }`}
                                >
                                  {s.score} / 5
                                </span>
                              </div>
                              {s.evidence && (
                                <div className="mt-1.5 rounded bg-rose-950/40 border border-rose-800/40 p-2 text-[11px] text-rose-200 italic">
                                  <strong>Evidence:</strong> &ldquo;{s.evidence}&rdquo;
                                </div>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
