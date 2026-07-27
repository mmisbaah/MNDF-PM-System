"use client";

import React from "react";
import {
  ShieldCheck,
  BarChart3,
  Award,
  Users,
  MessageSquare,
  Smartphone,
  LogOut,
  ChevronRight,
} from "lucide-react";

export type NavTabId = "evaluation" | "dashboard" | "actions" | "roster" | "feedback";

interface SidebarProps {
  activeTab: NavTabId;
  onTabChange: (tab: NavTabId) => void;
  assessmentCount: number;
  actionCount: number;
  rosterCount: number;
  onOpenIosModal: () => void;
  onLogout: () => void;
}

export function Sidebar({
  activeTab,
  onTabChange,
  assessmentCount,
  actionCount,
  rosterCount,
  onOpenIosModal,
  onLogout,
}: SidebarProps) {
  const navItems = [
    {
      id: "evaluation" as NavTabId,
      label: "Evaluate Marine",
      desc: "Al-'Adl Scorecard",
      icon: ShieldCheck,
      badge: null,
    },
    {
      id: "dashboard" as NavTabId,
      label: "Research Analytics",
      desc: "Composite & Gaps",
      icon: BarChart3,
      badge: assessmentCount > 0 ? assessmentCount : null,
    },
    {
      id: "actions" as NavTabId,
      label: "Unit Actions Log",
      desc: "Awards & Retraining",
      icon: Award,
      badge: actionCount > 0 ? actionCount : null,
    },
    {
      id: "roster" as NavTabId,
      label: "Personnel Roster",
      desc: "MDU Company",
      icon: Users,
      badge: rosterCount > 0 ? rosterCount : null,
    },
    {
      id: "feedback" as NavTabId,
      label: "System Feedback",
      desc: "PDS Perception",
      icon: MessageSquare,
      badge: null,
    },
  ];

  return (
    <>
      {/* Desktop Sidebar Navigation (lg and up) */}
      <aside className="hidden lg:flex flex-col w-64 shrink-0 bg-slate-900 border-r border-slate-800 min-h-[calc(100vh-64px)] justify-between p-4">
        <div className="space-y-6">
          <div className="px-2">
            <span className="text-[10px] font-extrabold uppercase tracking-widest text-cyan-400">
              MNDF MDU Command
            </span>
            <p className="text-xs text-slate-400 mt-0.5">
              Marine Deployment Unit Operations
            </p>
          </div>

          <nav className="space-y-1.5">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = activeTab === item.id;
              return (
                <button
                  key={item.id}
                  onClick={() => onTabChange(item.id)}
                  className={`w-full flex items-center justify-between rounded-xl px-3.5 py-3 text-left transition-all ${
                    isActive
                      ? "bg-gradient-to-r from-cyan-600/90 to-blue-700 text-white shadow-lg shadow-cyan-950/50 font-bold"
                      : "text-slate-400 hover:bg-slate-800/80 hover:text-slate-200"
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <Icon
                      className={`h-5 w-5 shrink-0 ${
                        isActive ? "text-white" : "text-slate-400"
                      }`}
                    />
                    <div>
                      <div className="text-sm font-semibold leading-none">
                        {item.label}
                      </div>
                      <div
                        className={`text-[11px] mt-1 ${
                          isActive ? "text-cyan-200" : "text-slate-500"
                        }`}
                      >
                        {item.desc}
                      </div>
                    </div>
                  </div>
                  {item.badge !== null && (
                    <span
                      className={`rounded-full px-2 py-0.5 text-[10px] font-extrabold ${
                        isActive
                          ? "bg-white/20 text-white"
                          : "bg-slate-800 text-slate-400 border border-slate-700"
                      }`}
                    >
                      {item.badge}
                    </span>
                  )}
                </button>
              );
            })}
          </nav>
        </div>

        {/* Bottom footer controls in desktop sidebar */}
        <div className="space-y-2 pt-4 border-t border-slate-800/80">
          <button
            onClick={onOpenIosModal}
            className="w-full flex items-center gap-2.5 rounded-xl bg-slate-950/80 border border-slate-800 px-3 py-2.5 text-xs font-semibold text-cyan-400 hover:border-cyan-700 transition-colors"
          >
            <Smartphone className="h-4 w-4 shrink-0" />
            <span>iPhone App Guide</span>
          </button>
          <button
            onClick={onLogout}
            className="w-full flex items-center gap-2.5 rounded-xl bg-rose-950/40 border border-rose-900/60 px-3 py-2.5 text-xs font-semibold text-rose-300 hover:bg-rose-950 transition-colors"
          >
            <LogOut className="h-4 w-4 shrink-0" />
            <span>End Evaluator Session</span>
          </button>
        </div>
      </aside>

      {/* Mobile / iPhone Bottom Navigation Bar (below lg) */}
      <nav className="lg:hidden fixed bottom-0 left-0 right-0 z-40 bg-slate-900/95 backdrop-blur-md border-t border-slate-800 px-2 py-1.5 flex justify-around items-center">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = activeTab === item.id;
          return (
            <button
              key={item.id}
              onClick={() => onTabChange(item.id)}
              className={`flex flex-col items-center justify-center py-1.5 px-2 rounded-lg transition-all min-w-[56px] ${
                isActive
                  ? "text-cyan-400 font-bold scale-105"
                  : "text-slate-400 hover:text-slate-200"
              }`}
            >
              <Icon className="h-5 w-5 mb-0.5" />
              <span className="text-[10px] leading-none tracking-tight">
                {item.label.split(" ")[0]}
              </span>
              {isActive && (
                <span className="h-1 w-1 rounded-full bg-cyan-400 mt-0.5" />
              )}
            </button>
          );
        })}
      </nav>
    </>
  );
}
