"use client";

import React, { useState, useEffect } from "react";
import {
  EvaluatorSession,
  MarinePersonnel,
  MarineEvaluation,
  UnitAction,
  SystemFeedback,
} from "@/types/mdu";
import { Navbar } from "@/components/Navbar";
import { IosInstallModal } from "@/components/IosInstallModal";
import { LoginScreen } from "@/components/LoginScreen";
import { Sidebar, NavTabId } from "@/components/Sidebar";
import { EvaluationForm } from "@/components/EvaluationForm";
import { AnalyticsDashboard } from "@/components/AnalyticsDashboard";
import { UnitActionsTab } from "@/components/UnitActionsTab";
import { SystemFeedbackTab } from "@/components/SystemFeedbackTab";
import { PersonnelRosterTab } from "@/components/PersonnelRosterTab";
import { Shield, RefreshCw, Smartphone, AlertCircle } from "lucide-react";

export function MduApp() {
  // Global data states
  const [personnel, setPersonnel] = useState<MarinePersonnel[]>([]);
  const [evaluations, setEvaluations] = useState<MarineEvaluation[]>([]);
  const [actions, setActions] = useState<UnitAction[]>([]);
  const [feedbackList, setFeedbackList] = useState<SystemFeedback[]>([]);

  // UI state
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [errorMsg, setErrorMsg] = useState<string>("");
  const [session, setSession] = useState<EvaluatorSession | null>(null);
  const [activeTab, setActiveTab] = useState<NavTabId>("evaluation");
  const [isIosModalOpen, setIsIosModalOpen] = useState<boolean>(false);

  // Initialize data on load
  const loadInitialData = async () => {
    setIsLoading(true);
    setErrorMsg("");
    try {
      const res = await fetch("/api/init");
      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || "Failed to initialize MNDF MDU database.");
      }
      setPersonnel(data.personnel || []);
      setEvaluations(data.evaluations || []);
      setActions(data.unitActions || []);
      setFeedbackList(data.feedback || []);
    } catch (err: any) {
      console.error("Initialization error:", err);
      setErrorMsg(err.message || "Unable to connect to database.");
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadInitialData();
  }, []);

  // CRUD Handler - Delete Evaluation
  const handleDeleteEvaluation = async (id: number) => {
    try {
      const res = await fetch(`/api/evaluations?id=${id}`, {
        method: "DELETE",
      });
      const data = await res.json();
      if (res.ok && data.success) {
        setEvaluations((prev) => prev.filter((ev) => ev.id !== id));
      }
    } catch (err) {
      console.error("Delete evaluation error:", err);
    }
  };

  // CRUD Handler - Delete Action
  const handleDeleteAction = async (id: number) => {
    try {
      const res = await fetch(`/api/actions?id=${id}`, {
        method: "DELETE",
      });
      const data = await res.json();
      if (res.ok && data.success) {
        setActions((prev) => prev.filter((act) => act.id !== id));
      }
    } catch (err) {
      console.error("Delete action error:", err);
    }
  };

  // CRUD Handler - Delete Feedback
  const handleDeleteFeedback = async (id: number) => {
    try {
      const res = await fetch(`/api/feedback?id=${id}`, {
        method: "DELETE",
      });
      const data = await res.json();
      if (res.ok && data.success) {
        setFeedbackList((prev) => prev.filter((fb) => fb.id !== id));
      }
    } catch (err) {
      console.error("Delete feedback error:", err);
    }
  };

  // CRUD Handler - Delete Marine from Roster
  const handleDeleteMarine = async (id: number) => {
    try {
      const res = await fetch(`/api/personnel?id=${id}`, {
        method: "DELETE",
      });
      const data = await res.json();
      if (res.ok && data.success) {
        setPersonnel((prev) => prev.filter((p) => p.id !== id));
      }
    } catch (err) {
      console.error("Delete marine error:", err);
    }
  };

  // Switch target marine directly from roster
  const handleEvaluateMarineFromRoster = (marine: MarinePersonnel) => {
    if (!session) return;
    setSession((prev) =>
      prev
        ? {
            ...prev,
            mode: "other",
            targetRank: marine.rank,
            targetName: marine.name,
            evalType: "Supervisor",
          }
        : null
    );
    setActiveTab("evaluation");
  };

  if (isLoading) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-slate-950 text-slate-100 p-6 space-y-4">
        <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-cyan-950 border border-cyan-500/40 text-cyan-400 animate-pulse">
          <Shield className="h-8 w-8" />
        </div>
        <div className="text-center">
          <h2 className="text-lg font-bold text-white">
            Initializing MNDF Marine Deployment Unit
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Connecting to PostgreSQL and verifying Al-&lsquo;Adl safeguard demo data...
          </p>
        </div>
      </div>
    );
  }

  if (errorMsg && personnel.length === 0) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-slate-950 text-slate-100 p-6">
        <div className="max-w-md rounded-2xl bg-rose-950/80 border border-rose-700 p-6 text-center space-y-4">
          <AlertCircle className="h-10 w-10 text-rose-400 mx-auto" />
          <h2 className="text-lg font-bold text-white">
            System Connection Notice
          </h2>
          <p className="text-xs text-rose-200">{errorMsg}</p>
          <button
            onClick={loadInitialData}
            className="rounded-xl bg-rose-600 hover:bg-rose-500 px-6 py-2.5 text-xs font-bold text-white shadow-lg transition-colors"
          >
            Retry Connection
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex flex-col bg-slate-950 text-slate-100">
      {/* Top Navbar */}
      <Navbar
        session={session}
        onOpenIosModal={() => setIsIosModalOpen(true)}
        onSwitchTarget={() => setSession(null)}
        onLogout={() => {
          setSession(null);
          setActiveTab("evaluation");
        }}
      />

      {/* iPhone PWA Installation Modal */}
      <IosInstallModal
        isOpen={isIosModalOpen}
        onClose={() => setIsIosModalOpen(false)}
      />

      {/* Main container */}
      {!session ? (
        <LoginScreen
          personnelRoster={personnel}
          onLoginSuccess={(sess) => {
            setSession(sess);
            setActiveTab("evaluation");
          }}
          onOpenIosModal={() => setIsIosModalOpen(true)}
          onRosterUpdated={(newRoster) => setPersonnel(newRoster)}
        />
      ) : (
        <div className="flex-1 flex flex-col lg:flex-row max-w-7xl w-full mx-auto pb-20 lg:pb-0">
          {/* Sidebar Navigation */}
          <Sidebar
            activeTab={activeTab}
            onTabChange={(tab) => {
              setActiveTab(tab);
              window.scrollTo({ top: 0, behavior: "smooth" });
            }}
            assessmentCount={evaluations.length}
            actionCount={actions.length}
            rosterCount={personnel.length}
            onOpenIosModal={() => setIsIosModalOpen(true)}
            onLogout={() => {
              setSession(null);
              setActiveTab("evaluation");
            }}
          />

          {/* Active Tab Main Content */}
          <main className="flex-1 p-4 sm:p-6 lg:p-8 overflow-y-auto">
            {activeTab === "evaluation" && (
              <EvaluationForm
                session={session}
                onSubmitted={(newEval) => {
                  setEvaluations((prev) => [newEval, ...prev]);
                }}
                onSwitchTarget={() => setSession(null)}
              />
            )}

            {activeTab === "dashboard" && (
              <AnalyticsDashboard
                evaluations={evaluations}
                onDeleteEvaluation={handleDeleteEvaluation}
              />
            )}

            {activeTab === "actions" && (
              <UnitActionsTab
                session={session}
                actions={actions}
                onActionCreated={(newAction) => {
                  setActions((prev) => [newAction, ...prev]);
                }}
                onActionUpdated={(updatedAction) => {
                  setActions((prev) =>
                    prev.map((a) => (a.id === updatedAction.id ? updatedAction : a))
                  );
                }}
                onActionDeleted={handleDeleteAction}
              />
            )}

            {activeTab === "roster" && (
              <PersonnelRosterTab
                personnel={personnel}
                onMarineAdded={(newMarine) => {
                  setPersonnel((prev) => [...prev, newMarine]);
                }}
                onMarineDeleted={handleDeleteMarine}
                onEvaluateMarine={handleEvaluateMarineFromRoster}
                onRosterUpdated={(newRoster) => setPersonnel(newRoster)}
              />
            )}

            {activeTab === "feedback" && (
              <SystemFeedbackTab
                session={session}
                feedbackList={feedbackList}
                onFeedbackCreated={(newFb) => {
                  setFeedbackList((prev) => [newFb, ...prev]);
                }}
                onFeedbackDeleted={handleDeleteFeedback}
              />
            )}
          </main>
        </div>
      )}
    </div>
  );
}
