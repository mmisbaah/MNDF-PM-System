"use client";

import React, { useState, useRef } from "react";
import { MNDF_RANKS, getRankOrder } from "@/lib/mduConstants";
import { EvaluatorSession, MarinePersonnel } from "@/types/mdu";
import {
  parsePersonnelCsv,
  downloadSampleCsvTemplate,
} from "@/lib/csvHelper";
import {
  ShieldAlert,
  ShieldCheck,
  UserCheck,
  Users,
  Smartphone,
  ChevronRight,
  Lock,
  Upload,
  Download,
  CheckCircle2,
  AlertCircle,
  RefreshCw,
} from "lucide-react";

interface LoginScreenProps {
  personnelRoster: MarinePersonnel[];
  onLoginSuccess: (session: EvaluatorSession) => void;
  onOpenIosModal: () => void;
  onRosterUpdated: (newRoster: MarinePersonnel[]) => void;
}

export function LoginScreen({
  personnelRoster,
  onLoginSuccess,
  onOpenIosModal,
  onRosterUpdated,
}: LoginScreenProps) {
  // Evaluator fields
  const [evalRank, setEvalRank] = useState<string>("");
  const [evalName, setEvalName] = useState<string>("");

  // Target mode: self vs other
  const [mode, setMode] = useState<"self" | "other">("self");

  // Target fields when evaluating someone else
  const [targetRank, setTargetRank] = useState<string>("");
  const [targetName, setTargetName] = useState<string>("");
  const [roleType, setRoleType] = useState<"Supervisor" | "Peer">("Supervisor");

  const [errorMsg, setErrorMsg] = useState<string>("");

  // CSV upload state on Login screen
  const [isUploading, setIsUploading] = useState<boolean>(false);
  const [uploadStatus, setUploadStatus] = useState<string>("");
  const [uploadErrors, setUploadErrors] = useState<string[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Check if evaluator selected a roster marine (Option A experience)
  const handleSelectRosterEvaluator = (
    e: React.ChangeEvent<HTMLSelectElement>
  ) => {
    const serviceNo = e.target.value;
    if (!serviceNo) {
      setEvalRank("");
      setEvalName("");
      return;
    }
    const found = personnelRoster.find((p) => p.serviceNo === serviceNo);
    if (found) {
      setEvalRank(found.rank);
      setEvalName(found.name);
      setErrorMsg("");
    }
  };

  const handleSelectRosterTarget = (
    e: React.ChangeEvent<HTMLSelectElement>
  ) => {
    const serviceNo = e.target.value;
    if (!serviceNo) {
      setTargetRank("");
      setTargetName("");
      return;
    }
    const found = personnelRoster.find((p) => p.serviceNo === serviceNo);
    if (found) {
      setTargetRank(found.rank);
      setTargetName(found.name);
      setErrorMsg("");
    }
  };

  // Real-time hierarchy check calculation
  const currentEvalOrder = getRankOrder(evalRank);
  const currentTargetOrder =
    mode === "self" ? currentEvalOrder : getRankOrder(targetRank);
  const isHierarchyRestricted =
    mode === "other" &&
    Boolean(evalRank) &&
    Boolean(targetRank) &&
    currentEvalOrder < currentTargetOrder;

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg("");

    if (!evalRank || !evalName.trim()) {
      setErrorMsg("Please select your Evaluator Rank and enter your Name.");
      return;
    }

    if (mode === "other") {
      if (!targetRank || !targetName.trim()) {
        setErrorMsg(
          "Please specify the Rank and Name of the personnel being evaluated."
        );
        return;
      }
      // If user typed identical name/rank for evaluator and evaluated, gracefully switch mode to 'self' and login!
      if (
        evalRank === targetRank &&
        evalName.trim().toLowerCase() === targetName.trim().toLowerCase()
      ) {
        const selfSession: EvaluatorSession = {
          evaluatorRank: evalRank,
          evaluatorName: evalName.trim(),
          targetRank: evalRank,
          targetName: evalName.trim(),
          evalType: "Self",
          mode: "self",
        };
        onLoginSuccess(selfSession);
        return;
      }
      if (currentEvalOrder < currentTargetOrder) {
        setErrorMsg(
          `MILITARY HIERARCHY RESTRICTION: ${evalRank} ${evalName.trim()} (Junior Rank) cannot evaluate ${targetRank} ${targetName.trim()} (Senior Rank). Evaluators must be of equal or senior rank to the evaluated marine.`
        );
        return;
      }
    }

    const session: EvaluatorSession = {
      evaluatorRank: evalRank,
      evaluatorName: evalName.trim(),
      targetRank: mode === "self" ? evalRank : targetRank,
      targetName: mode === "self" ? evalName.trim() : targetName.trim(),
      evalType: mode === "self" ? "Self" : roleType,
      mode,
    };

    onLoginSuccess(session);
  };

  // CSV Upload Handler
  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setIsUploading(true);
    setUploadStatus("");
    setUploadErrors([]);

    try {
      const text = await file.text();
      const { valid, errors } = parsePersonnelCsv(text);

      if (valid.length === 0) {
        setUploadErrors(
          errors.length > 0 ? errors : ["No valid personnel rows found in file."]
        );
        setIsUploading(false);
        return;
      }

      // Submit batch to PostgreSQL API
      const res = await fetch("/api/personnel", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ batch: valid }),
      });
      const data = await res.json();

      if (!res.ok || !data.success) {
        throw new Error(data.error || "Failed to import CSV roster.");
      }

      setUploadStatus(
        `✅ Successfully imported ${valid.length} personnel from CSV file (${file.name})!`
      );
      if (errors.length > 0) {
        setUploadErrors(errors);
      }
      if (data.personnel) {
        onRosterUpdated(data.personnel);
      }
    } catch (err: any) {
      setUploadErrors([err.message || "Error importing CSV file."]);
    } finally {
      setIsUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const handleSwapRoles = () => {
    const tmpRank = evalRank;
    const tmpName = evalName;
    setEvalRank(targetRank);
    setEvalName(targetName);
    setTargetRank(tmpRank);
    setTargetName(tmpName);
    setErrorMsg("");
  };

  return (
    <div className="min-h-[calc(100vh-64px)] flex items-center justify-center py-10 px-4 sm:px-6">
      <div className="w-full max-w-2xl rounded-2xl bg-slate-900 border border-slate-800 shadow-2xl overflow-hidden">
        {/* Header banner */}
        <div className="bg-gradient-to-r from-cyan-950 via-slate-900 to-blue-950 px-6 py-6 border-b border-slate-800">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-cyan-600 text-white shadow-lg shrink-0">
                <Lock className="h-6 w-6" />
              </div>
              <div>
                <span className="inline-block rounded-md bg-cyan-900/60 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-cyan-300 mb-1 border border-cyan-700/50">
                  MNDF Marine Deployment Unit
                </span>
                <h1 className="text-xl sm:text-2xl font-black tracking-tight text-white">
                  Evaluator Login Portal
                </h1>
              </div>
            </div>

            {/* CSV Import / Download Template buttons in header */}
            <div className="flex items-center gap-2 flex-wrap">
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={isUploading}
                className="inline-flex items-center gap-1.5 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white px-3 py-1.5 text-xs font-bold transition-colors shadow-md cursor-pointer disabled:opacity-50"
                title="Upload .csv or .cvs file with serviceNo, rank, name, platoon, role"
              >
                <Upload className="h-3.5 w-3.5" />
                <span>{isUploading ? "Importing..." : "Upload CSV / CVS Roster"}</span>
              </button>
              <button
                type="button"
                onClick={downloadSampleCsvTemplate}
                className="inline-flex items-center gap-1 rounded-lg bg-slate-800 border border-slate-700 hover:bg-slate-700 text-slate-300 px-2.5 py-1.5 text-xs font-semibold transition-colors"
                title="Download formatted CSV template with required parameters"
              >
                <Download className="h-3.5 w-3.5 text-cyan-400" />
                <span>Sample CSV</span>
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept=".csv,.cvs,text/csv,application/vnd.ms-excel"
                onChange={handleFileChange}
                className="hidden"
              />
            </div>
          </div>

          <p className="mt-3 text-xs sm:text-sm text-slate-300 leading-relaxed">
            Select personnel from your active MDU Roster (Option A) or import any
            roster via CSV/CVS file.
          </p>

          {/* Upload Status Notification */}
          {uploadStatus && (
            <div className="mt-3 rounded-xl bg-emerald-950/80 border border-emerald-600 p-3 text-xs sm:text-sm text-emerald-200 flex items-center gap-2">
              <CheckCircle2 className="h-5 w-5 text-emerald-400 shrink-0" />
              <span className="font-semibold">{uploadStatus}</span>
            </div>
          )}
          {uploadErrors.length > 0 && (
            <div className="mt-2 rounded-xl bg-rose-950/80 border border-rose-700 p-3 text-xs text-rose-200 space-y-1 max-h-28 overflow-y-auto">
              <div className="flex items-center gap-1.5 font-bold text-rose-300">
                <AlertCircle className="h-4 w-4 shrink-0" />
                <span>CSV Upload Notes ({uploadErrors.length}):</span>
              </div>
              {uploadErrors.map((err, i) => (
                <div key={i} className="text-rose-300/90 text-[11px]">
                  • {err}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Login form */}
        <form onSubmit={handleLogin} className="p-6 space-y-6">
          {/* STEP 1: EVALUATOR IDENTITY */}
          <div className="space-y-3 rounded-xl bg-slate-800/40 p-4 border border-slate-800">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <label className="text-xs font-bold uppercase tracking-wider text-cyan-400 flex items-center gap-1.5">
                <UserCheck className="h-4 w-4" /> 1. Who is the Evaluator? (Your Identity)
              </label>

              {/* OPTION A ROSTER SELECTOR */}
              {personnelRoster.length > 0 && (
                <select
                  onChange={handleSelectRosterEvaluator}
                  className="rounded-lg bg-slate-800 border border-slate-700 px-3 py-1.5 text-xs font-semibold text-cyan-300 focus:outline-none focus:border-cyan-500 shadow"
                  defaultValue=""
                >
                  <option value="">⚡ Quick Select from MDU Roster...</option>
                  {personnelRoster.map((p) => (
                    <option key={p.serviceNo} value={p.serviceNo}>
                      {p.rank} {p.name} ({p.role})
                    </option>
                  ))}
                </select>
              )}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div>
                <label className="block text-xs font-semibold text-slate-300 mb-1">
                  Evaluator Rank
                </label>
                <select
                  value={evalRank}
                  onChange={(e) => setEvalRank(e.target.value)}
                  className="w-full rounded-lg bg-slate-900 border border-slate-700 px-3 py-2.5 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
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
                <label className="block text-xs font-semibold text-slate-300 mb-1">
                  Evaluator Name
                </label>
                <input
                  type="text"
                  value={evalName}
                  onChange={(e) => setEvalName(e.target.value)}
                  placeholder="e.g. M. Misbaah"
                  className="w-full rounded-lg bg-slate-900 border border-slate-700 px-3 py-2.5 text-sm text-slate-100 placeholder:text-slate-500 focus:border-cyan-500 focus:outline-none"
                  required
                />
              </div>
            </div>
          </div>

          {/* STEP 2: WHO IS BEING EVALUATED */}
          <div className="space-y-4 rounded-xl bg-slate-800/40 p-4 border border-slate-800">
            <label className="text-xs font-bold uppercase tracking-wider text-cyan-400 flex items-center gap-1.5">
              <Users className="h-4 w-4" /> 2. Who is being evaluated?
            </label>

            <div className="grid grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => setMode("self")}
                className={`flex items-center justify-center gap-2 rounded-lg p-3 text-sm font-semibold transition-all border ${
                  mode === "self"
                    ? "bg-cyan-950/90 border-cyan-500 text-cyan-200 shadow-lg"
                    : "bg-slate-900/60 border-slate-700 text-slate-400 hover:text-slate-200"
                }`}
              >
                <UserCheck className="h-4 w-4" />
                <span>Self Evaluation</span>
              </button>

              <button
                type="button"
                onClick={() => setMode("other")}
                className={`flex items-center justify-center gap-2 rounded-lg p-3 text-sm font-semibold transition-all border ${
                  mode === "other"
                    ? "bg-cyan-950/90 border-cyan-500 text-cyan-200 shadow-lg"
                    : "bg-slate-900/60 border-slate-700 text-slate-400 hover:text-slate-200"
                }`}
              >
                <Users className="h-4 w-4" />
                <span>Evaluate Another Marine</span>
              </button>
            </div>

            {/* Target inputs if evaluating someone else */}
            {mode === "other" && (
              <div className="space-y-3 pt-2 border-t border-slate-800/80 animate-in fade-in duration-200">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <span className="text-xs font-medium text-slate-400">
                    Target Marine Information:
                  </span>
                  {personnelRoster.length > 0 && (
                    <select
                      onChange={handleSelectRosterTarget}
                      className="rounded-lg bg-slate-800 border border-slate-700 px-3 py-1.5 text-xs font-semibold text-cyan-300 focus:outline-none focus:border-cyan-500 shadow"
                      defaultValue=""
                    >
                      <option value="">⚡ Select Target from MDU Roster...</option>
                      {personnelRoster.map((p) => (
                        <option key={p.serviceNo} value={p.serviceNo}>
                          {p.rank} {p.name} ({p.role})
                        </option>
                      ))}
                    </select>
                  )}
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div>
                    <label className="block text-xs font-semibold text-slate-300 mb-1">
                      Evaluated Rank
                    </label>
                    <select
                      value={targetRank}
                      onChange={(e) => setTargetRank(e.target.value)}
                      className="w-full rounded-lg bg-slate-900 border border-slate-700 px-3 py-2.5 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
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
                    <label className="block text-xs font-semibold text-slate-300 mb-1">
                      Evaluated Marine Name
                    </label>
                    <input
                      type="text"
                      value={targetName}
                      onChange={(e) => setTargetName(e.target.value)}
                      placeholder="e.g. H. Ibrahim"
                      className="w-full rounded-lg bg-slate-900 border border-slate-700 px-3 py-2.5 text-sm text-slate-100 placeholder:text-slate-500 focus:border-cyan-500 focus:outline-none"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">
                    Evaluation Perspective (Weighting in Multi-Rater Score)
                  </label>
                  <select
                    value={roleType}
                    onChange={(e) =>
                      setRoleType(e.target.value as "Supervisor" | "Peer")
                    }
                    className="w-full rounded-lg bg-slate-900 border border-slate-700 px-3 py-2.5 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
                  >
                    <option value="Supervisor">
                      Supervisor Assessment (60% Weight in Composite)
                    </option>
                    <option value="Peer">
                      Peer Assessment (15% Weight in Composite)
                    </option>
                  </select>
                </div>
              </div>
            )}
          </div>

          {/* REAL-TIME HIERARCHY RESTRICTION BANNER */}
          {isHierarchyRestricted && (
            <div className="rounded-xl bg-rose-950/80 border-2 border-rose-600/80 p-4 text-rose-200 animate-in fade-in duration-200 shadow-xl">
              <div className="flex items-start gap-3">
                <ShieldAlert className="h-6 w-6 text-rose-400 shrink-0 mt-0.5" />
                <div className="text-xs sm:text-sm space-y-2">
                  <p className="font-bold uppercase tracking-wide text-rose-300">
                    Military Hierarchy Violation — Login Restricted
                  </p>
                  <p className="leading-relaxed">
                    Evaluator{" "}
                    <strong className="text-white">
                      {evalRank} {evalName}
                    </strong>{" "}
                    (Junior Rank, Order {currentEvalOrder}) cannot evaluate{" "}
                    <strong className="text-white">
                      {targetRank} {targetName}
                    </strong>{" "}
                    (Senior Rank, Order {currentTargetOrder}).
                  </p>
                  <p className="text-rose-300 font-semibold">
                    ⚠️ By MNDF MDU Standing Orders, evaluators must be of equal or
                    senior rank to the personnel being evaluated.
                  </p>
                  <div className="flex items-center gap-2 pt-1">
                    <button
                      type="button"
                      onClick={handleSwapRoles}
                      className="inline-flex items-center gap-1.5 rounded-lg bg-rose-900 hover:bg-rose-800 text-white px-3 py-1.5 text-xs font-bold transition-colors shadow"
                    >
                      <RefreshCw className="h-3.5 w-3.5" />
                      <span>Swap Roles ({targetRank} evaluating {evalRank})</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => setMode("self")}
                      className="inline-flex items-center gap-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 px-3 py-1.5 text-xs font-semibold transition-colors"
                    >
                      <span>Switch to Self Assessment</span>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* GENERAL ERROR BANNER */}
          {errorMsg && !isHierarchyRestricted && (
            <div className="rounded-xl bg-rose-950/70 border border-rose-700 p-3.5 text-xs sm:text-sm text-rose-200 flex items-center gap-2">
              <ShieldAlert className="h-5 w-5 text-rose-400 shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}

          {/* SUBMIT / UNLOCK BUTTON */}
          <button
            type="submit"
            disabled={isHierarchyRestricted}
            className={`w-full flex items-center justify-center gap-2 rounded-xl py-3.5 px-6 font-bold text-sm sm:text-base shadow-lg transition-all ${
              isHierarchyRestricted
                ? "bg-slate-800 text-slate-500 cursor-not-allowed border border-slate-700"
                : "bg-gradient-to-r from-cyan-600 to-blue-700 hover:from-cyan-500 hover:to-blue-600 text-white shadow-cyan-900/30"
            }`}
          >
            <ShieldCheck className="h-5 w-5" />
            <span>
              {isHierarchyRestricted
                ? "Login Blocked by Military Hierarchy"
                : mode === "self"
                ? `Unlock Self Assessment for ${evalRank || "Marine"} ${evalName}`
                : `Unlock Evaluation for ${targetRank || "Marine"} ${targetName}`}
            </span>
            {!isHierarchyRestricted && <ChevronRight className="h-5 w-5" />}
          </button>
        </form>

        {/* Footer info */}
        <div className="bg-slate-950/80 px-6 py-4 border-t border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-2 text-xs text-slate-400">
          <span>Maldives National Defence Force • MDU Command HQ</span>
          <div className="flex items-center gap-4">
            <span className="text-cyan-400 font-semibold">
              Al-&lsquo;Adl Safeguards Active
            </span>
            <span>Roster count: {personnelRoster.length}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
