# Operational acceptance and December rehearsal

The pilot capacity target is 40 simultaneous authenticated users in an organization containing 10–200 personnel. `capacity-smoke.mjs` creates one independent session per virtual user and repeatedly exercises tenant workspace, notification, and session-identity reads. The default deployment thresholds are no more than 1% failed requests and a p95 latency no greater than 3 seconds over 60 seconds.

The full release gate runs this authenticated 40-user check with the dedicated dummy acceptance account. A short anonymous engineering diagnostic may be run before that account exists:

```powershell
$env:CAPACITY_ALLOW_ANONYMOUS="true"
$env:CAPACITY_DURATION_SECONDS="10"
npm run capacity:smoke
```

Anonymous mode is not deployment evidence.

## December onboarding rehearsal

During December 2026, set training mode before entering onboarding records and run:

```powershell
$env:ACCEPTANCE_LOGIN_ID="dummy-load-user"
$env:ACCEPTANCE_PASSWORD="temporary controlled value"
.\scripts\run-onboarding-rehearsal.ps1 -AdminDatabaseUrl $env:POSTGRES_ADMIN_URL -BaseUrl "https://performance-tracker.internal"
```

Before December, engineering may add `-PreDecemberDryRun`. The administrative PostgreSQL URL is required because a tenant-scoped runtime connection must not and cannot inspect every tenant for isolation mistakes. The database gate rejects December cycles, activities, reports, disciplinary matters, or AWOL incidents stored as production data. It also rejects production exports or eligibility recommendations derived from training appraisals.

The generated JSON deliberately remains `PENDING_ATTENDED_SIGNOFF` after automated checks pass. The System Authorizer must record personal MFA enrollment, Administrator authorization, Authorizer handover, full appraisal/grievance/correction workflow, mobile usability, evidence quarantine, and backup restoration. Automation must never mark those human procedures complete.
