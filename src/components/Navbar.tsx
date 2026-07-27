"use client";

import React from "react";
import { EvaluatorSession } from "@/types/mdu";
import { getRankBadgeColor, getRankLabel } from "@/lib/mduConstants";
import { Shield, Smartphone, RefreshCw, LogOut, Award } from "lucide-react";

interface NavbarProps {
  session: EvaluatorSession | null;
  onOpenIosModal: () => void;
  onSwitchTarget: () => void;
  onLogout: () => void;
}

export function Navbar({
  session,
  onOpenIosModal,
  onSwitchTarget,
  onLogout,
}: NavbarProps) {
  return (
    <header className="sticky top-0 z-40 w-full border-b border-slate-800 bg-slate-900/95 backdrop-blur-md shadow-md">
      <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3 sm:px-6">
        {/* Left: MNDF MDU Logo & App Name */}
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-cyan-600 to-blue-900 border border-cyan-500/30 text-white shadow-lg">
            <Shield className="h-6 w-6" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-extrabold tracking-tight text-white text-base sm:text-lg">
                MNDF MDU
              </span>
              <span className="hidden sm:inline-flex items-center gap-1 rounded-full bg-cyan-950/80 px-2.5 py-0.5 text-xs font-semibold text-cyan-300 border border-cyan-800/60">
                <Award className="h-3 w-3" /> Marine Deployment Unit
              </span>
            </div>
            <p className="text-[11px] text-slate-400 font-medium tracking-wide">
              Performance Management &amp; Al-&lsquo;Adl Safeguards System
            </p>
          </div>
        </div>

        {/* Right: Evaluator Session Badge & Controls */}
        <div className="flex items-center gap-2 sm:gap-3">
          {/* iPhone install button */}
          <button
            onClick={onOpenIosModal}
            className="flex items-center gap-1.5 rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-1.5 text-xs font-semibold text-cyan-300 hover:bg-slate-700/80 transition-colors"
            title="iPhone / iOS app download instructions"
          >
            <Smartphone className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">iPhone App</span>
          </button>

          {session && (
            <>
              {/* Evaluator identity pill */}
              <div className="hidden md:flex items-center gap-2 rounded-lg bg-slate-800/90 border border-slate-700 px-3 py-1.5 text-xs">
                <span className="text-slate-400 font-medium">Evaluator:</span>
                <span
                  className={`inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-bold ${getRankBadgeColor(
                    session.evaluatorRank
                  )}`}
                >
                  {session.evaluatorRank}
                </span>
                <span className="font-bold text-slate-200">
                  {session.evaluatorName}
                </span>
              </div>

              {/* Switch evaluation target */}
              <button
                onClick={onSwitchTarget}
                className="flex items-center gap-1.5 rounded-lg bg-cyan-950 border border-cyan-700/60 px-3 py-1.5 text-xs font-semibold text-cyan-200 hover:bg-cyan-900 transition-colors"
                title="Switch evaluation target marine"
              >
                <RefreshCw className="h-3.5 w-3.5" />
                <span className="hidden sm:inline">Switch Target</span>
              </button>

              {/* Logout button */}
              <button
                onClick={onLogout}
                className="flex items-center gap-1.5 rounded-lg border border-rose-900/60 bg-rose-950/50 px-3 py-1.5 text-xs font-semibold text-rose-300 hover:bg-rose-900/60 transition-colors"
                title="Log out of evaluator session"
              >
                <LogOut className="h-3.5 w-3.5" />
                <span className="hidden sm:inline">Log Out</span>
              </button>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
