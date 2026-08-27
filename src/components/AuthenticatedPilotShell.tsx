"use client";

import { useEffect, useState } from "react";
import { ShieldCheck } from "lucide-react";
import { PilotWorkspace } from "./PilotWorkspace";
import { InitialSetupWizard } from "./InitialSetupWizard";

type Principal = { accountId: string; tenantId: string; roles: string[]; mfa: boolean };
type AuthStep = "PASSWORD" | "PASSWORD_CHANGE" | "MFA_SETUP" | "MFA_VERIFY";
type Installation = { configured: boolean; status: string; organizationName?: string | null; organizationCode?: string | null };
type AdministratorAuthorization={required:boolean;state:"NOT_APPLICABLE"|"NOT_CONFIGURED"|"REQUEST_REQUIRED"|"PENDING"|"VALID";requestedAt?:string;validUntil?:string;operators?:Array<{personnelId:string;name:string;appointment:string}>};

async function readJsonResponse(response: Response): Promise<Record<string, unknown>> {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch {
    return {};
  }
}

export function AuthenticatedPilotShell() {
  const [principal, setPrincipal] = useState<Principal | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState("");
  const [authStep, setAuthStep] = useState<AuthStep>("PASSWORD");
  const [identity, setIdentity] = useState({ tenantCode: "", email: "" });
  const [mfa, setMfa] = useState({ secret: "", uri: "" });
  const [installation, setInstallation] = useState<Installation | null>(null);
  const [administratorAuthorization,setAdministratorAuthorization]=useState<AdministratorAuthorization|null>(null);

  useEffect(() => {
    Promise.all([
      fetch("/api/auth/me", { cache: "no-store" }).then((response) => response.ok ? response.json() : null),
      fetch("/api/installation", { cache: "no-store" }).then((response) => response.ok ? response.json() : null),
    ])
      .then(([session, identity]) => { setPrincipal(session?.principal ?? null); setAdministratorAuthorization(session?.administratorAuthorization??null); setInstallation(identity?.installation ?? null); })
      .finally(() => setLoading(false));
  }, []);

  async function login(data: FormData) {
    setSubmitting(true);
    setMessage("");
    const nextIdentity = { tenantCode: "", email: String(data.get("email") ?? "") };
    setIdentity(nextIdentity);
    const response = await fetch("/api/auth/login", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...nextIdentity, password: data.get("password") }),
    });
    const body = await readJsonResponse(response);
    if (body.next === "AUTHENTICATED") location.reload();
    else if (body.next === "PASSWORD_CHANGE_REQUIRED") setAuthStep("PASSWORD_CHANGE");
    else if (body.next === "MFA_VERIFY") setAuthStep("MFA_VERIFY");
    else if (body.next === "MFA_SETUP_REQUIRED") {
      const setupResponse = await fetch("/api/auth/mfa/setup", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(nextIdentity),
      });
      const setup = await readJsonResponse(setupResponse);
      if (setupResponse.ok && typeof setup.secret === "string" && typeof setup.otpauthUri === "string") {
        setMfa({ secret: setup.secret, uri: setup.otpauthUri });
        setAuthStep("MFA_SETUP");
      } else setMessage(typeof setup.error === "string" ? setup.error : "MFA enrolment could not be started");
    } else setMessage(typeof body.error === "string" ? body.error : "Sign-in service is temporarily unavailable");
    setSubmitting(false);
  }

  async function changeRequiredPassword(data: FormData) {
    setSubmitting(true);
    setMessage("");
    const response = await fetch("/api/auth/password/change-required", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password: data.get("password"), confirmPassword: data.get("confirmPassword") }),
    });
    const body = await readJsonResponse(response);
    if (body.next === "AUTHENTICATED") location.reload();
    else if (body.next === "MFA_VERIFY") setAuthStep("MFA_VERIFY");
    else if (body.next === "MFA_SETUP_REQUIRED") {
      const setupResponse = await fetch("/api/auth/mfa/setup", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(identity) });
      const setup = await readJsonResponse(setupResponse);
      if (setupResponse.ok && typeof setup.secret === "string" && typeof setup.otpauthUri === "string") {
        setMfa({ secret: setup.secret, uri: setup.otpauthUri });
        setAuthStep("MFA_SETUP");
      } else setMessage(typeof setup.error === "string" ? setup.error : "MFA enrolment could not be started");
    } else setMessage(typeof body.error === "string" ? body.error : "Password could not be changed");
    setSubmitting(false);
  }

  async function verifyMfa(data: FormData) {
    setSubmitting(true);
    setMessage("");
    const response = await fetch("/api/auth/mfa/verify", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code: data.get("code") }),
    });
    const body = await readJsonResponse(response);
    if (body.next === "AUTHENTICATED") location.reload();
    else setMessage(typeof body.error === "string" ? body.error : "MFA verification service is temporarily unavailable");
    setSubmitting(false);
  }

  if (loading) return <main className="grid min-h-screen place-items-center"><p>Checking secure session...</p></main>;
  if (installation && !installation.configured) return <InitialSetupWizard onComplete={() => location.reload()}/>;
  if (!principal) return (
    <main className="grid min-h-screen place-items-center p-4">
      <form action={authStep === "PASSWORD" ? login : authStep === "PASSWORD_CHANGE" ? changeRequiredPassword : verifyMfa} className="w-full max-w-md rounded-2xl border border-slate-700 bg-slate-900 p-6">
        <ShieldCheck className="h-12 w-12 text-cyan-400" />
        <p className="mt-4 text-sm font-bold uppercase tracking-widest text-cyan-400">Performance Tracker</p>
        <h1 className="mt-1 text-2xl font-bold">{installation?.organizationName ?? "Organization setup"}</h1>
        {installation?.status === "PENDING_ACTIVATION" && authStep === "PASSWORD" ? <div className="mt-4 rounded-xl border border-amber-600/60 bg-amber-950/30 p-4 text-sm text-amber-100"><p className="font-semibold">Organization activation is pending.</p><p className="mt-1">Sign in with the System Authorizer login created during setup. The dedicated Administrator account becomes available only after the Authorizer completes MFA and activates the organization.</p></div> : null}
        {authStep === "PASSWORD" ? <>
          <label className="mt-5 block">Pilot login ID<input name="email" type="text" inputMode="email" autoComplete="username" required className="mt-2 min-h-12 w-full rounded-xl border border-slate-600 bg-slate-950 px-3" /></label>
          <label className="mt-4 block">Password<input name="password" type="password" required className="mt-2 min-h-12 w-full rounded-xl border border-slate-600 bg-slate-950 px-3" /></label>
          <button disabled={submitting} className="mt-6 min-h-12 w-full rounded-xl bg-cyan-500 px-4 font-bold text-slate-950 disabled:opacity-60">{submitting ? "Verifying..." : "Sign in"}</button>
        </> : authStep === "PASSWORD_CHANGE" ? <>
          <p className="mt-3 text-sm text-slate-400">{installation?.organizationName} · {identity.email}</p>
          <div className="mt-5 rounded-xl border border-amber-600/60 bg-amber-950/30 p-4 text-sm text-amber-100">This is a temporary password. Create your private password before continuing.</div>
          <label className="mt-4 block">New password (minimum 12 characters)<input name="password" type="password" autoComplete="new-password" minLength={12} required className="mt-2 min-h-12 w-full rounded-xl border border-slate-600 bg-slate-950 px-3" /></label>
          <label className="mt-4 block">Confirm new password<input name="confirmPassword" type="password" autoComplete="new-password" minLength={12} required className="mt-2 min-h-12 w-full rounded-xl border border-slate-600 bg-slate-950 px-3" /></label>
          <button disabled={submitting} className="mt-6 min-h-12 w-full rounded-xl bg-cyan-500 px-4 font-bold text-slate-950 disabled:opacity-60">{submitting ? "Changing password..." : "Change password and continue"}</button>
          <button type="button" onClick={() => { setAuthStep("PASSWORD"); setMessage(""); }} className="mt-3 min-h-12 w-full rounded-xl border border-slate-600">Start again</button>
        </> : <>
          <p className="mt-3 text-sm text-slate-400">{installation?.organizationName} · {identity.email}</p>
          {authStep === "MFA_SETUP" ? <div className="mt-5 rounded-xl border border-slate-700 bg-slate-950 p-4">
            <p className="font-semibold">Add this account to your authenticator app.</p>
            <p className="mt-3 break-all font-mono text-sm text-cyan-300">{mfa.secret}</p>
            <a href={mfa.uri} className="mt-3 inline-flex min-h-12 items-center text-cyan-300 underline">Open authenticator link</a>
          </div> : <p className="mt-5 text-slate-300">Enter the current code from your authenticator app.</p>}
          <label className="mt-4 block">Six-digit code<input name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required className="mt-2 min-h-12 w-full rounded-xl border border-slate-600 bg-slate-950 px-3 text-center font-mono text-xl tracking-widest" /></label>
          <button disabled={submitting} className="mt-6 min-h-12 w-full rounded-xl bg-cyan-500 px-4 font-bold text-slate-950 disabled:opacity-60">{submitting ? "Verifying..." : "Verify and continue"}</button>
          <button type="button" onClick={() => { setAuthStep("PASSWORD"); setMessage(""); }} className="mt-3 min-h-12 w-full rounded-xl border border-slate-600">Start again</button>
        </>}
        {message ? <p role="alert" className="mt-4 text-sm text-amber-300">{message}</p> : null}
      </form>
    </main>
  );

  if (installation?.status === "PENDING_ACTIVATION") return <main className="grid min-h-screen place-items-center p-4"><section className="w-full max-w-md rounded-2xl border border-slate-700 bg-slate-900 p-6"><ShieldCheck className="h-12 w-12 text-cyan-400"/><h1 className="mt-4 text-2xl font-bold">Activate {installation.organizationName}</h1><p className="mt-3 text-slate-300">MFA is complete. Confirm that this structure belongs to your organization, then activate the installation and enable the Administrator account.</p><button onClick={async()=>{setSubmitting(true);setMessage("");const r=await fetch("/api/installation/activate",{method:"POST"});const b=await readJsonResponse(r);if(r.ok)location.reload();else{setMessage(typeof b.error==="string"?b.error:"Activation failed");setSubmitting(false)}}} disabled={submitting} className="mt-6 min-h-12 w-full rounded-xl bg-cyan-500 font-bold text-slate-950">{submitting?"Activating...":"Activate organization"}</button>{message?<p className="mt-4 text-amber-300">{message}</p>:null}</section></main>;
  if(administratorAuthorization?.required&&administratorAuthorization.state!=="VALID")return <main className="grid min-h-screen place-items-center p-4"><section className="w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6"><ShieldCheck className="h-12 w-12 text-cyan-400"/><p className="mt-4 text-sm font-bold uppercase tracking-widest text-cyan-400">Restricted System Administrator</p><h1 className="mt-1 text-2xl font-bold">Authorizer approval required</h1><p className="mt-3 text-slate-300">Password and MFA verification are complete. Operational access also requires approval from the current System Authorizer and expires after seven calendar days.</p>{administratorAuthorization.operators?.length?<div className="mt-4 rounded-xl border border-slate-700 p-4"><p className="text-sm font-bold">Currently eligible operators</p>{administratorAuthorization.operators.map(operator=><p key={operator.personnelId} className="mt-1 text-sm text-slate-300">{operator.name} · {operator.appointment}</p>)}</div>:null}{administratorAuthorization.state==="NOT_CONFIGURED"?<p className="mt-4 text-amber-300">No eligible Admin In-Charge or Admin Clerk appointment holder is configured. The System Authorizer must configure and assign one before access can be requested.</p>:administratorAuthorization.state==="PENDING"?<p className="mt-4 text-amber-200">Approval request submitted. Ask the current System Authorizer to review it in the Organization section.</p>:<button disabled={submitting} onClick={async()=>{setSubmitting(true);setMessage("");const response=await fetch("/api/administrator-authorization/request",{method:"POST"}),body=await readJsonResponse(response);if(response.ok)location.reload();else{setMessage(typeof body.error==="string"?body.error:"Approval request failed");setSubmitting(false)}}} className="mt-5 min-h-12 w-full rounded-xl bg-cyan-500 px-4 font-bold text-slate-950">Request seven-day access approval</button>}{message?<p className="mt-4 text-amber-300">{message}</p>:null}<div className="mt-4 grid grid-cols-2 gap-3"><button onClick={()=>location.reload()} className="min-h-12 rounded-xl border border-slate-600">Refresh status</button><button onClick={async()=>{await fetch("/api/auth/logout",{method:"POST"});location.reload()}} className="min-h-12 rounded-xl border border-slate-600">Sign out</button></div></section></main>;
  return <PilotWorkspace principal={principal}/>;
}
