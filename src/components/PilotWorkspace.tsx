"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity,
  AlertTriangle,
  Building2,
  ClipboardCheck,
  Home,
  LogOut,
  MessageSquare,
  Pencil,
  RefreshCw,
  ShieldAlert,
  ShieldCheck,
  UserPlus,
  UserX,
  Users,
} from "lucide-react";
import { NotificationCenter } from "./NotificationCenter";
type Principal = {
  accountId: string;
  tenantId: string;
  roles: string[];
  mfa: boolean;
};
type Tab =
  | "home"
  | "appraisals"
  | "activities"
  | "grievances"
  | "corrections"
  | "recommendations"
  | "reports"
  | "organization"
  | "personnel"
  | "records"
  | "readiness";
type Workspace = {
  profile: any;
  permissions: Record<string, boolean>;
  personnel: any[];
  organizationalNodes: any[];
  organizationLevelDefinitions: any[];
  appointmentTypes: any[];
  appointmentDefinitions: any[];
  leadershipSuccession: any[];
  authorizerTransfers: any[];
  administratorAuthorizations: any[];
  cycles: any[];
  cycleSchedule: any[];
  appraisals: any[];
  criteria: any[];
  ratings: any[];
  comments: any[];
  selfAssessments: any[];
  activities: any[];
  awol: any[];
  discipline: any[];
  complaints: any[];
  correctionOfficers: any[];
  adminErrorFlags: any[];
  reopenAuthorizations: any[];
  correctionVersions: any[];
  correctionRatings: any[];
  recommendations: any[];
  operationalReports: any[];
  runtimeSettings: any;
  readinessAccounts: any[];
  readinessChecks: Array<{code:string;label:string;passed:boolean}>;
};
const field =
  "mt-2 min-h-12 w-full min-w-0 max-w-full rounded-xl border border-slate-600 bg-slate-950 px-3";
const button =
  "min-h-12 rounded-xl bg-cyan-500 px-4 font-bold text-slate-950 disabled:opacity-50";
