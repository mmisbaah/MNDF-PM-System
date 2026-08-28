# Release-candidate gate

No commit is deployable merely because it builds. Performance Tracker has two release gates:

1. GitHub runs the code gate on every pull request and push to the release branch: frozen dependency installation, TypeScript, automated policy tests, and production compilation.
2. An authorized operator runs the full Windows gate against the intended release, a newly created disposable PostgreSQL database, and the staged application.

## Full attended gate

Use a dedicated active appraisee acceptance account with no privileged role and no MFA requirement. It must contain only dummy pilot identity data. Store its credentials temporarily in the operator process and clear them afterward.

```powershell
$env:POSTGRES_ADMIN_URL = "postgresql://release_operator:...@127.0.0.1:5432/postgres"
$env:DATABASE_URL = "postgresql://mndf_pms_app:...@127.0.0.1:5432/postgres"
$env:ACCEPTANCE_LOGIN_ID = "release-test-user"
$env:ACCEPTANCE_PASSWORD = "temporary value from the controlled test account"
$env:BROWSER_CHANNEL = "msedge" # organization-controlled Windows host

.\scripts\release-gate.ps1 `
  -AcceptanceBaseUrl https://performance-tracker.internal `
  -ApplicationRole mndf_pms_app `
  -PostgresBinDirectory "C:\Program Files\PostgreSQL\17\bin" `
  -RestoreRehearsalResult C:\PerformanceTracker\recovery-results\latest-success.json `
  -OperationalReadinessRecord C:\PerformanceTracker\release\operational-readiness.json `
  -ProductionServiceAccount 'DOMAIN\PerformanceTrackerService'
```

The script creates a database named only under the guarded `mndf_pms_release_verify_<timestamp>` pattern, applies every migration, runs constraint/RLS/audit gates, and removes that disposable database in `finally`. It never points destructive cleanup at a supplied production database name.

The authenticated API smoke checks installation identity, security headers, database health, anonymous rejection, cross-origin rejection, PWA cache safety, login, session identity, and tenant workspace loading. The browser regression then uses the same dummy account at a 390×844 viewport to verify the real login form, completed workspace loading, mobile overflow, primary navigation selection, console/server failures, and sign-out. On failure it writes a screenshot and redacted JSON result under the release-gate output directory. Privileged MFA ceremonies remain attended acceptance tests and are not bypassed for automation.

Before application smoke tests, the gate verifies the public HTTPS boundary: trusted hostname certificate, at least 14 days of certificate life, TLS 1.2 or newer, HTTP-to-HTTPS redirect, one-year HSTS, suppressed `Server` header, and denial of `/api/internal/*`. See `docs/TLS_AND_REVERSE_PROXY.md`.

The full Windows gate also verifies enabled firewall profiles, loopback-only application and database listeners, successful Windows Time synchronization, and every required scheduled operations task. See `docs/WINDOWS_HOST_HARDENING.md`.

The gate also verifies protected production directory ACLs and explicit access for the dedicated application identity. See `docs/FILESYSTEM_ACCESS_CONTROL.md`.

Install the browser automation dependency during release-host provisioning. On the Windows staging host, set `BROWSER_CHANNEL=msedge` to use the organization-managed Edge installation. For isolated engineering environments using bundled Chromium, run `pnpm exec playwright install chromium` once after the frozen dependency installation.

The restoration result must report `SUCCESS` and be no older than 31 days by default. Recovery keys are never passed to CI or the release gate.

Copy `deploy/operational-readiness.example.json` outside the repository and complete it during December onboarding. The validator rejects placeholders, incomplete training, missing attended evidence, open severity-1 or severity-2 incidents, an unverified rollback target, or Authorizer approval older than 14 days.

## Result and approval

Every run writes `output/release-gates/release-gate-<UTC timestamp>.json` with the exact Git commit, branch, duration, and each check result. `CODE_ONLY_PASS` is useful during development but is not a deployable result. Only `PASS` may be attached to the release record.

The System Authorizer reviews the full result, the attended acceptance record, the recent restoration rehearsal, open incidents, and rollback target before signing release approval. A failed or incomplete check cannot be converted to a pass by editing the JSON file; rerun the gate after remediation.
