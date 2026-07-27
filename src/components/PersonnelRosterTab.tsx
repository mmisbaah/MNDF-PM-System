"use client";

import React, { useState, useRef } from "react";
import { MarinePersonnel } from "@/types/mdu";
import { MNDF_RANKS, getRankBadgeColor } from "@/lib/mduConstants";
import {
  parsePersonnelCsv,
  downloadSampleCsvTemplate,
} from "@/lib/csvHelper";
import {
  Users,
  UserPlus,
  Trash2,
  ShieldCheck,
  Search,
  Filter,
  Upload,
  Download,
  CheckCircle2,
  AlertCircle,
} from "lucide-react";

interface PersonnelRosterTabProps {
  personnel: MarinePersonnel[];
  onMarineAdded: (newMarine: MarinePersonnel) => void;
  onMarineDeleted: (id: number) => Promise<void>;
  onEvaluateMarine: (marine: MarinePersonnel) => void;
  onRosterUpdated: (newRoster: MarinePersonnel[]) => void;
}

export function PersonnelRosterTab({
  personnel,
  onMarineAdded,
  onMarineDeleted,
  onEvaluateMarine,
  onRosterUpdated,
}: PersonnelRosterTabProps) {
  const [searchTerm, setSearchTerm] = useState<string>("");
  const [rankFilter, setRankFilter] = useState<string>("");
  const [showAddForm, setShowAddForm] = useState<boolean>(false);

  // Form state
  const [serviceNo, setServiceNo] = useState<string>("");
  const [rank, setRank] = useState<string>("");
  const [name, setName] = useState<string>("");
  const [platoon, setPlatoon] = useState<string>("Alpha Platoon - MDU");
  const [role, setRole] = useState<string>("Marine Rifleman");
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [errorMsg, setErrorMsg] = useState<string>("");

  // CSV upload state
  const [isUploadingCsv, setIsUploadingCsv] = useState<boolean>(false);
  const [csvStatusMsg, setCsvStatusMsg] = useState<string>("");
  const [csvErrors, setCsvErrors] = useState<string[]>([]);
  const csvInputRef = useRef<HTMLInputElement>(null);

  const handleAddMarine = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg("");

    if (!serviceNo.trim() || !rank || !name.trim()) {
      setErrorMsg("Please provide a Service Number, Rank, and Name.");
      return;
    }

    setIsSubmitting(true);
    try {
      const res = await fetch("/api/personnel", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          serviceNo: serviceNo.trim(),
          rank,
          name: name.trim(),
          platoon,
          role,
        }),
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || "Failed to add marine to roster.");
      }

      onMarineAdded(data.marine);
      setServiceNo("");
      setRank("");
      setName("");
      setShowAddForm(false);
    } catch (err: any) {
      setErrorMsg(err.message || "An error occurred while adding marine.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleCsvUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setIsUploadingCsv(true);
    setCsvStatusMsg("");
    setCsvErrors([]);

    try {
      const text = await file.text();
      const { valid, errors } = parsePersonnelCsv(text);

      if (valid.length === 0) {
        setCsvErrors(
          errors.length > 0 ? errors : ["No valid personnel rows found in file."]
        );
        setIsUploadingCsv(false);
        return;
      }

      const res = await fetch("/api/personnel", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ batch: valid }),
      });
      const data = await res.json();

      if (!res.ok || !data.success) {
        throw new Error(data.error || "Failed to import CSV roster.");
      }

      setCsvStatusMsg(
        `✅ Successfully imported ${valid.length} personnel from ${file.name}!`
      );
      if (errors.length > 0) {
        setCsvErrors(errors);
      }
      if (data.personnel) {
        onRosterUpdated(data.personnel);
      }
    } catch (err: any) {
      setCsvErrors([err.message || "Error importing CSV file."]);
    } finally {
      setIsUploadingCsv(false);
      if (csvInputRef.current) csvInputRef.current.value = "";
    }
  };

  const filteredPersonnel = personnel.filter((p) => {
    const matchesSearch =
      p.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.serviceNo.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.role.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesRank = !rankFilter || p.rank === rankFilter;
    return matchesSearch && matchesRank;
  });

  return (
    <div className="space-y-6">
      {/* Roster header & actions */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-900 border border-slate-800 p-5 rounded-2xl shadow-xl">
        <div>
          <h2 className="text-lg sm:text-xl font-black text-white flex items-center gap-2">
            <Users className="h-6 w-6 text-cyan-400" />
            <span>MNDF Marine Deployment Unit Roster</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Total active deployment personnel:{" "}
            <strong className="text-cyan-400">{personnel.length}</strong> • Support
            CSV / CVS file batch import
          </p>
        </div>

        <div className="flex items-center gap-2.5 flex-wrap">
          {/* CSV Import Button */}
          <button
            type="button"
            onClick={() => csvInputRef.current?.click()}
            disabled={isUploadingCsv}
            className="flex items-center gap-1.5 rounded-xl bg-cyan-600 hover:bg-cyan-500 px-4 py-2.5 font-bold text-xs sm:text-sm text-white shadow-lg transition-colors cursor-pointer disabled:opacity-50"
            title="Upload CSV or CVS file with serviceNo, rank, name, platoon, role"
          >
            <Upload className="h-4 w-4" />
            <span>
              {isUploadingCsv ? "Importing CSV..." : "Upload CSV / CVS Roster"}
            </span>
          </button>
          <input
            ref={csvInputRef}
            type="file"
            accept=".csv,.cvs,text/csv,application/vnd.ms-excel"
            onChange={handleCsvUpload}
            className="hidden"
          />

          {/* Download sample CSV template button */}
          <button
            type="button"
            onClick={downloadSampleCsvTemplate}
            className="flex items-center gap-1.5 rounded-xl bg-slate-800 border border-slate-700 hover:bg-slate-700 px-3.5 py-2.5 font-semibold text-xs text-slate-300 transition-colors"
            title="Download CSV template with required headers"
          >
            <Download className="h-4 w-4 text-cyan-400" />
            <span>CSV Template</span>
          </button>

          {/* Add single marine button */}
          <button
            onClick={() => setShowAddForm(!showAddForm)}
            className="flex items-center gap-1.5 rounded-xl bg-slate-800 border border-slate-700 hover:bg-slate-700 px-4 py-2.5 font-bold text-xs sm:text-sm text-cyan-300 shadow-lg transition-colors"
          >
            <UserPlus className="h-4 w-4" />
            <span>{showAddForm ? "Close Form" : "Add Single Marine"}</span>
          </button>
        </div>
      </div>

      {/* CSV Status / Errors Banner */}
      {csvStatusMsg && (
        <div className="rounded-xl bg-emerald-950/80 border border-emerald-600 p-4 text-xs sm:text-sm text-emerald-200 flex items-center gap-2.5 shadow">
          <CheckCircle2 className="h-5 w-5 text-emerald-400 shrink-0" />
          <span className="font-bold">{csvStatusMsg}</span>
        </div>
      )}

      {csvErrors.length > 0 && (
        <div className="rounded-xl bg-rose-950/80 border border-rose-700 p-4 text-xs text-rose-200 space-y-1.5 shadow">
          <div className="flex items-center gap-1.5 font-bold text-rose-300">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>CSV Upload Notes ({csvErrors.length}):</span>
          </div>
          <ul className="list-disc pl-5 space-y-1 text-rose-300/90 max-h-36 overflow-y-auto">
            {csvErrors.map((err, idx) => (
              <li key={idx}>{err}</li>
            ))}
          </ul>
        </div>
      )}

      {/* Add Marine Form (conditionally shown) */}
      {showAddForm && (
        <div className="rounded-2xl bg-slate-900 border border-slate-800 p-5 sm:p-6 shadow-xl space-y-4 animate-in fade-in duration-200">
          <div className="flex items-center justify-between border-b border-slate-800 pb-3">
            <h3 className="text-sm sm:text-base font-extrabold text-white">
              Enlist / Transfer Personnel to MDU Roster
            </h3>
            <span className="text-xs text-slate-400">MNDF Form 402</span>
          </div>

          {errorMsg && (
            <div className="rounded-xl bg-rose-950/80 border border-rose-700 p-3 text-xs text-rose-200">
              {errorMsg}
            </div>
          )}

          <form onSubmit={handleAddMarine} className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">
                  Service Number
                </label>
                <input
                  type="text"
                  value={serviceNo}
                  onChange={(e) => setServiceNo(e.target.value)}
                  placeholder="e.g. MNDF-9842"
                  className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500 focus:border-cyan-500 focus:outline-none"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">
                  Rank
                </label>
                <select
                  value={rank}
                  onChange={(e) => setRank(e.target.value)}
                  className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3 py-2 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
                  required
                >
                  <option value="">-- Select Rank --</option>
                  {MNDF_RANKS.map((r) => (
                    <option key={r.code} value={r.code}>
                      {r.label}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">
                  Personnel Name
                </label>
                <input
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. M. Fazeel"
                  className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500 focus:border-cyan-500 focus:outline-none"
                  required
                />
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">
                  Platoon Assignment
                </label>
                <select
                  value={platoon}
                  onChange={(e) => setPlatoon(e.target.value)}
                  className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3 py-2 text-sm text-slate-100 focus:border-cyan-500 focus:outline-none"
                >
                  <option value="Alpha Platoon - MDU">Alpha Platoon - MDU</option>
                  <option value="Bravo Platoon - MDU">Bravo Platoon - MDU</option>
                  <option value="MDU Command HQ">MDU Command HQ</option>
                  <option value="Logistics Company - MDU">
                    Logistics Company - MDU
                  </option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">
                  Duty Role
                </label>
                <input
                  type="text"
                  value={role}
                  onChange={(e) => setRole(e.target.value)}
                  placeholder="e.g. Assault Rifleman, Section Commander"
                  className="w-full rounded-lg bg-slate-950 border border-slate-700 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500 focus:border-cyan-500 focus:outline-none"
                />
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setShowAddForm(false)}
                className="rounded-xl bg-slate-800 px-4 py-2 text-xs font-semibold text-slate-300 hover:bg-slate-700 transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isSubmitting}
                className="rounded-xl bg-cyan-600 hover:bg-cyan-500 px-6 py-2 text-xs font-bold text-white shadow-lg transition-colors disabled:opacity-50"
              >
                {isSubmitting
                  ? "Adding to Roster..."
                  : "Save Marine to Roster"}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Roster Search & Filter */}
      <div className="flex flex-wrap items-center justify-between gap-3 bg-slate-900 border border-slate-800 p-4 rounded-xl">
        <div className="relative flex-1 min-w-[240px]">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-slate-500" />
          <input
            type="text"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder="Search by name, service number, or role..."
            className="w-full rounded-lg bg-slate-950 border border-slate-700 pl-9 pr-4 py-2 text-xs sm:text-sm text-slate-200 placeholder:text-slate-500 focus:outline-none focus:border-cyan-500"
          />
        </div>

        <div className="flex items-center gap-2">
          <Filter className="h-4 w-4 text-slate-400" />
          <select
            value={rankFilter}
            onChange={(e) => setRankFilter(e.target.value)}
            className="rounded-lg bg-slate-950 border border-slate-700 px-3 py-2 text-xs text-slate-200 focus:outline-none focus:border-cyan-500"
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

      {/* Roster table */}
      <div className="rounded-2xl bg-slate-900 border border-slate-800 shadow-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse text-xs sm:text-sm">
            <thead>
              <tr className="border-b border-slate-800 bg-slate-950/60 text-slate-400 font-bold uppercase tracking-wider text-[11px]">
                <th className="py-3.5 px-4">Service No.</th>
                <th className="py-3.5 px-4">Rank</th>
                <th className="py-3.5 px-4">Marine Name</th>
                <th className="py-3.5 px-4">Platoon</th>
                <th className="py-3.5 px-4">Duty Role</th>
                <th className="py-3.5 px-4 text-right">Quick Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60">
              {filteredPersonnel.length === 0 ? (
                <tr>
                  <td
                    colSpan={6}
                    className="py-12 text-center text-slate-500 text-xs font-medium"
                  >
                    No personnel found in roster. Upload a CSV / CVS file above to
                    populate your unit roster.
                  </td>
                </tr>
              ) : (
                filteredPersonnel.map((p) => (
                  <tr
                    key={p.id}
                    className="hover:bg-slate-800/40 transition-colors"
                  >
                    <td className="py-3.5 px-4 font-mono text-cyan-400 font-semibold">
                      {p.serviceNo}
                    </td>
                    <td className="py-3.5 px-4">
                      <span
                        className={`inline-flex items-center rounded px-2.5 py-0.5 text-xs font-bold ${getRankBadgeColor(
                          p.rank
                        )}`}
                      >
                        {p.rank}
                      </span>
                    </td>
                    <td className="py-3.5 px-4 font-bold text-white">
                      {p.name}
                    </td>
                    <td className="py-3.5 px-4 text-slate-300">{p.platoon}</td>
                    <td className="py-3.5 px-4 text-slate-400">{p.role}</td>
                    <td className="py-3.5 px-4 text-right whitespace-nowrap space-x-2">
                      <button
                        onClick={() => onEvaluateMarine(p)}
                        className="inline-flex items-center gap-1 rounded-lg bg-cyan-950 border border-cyan-600/80 hover:bg-cyan-900 px-3 py-1.5 text-xs font-bold text-cyan-200 transition-colors"
                        title="Evaluate this marine now"
                      >
                        <ShieldCheck className="h-3.5 w-3.5" />
                        <span>Evaluate</span>
                      </button>
                      <button
                        onClick={() => onMarineDeleted(p.id)}
                        className="rounded-lg p-1.5 text-slate-400 hover:bg-rose-950 hover:text-rose-300 transition-colors inline-flex items-center"
                        title="Remove marine from roster"
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