export function PilotWorkspace({ principal }: { principal: Principal }) {
  const [data, setData] = useState<Workspace | null>(null),
    [tab, setTab] = useState<Tab>("home"),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState("");
  const load = useCallback(async (preserveNotice = false) => {
    setBusy(true);
    try {
      const r = await fetch("/api/workspace", { cache: "no-store" });
      const b = await r.json().catch(() => ({}));
      if (r.ok) {
        setData(b.workspace);
        if (!preserveNotice) setNotice("");
      } else setNotice(b.error ?? "Workspace could not be loaded");
    } catch {
      setNotice("Workspace service is temporarily unavailable");
    } finally {
      setBusy(false);
    }
  }, []);
  useEffect(() => {
    void load();
  }, [load]);
  async function request(path: string, method = "POST", body?: unknown) {
    setBusy(true);
    setNotice("");
    const r = await fetch(path, {
      method,
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
    });
    const b = await r.json().catch(() => ({}));
    setNotice(r.ok ? "Saved successfully." : (b.error ?? "Request failed"));
    if (!r.ok) window.scrollTo({ top: 0, behavior: "smooth" });
    if (r.ok) await load(true);
    setBusy(false);
    return { ok: r.ok, body: b };
  }
  async function logout() {
    await fetch("/api/auth/logout", { method: "POST" });
    location.reload();
  }
  const pending =
    data?.appraisals.filter(
      (a) => a.can_evaluate || a.can_acknowledge || a.final_approver,
    ).length ?? 0;
  const dedicatedAdministrator =
    principal.roles.length === 1 && principal.roles[0] === "UNIT_ADMINISTRATOR";
  return (
    <div className="min-h-screen overflow-x-hidden bg-slate-950 text-slate-100">
      <header className="border-b border-slate-800 bg-slate-900/90">
        <div className="mx-auto flex max-w-7xl flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <p className="text-xs font-bold uppercase tracking-[.22em] text-cyan-400">
              Performance Tracker
            </p>
            {data?.profile?.organizational_node_id ? (
              <p className="mt-1 text-sm text-slate-500">
                {data.organizationalNodes.find((node) => node.id === data.profile.organizational_node_id)?.path}
              </p>
            ) : null}
            <h1 className="truncate text-2xl font-bold">
              {data?.profile?.display_name ?? "Secure workspace"}
            </h1>
            <p className="text-sm text-slate-400">
              {data?.profile
                ? data.profile.appointment_title
                : principal.roles.join(", ")}
            </p>
          </div>
          <div className="flex gap-2">
            <NotificationCenter />
            <button
              onClick={() => void load()}
              disabled={busy}
              aria-label="Refresh"
              className="grid h-12 w-12 shrink-0 place-items-center rounded-xl border border-slate-700"
            >
              <RefreshCw className={busy ? "animate-spin" : ""} />
            </button>
            <button
              onClick={logout}
              className="flex min-h-12 items-center gap-2 rounded-xl border border-slate-700 px-4"
            >
              <LogOut />
              Sign out
            </button>
          </div>
        </div>
      </header>
      <nav aria-label="Workspace sections" className="sticky top-0 z-20 border-b border-slate-800 bg-slate-950/95">
        <div className="mx-auto flex max-w-7xl gap-1 overflow-x-auto p-2">
          {(
            [
              ["home", Home, "Overview"],
              ["appraisals", ClipboardCheck, "Appraisals"],
              ["activities", Activity, "Activities"],
              ["grievances", MessageSquare, "Complaints"],
              ["corrections", RefreshCw, "Corrections"],
              ["recommendations", Users, "Recommendations"],
              ["reports", ClipboardCheck, "Reports"],
              ["organization", Building2, "Organization"],
              ["personnel", Users, "Personnel"],
              ["records", ShieldAlert, "Absence & conduct"],
              ["readiness", ShieldCheck, "Pilot readiness"],
            ] as const
          )
            .filter(([id]) =>
              dedicatedAdministrator
                ? ["home", "reports", "organization", "personnel"].includes(id)
                : id!=="readiness" || data?.permissions.readinessView,
            )
            .map(([id, Icon, label]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              aria-current={tab === id ? "page" : undefined}
              className={`flex min-h-12 shrink-0 items-center gap-2 whitespace-nowrap rounded-xl px-4 ${tab === id ? "bg-cyan-500 font-bold text-slate-950" : "text-slate-300"}`}
            >
              <Icon className="h-5 w-5 shrink-0" />
              {label}
            </button>
          ))}
        </div>
      </nav>
      <main className="mx-auto min-w-0 max-w-7xl p-4 sm:p-6">
        {notice ? (
          <div
            role="status"
            className="mb-5 rounded-xl border border-cyan-800 bg-cyan-950/50 p-4 text-cyan-100"
          >
            {notice}
          </div>
        ) : null}
        {!data ? (
          <Loading />
        ) : tab === "home" ? (
          <Overview data={data} pending={pending} />
        ) : tab === "appraisals" ? (
          <Appraisals data={data} busy={busy} request={request} />
        ) : tab === "activities" ? (
          <Activities data={data} busy={busy} request={request} />
        ) : tab === "grievances" ? (
          <Grievances data={data} busy={busy} request={request} />
        ) : tab === "corrections" ? (
          <Corrections data={data} busy={busy} request={request} />
        ) : tab === "recommendations" ? (
          <Recommendations data={data} busy={busy} request={request} />
        ) : tab === "reports" ? (
          <Reports data={data} busy={busy} request={request} />
        ) : tab === "organization" ? (
          <><AdministratorAuthorizationApprovals data={data} busy={busy} request={request}/><Organization data={data} busy={busy} request={request} /></>
        ) : tab === "personnel" ? (
          <Personnel data={data} busy={busy} request={request} />
        ) : tab === "readiness" ? (
          <PilotReadiness data={data} />
        ) : (
          <Records data={data} busy={busy} request={request} />
        )}
      </main>
    </div>
  );
}
function PilotReadiness({data}:{data:Workspace}){
  const passed=data.readinessChecks.filter(check=>check.passed).length;
  const complete=data.readinessChecks.length>0&&passed===data.readinessChecks.length;
  return <section>
    <div className={`rounded-2xl border p-5 ${complete?"border-emerald-700 bg-emerald-950/30":"border-amber-700 bg-amber-950/20"}`}>
      <p className="text-xs font-bold uppercase tracking-[.18em] text-cyan-400">Pre-December acceptance</p>
      <h2 className="mt-2 text-2xl font-bold">Pilot readiness</h2>
      <p className="mt-2 text-slate-300">{passed} of {data.readinessChecks.length} automated readiness checks passed. Login passwords, MFA secrets, and recovery codes are never displayed here.</p>
    </div>
    <div className="mt-6 grid gap-3 md:grid-cols-2">
      {data.readinessChecks.map(check=><article key={check.code} className="flex min-h-20 items-center gap-3 rounded-2xl border border-slate-700 bg-slate-900 p-4">
        <span aria-hidden className={`grid h-10 w-10 shrink-0 place-items-center rounded-full font-bold ${check.passed?"bg-emerald-500/20 text-emerald-300":"bg-amber-500/20 text-amber-200"}`}>{check.passed?"✓":"!"}</span>
        <div><p className="font-semibold">{check.label}</p><p className="text-sm text-slate-400">{check.passed?"Ready":"Action required"}</p></div>
      </article>)}
    </div>
    <h3 className="mt-8 text-xl font-bold">Account readiness</h3>
    <div className="mt-3 overflow-x-auto rounded-2xl border border-slate-700">
      <table className="min-w-full text-left text-sm"><thead className="bg-slate-900 text-slate-300"><tr><th className="p-3">User</th><th className="p-3">Roles</th><th className="p-3">Account</th><th className="p-3">MFA</th></tr></thead>
      <tbody>{data.readinessAccounts.map(account=><tr key={account.id} className="border-t border-slate-800"><td className="p-3"><p className="font-semibold">{account.display_name}</p><p className="text-slate-400">{account.account_login}</p></td><td className="p-3">{account.roles.join(", ")||"No active role"}</td><td className="p-3">{account.is_active?"Active":"Inactive"}</td><td className="p-3">{account.mfa_enabled?"Enrolled":"Not enrolled"}</td></tr>)}</tbody></table>
    </div>
  </section>
}
function Loading() {
  return (
    <div className="grid min-h-80 place-items-center text-slate-400">
      Loading tenant workspace...
    </div>
  );
}
function Overview({ data, pending }: { data: Workspace; pending: number }) {
  const[enrollment,setEnrollment]=useState<{secret:string;uri:string}|null>(null),[mfaMessage,setMfaMessage]=useState("");
  async function beginMfa(){const response=await fetch("/api/auth/mfa/self-enroll",{method:"POST"}),body=await response.json().catch(()=>({}));if(response.ok)setEnrollment({secret:body.secret,uri:body.otpauthUri});else setMfaMessage(body.error??"MFA enrollment failed")}
  async function verifyMfa(event:React.FormEvent<HTMLFormElement>){event.preventDefault();const values=new FormData(event.currentTarget),response=await fetch("/api/auth/mfa/self-enroll/verify",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({code:values.get("code")})}),body=await response.json().catch(()=>({}));if(response.ok)location.reload();else setMfaMessage(body.error??"MFA verification failed")}
  return (
    <>
      <h2 className="text-2xl font-bold">Operational overview</h2>
      <p className="mt-2 text-slate-400">
        Only records allowed by your role and reporting relationships are shown.
      </p>
      <section className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="Actionable appraisals" value={pending} />
        <Metric label="Activities" value={data.activities.length} />
        <Metric
          label="Open unauthorized absence"
          value={
            data.awol.filter(
              (x) => !["RESOLVED", "DISMISSED"].includes(x.status),
            ).length
          }
        />
        <Metric
          label="Open conduct matters"
          value={
            data.discipline.filter(
              (x) => !["RESOLVED", "DISMISSED"].includes(x.status),
            ).length
          }
        />
      </section>
      <section className="mt-8 rounded-2xl border border-slate-800 bg-slate-900 p-5">
        <h3 className="font-bold">Access profile</h3>
        <div className="mt-3 flex flex-wrap gap-2">
          {Object.entries(data.permissions)
            .filter(([, v]) => v)
            .map(([k]) => (
              <span
                key={k}
                className="rounded-full bg-slate-800 px-3 py-1 text-sm text-slate-300"
              >
                {k}
              </span>
            ))}
        </div>
      </section>
      {!data.profile?.mfa_enabled?<section className="mt-8 rounded-2xl border border-amber-700/60 bg-amber-950/20 p-5"><h3 className="font-bold">Prepare for a leadership or administrative appointment</h3><p className="mt-2 text-sm text-slate-300">MFA must be enrolled before System Authorizer authority can be transferred to this account.</p>{!enrollment?<button type="button" onClick={beginMfa} className={`${button} mt-4`}>Enroll authenticator MFA</button>:<form onSubmit={verifyMfa} className="mt-4"><p className="break-all font-mono text-sm text-cyan-300">{enrollment.secret}</p><a href={enrollment.uri} className="mt-2 inline-flex min-h-12 items-center text-cyan-300 underline">Open authenticator link</a><label className="mt-3 block">Six-digit code<input name="code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} required className={field}/></label><button className={`${button} mt-3`}>Verify MFA enrollment</button></form>}{mfaMessage?<p className="mt-3 text-sm text-amber-300">{mfaMessage}</p>:null}</section>:null}
    </>
  );
}
function Metric({ label, value }: { label: string; value: number }) {
  return (
    <article className="rounded-2xl border border-slate-800 bg-slate-900 p-5">
      <p className="text-sm text-slate-400">{label}</p>
      <p className="mt-2 text-3xl font-bold text-cyan-300">{value}</p>
    </article>
  );
}
function Appraisals({
  data,
  busy,
  request,
}: {
  data: Workspace;
  busy: boolean;
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
}) {
  const [selected, setSelected] = useState(
    data.appraisals.find((a) => a.can_evaluate || a.can_self_assess)?.id ??
      data.appraisals[0]?.id ??
      "",
  );
  const [criterionIndex, setCriterionIndex] = useState(0);
  const [evaluatorCriterionIndex, setEvaluatorCriterionIndex] = useState(0);
  const appraisal = data.appraisals.find((a) => a.id === selected);
  const criteria = useMemo(
    () => data.criteria.filter((c) => c.appraisal_id === selected),
    [data.criteria, selected],
  );
  const savedAssessments = data.selfAssessments.filter(
    (entry) => entry.appraisal_id === selected,
  );
  const completedCriterionIds = new Set(
    savedAssessments.map((entry) => entry.criterion_id),
  );
  const completedCount = criteria.filter((criterion) =>
    completedCriterionIds.has(criterion.criterion_id),
  ).length;
  const currentCriterion = criteria[criterionIndex];
  const currentAssessment = savedAssessments.find(
    (entry) => entry.criterion_id === currentCriterion?.criterion_id,
  );
  // Each evaluator in the immutable chain must complete an independent set of
  // ratings. Prior steps remain visible in the audit history, but must never
  // satisfy the active evaluator's completion counter or prefill its form.
  const savedRatings = useMemo(
    () =>
      data.ratings.filter(
        (entry) =>
          entry.appraisal_id === selected &&
          (!appraisal?.current_evaluator_step_id ||
            entry.evaluator_step_id === appraisal.current_evaluator_step_id),
      ),
    [appraisal?.current_evaluator_step_id, data.ratings, selected],
  );
  const ratedCriterionIds = new Set(
    savedRatings.map((entry) => entry.criterion_id),
  );
  const ratedCount = criteria.filter((criterion) =>
    ratedCriterionIds.has(criterion.criterion_id),
  ).length;
  const currentEvaluatorCriterion = criteria[evaluatorCriterionIndex];
  const currentRating = savedRatings.find(
    (entry) => entry.criterion_id === currentEvaluatorCriterion?.criterion_id,
  );
  const currentEvaluatorSelfAssessment = savedAssessments.find(
    (entry) => entry.criterion_id === currentEvaluatorCriterion?.criterion_id,
  );

  useEffect(() => {
    const firstIncomplete = criteria.findIndex(
      (criterion) =>
        !data.selfAssessments.some(
          (entry) =>
            entry.appraisal_id === selected &&
            entry.criterion_id === criterion.criterion_id,
        ),
    );
    setCriterionIndex(
      firstIncomplete >= 0 ? firstIncomplete : Math.max(criteria.length - 1, 0),
    );
  }, [criteria, data.selfAssessments, selected]);

  useEffect(() => {
    const firstUnrated = criteria.findIndex(
      (criterion) =>
        !savedRatings.some(
          (entry) =>
            entry.criterion_id === criterion.criterion_id,
        ),
    );
    setEvaluatorCriterionIndex(
      firstUnrated >= 0 ? firstUnrated : Math.max(criteria.length - 1, 0),
    );
  }, [criteria, savedRatings]);
  async function initialize(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    await request("/api/appraisals/initialize", "POST", {
      cycleId: f.get("cycleId"),
      personnelId: f.get("personnelId"),
    });
  }
  async function selfAssess(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!currentCriterion) return;
    const f = new FormData(e.currentTarget);
    const result = await request(
      `/api/appraisals/${selected}/self-assessment`,
      "POST",
      {
        criterionId: currentCriterion.criterion_id,
        selfRating: Number(f.get("selfRating")),
        narrative: f.get("narrative"),
      },
    );
    if (result.ok && criterionIndex < criteria.length - 1) {
      setCriterionIndex((index) => index + 1);
    }
  }
  async function rate(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!currentEvaluatorCriterion) return;
    const f = new FormData(e.currentTarget),
      rating = Number(f.get("rating"));
    let evidence;
    if ([1, 2, 5].includes(rating)) {
      const file = f.get("evidence");
      if (!(file instanceof File) || !file.size) return;
      const upload = new FormData();
      upload.set("file", file);
      const ur = await fetch("/api/evidence", { method: "POST", body: upload });
      const ub = await ur.json();
      if (!ur.ok) return;
      evidence = { uploadId: ub.evidence.uploadId };
    }
    const result = await request(
      `/api/appraisals/${selected}/ratings`,
      "POST",
      {
        criterionId: currentEvaluatorCriterion.criterion_id,
        rating,
        justification: f.get("justification"),
        evidence,
      },
    );
    if (result.ok && evaluatorCriterionIndex < criteria.length - 1) {
      setEvaluatorCriterionIndex((index) => index + 1);
    }
  }
  async function comment(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    await request(`/api/appraisals/${selected}/comments`, "POST", {
      body: f.get("body"),
      visibility: f.get("visibility"),
    });
  }
  return (
    <>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-2xl font-bold">Appraisal workflow</h2>
          <p className="mt-1 text-slate-400">
            Evaluation-chain assignments are snapshotted when initialized.
          </p>
        </div>
        <span className="rounded-full bg-slate-800 px-3 py-2 text-sm">
          {data.appraisals.length} visible
        </span>
      </div>
      {data.permissions.templateManage ? (
        <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-900 p-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 className="font-bold">Quarterly cycle schedule</h3>
              <p className="mt-1 text-sm text-slate-400">
                Each quarter remains in completion and complaint processing for
                25 calendar days after its end date.
              </p>
            </div>
            <button
              type="button"
              disabled={busy}
              onClick={() => request("/api/cycles/lifecycle", "POST")}
              className={button}
            >
              Synchronize quarterly cycles
            </button>
          </div>
          <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {data.cycleSchedule
              .filter((cycle) => cycle.cycle_type === "QUARTERLY")
              .map((cycle) => (
                <article
                  key={cycle.id}
                  className="rounded-xl border border-slate-700 bg-slate-950 p-3"
                >
                  <div className="flex items-start justify-between gap-2">
                    <strong>{cycle.name}</strong>
                    <Status value={cycle.status} />
                  </div>
                  <p className="mt-2 text-xs text-slate-400">
                    {cycle.starts_on} to {cycle.ends_on}
                  </p>
                  <p className="mt-1 text-xs text-slate-300">
                    Closes after {cycle.closure_due_on}
                  </p>
                </article>
              ))}
          </div>
        </section>
      ) : null}
      {data.permissions.initialize ? (
        <form
          onSubmit={initialize}
          className="mt-6 grid gap-4 rounded-2xl border border-slate-800 bg-slate-900 p-5 md:grid-cols-[1fr_1fr_auto]"
        >
          <label>
            Cycle
            <select name="cycleId" required className={field}>
              {data.cycles.map((x) => (
                <option key={x.id} value={x.id}>
                  {x.name} · {x.cycle_type}
                </option>
              ))}
            </select>
          </label>
          <label>
            Personnel
            <select name="personnelId" required className={field}>
              {data.personnel.map((x) => (
                <option key={x.id} value={x.id}>
                  {x.rank_name} {x.full_name}
                </option>
              ))}
            </select>
          </label>
          <button disabled={busy} className={`${button} md:self-end`}>
            Initialize
          </button>
        </form>
      ) : null}
      <div className="mt-6 grid gap-5 lg:grid-cols-[340px_1fr]">
        <aside className="space-y-2">
          {data.appraisals.map((a) => (
            <button
              key={a.id}
              onClick={() => setSelected(a.id)}
              className={`w-full rounded-xl border p-4 text-left ${selected === a.id ? "border-cyan-500 bg-cyan-950/30" : "border-slate-800 bg-slate-900"}`}
            >
              <span className="font-bold">{a.full_name}</span>
              <span className="mt-1 block text-sm text-slate-400">
                {a.cycle_name} · {a.status}
              </span>
            </button>
          ))}
          {!data.appraisals.length ? (
            <p className="rounded-xl border border-slate-800 p-5 text-slate-400">
              No accessible appraisals.
            </p>
          ) : null}
        </aside>
        {appraisal ? (
          <section className="space-y-5">
            <div className="rounded-2xl border border-slate-800 bg-slate-900 p-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h3 className="text-xl font-bold">{appraisal.full_name}</h3>
                  <p className="text-slate-400">
                    {appraisal.personnel_code} ·{" "}
                    {appraisal.appointment_type_snapshot}
                  </p>
                  {appraisal.score_percentage !== null ? (
                    <p className="mt-2 font-bold text-cyan-300">
                      Score: {appraisal.score_percentage}% ·{" "}
                      {appraisal.total_points}/{appraisal.maximum_points} points
                    </p>
                  ) : null}
                </div>
                <Status value={appraisal.status} />
              </div>
              <div className="mt-5 flex flex-wrap gap-2">
                {appraisal.can_self_assess ? (
                  <button
                    disabled={busy}
                    onClick={() =>
                      request(
                        `/api/appraisals/${selected}/self-assessment`,
                        "PATCH",
                      )
                    }
                    className={button}
                  >
                    Submit self-assessment
                  </button>
                ) : null}
                {appraisal.can_evaluate ? (
                  <button
                    disabled={busy || ratedCount !== criteria.length}
                    onClick={() =>
                      request(`/api/appraisals/${selected}/steps/submit`)
                    }
                    className={button}
                  >
                    {ratedCount === criteria.length
                      ? "Submit completed evaluator step"
                      : `Complete all ratings (${ratedCount}/${criteria.length})`}
                  </button>
                ) : null}
                {appraisal.final_approver &&
                appraisal.status === "AWAITING_COMMANDER_APPROVAL" ? (
                  <button
                    disabled={busy}
                    onClick={() =>
                      request(`/api/appraisals/${selected}/approve`)
                    }
                    className={button}
                  >
                    Approve appraisal
                  </button>
                ) : null}
                {appraisal.can_acknowledge &&
                appraisal.status === "APPROVED" ? (
                  <button
                    disabled={busy}
                    onClick={() =>
                      request(`/api/appraisals/${selected}/acknowledge`)
                    }
                    className={button}
                  >
                    Acknowledge
                  </button>
                ) : null}
                {appraisal.final_approver &&
                appraisal.status === "ACKNOWLEDGED" ? (
                  <button
                    disabled={busy}
                    onClick={() => request(`/api/appraisals/${selected}/close`)}
                    className={button}
                  >
                    Close appraisal
                  </button>
                ) : null}
              </div>
            </div>
            {appraisal.can_self_assess && currentCriterion ? (
              <form
                key={currentCriterion.criterion_id}
                onSubmit={selfAssess}
                className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
              >
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <h3 className="font-bold">Self-assessment</h3>
                  <span className="rounded-full bg-slate-800 px-3 py-1 text-sm text-cyan-300">
                    {completedCount} of {criteria.length} completed
                  </span>
                </div>
                <div
                  className="mt-4 h-2 overflow-hidden rounded-full bg-slate-800"
                  role="progressbar"
                  aria-label="Self-assessment progress"
                  aria-valuemin={0}
                  aria-valuemax={criteria.length}
                  aria-valuenow={completedCount}
                >
                  <div
                    className="h-full rounded-full bg-cyan-400 transition-[width]"
                    style={{
                      width: `${criteria.length ? (completedCount / criteria.length) * 100 : 0}%`,
                    }}
                  />
                </div>
                <p className="mt-5 text-sm font-bold uppercase tracking-wide text-cyan-300">
                  Criterion {criterionIndex + 1} of {criteria.length}
                </p>
                <div className="mt-2 rounded-xl border border-slate-700 bg-slate-950 p-4">
                  <p className="text-sm text-slate-400">
                    {currentCriterion.section_name}
                  </p>
                  <h4 className="mt-1 text-lg font-bold">
                    {currentCriterion.name}
                  </h4>
                  {currentCriterion.description ? (
                    <p className="mt-2 text-sm text-slate-300">
                      {currentCriterion.description}
                    </p>
                  ) : null}
                </div>
                <div className="mt-4 grid gap-4">
                  <label>
                    Self-rating
                    <select
                      name="selfRating"
                      defaultValue={String(currentAssessment?.self_rating ?? 3)}
                      className={field}
                    >
                      {[1, 2, 3, 4, 5].map((n) => (
                        <option key={n} value={n}>
                          {n}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Narrative
                    <textarea
                      name="narrative"
                      required
                      defaultValue={currentAssessment?.narrative ?? ""}
                      className={`${field} min-h-28`}
                    />
                  </label>
                </div>
                <div className="mt-4 flex flex-wrap gap-3">
                  <button
                    type="button"
                    disabled={busy || criterionIndex === 0}
                    onClick={() => setCriterionIndex((index) => index - 1)}
                    className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Previous
                  </button>
                  <button disabled={busy} className={button}>
                    {criterionIndex === criteria.length - 1
                      ? "Save final criterion"
                      : "Save and next"}
                  </button>
                  {currentAssessment && criterionIndex < criteria.length - 1 ? (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => setCriterionIndex((index) => index + 1)}
                      className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
                    >
                      Next saved criterion
                    </button>
                  ) : null}
                </div>
              </form>
            ) : null}
            {appraisal.can_evaluate && currentEvaluatorCriterion ? (
              <form
                key={currentEvaluatorCriterion.criterion_id}
                onSubmit={rate}
                className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
              >
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <h3 className="font-bold">Evaluator assessment</h3>
                  <span className="rounded-full bg-slate-800 px-3 py-1 text-sm text-cyan-300">
                    {ratedCount} of {criteria.length} completed
                  </span>
                </div>
                <div
                  className="mt-4 h-2 overflow-hidden rounded-full bg-slate-800"
                  role="progressbar"
                  aria-label="Evaluator assessment progress"
                  aria-valuemin={0}
                  aria-valuemax={criteria.length}
                  aria-valuenow={ratedCount}
                >
                  <div
                    className="h-full rounded-full bg-cyan-400 transition-[width]"
                    style={{
                      width: `${criteria.length ? (ratedCount / criteria.length) * 100 : 0}%`,
                    }}
                  />
                </div>
                <p className="mt-5 text-sm font-bold uppercase tracking-wide text-cyan-300">
                  Criterion {evaluatorCriterionIndex + 1} of {criteria.length}
                </p>
                <div className="mt-2 rounded-xl border border-slate-700 bg-slate-950 p-4">
                  <p className="text-sm text-slate-400">
                    {currentEvaluatorCriterion.section_name}
                  </p>
                  <h4 className="mt-1 text-lg font-bold">
                    {currentEvaluatorCriterion.name}
                  </h4>
                  {currentEvaluatorCriterion.description ? (
                    <p className="mt-2 text-sm text-slate-300">
                      {currentEvaluatorCriterion.description}
                    </p>
                  ) : null}
                </div>
                {currentEvaluatorSelfAssessment ? (
                  <div className="mt-4 rounded-xl border border-cyan-900 bg-cyan-950/20 p-4">
                    <p className="text-sm font-bold text-cyan-300">
                      Appraisee self-assessment:{" "}
                      {currentEvaluatorSelfAssessment.self_rating}/5
                    </p>
                    <p className="mt-2 whitespace-pre-wrap text-sm text-slate-300">
                      {currentEvaluatorSelfAssessment.narrative}
                    </p>
                  </div>
                ) : null}
                <div className="mt-4 grid gap-4">
                  <label>
                    Rating
                    <select
                      name="rating"
                      required
                      defaultValue={String(currentRating?.rating ?? 3)}
                      className={field}
                    >
                      {[1, 2, 3, 4, 5].map((n) => (
                        <option key={n} value={n}>
                          {n}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Justification
                    <textarea
                      name="justification"
                      defaultValue={currentRating?.justification ?? ""}
                      className={`${field} min-h-28`}
                    />
                  </label>
                  <label>
                    Evidence for ratings 1, 2 or 5
                    <input
                      name="evidence"
                      type="file"
                      accept="application/pdf,image/jpeg,image/png,image/webp"
                      className={field}
                    />
                  </label>
                </div>
                <div className="mt-4 flex flex-wrap gap-3">
                  <button
                    type="button"
                    disabled={busy || evaluatorCriterionIndex === 0}
                    onClick={() =>
                      setEvaluatorCriterionIndex((index) => index - 1)
                    }
                    className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Previous
                  </button>
                  <button disabled={busy} className={button}>
                    {evaluatorCriterionIndex === criteria.length - 1
                      ? "Save final rating"
                      : "Save and next"}
                  </button>
                  {currentRating &&
                  evaluatorCriterionIndex < criteria.length - 1 ? (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() =>
                        setEvaluatorCriterionIndex((index) => index + 1)
                      }
                      className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
                    >
                      Next saved criterion
                    </button>
                  ) : null}
                </div>
                <p className="mt-3 text-xs text-slate-500">
                  Extreme-rating evidence remains pending until the configured
                  malware scanner marks it clean.
                </p>
              </form>
            ) : null}
            {data.permissions.comment &&
            (appraisal.can_evaluate || appraisal.final_approver) ? (
              <form
                onSubmit={comment}
                className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
              >
                <h3 className="font-bold">Evaluator comment</h3>
                <textarea
                  name="body"
                  required
                  className={`${field} mt-4 min-h-28`}
                />
                <select name="visibility" className={field}>
                  <option value="MEMBER_VISIBLE">Member-visible</option>
                  <option value="RESTRICTED_SUPERVISORY">
                    Restricted supervisory
                  </option>
                </select>
                <button disabled={busy} className={`mt-4 ${button}`}>
                  Add comment
                </button>
              </form>
            ) : null}
            <RatingSummary
              criteria={criteria}
              ratings={data.ratings.filter((r) => r.appraisal_id === selected)}
              comments={data.comments.filter(
                (c) => c.appraisal_id === selected,
              )}
            />
          </section>
        ) : (
          <div />
        )}
      </div>
    </>
  );
}
function RatingSummary({
  criteria,
  ratings,
  comments,
}: {
  criteria: any[];
  ratings: any[];
  comments: any[];
}) {
  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900 p-5">
      <h3 className="font-bold">Current record</h3>
      <div className="mt-4 space-y-2">
        {ratings.map((r) => (
          <div
            key={r.criterion_id}
            className="flex justify-between gap-4 border-b border-slate-800 py-2"
          >
            <span>
              {criteria.find((c) => c.criterion_id === r.criterion_id)?.name ??
                r.criterion_id}
            </span>
            <strong>{r.rating}/5</strong>
          </div>
        ))}
      </div>
      {comments.length ? (
        <div className="mt-5">
          <h4 className="font-semibold">
            <MessageSquare className="mr-2 inline h-5 w-5" />
            Member-visible comments
          </h4>
          {comments.map((c, i) => (
            <p key={i} className="mt-2 rounded-xl bg-slate-950 p-3 text-sm">
              {c.body}
            </p>
          ))}
        </div>
      ) : null}
    </section>
  );
}

function Reports({
  data,
  busy,
  request,
}: {
  data: Workspace;
  busy: boolean;
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
}) {
  const [formalReport, setFormalReport] = useState<any>(null);
  const [operationalDetail, setOperationalDetail] = useState<any>(null);
  async function loadFormal(appraisalId: string) {
    const response = await fetch(`/api/reports/formal/${appraisalId}`, {
      cache: "no-store",
    });
    const body = await response.json().catch(() => ({}));
    setFormalReport(
      response.ok ? body.report : { error: body.error ?? "Report unavailable" },
    );
  }
  async function loadOperational(reportId: string) {
    const response = await fetch(`/api/reports/operational/${reportId}`, {
      cache: "no-store",
    });
    const body = await response.json().catch(() => ({}));
    setOperationalDetail(
      response.ok ? body.report : { error: body.error ?? "Report unavailable" },
    );
  }
  async function createOperational(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    await request("/api/reports/operational", "POST", {
      personnelId: form.get("personnelId"),
      periodType: form.get("periodType"),
      periodStart: form.get("periodStart"),
      periodEnd: form.get("periodEnd"),
      progress: form.get("progress"),
      supervisorFeedback: form.get("supervisorFeedback"),
      challenges: form.get("challenges"),
      trainingRequirements: form.get("trainingRequirements"),
      activityIds: form.getAll("activityIds"),
    });
  }
  async function transitionOperational(reportId:string,action:"submit"|"confirm"){
    await request(`/api/reports/operational/${reportId}/transition`,"POST",{action});
  }
  const december2026 =
    new Date().getFullYear() === 2026 && new Date().getMonth() === 11;
  return (
    <>
      <h2 className="text-2xl font-bold">Reports</h2>
      <p className="mt-2 text-slate-400">
        Operational reports contain no numerical ratings. Formal reports exclude
        restricted comments and production reports exclude training-mode
        records.
      </p>
      {data.permissions.templateManage ? (
        <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-900 p-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 className="font-bold">December onboarding data mode</h3>
              <p className="mt-1 text-sm text-slate-400">
                Configured: {data.runtimeSettings.active_data_mode}. The toggle
                is available only during December 2026.
              </p>
            </div>
            <button
              type="button"
              disabled={busy || !december2026}
              onClick={() =>
                request("/api/settings/training-mode", "POST", {
                  enabled: data.runtimeSettings.active_data_mode !== "TRAINING",
                })
              }
              className={button}
            >
              {data.runtimeSettings.active_data_mode === "TRAINING"
                ? "Switch to production"
                : "Enable training mode"}
            </button>
          </div>
        </section>
      ) : null}
      {data.permissions.comment ? (
        <form
          onSubmit={createOperational}
          className="mt-6 rounded-2xl border border-slate-800 bg-slate-900 p-5"
        >
          <h3 className="font-bold">Create non-scored operational report</h3>
          <div className="mt-4 grid gap-4 md:grid-cols-2">
            <label>
              Personnel
              <select name="personnelId" required className={field}>
                {data.personnel.map((person) => (
                  <option key={person.id} value={person.id}>
                    {person.full_name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Period
              <select name="periodType" className={field}>
                <option value="WEEKLY">Weekly</option>
                <option value="TWICE_MONTHLY">Twice monthly</option>
                <option value="MONTHLY">Monthly</option>
                <option value="EVERY_TWO_MONTHS">Every two months</option>
              </select>
            </label>
            <label>
              Start date
              <input
                name="periodStart"
                type="date"
                required
                className={field}
              />
            </label>
            <label>
              End date
              <input name="periodEnd" type="date" required className={field} />
            </label>
            <label>
              Progress
              <textarea
                name="progress"
                required
                className={`${field} min-h-24`}
              />
            </label>
            <label>
              Supervisor feedback
              <textarea
                name="supervisorFeedback"
                required
                className={`${field} min-h-24`}
              />
            </label>
            <label>
              Challenges
              <textarea
                name="challenges"
                required
                className={`${field} min-h-24`}
              />
            </label>
            <label>
              Training requirements
              <textarea
                name="trainingRequirements"
                required
                className={`${field} min-h-24`}
              />
            </label>
          </div>
          {data.activities.length ? (
            <fieldset className="mt-4">
              <legend className="font-bold">Include activity records</legend>
              <div className="mt-2 grid gap-2">
                {data.activities.map((activity) => (
                  <label
                    key={activity.id}
                    className="flex min-h-12 items-center gap-3 rounded-xl border border-slate-700 p-3"
                  >
                    <input
                      type="checkbox"
                      name="activityIds"
                      value={activity.id}
                      className="h-5 w-5"
                    />
                    <span>
                      {activity.activity_date} · {activity.title}
                    </span>
                  </label>
                ))}
              </div>
            </fieldset>
          ) : null}
          <button disabled={busy} className={`mt-4 ${button}`}>
            Create operational report
          </button>
        </form>
      ) : null}
      <section className="mt-6">
        <h3 className="text-lg font-bold">Formal performance reports</h3>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          {data.appraisals.filter((appraisal)=>appraisal.data_mode==="PRODUCTION"&&["APPROVED","ACKNOWLEDGED","COMPLAINT_OPEN","CLOSED"].includes(appraisal.status)).map((appraisal) => (
            <article
              key={appraisal.id}
              className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
            >
              <p className="font-bold">{appraisal.full_name}</p>
              <p className="text-sm text-slate-400">
                {appraisal.cycle_name} · {appraisal.status}
              </p>
              <div className="mt-4 flex flex-wrap gap-3">
                <button
                  type="button"
                  onClick={() => loadFormal(appraisal.id)}
                  className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
                >
                  View report
                </button>
                {appraisal.cycle_type === "QUARTERLY" ? (
                  <a
                    href={`/api/reports/formal/${appraisal.id}/pdf`}
                    className={button}
                  >
                    Download PDF
                  </a>
                ) : null}
              </div>
            </article>
          ))}
        </div>
      </section>
      {formalReport ? (
        <section className="mt-6 rounded-2xl border border-cyan-800 bg-slate-900 p-5">
          <h3 className="font-bold">Formal report preview</h3>
          {formalReport.error ? (
            <p className="mt-3 text-red-300">{formalReport.error}</p>
          ) : (
            <>
              <p className="mt-3 text-xl font-bold">
                {formalReport.full_name} · {formalReport.score_percentage}%
              </p>
              <p className="mt-1 text-slate-400">
                {formalReport.total_points}/{formalReport.maximum_points} ·
                Complaint: {formalReport.complaint_status ?? "None"}
              </p>
              <h4 className="mt-5 font-bold">Ratings</h4>
              <div className="mt-2 space-y-2">
                {formalReport.ratings?.map((rating: any, index: number) => (
                  <p key={index} className="rounded-xl bg-slate-950 p-3">
                    {rating.criterion}: <strong>{rating.rating}/5</strong>
                    {rating.justification ? ` — ${rating.justification}` : ""}
                  </p>
                ))}
              </div>
              <h4 className="mt-5 font-bold">Member-visible comments</h4>
              {formalReport.public_comments?.length ? (
                formalReport.public_comments.map(
                  (comment: any, index: number) => (
                    <p key={index} className="mt-2 rounded-xl bg-slate-950 p-3">
                      {comment.body}
                    </p>
                  ),
                )
              ) : (
                <p className="mt-2 text-slate-400">None</p>
              )}
              <h4 className="mt-5 font-bold">Achievements and development requirements</h4>
              {formalReport.development?.length?formalReport.development.map((item:any,index:number)=><div key={index} className="mt-2 rounded-xl bg-slate-950 p-3"><p><strong>Achievement:</strong> {item.achievement??"None"}</p><p className="mt-1"><strong>Development:</strong> {item.developmentRequirement??item.challenge??"None"}</p></div>):<p className="mt-2 text-slate-400">None</p>}
              <h4 className="mt-5 font-bold">Evaluation chain</h4>
              {formalReport.evaluation_chain?.length?formalReport.evaluation_chain.map((step:any,index:number)=><p key={index} className="mt-2 rounded-xl bg-slate-950 p-3">{step.sequence}. {step.evaluator} · {step.kind} · {step.status}</p>):<p className="mt-2 text-slate-400">None</p>}
              <h4 className="mt-5 font-bold">Approval, acknowledgement, and complaint</h4>
              <dl className="mt-2 grid gap-2 rounded-xl bg-slate-950 p-3 sm:grid-cols-3"><div><dt className="text-slate-400">Approved</dt><dd>{formalReport.approved_at?formatDeadline(formalReport.approved_at):"Pending"}</dd></div><div><dt className="text-slate-400">Acknowledged</dt><dd>{formalReport.acknowledged_at?formatDeadline(formalReport.acknowledged_at):"Pending"}</dd></div><div><dt className="text-slate-400">Complaint</dt><dd>{formalReport.complaint_status??"None"}</dd></div></dl>
            </>
          )}
        </section>
      ) : null}
      <section className="mt-6">
        <h3 className="text-lg font-bold">Operational report history</h3>
        <div className="mt-4 space-y-3">
          {data.operationalReports.map((report) => (
            <article key={report.id} className="rounded-xl border border-slate-800 bg-slate-900 p-4">
              <div className="flex flex-wrap items-start justify-between gap-3"><div><strong>{report.full_name} · {report.period_type.replaceAll("_", " ")}</strong><span className="mt-1 block text-sm text-slate-400">{report.period_start} to {report.period_end} · {report.data_mode}</span></div><Status value={report.status}/></div>
              <div className="mt-3 flex flex-wrap gap-3"><button type="button" onClick={()=>loadOperational(report.id)} className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold">View details</button>
                {report.status==="DRAFT"&&data.permissions.comment?<button type="button" disabled={busy} onClick={()=>transitionOperational(report.id,"submit")} className={button}>Submit report</button>:null}
                {report.status==="SUBMITTED"&&data.permissions.confirm?<button type="button" disabled={busy} onClick={()=>transitionOperational(report.id,"confirm")} className={button}>Confirm report</button>:null}
              </div>
            </article>
          ))}
          {!data.operationalReports.length ? (
            <p className="rounded-xl border border-slate-800 p-5 text-slate-400">
              No operational reports available.
            </p>
          ) : null}
        </div>
      </section>
      {operationalDetail ? (
        <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-900 p-5">
          <h3 className="font-bold">Operational report detail</h3>
          {operationalDetail.error ? (
            <p className="mt-3 text-red-300">{operationalDetail.error}</p>
          ) : (
            <dl className="mt-4 grid gap-4">
              <div>
                <dt className="text-slate-400">Progress</dt>
                <dd>{operationalDetail.progress}</dd>
              </div>
              <div>
                <dt className="text-slate-400">Supervisor feedback</dt>
                <dd>{operationalDetail.supervisor_feedback}</dd>
              </div>
              <div>
                <dt className="text-slate-400">Challenges</dt>
                <dd>{operationalDetail.challenges}</dd>
              </div>
              <div>
                <dt className="text-slate-400">Training requirements</dt>
                <dd>{operationalDetail.training_requirements}</dd>
              </div>
              <div>
                <dt className="text-slate-400">Pending confirmations</dt>
                <dd>{operationalDetail.pending_confirmations}</dd>
              </div>
            </dl>
          )}
        </section>
      ) : null}
    </>
  );
}

function Recommendations({
  data,
  busy,
  request,
}: {
  data: Workspace;
  busy: boolean;
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
}) {
  async function recalculate(personnelId: string) {
    await request("/api/recommendations/recalculate", "POST", { personnelId });
  }
  async function transition(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const submitter = (e.nativeEvent as SubmitEvent)
      .submitter as HTMLButtonElement | null;
    const action = submitter?.value;
    if (!action || !["nominate", "approve", "reject"].includes(action)) return;
    await request(
      `/api/recommendations/${form.get("recommendationId")}/transition`,
      "POST",
      { action, reason: form.get("reason") },
    );
  }
  return (
    <>
      <h2 className="text-2xl font-bold">
        Promotion and commendation recommendations
      </h2>
      <p className="mt-2 text-slate-400">
        Eligibility is calculated from the latest completed annual appraisal and
        is recalculated after score corrections or conduct-matter resolution.
      </p>
      {data.permissions.manage ? (
        <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-900 p-5">
          <h3 className="font-bold">Recalculate eligibility</h3>
          <p className="mt-1 text-sm text-slate-400">
            Quarterly and half-year appraisals do not create annual eligibility
            records.
          </p>
          <div className="mt-4 flex flex-wrap gap-3">
            {data.personnel.map((person) => (
              <button
                key={person.id}
                type="button"
                disabled={busy}
                onClick={() => recalculate(person.id)}
                className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
              >
                {person.full_name}
              </button>
            ))}
          </div>
        </section>
      ) : null}
      <section className="mt-6 space-y-4">
        {data.recommendations.map((recommendation) => {
          const serviceMet =
            recommendation.service_threshold_at &&
            Date.now() >
              new Date(recommendation.service_threshold_at).getTime();
          return (
            <article
              key={recommendation.id}
              className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h3 className="text-lg font-bold">
                    {recommendation.full_name}
                  </h3>
                  <p className="text-sm text-slate-400">
                    {recommendation.personnel_code} ·{" "}
                    {recommendation.recommendation_type}
                  </p>
                </div>
                <Status value={recommendation.status} />
              </div>
              <div className="mt-5 grid gap-3 sm:grid-cols-2">
                <EligibilityCheck
                  passed={Number(recommendation.annual_score_percentage) > 85}
                  label={`Annual score above 85% (${recommendation.annual_score_percentage}%)`}
                />
                <EligibilityCheck
                  passed={!recommendation.has_rating_below_three}
                  label="No individual rating below 3"
                />
                <EligibilityCheck
                  passed={!recommendation.has_unresolved_disciplinary_matter}
                  label="No unresolved absence or conduct matter"
                />
                <EligibilityCheck
                  passed={Boolean(serviceMet)}
                  label={`More than nine months in the organization${recommendation.service_threshold_at ? ` (threshold ${formatDeadline(recommendation.service_threshold_at)})` : ""}`}
                />
              </div>
              <p
                className={`mt-4 font-bold ${recommendation.eligible ? "text-emerald-300" : "text-amber-300"}`}
              >
                {recommendation.eligible
                  ? "System eligible"
                  : "System ineligible"}
              </p>
              {recommendation.nomination_reason ? (
                <p className="mt-2 text-sm">
                  Nomination: {recommendation.nomination_reason}
                </p>
              ) : null}
              {recommendation.decision_reason ? (
                <p className="mt-2 text-sm">
                  Commander decision: {recommendation.decision_reason}
                </p>
              ) : null}
              {(data.permissions.manage &&
                recommendation.status === "ELIGIBLE") ||
              (data.permissions.approve &&
                recommendation.status === "NOMINATED") ? (
                <form onSubmit={transition} className="mt-4 grid gap-3">
                  <input
                    type="hidden"
                    name="recommendationId"
                    value={recommendation.id}
                  />
                  <label>
                    {recommendation.status === "ELIGIBLE"
                      ? "Nomination reason"
                      : "Commander decision reason"}
                    <textarea
                      name="reason"
                      required
                      className={`${field} min-h-24`}
                    />
                  </label>
                  <div className="flex flex-wrap gap-3">
                    {recommendation.status === "ELIGIBLE" ? (
                      <button
                        name="action"
                        value="nominate"
                        disabled={busy}
                        className={button}
                      >
                        Nominate
                      </button>
                    ) : (
                      <>
                        <button
                          name="action"
                          value="approve"
                          disabled={busy}
                          className={button}
                        >
                          Approve recommendation
                        </button>
                        <button
                          name="action"
                          value="reject"
                          disabled={busy}
                          className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
                        >
                          Reject recommendation
                        </button>
                      </>
                    )}
                  </div>
                </form>
              ) : null}
            </article>
          );
        })}
        {!data.recommendations.length ? (
          <p className="rounded-xl border border-amber-800 bg-amber-950/20 p-5 text-amber-100">
            No annual eligibility record exists yet. The current Q1 2027 pilot
            appraisal is quarterly; eligibility requires a completed annual
            appraisal.
          </p>
        ) : null}
      </section>
    </>
  );
}

function EligibilityCheck({
  passed,
  label,
}: {
  passed: boolean;
  label: string;
}) {
  return (
    <div
      className={`rounded-xl border p-3 text-sm ${passed ? "border-emerald-800 bg-emerald-950/20 text-emerald-200" : "border-amber-800 bg-amber-950/20 text-amber-200"}`}
    >
      <span className="mr-2 font-bold">{passed ? "PASS" : "NOT MET"}</span>
      {label}
    </div>
  );
}

function Corrections({
  data,
  busy,
  request,
}: {
  data: Workspace;
  busy: boolean;
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
}) {
  const [correctionIndex, setCorrectionIndex] = useState(0);
  async function flagError(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    await request(
      `/api/appraisals/${form.get("appraisalId")}/error-flags`,
      "POST",
      { reason: form.get("reason") },
    );
  }
  async function authorize(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const basis = String(form.get("basis")).split(":");
    await request(
      `/api/appraisals/${form.get("appraisalId")}/reopen-authorizations`,
      "POST",
      {
        complaintId: basis[0] === "complaint" ? basis[1] : undefined,
        adminErrorFlagId: basis[0] === "flag" ? basis[1] : undefined,
        correctionOfficerAccountId: form.get("correctionOfficerAccountId"),
        reason: form.get("reason"),
      },
    );
  }
  async function createVersion(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    await request("/api/corrections", "POST", {
      authorizationId: form.get("authorizationId"),
      reason: form.get("reason"),
    });
  }
  async function saveCorrectedRating(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!draftVersion || !currentCorrectionRating) return;
    const form = new FormData(e.currentTarget);
    const rating = Number(form.get("rating"));
    let evidence;
    if ([1, 2, 5].includes(rating)) {
      const file = form.get("evidence");
      if (!(file instanceof File) || !file.size) return;
      const upload = new FormData();
      upload.set("file", file);
      const response = await fetch("/api/evidence", {
        method: "POST",
        body: upload,
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) return;
      evidence = { uploadId: body.evidence.uploadId };
    }
    const result = await request(
      `/api/corrections/${draftVersion.id}/ratings`,
      "POST",
      {
        criterionId: currentCorrectionRating.criterion_id,
        originalRatingId: currentCorrectionRating.original_rating_id,
        rating,
        justification: form.get("justification"),
        reason: form.get("reason"),
        evidence,
      },
    );
    if (result.ok && correctionIndex < draftRatings.length - 1)
      setCorrectionIndex((index) => index + 1);
  }
  async function transitionVersion(
    versionId: string,
    action: "submit" | "approve" | "reject",
    reason?: string,
  ) {
    await request(`/api/corrections/${versionId}/transition`, "POST", {
      action,
      reason,
    });
  }
  async function reviewVersion(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const submitter = (e.nativeEvent as SubmitEvent)
      .submitter as HTMLButtonElement | null;
    const action = submitter?.value;
    if (action !== "approve" && action !== "reject") return;
    await transitionVersion(
      String(form.get("versionId")),
      action,
      String(form.get("reason")),
    );
  }
  const draftVersion = data.correctionVersions.find(
    (version) => version.status === "DRAFT",
  );
  const draftRatings = draftVersion
    ? data.correctionRatings.filter(
        (rating) => rating.correction_version_id === draftVersion.id,
      )
    : [];
  const currentCorrectionRating = draftRatings[correctionIndex];
  const changedCount = draftRatings.filter(
    (rating) =>
      rating.rating !== rating.original_rating ||
      (rating.justification ?? "") !== (rating.original_justification ?? ""),
  ).length;
  const closed = data.appraisals.filter((item) => item.status === "CLOSED");
  const now = Date.now();
  return (
    <>
      <h2 className="text-2xl font-bold">Corrections and reopening</h2>
      <p className="mt-2 text-slate-400">
        Original appraisal content remains immutable. Reopening requires a
        complaint or formal error flag, System Authorizer approval, and use within
        five calendar days.
      </p>
      {!closed.length ? (
        <p className="mt-6 rounded-xl border border-amber-800 bg-amber-950/20 p-4 text-amber-100">
          No closed appraisal is currently eligible for reopening. The System Authorizer
          must close an acknowledged appraisal before this workflow can begin.
        </p>
      ) : null}
      {data.permissions.manage ? (
        <section className="mt-6 space-y-4">
          <h3 className="text-lg font-bold">
            Formal administrative error flag
          </h3>
          {closed.map((appraisal) => (
            <form
              key={appraisal.id}
              onSubmit={flagError}
              className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
            >
              <input type="hidden" name="appraisalId" value={appraisal.id} />
              <p className="font-bold">
                {appraisal.full_name} · {appraisal.cycle_name}
              </p>
              <label className="mt-4 block">
                Error description
                <textarea
                  name="reason"
                  required
                  className={`${field} min-h-24`}
                />
              </label>
              <button disabled={busy} className={`mt-4 ${button}`}>
                Formally flag error
              </button>
            </form>
          ))}
        </section>
      ) : null}
      {data.permissions.correctionAuthorize ? (
        <section className="mt-6 space-y-4">
          <h3 className="text-lg font-bold">
            System Authorizer reopening approval
          </h3>
          {closed.map((appraisal) => {
            const bases = [
              ...data.complaints
                .filter((item) => item.appraisal_id === appraisal.id)
                .map((item) => ({
                  value: `complaint:${item.id}`,
                  label: `Complaint · ${item.status}`,
                })),
              ...data.adminErrorFlags
                .filter(
                  (item) =>
                    item.appraisal_id === appraisal.id && !item.withdrawn_at,
                )
                .map((item) => ({
                  value: `flag:${item.id}`,
                  label: `Administrative flag · ${item.reason}`,
                })),
            ];
            const officers = data.correctionOfficers.filter(
              (item) => item.appraisal_id === appraisal.id,
            );
            return (
              <form
                key={appraisal.id}
                onSubmit={authorize}
                className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
              >
                <input type="hidden" name="appraisalId" value={appraisal.id} />
                <p className="font-bold">
                  {appraisal.full_name} · {appraisal.cycle_name}
                </p>
                <label className="mt-4 block">
                  Reopening basis
                  <select name="basis" required className={field}>
                    {bases.map((item) => (
                      <option key={item.value} value={item.value}>
                        {item.label}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="mt-4 block">
                  Assigned correction officer
                  <select
                    name="correctionOfficerAccountId"
                    required
                    className={field}
                  >
                    {officers.map((item) => (
                      <option key={item.account_id} value={item.account_id}>
                        {item.rank_name} {item.full_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="mt-4 block">
                  System Authorizer approval reason
                  <textarea
                    name="reason"
                    required
                    className={`${field} min-h-24`}
                  />
                </label>
                <button
                  disabled={busy || !bases.length || !officers.length}
                  className={`mt-4 ${button}`}
                >
                  Authorize reopening for five days
                </button>
              </form>
            );
          })}
        </section>
      ) : null}
      <section className="mt-6 space-y-4">
        <h3 className="text-lg font-bold">Assigned reopening authorizations</h3>
        {data.reopenAuthorizations.map((authorization) => {
          const expired = new Date(authorization.expires_at).getTime() < now;
          const usable = !authorization.used_at && !expired;
          return (
            <article
              key={authorization.id}
              className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
            >
              <div className="flex flex-wrap justify-between gap-3">
                <div>
                  <p className="font-bold">
                    Correction officer: {authorization.correction_officer_name}
                  </p>
                  <p className="mt-1 text-sm text-slate-400">
                    Expires {formatDeadline(authorization.expires_at)}
                  </p>
                </div>
                <Status
                  value={
                    authorization.used_at
                      ? "USED"
                      : expired
                        ? "EXPIRED"
                        : "AUTHORIZED"
                  }
                />
              </div>
              <p className="mt-4">{authorization.reason}</p>
              {usable && authorization.is_assigned_officer ? (
                <form onSubmit={createVersion} className="mt-4">
                  <input
                    type="hidden"
                    name="authorizationId"
                    value={authorization.id}
                  />
                  <label>
                    Mandatory correction reason
                    <textarea
                      name="reason"
                      required
                      className={`${field} min-h-24`}
                    />
                  </label>
                  <button disabled={busy} className={`mt-4 ${button}`}>
                    Create immutable correction version
                  </button>
                </form>
              ) : usable ? (
                <p className="mt-4 rounded-xl border border-slate-700 p-4 text-sm text-slate-300">
                  Awaiting action by the assigned correction officer. System Authorizer
                  accounts may authorize and later approve corrections, but
                  cannot create or edit the correction version.
                </p>
              ) : null}
            </article>
          );
        })}
        {!data.reopenAuthorizations.length ? (
          <p className="rounded-xl border border-slate-800 p-5 text-slate-400">
            No reopening authorization is assigned to this account.
          </p>
        ) : null}
      </section>
      {draftVersion && currentCorrectionRating ? (
        <section className="mt-6 rounded-2xl border border-cyan-800 bg-slate-900 p-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h3 className="text-lg font-bold">
              Edit correction version {draftVersion.version_no}
            </h3>
            <span className="rounded-full bg-slate-800 px-3 py-1 text-sm text-cyan-300">
              {changedCount} changed · Criterion {correctionIndex + 1} of{" "}
              {draftRatings.length}
            </span>
          </div>
          <div className="mt-4 rounded-xl border border-slate-700 bg-slate-950 p-4">
            <p className="text-sm text-slate-400">
              {currentCorrectionRating.section_name}
            </p>
            <h4 className="mt-1 font-bold">
              {currentCorrectionRating.criterion_name}
            </h4>
            <p className="mt-2 text-sm text-slate-300">
              {currentCorrectionRating.description}
            </p>
            <p className="mt-3 text-sm font-bold text-amber-300">
              Original approved rating:{" "}
              {currentCorrectionRating.original_rating}/5
            </p>
            {currentCorrectionRating.original_justification ? (
              <p className="mt-2 text-sm text-slate-400">
                Original justification:{" "}
                {currentCorrectionRating.original_justification}
              </p>
            ) : null}
          </div>
          <form
            key={currentCorrectionRating.id}
            onSubmit={saveCorrectedRating}
            className="mt-4 grid gap-4"
          >
            <label>
              Corrected rating
              <select
                name="rating"
                required
                defaultValue={String(currentCorrectionRating.rating)}
                className={field}
              >
                {[1, 2, 3, 4, 5].map((rating) => (
                  <option key={rating} value={rating}>
                    {rating}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Corrected justification
              <textarea
                name="justification"
                defaultValue={currentCorrectionRating.justification ?? ""}
                className={`${field} min-h-24`}
              />
            </label>
            <label>
              Mandatory reason for this rating change
              <textarea
                name="reason"
                required
                defaultValue={
                  currentCorrectionRating.correction_reason ===
                  "Original approved rating snapshot"
                    ? ""
                    : currentCorrectionRating.correction_reason
                }
                className={`${field} min-h-24`}
              />
            </label>
            <label>
              Evidence for corrected ratings 1, 2 or 5
              <input
                name="evidence"
                type="file"
                accept="application/pdf,image/jpeg,image/png,image/webp"
                className={field}
              />
            </label>
            <div className="flex flex-wrap gap-3">
              <button
                type="button"
                disabled={busy || correctionIndex === 0}
                onClick={() => setCorrectionIndex((index) => index - 1)}
                className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold disabled:opacity-40"
              >
                Previous
              </button>
              <button disabled={busy} className={button}>
                {correctionIndex === draftRatings.length - 1
                  ? "Save final correction"
                  : "Save and next"}
              </button>
              {correctionIndex < draftRatings.length - 1 ? (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => setCorrectionIndex((index) => index + 1)}
                  className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
                >
                  Next criterion
                </button>
              ) : null}
            </div>
          </form>
          <button
            type="button"
            disabled={busy || changedCount === 0}
            onClick={() => transitionVersion(draftVersion.id, "submit")}
            className={`mt-6 ${button}`}
          >
            {changedCount
              ? `Submit ${changedCount} correction${changedCount === 1 ? "" : "s"} for System Authorizer approval`
              : "Change at least one rating before submission"}
          </button>
        </section>
      ) : null}
      {data.correctionVersions.length ? (
        <section className="mt-6 space-y-4">
          <h3 className="text-lg font-bold">Correction version history</h3>
          {data.correctionVersions.map((version) => (
            <article
              key={version.id}
              className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
            >
              <div className="flex flex-wrap justify-between gap-3">
                <p className="font-bold">Version {version.version_no}</p>
                <Status value={version.status} />
              </div>
              <p className="mt-3">{version.reason}</p>
              {version.score_percentage !== null ? (
                <p className="mt-2 text-cyan-300">
                  Corrected score: {version.score_percentage}%
                </p>
              ) : null}
              {data.permissions.correctionAuthorize &&
              version.status === "AWAITING_APPROVAL" ? (
                <form onSubmit={reviewVersion} className="mt-4 grid gap-3">
                  <input type="hidden" name="versionId" value={version.id} />
                  <label>
                    System Authorizer decision reason
                    <textarea
                      name="reason"
                      required
                      className={`${field} min-h-24`}
                    />
                  </label>
                  <div className="flex flex-wrap gap-3">
                    <button
                      name="action"
                      value="approve"
                      disabled={busy}
                      className={button}
                    >
                      Approve corrected version
                    </button>
                    <button
                      name="action"
                      value="reject"
                      disabled={busy}
                      className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
                    >
                      Reject correction
                    </button>
                  </div>
                </form>
              ) : null}
            </article>
          ))}
        </section>
      ) : null}
    </>
  );
}

function formatDeadline(value: string | null) {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "long",
  }).format(new Date(value));
}

function Grievances({
  data,
  busy,
  request,
}: {
  data: Workspace;
  busy: boolean;
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
}) {
  const [restrictedByCase, setRestrictedByCase] = useState<
    Record<string, any[]>
  >({});
  const [restrictedLoading, setRestrictedLoading] = useState<string | null>(
    null,
  );
  const [restrictedError, setRestrictedError] = useState<
    Record<string, string>
  >({});

  async function loadRestrictedComments(complaintId: string) {
    setRestrictedLoading(complaintId);
    setRestrictedError((current) => ({ ...current, [complaintId]: "" }));
    try {
      const response = await fetch(
        `/api/complaints/${complaintId}/restricted-comments`,
        { cache: "no-store" },
      );
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        setRestrictedError((current) => ({
          ...current,
          [complaintId]:
            body.error ?? "Restricted comments could not be loaded",
        }));
        return;
      }
      setRestrictedByCase((current) => ({
        ...current,
        [complaintId]: body.comments ?? [],
      }));
    } finally {
      setRestrictedLoading(null);
    }
  }
  async function submitComplaint(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    await request("/api/complaints", "POST", {
      appraisalId: form.get("appraisalId"),
      grounds: form.get("grounds"),
    });
  }
  async function transitionComplaint(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    await request(
      `/api/complaints/${form.get("complaintId")}/transition`,
      "POST",
      {
        action: form.get("action"),
        reason: form.get("reason"),
        decision: form.get("decision"),
      },
    );
  }
  const complaintAppraisalIds = new Set(
    data.complaints.map((item) => item.appraisal_id),
  );
  const eligibleAppraisals = data.appraisals.filter(
    (item) =>
      item.can_acknowledge &&
      item.available_to_member_at &&
      ["APPROVED", "ACKNOWLEDGED"].includes(item.status) &&
      !complaintAppraisalIds.has(item.id),
  );
  return (
    <>
      <h2 className="text-2xl font-bold">Complaints and grievances</h2>
      <p className="mt-2 text-slate-400">
        All deadlines use server timestamps and include weekends and public
        holidays.
      </p>
      {eligibleAppraisals.map((appraisal) => {
        const deadline = new Date(
          new Date(appraisal.available_to_member_at).getTime() +
            3 * 24 * 60 * 60 * 1000,
        );
        const expired = Date.now() > deadline.getTime();
        return (
          <form
            key={appraisal.id}
            onSubmit={submitComplaint}
            className="mt-6 rounded-2xl border border-slate-800 bg-slate-900 p-5"
          >
            <input type="hidden" name="appraisalId" value={appraisal.id} />
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h3 className="text-lg font-bold">{appraisal.cycle_name}</h3>
                <p className="text-slate-400">{appraisal.full_name}</p>
              </div>
              <span
                className={`rounded-full px-3 py-1 text-sm font-bold ${expired ? "bg-red-950 text-red-300" : "bg-cyan-950 text-cyan-300"}`}
              >
                {expired ? "Submission window expired" : "Submission open"}
              </span>
            </div>
            <p className="mt-4 text-sm">
              Complaint submission deadline:{" "}
              {formatDeadline(deadline.toISOString())}
            </p>
            <label className="mt-4 block">
              Grounds for complaint
              <textarea
                name="grounds"
                required
                disabled={expired}
                className={`${field} min-h-32`}
              />
            </label>
            <button disabled={busy || expired} className={`mt-4 ${button}`}>
              Submit complaint
            </button>
          </form>
        );
      })}
      <section className="mt-6 space-y-4">
        {data.complaints.map((complaint) => (
          <article
            key={complaint.id}
            className={`rounded-2xl border p-5 ${complaint.is_overdue ? "border-red-700 bg-red-950/20" : "border-slate-800 bg-slate-900"}`}
          >
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h3 className="text-lg font-bold">{complaint.full_name}</h3>
                <p className="text-sm text-slate-400">
                  {complaint.personnel_code} · Submitted{" "}
                  {formatDeadline(complaint.submitted_at)}
                </p>
              </div>
              <Status
                value={
                  complaint.is_overdue
                    ? `${complaint.status}_OVERDUE`
                    : complaint.status
                }
              />
            </div>
            <p className="mt-4 whitespace-pre-wrap">{complaint.grounds}</p>
            <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
              <div>
                <dt className="text-slate-400">Acceptance deadline</dt>
                <dd>{formatDeadline(complaint.acceptance_deadline_at)}</dd>
              </div>
              <div>
                <dt className="text-slate-400">Final decision deadline</dt>
                <dd>{formatDeadline(complaint.decision_deadline_at)}</dd>
              </div>
            </dl>
            {complaint.return_reason ? (
              <p className="mt-4 text-amber-300">
                Returned: {complaint.return_reason}
              </p>
            ) : null}
            {complaint.decision ? (
              <p className="mt-4 text-cyan-300">
                Decision: {complaint.decision.replaceAll("_", " ")} —{" "}
                {complaint.decision_reason}
              </p>
            ) : null}
            {data.permissions.grievanceManage &&
            ["ACCEPTED", "UNDER_REVIEW", "DECIDED"].includes(
              complaint.status,
            ) ? (
              <section className="mt-5 rounded-xl border border-amber-800 bg-amber-950/20 p-4">
                <h4 className="font-bold text-amber-200">
                  Restricted supervisory comments
                </h4>
                <p className="mt-1 text-sm text-amber-100/80">
                  Access is case-specific. Every retrieval is recorded in the
                  immutable restricted-access audit trail.
                </p>
                <button
                  type="button"
                  disabled={restrictedLoading === complaint.id}
                  onClick={() => loadRestrictedComments(complaint.id)}
                  className="mt-3 min-h-12 rounded-xl border border-amber-700 px-4 font-bold text-amber-100"
                >
                  {restrictedLoading === complaint.id
                    ? "Loading and auditing access…"
                    : restrictedByCase[complaint.id]
                      ? "Retrieve again (new audit event)"
                      : "Retrieve restricted comments"}
                </button>
                {restrictedError[complaint.id] ? (
                  <p className="mt-3 text-sm text-red-300">
                    {restrictedError[complaint.id]}
                  </p>
                ) : null}
                {restrictedByCase[complaint.id] ? (
                  <div className="mt-4 space-y-3">
                    {restrictedByCase[complaint.id].map((comment) => (
                      <article
                        key={comment.comment_id}
                        className="rounded-xl border border-amber-900 bg-slate-950 p-3"
                      >
                        <p className="whitespace-pre-wrap">{comment.body}</p>
                        <p className="mt-2 text-xs text-slate-400">
                          Recorded {formatDeadline(comment.created_at)}
                        </p>
                      </article>
                    ))}
                    {!restrictedByCase[complaint.id].length ? (
                      <p className="text-sm text-slate-400">
                        No restricted supervisory comments exist for this
                        appraisal. This access was still audited.
                      </p>
                    ) : null}
                  </div>
                ) : null}
              </section>
            ) : null}
            {data.permissions.grievanceManage &&
            !["RETURNED", "CLOSED"].includes(complaint.status) ? (
              <div className="mt-5 grid gap-4">
                {complaint.status === "SUBMITTED" ? (
                  <>
                    <p className="text-sm text-slate-400">
                      Accepting opens the five-calendar-day decision period and
                      enables Begin review.
                    </p>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() =>
                        request(
                          `/api/complaints/${complaint.id}/transition`,
                          "POST",
                          { action: "accept" },
                        )
                      }
                      className={button}
                    >
                      Accept complaint
                    </button>
                    <form onSubmit={transitionComplaint} className="grid gap-3">
                      <input
                        type="hidden"
                        name="complaintId"
                        value={complaint.id}
                      />
                      <input type="hidden" name="action" value="return" />
                      <label>
                        Reason for returning
                        <textarea
                          name="reason"
                          required
                          className={`${field} min-h-24`}
                        />
                      </label>
                      <button
                        disabled={busy}
                        className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
                      >
                        Return complaint with reason
                      </button>
                    </form>
                  </>
                ) : null}
                {complaint.status === "ACCEPTED" ? (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      request(
                        `/api/complaints/${complaint.id}/transition`,
                        "POST",
                        { action: "review" },
                      )
                    }
                    className="min-h-12 rounded-xl border border-slate-600 px-4 font-bold"
                  >
                    Begin review
                  </button>
                ) : null}
                {["ACCEPTED", "UNDER_REVIEW"].includes(complaint.status) ? (
                  <form onSubmit={transitionComplaint} className="grid gap-3">
                    <input
                      type="hidden"
                      name="complaintId"
                      value={complaint.id}
                    />
                    <input type="hidden" name="action" value="decide" />
                    <label>
                      Decision
                      <select name="decision" className={field}>
                        <option value="UPHELD">Upheld</option>
                        <option value="PARTIALLY_UPHELD">
                          Partially upheld
                        </option>
                        <option value="REJECTED">Rejected</option>
                        <option value="WITHDRAWN">Withdrawn</option>
                      </select>
                    </label>
                    <label>
                      Decision reason
                      <textarea
                        name="reason"
                        required
                        className={`${field} min-h-24`}
                      />
                    </label>
                    <button disabled={busy} className={button}>
                      Record final decision
                    </button>
                  </form>
                ) : null}
                {complaint.status === "DECIDED" ? (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      request(
                        `/api/complaints/${complaint.id}/transition`,
                        "POST",
                        { action: "close" },
                      )
                    }
                    className={button}
                  >
                    Close case
                  </button>
                ) : null}
              </div>
            ) : null}
          </article>
        ))}
        {!data.complaints.length && !eligibleAppraisals.length ? (
          <p className="rounded-xl border border-slate-800 p-5 text-slate-400">
            No complaints are available to this account.
          </p>
        ) : null}
      </section>
    </>
  );
}

function Activities({
  data,
  busy,
  request,
}: {
  data: Workspace;
  busy: boolean;
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
}) {
  async function create(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    await request("/api/activities", "POST", {
      personnelId: data.profile.personnel_id,
      activityDate: f.get("activityDate"),
      title: f.get("title"),
      description: f.get("description"),
      outcome: f.get("outcome"),
      challenges: f.get("challenges"),
      lessonsLearned: f.get("lessonsLearned"),
    });
  }
  return (
    <>
      <h2 className="text-2xl font-bold">Continuous activities</h2>
      {data.permissions.selfActivity && data.profile?.personnel_id ? (
        <form
          onSubmit={create}
          className="mt-6 rounded-2xl border border-slate-800 bg-slate-900 p-5"
        >
          <div className="grid gap-4 md:grid-cols-2">
            <label>
              Date
              <input
                name="activityDate"
                type="date"
                required
                className={field}
              />
            </label>
            <label>
              Title
              <input name="title" required className={field} />
            </label>
            <label className="md:col-span-2">
              Description
              <textarea
                name="description"
                required
                className={`${field} min-h-28`}
              />
            </label>
            <label>
              Outcome
              <textarea name="outcome" className={`${field} min-h-24`} />
            </label>
            <label>
              Challenges
              <textarea name="challenges" className={`${field} min-h-24`} />
            </label>
            <label className="md:col-span-2">
              Lessons learned
              <textarea name="lessonsLearned" className={`${field} min-h-24`} />
            </label>
          </div>
          <button disabled={busy} className={`mt-4 ${button}`}>
            Save draft
          </button>
        </form>
      ) : null}
      <div className="mt-6 space-y-3">
        {data.activities.map((a) => (
          <article
            key={a.id}
            className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
          >
            <div className="flex flex-wrap justify-between gap-3">
              <div>
                <h3 className="font-bold">{a.title}</h3>
                <p className="text-sm text-slate-400">
                  {a.full_name} · {a.activity_date}
                </p>
              </div>
              <Status value={a.status} />
            </div>
            <p className="mt-3 text-slate-300">{a.description}</p>
            <div className="mt-4 flex gap-2">
              {a.own_record &&
              ["DRAFT", "RETURNED", "EDITABLE"].includes(a.status) ? (
                <button
                  disabled={busy}
                  onClick={() => request(`/api/activities/${a.id}/submit`)}
                  className={button}
                >
                  Submit
                </button>
              ) : null}
              {!a.own_record && a.status === "SUBMITTED" ? (
                <button
                  disabled={busy}
                  onClick={() => request(`/api/activities/${a.id}/confirm`)}
                  className={button}
                >
                  Confirm
                </button>
              ) : null}
            </div>
          </article>
        ))}
      </div>
    </>
  );
}
function PersonnelFields({data,person}:{data:Workspace;person?:any}){
  const today=new Date().toISOString().slice(0,10);
  const appointments=data.appointmentDefinitions.filter((appointment)=>appointment.active);
  const [appointmentId,setAppointmentId]=useState(person?.appointment_id??"");
  const selected=appointments.find((appointment)=>appointment.id===appointmentId);
  return <><label>Unique ID<input name="personnelCode" required maxLength={32} defaultValue={person?.personnel_code??""} className={field} placeholder="Dummy or pilot ID"/></label><label>Name<input name="fullName" required maxLength={120} defaultValue={person?.full_name??""} className={field}/></label><label>Grade or designation<input name="rankName" required maxLength={120} defaultValue={person?.rank_name??""} className={field}/></label><label>Personnel category<input name="personnelCategory" required maxLength={80} defaultValue={person?.personnel_category??""} className={field} placeholder="For example: Professional staff"/></label><label>Rank precedence<input name="rankPrecedence" type="number" min={1} max={1000} required defaultValue={person?.rank_precedence??""} className={field} placeholder="1 is the highest rank"/></label><label>Date of rank or grade<input name="dateOfRank" type="date" required defaultValue={person?.date_of_rank?.slice?.(0,10)??""} className={field}/></label><label>Manual precedence (only for a final tie)<input name="manualPrecedence" type="number" min={1} max={1000} defaultValue={person?.manual_precedence??""} className={field} placeholder="1 is most senior"/></label><label className="md:col-span-2">Appointment<select name="appointmentId" required value={appointmentId} onChange={(event)=>setAppointmentId(event.target.value)} className={field}><option value="" disabled>Select appointment</option>{appointments.map((appointment)=><option key={appointment.id} value={appointment.id}>{appointment.title} · {appointment.organizational_node_name}</option>)}</select></label><label className="md:col-span-2">Basic role and responsibilities<textarea readOnly value={selected?.role_description??person?.appointment_role_description??"Select an appointment to view its standard responsibilities."} className={`${field} min-h-24 py-3 text-slate-300`}/></label><label>Date joined organization or profession<input name="dateJoinedService" type="date" required defaultValue={person?.date_joined_service?.slice?.(0,10)??today} className={field}/></label><label>Started in this organization<input name="unitServiceStartedOn" type="date" required defaultValue={person?.unit_service_started_on?.slice?.(0,10)??today} className={field}/></label><label className="md:col-span-2">Additional responsibilities (optional)<textarea name="additionalResponsibilities" maxLength={1000} defaultValue={person?.role_description??""} className={`${field} min-h-24 py-3`} placeholder="Add only responsibilities beyond the appointment’s standard description."/></label></>;
}
function PersonnelAccountControls({person,busy,request}:{person:any;busy:boolean;request:(p:string,m?:string,b?:unknown)=>Promise<any>}){
  async function submit(event:React.FormEvent<HTMLFormElement>){
    event.preventDefault();
    const form=event.currentTarget,values=new FormData(form);
    const result=await request(`/api/personnel/${person.id}/account`,person.account_id?"PATCH":"POST",{loginId:values.get("loginId"),temporaryPassword:values.get("temporaryPassword")});
    if(result.ok)form.reset();
  }
  return <form onSubmit={submit} className="mt-4 grid gap-3 rounded-xl border border-slate-700 bg-slate-950/50 p-4 md:grid-cols-2">
    <div className="md:col-span-2"><h4 className="font-bold">User login</h4>{person.account_id?<p className="mt-1 text-sm text-slate-400">{person.account_login} · {person.account_active?"Active":"Inactive"}{person.must_change_password?" · Temporary password must be changed":""}</p>:<p className="mt-1 text-sm text-slate-400">No login has been created for this person.</p>}</div>
    {!person.account_id?<label>Pilot login ID<input name="loginId" type="text" inputMode="email" required className={field} placeholder="name@pilot.test"/></label>:null}
    <label className={!person.account_id?"":"md:col-span-2"}>Temporary password (minimum 12 characters)<input name="temporaryPassword" type="password" autoComplete="new-password" minLength={12} required className={field}/></label>
    <button disabled={busy||person.status!=="ACTIVE"} className={`${button} md:col-span-2`}>{person.account_id?"Reset temporary password":"Create login and temporary password"}</button>
    <p className="text-xs text-slate-400 md:col-span-2">Give the temporary password securely to the user. They must replace it with a private password at first sign-in.</p>
  </form>;
}
function Personnel({data,busy,request}:{data:Workspace;busy:boolean;request:(p:string,m?:string,b?:unknown)=>Promise<any>}){
  const[editingId,setEditingId]=useState<string|null>(null);
  async function submit(event:React.FormEvent<HTMLFormElement>,id?:string){event.preventDefault();const form=event.currentTarget,values=new FormData(form);const body={personnelCode:values.get("personnelCode"),fullName:values.get("fullName"),rankName:values.get("rankName"),personnelCategory:values.get("personnelCategory"),rankPrecedence:values.get("rankPrecedence"),dateOfRank:values.get("dateOfRank"),manualPrecedence:values.get("manualPrecedence"),dateJoinedService:values.get("dateJoinedService"),unitServiceStartedOn:values.get("unitServiceStartedOn"),appointmentId:values.get("appointmentId"),additionalResponsibilities:values.get("additionalResponsibilities")};const result=await request(id?`/api/personnel/${id}`:"/api/personnel",id?"PATCH":"POST",body);if(result.ok){form.reset();setEditingId(null)}}
  return <section><h2 className="text-2xl font-bold">Personnel administration</h2><p className="mt-2 max-w-3xl text-slate-400">Add and maintain personnel using dummy unique IDs. Removal marks a person as no longer active while preserving their historical records.</p>{data.permissions.manage?<form onSubmit={(event)=>submit(event)} className="mt-6 grid gap-4 rounded-2xl border border-slate-700 bg-slate-900 p-5 md:grid-cols-2"><h3 className="flex items-center gap-2 text-lg font-bold md:col-span-2"><UserPlus className="text-cyan-400"/>Add personnel</h3><PersonnelFields data={data}/><button disabled={busy} className={`${button} md:col-span-2`}>Add personnel</button></form>:null}<div className="mt-6 space-y-3">{data.personnel.map(person=><article key={person.id} className="rounded-2xl border border-slate-700 bg-slate-900 p-5"><div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wider text-cyan-400">{person.personnel_code} · {person.status}</p><h3 className="text-lg font-bold">{person.rank_name} {person.full_name}</h3><p className="text-slate-400">{person.appointment_title??"No appointment"} · {data.organizationalNodes.find((node)=>node.id===person.organizational_node_id)?.path??person.organizational_node_name??"No section"}</p>{person.appointment_role_description?<p className="mt-2 text-sm">{person.appointment_role_description}</p>:null}{person.role_description?<p className="mt-2 text-sm text-slate-400">Additional: {person.role_description}</p>:null}</div>{data.permissions.manage?<div className="flex flex-wrap gap-2"><button type="button" aria-label={`Edit ${person.full_name}`} onClick={()=>setEditingId(person.id)} className="grid min-h-12 min-w-12 place-items-center rounded-xl border border-cyan-700 text-cyan-200"><Pencil className="h-5 w-5"/></button>{person.status==="ACTIVE"?<button type="button" disabled={busy} onClick={()=>request(`/api/personnel/${person.id}`,"PATCH",{action:"DEACTIVATE"})} className="min-h-12 rounded-xl border border-amber-700 px-3 text-amber-200">Deactivate</button>:person.status==="SUSPENDED"?<button type="button" disabled={busy} onClick={()=>request(`/api/personnel/${person.id}`,"PATCH",{action:"ACTIVATE"})} className="min-h-12 rounded-xl border border-emerald-700 px-3 text-emerald-200">Reactivate</button>:null}{person.status!=="POSTED_OUT"?<button type="button" disabled={busy} onClick={()=>request(`/api/personnel/${person.id}`,"PATCH",{action:"REMOVE"})} className="flex min-h-12 items-center gap-2 rounded-xl border border-rose-700 px-3 text-rose-200"><UserX className="h-4 w-4"/>Remove</button>:null}</div>:null}</div>{data.permissions.accountProvision?<PersonnelAccountControls person={person} busy={busy} request={request}/>:null}{editingId===person.id?<form onSubmit={(event)=>submit(event,person.id)} className="mt-4 grid gap-3 border-t border-slate-700 pt-4 md:grid-cols-2"><PersonnelFields data={data} person={person}/><div className="flex gap-2 md:col-span-2"><button disabled={busy} className={button}>Save changes</button><button type="button" onClick={()=>setEditingId(null)} className="min-h-12 rounded-xl border border-slate-600 px-4">Cancel</button></div></form>:null}</article>)}</div></section>
}
function AdministratorAuthorizationApprovals({data,busy,request}:{data:Workspace;busy:boolean;request:(p:string,m?:string,b?:unknown)=>Promise<any>}){
 if(!data.permissions.authorizerTransfer)return null;
 return <section className="mb-10 rounded-2xl border border-cyan-800 bg-cyan-950/20 p-5"><h2 className="text-2xl font-bold">System Administrator access approvals</h2><p className="mt-2 text-slate-300">Approval is valid for seven calendar days and becomes invalid immediately if an eligible operator appointment holder changes.</p><div className="mt-5 space-y-3">{data.administratorAuthorizations.length?data.administratorAuthorizations.map(authorization=><article key={authorization.id} className="rounded-xl border border-slate-700 bg-slate-900 p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-bold">{authorization.administrator_login}</h3><p className="mt-1 text-sm text-slate-400">Operators: {authorization.operator_names?.join(", ")||"None"}</p></div><Status value={authorization.status}/></div>{authorization.status==="PENDING"?<form className="mt-4" onSubmit={async event=>{event.preventDefault();const values=new FormData(event.currentTarget),submitter=(event.nativeEvent as SubmitEvent).submitter as HTMLButtonElement;await request(`/api/administrator-authorization/${authorization.id}/decision`,"POST",{decision:submitter.value,reason:values.get("reason")})}}><label>Decision reason<textarea name="reason" required maxLength={1000} className={`${field} min-h-24 py-3`}/></label><div className="mt-3 grid grid-cols-2 gap-3"><button value="APPROVE" disabled={busy} className={button}>Approve for 7 days</button><button value="REJECT" disabled={busy} className="min-h-12 rounded-xl border border-rose-700 px-4 text-rose-200">Reject</button></div></form>:authorization.valid_until?<p className="mt-3 text-sm text-cyan-300">Valid until {formatDeadline(authorization.valid_until)}</p>:authorization.decision_reason?<p className="mt-3 text-sm">{authorization.decision_reason}</p>:null}</article>):<p className="rounded-xl border border-dashed border-slate-700 p-5 text-slate-400">No Administrator approval requests have been submitted.</p>}</div></section>
}
function Organization({
  data,
  busy,
  request,
}: {
  data: Workspace;
  busy: boolean;
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
}) {
  const [selectedParentId,setSelectedParentId]=useState("");
  const [editingNodeId,setEditingNodeId]=useState<string|null>(null);
  const [editingAppointmentId,setEditingAppointmentId]=useState<string|null>(null);
  const [editingAppointmentTypeId,setEditingAppointmentTypeId]=useState<string|null>(null);
  const [editParentId,setEditParentId]=useState("");
  const selectedParent=data.organizationalNodes.find((node)=>node.id===selectedParentId);
  const requiredLevel=(selectedParent?.level_number??0)+1;
  const availableLevels=data.organizationLevelDefinitions.filter((level)=>level.level_number===requiredLevel);
  return (
    <section>
      <h2 className="text-2xl font-bold">Organizational structure</h2>
      <p className="mt-2 max-w-3xl text-slate-400">
        Build the organization from the top down using its configured level types.
        Every structural element has a unique code and a defined parent relationship.
      </p>
      {data.permissions.organizationManage ? (
        <form
          className="mt-6 grid gap-4 rounded-2xl border border-slate-700 bg-slate-900 p-5 md:grid-cols-2"
          onSubmit={async (event) => {
            event.preventDefault();
            const form = event.currentTarget;
            const values = new FormData(form);
            let levelDefinitionId=values.get("levelDefinitionId");
            if(!levelDefinitionId&&requiredLevel<=10){
              const levelResult=await request("/api/organization/levels","POST",{levelNumber:requiredLevel,name:values.get("newLevelName"),code:values.get("newLevelCode")});
              if(!levelResult.ok)return;
              levelDefinitionId=levelResult.body.level.id;
            }
            const result = await request("/api/organization/nodes", "POST", {
              parentId: values.get("parentId") || null,
              levelDefinitionId,
              code: values.get("code"),
              name: values.get("name"),
              description: values.get("description"),
            });
            if (result.ok) {form.reset();setSelectedParentId("");}
          }}
        >
          <h3 className="md:col-span-2 text-lg font-bold">Add structure node</h3>
          <label>
            Parent
            <select name="parentId" className={field} value={selectedParentId} onChange={(event)=>setSelectedParentId(event.target.value)}>
              <option value="">Top level organization</option>
              {data.organizationalNodes.filter((node) => node.active).map((node) => (
                <option key={node.id} value={node.id}>
                  {"— ".repeat(node.depth)}{node.name}
                </option>
              ))}
            </select>
          </label>
          {availableLevels.length?<label>Structure type<select key={selectedParentId} name="levelDefinitionId" className={field} required defaultValue={availableLevels[0]?.id??""}>{availableLevels.map((level)=><option key={level.id} value={level.id}>Level {level.level_number} · {level.name}</option>)}</select></label>:requiredLevel<=10?<div className="rounded-xl border border-cyan-800 bg-cyan-950/30 p-4 md:col-span-2"><p className="font-bold text-cyan-200">Define lower Level {requiredLevel}</p><p className="mt-1 text-sm text-slate-400">This level will be saved and can then be used beneath any Level {requiredLevel-1} section.</p><div className="mt-3 grid gap-3 md:grid-cols-2"><label>Level name<input name="newLevelName" required maxLength={80} className={field} placeholder="For example: Team"/></label><label>Level code<input name="newLevelCode" required maxLength={32} className={field} placeholder={`For example: LEVEL-${requiredLevel}`}/></label></div></div>:<p className="rounded-xl border border-amber-700 p-4 text-amber-200 md:col-span-2">The maximum of 10 organizational levels has been reached.</p>}
          <label>
            Unique code
            <input name="code" required maxLength={32} className={field} placeholder="For example: FIN-01" />
          </label>
          <label>
            Name
            <input name="name" required maxLength={120} className={field} placeholder="For example: Finance Operations" />
          </label>
          <label className="md:col-span-2">
            Description
            <textarea name="description" maxLength={500} className={`${field} min-h-24 py-3`} />
          </label>
          <button disabled={busy||requiredLevel>10} className={`${button} md:col-span-2`}>
            Add to organization
          </button>
        </form>
      ) : null}
      <div className="mt-6 space-y-3">
        {data.organizationalNodes.length ? data.organizationalNodes.map((node) => (
          <article
            key={node.id}
            className={`rounded-2xl border p-4 ${node.active ? "border-slate-700 bg-slate-900" : "border-slate-800 bg-slate-950 opacity-60"}`}
            style={{ marginLeft: `${Math.min(node.depth, 6) * 12}px` }}
          >
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-xs font-bold uppercase tracking-wider text-cyan-400">{node.level_name??"Organization"} · {node.code}</p>
                <h3 className="text-lg font-bold">{node.name}</h3>
                <p className="text-sm text-slate-400">{node.path}</p>
                {node.description ? <p className="mt-2 text-sm">{node.description}</p> : null}
              </div>
              <div className="flex items-center gap-2">
                <Status value={node.active ? "ACTIVE" : "INACTIVE"} />
                {data.permissions.organizationManage && node.active && node.node_type!=="ORGANIZATION" ? <button type="button" aria-label={`Edit ${node.name}`} title={`Edit ${node.name}`} onClick={()=>{setEditingNodeId(node.id);setEditParentId(node.parent_id??"")}} className="grid min-h-12 min-w-12 place-items-center rounded-xl border border-cyan-700 text-cyan-200"><Pencil className="h-5 w-5"/></button>:null}
                {data.permissions.organizationManage && node.active ? (
                  <button
                    disabled={busy}
                    onClick={() => request(`/api/organization/nodes/${node.id}`, "PATCH", { active: false })}
                    className="min-h-12 rounded-xl border border-amber-700 px-3 text-sm text-amber-200"
                  >
                    Deactivate
                  </button>
                ) : null}
              </div>
            </div>
            {editingNodeId===node.id ? <form className="mt-4 grid gap-3 border-t border-slate-700 pt-4 md:grid-cols-2" onSubmit={async(event)=>{event.preventDefault();const form=event.currentTarget;const values=new FormData(form);const result=await request(`/api/organization/nodes/${node.id}`,"PATCH",{parentId:values.get("parentId")||null,levelDefinitionId:values.get("levelDefinitionId"),code:values.get("code"),name:values.get("name"),description:values.get("description")});if(result.ok)setEditingNodeId(null)}}><label>Parent<select name="parentId" className={field} value={editParentId} onChange={(event)=>setEditParentId(event.target.value)}><option value="">Top level organization</option>{data.organizationalNodes.filter((candidate)=>candidate.active&&candidate.id!==node.id).map((candidate)=><option key={candidate.id} value={candidate.id}>{"— ".repeat(candidate.depth)}{candidate.name}</option>)}</select></label><label>Structure type<select key={editParentId} name="levelDefinitionId" className={field} required defaultValue={data.organizationLevelDefinitions.find((level)=>level.level_number===((data.organizationalNodes.find((candidate)=>candidate.id===editParentId)?.level_number??0)+1))?.id??""}>{data.organizationLevelDefinitions.filter((level)=>level.level_number===((data.organizationalNodes.find((candidate)=>candidate.id===editParentId)?.level_number??0)+1)).map((level)=><option key={level.id} value={level.id}>Level {level.level_number} · {level.name}</option>)}</select></label><label>Unique code<input name="code" required maxLength={32} defaultValue={node.code} className={field}/></label><label>Name<input name="name" required maxLength={120} defaultValue={node.name} className={field}/></label><label className="md:col-span-2">Description<textarea name="description" maxLength={500} defaultValue={node.description??""} className={`${field} min-h-24 py-3`}/></label><div className="flex gap-2 md:col-span-2"><button disabled={busy} className={button}>Save changes</button><button type="button" onClick={()=>setEditingNodeId(null)} className="min-h-12 rounded-xl border border-slate-600 px-4">Cancel</button></div></form>:null}
          </article>
        )) : <p className="rounded-2xl border border-dashed border-slate-700 p-6 text-slate-400">No organizational structure has been entered.</p>}
      </div>
      <div className="mt-10 border-t border-slate-800 pt-8">
        <h2 className="text-2xl font-bold">Appointment types and positions</h2>
        <p className="mt-2 max-w-3xl text-slate-400">Create a reusable appointment type once, then place that appointment in any appropriate section or subsection.</p>
        {data.permissions.organizationManage ? <form className="mt-6 grid gap-4 rounded-2xl border border-slate-700 bg-slate-900 p-5 md:grid-cols-2" onSubmit={async(event)=>{event.preventDefault();const form=event.currentTarget,values=new FormData(form);const result=await request("/api/organization/appointment-types","POST",{name:values.get("name"),roleDescription:values.get("roleDescription"),leadershipPriority:values.get("leadershipPriority"),systemAdministratorOperator:values.get("systemAdministratorOperator")==="on"});if(result.ok)form.reset()}}>
          <h3 className="text-lg font-bold md:col-span-2">Add reusable appointment type</h3>
          <label>Appointment type name<input name="name" required maxLength={120} className={field} placeholder="For example: Finance Manager"/></label>
          <label className="md:col-span-2">Standard role and responsibilities<textarea name="roleDescription" required maxLength={1000} className={`${field} min-h-28 py-3`} placeholder="Describe the responsibilities shared by every position of this type."/></label>
          <label className="md:col-span-2">Leadership succession priority (optional)<input name="leadershipPriority" type="number" min={1} max={100} className={field} placeholder="1 is the highest leadership appointment"/><span className="mt-1 block text-xs text-slate-400">Leave blank if this appointment is not eligible to lead the organization.</span></label>
          <label className="flex min-h-12 items-center gap-3 md:col-span-2"><input name="systemAdministratorOperator" type="checkbox" className="h-6 w-6"/><span>Holder may operate the dedicated System Administrator account after Authorizer approval</span></label>
          <button disabled={busy} className={`${button} md:col-span-2`}>Add appointment type</button>
        </form>:null}
        <div className="mt-6 grid gap-3 md:grid-cols-2">{data.appointmentTypes.map((type)=><article key={type.id} className="rounded-2xl border border-slate-700 bg-slate-900 p-5"><div className="flex items-start justify-between gap-3"><h3 className="font-bold">{type.name}</h3><div className="flex gap-2"><Status value={type.active?"ACTIVE":"INACTIVE"}/>{data.permissions.organizationManage&&type.active?<button type="button" aria-label={`Edit ${type.name}`} onClick={()=>setEditingAppointmentTypeId(type.id)} className="grid min-h-12 min-w-12 place-items-center rounded-xl border border-cyan-700 text-cyan-200"><Pencil className="h-5 w-5"/></button>:null}</div></div><p className="mt-3 text-sm text-slate-300">{type.role_description}</p><p className="mt-2 text-xs text-cyan-300">{type.leadership_priority?`Leadership priority ${type.leadership_priority}`:"Not in leadership succession"}</p>{type.system_administrator_operator?<p className="mt-2 text-xs font-bold text-amber-300">Eligible System Administrator operator appointment</p>:null}{editingAppointmentTypeId===type.id?<form className="mt-4 grid gap-3 border-t border-slate-700 pt-4" onSubmit={async(event)=>{event.preventDefault();const form=event.currentTarget,values=new FormData(form);const result=await request(`/api/organization/appointment-types/${type.id}`,"PATCH",{name:values.get("name"),roleDescription:values.get("roleDescription"),leadershipPriority:values.get("leadershipPriority"),systemAdministratorOperator:values.get("systemAdministratorOperator")==="on"});if(result.ok)setEditingAppointmentTypeId(null)}}><label>Appointment type name<input name="name" required maxLength={120} defaultValue={type.name} className={field}/></label><label>Standard role and responsibilities<textarea name="roleDescription" required maxLength={1000} defaultValue={type.role_description} className={`${field} min-h-28 py-3`}/></label><label>Leadership succession priority (optional)<input name="leadershipPriority" type="number" min={1} max={100} defaultValue={type.leadership_priority??""} className={field}/></label><label className="flex min-h-12 items-center gap-3"><input name="systemAdministratorOperator" type="checkbox" defaultChecked={type.system_administrator_operator} className="h-6 w-6"/><span>Eligible System Administrator operator</span></label><div className="flex gap-2"><button disabled={busy} className={button}>Save type</button><button type="button" onClick={()=>setEditingAppointmentTypeId(null)} className="min-h-12 rounded-xl border border-slate-600 px-4">Cancel</button></div></form>:null}</article>)}</div>
        {data.permissions.organizationManage ? <form className="mt-8 grid gap-4 rounded-2xl border border-slate-700 bg-slate-900 p-5 md:grid-cols-2" onSubmit={async(event)=>{event.preventDefault();const form=event.currentTarget,values=new FormData(form);const result=await request("/api/organization/appointments","POST",{organizationalNodeId:values.get("organizationalNodeId"),appointmentTypeId:values.get("appointmentTypeId")});if(result.ok)form.reset()}}>
          <h3 className="text-lg font-bold md:col-span-2">Add node-specific appointment position</h3>
          <label>Section or subsection<select name="organizationalNodeId" required defaultValue="" className={field}><option value="" disabled>Select structure</option>{data.organizationalNodes.filter((node)=>node.active&&node.parent_id!==null).map((node)=><option key={node.id} value={node.id}>{node.name}</option>)}</select></label>
          <label>Appointment type<select name="appointmentTypeId" required defaultValue="" className={field}><option value="" disabled>Select appointment type</option>{data.appointmentTypes.filter((type)=>type.active).map((type)=><option key={type.id} value={type.id}>{type.name}</option>)}</select></label>
          <button disabled={busy} className={`${button} md:col-span-2`}>Add appointment position</button>
        </form>:null}
        <div className="mt-6 grid gap-3 md:grid-cols-2">{data.appointmentDefinitions.map((appointment)=><article key={appointment.id} className="rounded-2xl border border-slate-700 bg-slate-900 p-5"><div className="flex items-start justify-between gap-3"><div><h3 className="font-bold">{appointment.title}</h3><p className="text-sm text-cyan-300">{appointment.organizational_node_name}</p></div><div className="flex gap-2"><Status value={appointment.active?"ACTIVE":"INACTIVE"}/>{data.permissions.organizationManage&&appointment.active?<button type="button" aria-label={`Edit ${appointment.title}`} onClick={()=>setEditingAppointmentId(appointment.id)} className="grid min-h-12 min-w-12 place-items-center rounded-xl border border-cyan-700 text-cyan-200"><Pencil className="h-5 w-5"/></button>:null}</div></div><p className="mt-3 text-sm text-slate-300">{appointment.role_description||"No standard description has been entered."}</p>{editingAppointmentId===appointment.id?<form className="mt-4 grid gap-3 border-t border-slate-700 pt-4" onSubmit={async(event)=>{event.preventDefault();const form=event.currentTarget,values=new FormData(form);const result=await request(`/api/organization/appointments/${appointment.id}`,"PATCH",{organizationalNodeId:values.get("organizationalNodeId"),appointmentTypeId:values.get("appointmentTypeId")});if(result.ok)setEditingAppointmentId(null)}}><label>Section or subsection<select name="organizationalNodeId" required defaultValue={appointment.organizational_node_id} className={field}>{data.organizationalNodes.filter((node)=>node.active&&node.parent_id!==null).map((node)=><option key={node.id} value={node.id}>{node.name}</option>)}</select></label><label>Appointment type<select name="appointmentTypeId" required defaultValue={appointment.appointment_type_id} className={field}>{data.appointmentTypes.filter((type)=>type.active).map((type)=><option key={type.id} value={type.id}>{type.name}</option>)}</select></label><div className="flex gap-2"><button disabled={busy} className={button}>Save appointment</button><button type="button" onClick={()=>setEditingAppointmentId(null)} className="min-h-12 rounded-xl border border-slate-600 px-4">Cancel</button></div></form>:null}</article>)}</div>
        <section className="mt-10 border-t border-slate-800 pt-8"><h2 className="text-2xl font-bold">Calculated leadership succession</h2><p className="mt-2 text-slate-400">Order: leadership appointment priority, rank precedence, date of rank, organization start date, then manual precedence.</p><div className="mt-5 space-y-3">{data.leadershipSuccession.length?data.leadershipSuccession.map((candidate)=><article key={candidate.personnel_id} className="flex items-start gap-4 rounded-2xl border border-slate-700 bg-slate-900 p-4"><span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-cyan-500 font-bold text-slate-950">{candidate.succession_order}</span><div><h3 className="font-bold">{candidate.rank_name} {candidate.full_name}</h3><p className="text-sm text-cyan-300">{candidate.appointment_type} · {candidate.organizational_node_name}</p><p className="mt-1 text-xs text-slate-400">Leadership {candidate.leadership_priority} · Rank {candidate.rank_precedence??"not set"} · Rank date {candidate.date_of_rank??"not set"} · Organization start {candidate.unit_service_started_on}{candidate.manual_precedence?` · Manual ${candidate.manual_precedence}`:""}</p></div></article>):<p className="rounded-xl border border-dashed border-slate-700 p-5 text-slate-400">No succession candidates are complete yet. Set a leadership priority on appointment types and fill the seniority fields for their personnel.</p>}</div><div className="mt-8 border-t border-slate-700 pt-6"><h3 className="text-xl font-bold">System Authorizer transfer</h3>{data.permissions.authorizerTransfer?(()=>{const successor=data.leadershipSuccession.find((candidate)=>candidate.personnel_id!==data.profile?.personnel_id);return successor?<div className="mt-4 rounded-2xl border border-cyan-800 bg-cyan-950/20 p-5"><p className="font-bold">Next eligible successor: {successor.rank_name} {successor.full_name}</p><p className="text-sm text-slate-400">{successor.appointment_type} · {successor.organizational_node_name}</p>{!successor.account_id?<p className="mt-3 text-amber-300">Create a login account for this person before transfer.</p>:!successor.mfa_enabled?<p className="mt-3 text-amber-300">This person must enroll MFA before authority can be transferred.</p>:<form className="mt-4" onSubmit={async(event)=>{event.preventDefault();const form=event.currentTarget,values=new FormData(form);await request("/api/organization/authorizer-transfer","POST",{incomingAccountId:successor.account_id,reason:values.get("reason")})}}><label>Mandatory transfer and handover reason<textarea name="reason" required maxLength={1000} className={`${field} min-h-24 py-3`}/></label><button disabled={busy} className={`${button} mt-3 w-full`}>Transfer System Authorizer authority</button></form>}</div>:<p className="mt-4 rounded-xl border border-dashed border-slate-700 p-5 text-slate-400">No eligible successor with a linked login account is available.</p>})():data.permissions.handoverRead?<p className="mt-3 text-amber-200">Handover access is read-only. Organization and authorization changes are disabled.</p>:null}<div className="mt-5 space-y-3">{data.authorizerTransfers.map((transfer)=><article key={transfer.id} className="rounded-xl border border-slate-700 p-4"><p className="font-bold">{transfer.outgoing_name??transfer.outgoing_login} → {transfer.incoming_name??transfer.incoming_login}</p><p className="mt-1 text-sm text-slate-400">Transferred {formatDeadline(transfer.transferred_at)} · Outgoing handover expires {formatDeadline(transfer.handover_expires_at)}</p><p className="mt-2 text-sm">{transfer.reason}</p></article>)}</div></div></section>
      </div>
    </section>
  );
}

function Records({
  data,
  busy,
  request,
}: {
  data: Workspace;
  busy: boolean;
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
}) {
  if (!data.permissions.recordsManage)
    return (
      <div className="rounded-2xl border border-slate-800 p-8 text-center text-slate-400">
        <Users className="mx-auto mb-3" />
        Personnel-management permission is required.
      </div>
    );
  async function awol(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    await request("/api/awol", "POST", {
      personnelId: f.get("personnelId"),
      startedAt: f.get("startedAt"),
      endedAt: f.get("endedAt") || undefined,
      reference: f.get("reference"),
    });
  }
  async function discipline(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    await request("/api/discipline", "POST", {
      personnelId: f.get("personnelId"),
      referenceCode: f.get("referenceCode"),
      occurredOn: f.get("occurredOn") || undefined,
      summary: f.get("summary"),
    });
  }
  return (
    <>
      <h2 className="text-2xl font-bold">Unauthorized absence and conduct matters</h2>
      <div className="mt-6 grid gap-5 lg:grid-cols-2">
        <form
          onSubmit={awol}
          className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
        >
          <h3 className="font-bold">
            <AlertTriangle className="mr-2 inline text-amber-400" />
            Record unauthorized absence
          </h3>
          <PersonSelect data={data} />
          <label className="mt-4 block">
            Started at
            <input
              name="startedAt"
              type="datetime-local"
              required
              className={field}
            />
          </label>
          <label className="mt-4 block">
            Ended at
            <input name="endedAt" type="datetime-local" className={field} />
          </label>
          <label className="mt-4 block">
            Reference
            <input name="reference" className={field} />
          </label>
          <button disabled={busy} className={`mt-4 ${button}`}>
            Create absence record
          </button>
        </form>
        <form
          onSubmit={discipline}
          className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
        >
          <h3 className="font-bold">
            <ShieldAlert className="mr-2 inline text-rose-400" />
            Record conduct matter
          </h3>
          <PersonSelect data={data} />
          <label className="mt-4 block">
            Reference code
            <input name="referenceCode" required className={field} />
          </label>
          <label className="mt-4 block">
            Occurred on
            <input name="occurredOn" type="date" className={field} />
          </label>
          <label className="mt-4 block">
            Summary
            <textarea name="summary" required className={`${field} min-h-24`} />
          </label>
          <button disabled={busy} className={`mt-4 ${button}`}>
            Create matter
          </button>
        </form>
      </div>
      <RecordList
        title="Unauthorized absence records"
        items={data.awol}
        request={request}
        base="awol"
        busy={busy}
      />
      <RecordList
        title="Conduct matters"
        items={data.discipline}
        request={request}
        base="discipline"
        busy={busy}
      />
    </>
  );
}
function PersonSelect({ data }: { data: Workspace }) {
  return (
    <label className="mt-4 block">
      Personnel
      <select name="personnelId" required className={field}>
        {data.personnel.map((p) => (
          <option key={p.id} value={p.id}>
            {p.rank_name} {p.full_name}
          </option>
        ))}
      </select>
    </label>
  );
}
function RecordList({
  title,
  items,
  request,
  base,
  busy,
}: {
  title: string;
  items: any[];
  request: (p: string, m?: string, b?: unknown) => Promise<any>;
  base: "awol" | "discipline";
  busy: boolean;
}) {
  return (
    <section className="mt-6">
      <h3 className="text-lg font-bold">{title}</h3>
      <div className="mt-3 space-y-3">
        {items.map((x) => (
          <article
            key={x.id}
            className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
          >
            <div className="flex flex-wrap justify-between gap-3">
              <div>
                <strong>{x.full_name}</strong>
                <p className="text-sm text-slate-400">
                  {x.reference ?? x.reference_code ?? "No reference"}
                </p>
              </div>
              <Status value={x.status} />
            </div>
            {x.summary ? <p className="mt-3">{x.summary}</p> : null}
            <div className="mt-4 flex flex-wrap gap-2">
              {["UNDER_REVIEW", "CONFIRMED", "RESOLVED", "DISMISSED"].map(
                (s) => (
                  <button
                    key={s}
                    disabled={busy || x.status === s}
                    onClick={() =>
                      request(`/api/${base}/${x.id}`, "PATCH", {
                        status: s,
                        resolution:
                          base === "awol" &&
                          ["RESOLVED", "DISMISSED"].includes(s)
                            ? "Resolved by authorized organization administrator"
                            : undefined,
                      })
                    }
                    className="min-h-12 rounded-xl border border-slate-700 px-3 text-sm disabled:opacity-40"
                  >
                    {s.replaceAll("_", " ")}
                  </button>
                ),
              )}
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
function Status({ value }: { value: string }) {
  const label = value
    .replaceAll("_", " ")
    .replaceAll("AWOL", "UNAUTHORIZED ABSENCE")
    .replaceAll("DISCIPLINARY", "CONDUCT")
    .replaceAll("COMMANDER", "SYSTEM AUTHORIZER")
    .replaceAll("POSTED OUT", "REMOVED FROM ORGANIZATION");
  return (
    <span className="h-fit rounded-full bg-slate-800 px-3 py-1 text-xs font-bold text-cyan-300">
      {label}
    </span>
  );
}
