# Release-candidate gate

No commit is deployable merely because it builds. Performance Tracker has two release gates:

1. GitHub runs the code gate on every pull request and push to the release branch: frozen dependency installation, TypeScript, automated policy tests, and production compilation.
2. An authorized operator runs the full Windows gate against the intended release, a newly created disposable PostgreSQL database, and the staged application.

## Full attended gate

Use a fresh clean committed checkout with no `.next` output. The gate invokes
`release-build.ps1` to record build-to-commit provenance, then verifies it during
packaging. Existing builds are preserved and rejected, not relabelled. A normal
development build does not satisfy this requirement.

Both the local `-CodeOnly` and full gates first run the lint-progress regression
tests and `npm run lint`. ESLint emits elapsed-time updates every ten seconds.
Either check failing stops the gate before build, packaging, or database work,
and records `FAIL` in the gate result. ESLint's existing warning policy is unchanged.
Run `scripts/test-release-lint-gate.ps1` for the isolated failure-propagation test.

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
  -ProductionServiceAccount 'DOMAIN\PerformanceTrackerService' `
  -ProductionApprovedAdministrators @('DOMAIN\PerformanceTrackerDeployers','DOMAIN\ApprovedDeploymentOperator')
```

The script generates a database name under the guarded
`mndf_pms_release_verify_<32 lowercase hexadecimal UUID characters>` pattern
(54 characters, below PostgreSQL's identifier limit). It applies migrations and
runs constraint/RLS/audit checks, then cleans up in `finally` **only if this run's
creation command confirmed success**. Merely assigning a name or finding an
existing database never authorizes deletion. Failed or uncertain creation leaves
the server untouched by automatic cleanup; an operator must inspect uncertain
outcomes. A failed cleanup is recorded as a failed check and prevents release
approval, while preserving any earlier validation failure. This assumes no other
operator drops/recreates the run's UUID-named database while the gate runs.

`scripts/test-release-database-ownership.ps1` tests ownership and failure handling
with mocked PostgreSQL utilities; it never connects to a database.

The authenticated API smoke checks installation identity, security headers, database health, anonymous rejection, cross-origin rejection, PWA cache safety, login, session identity, and tenant workspace loading. The browser regression then uses the same dummy account at a 390×844 viewport to verify the real login form, completed workspace loading, mobile overflow, primary navigation selection, console/server failures, and sign-out. On failure it writes a screenshot and redacted JSON result under the release-gate output directory. Privileged MFA ceremonies remain attended acceptance tests and are not bypassed for automation.

Before application smoke tests, the gate verifies the public HTTPS boundary: trusted hostname certificate, at least 14 days of certificate life, TLS 1.2 or newer, HTTP-to-HTTPS redirect, one-year HSTS, suppressed `Server` header, and denial of `/api/internal/*`. See `docs/TLS_AND_REVERSE_PROXY.md`.

The full Windows gate also verifies enabled firewall profiles, loopback-only application and database listeners, successful Windows Time synchronization, and every required scheduled operations task. See `docs/WINDOWS_HOST_HARDENING.md`.

The gate also verifies protected production directory ACLs and explicit access for the dedicated application identity. See `docs/FILESYSTEM_ACCESS_CONTROL.md`.

Install the browser automation dependency during release-host provisioning. On the Windows staging host, set `BROWSER_CHANNEL=msedge` to use the organization-managed Edge installation. For isolated engineering environments using bundled Chromium, run `pnpm exec playwright install chromium` once after the frozen dependency installation.

The restoration result must report `SUCCESS` and be no older than 31 days by default. Recovery keys are never passed to CI or the release gate.

Copy `deploy/operational-readiness.example.json` outside the repository and complete it during December onboarding. The validator rejects placeholders, incomplete training, missing attended evidence, open severity-1 or severity-2 incidents, an unverified rollback target, or Authorizer approval older than 14 days.

## Result and approval

### Self-contained release dependencies

In a fresh release checkout, install with `pnpm install --frozen-lockfile --node-linker=hoisted --package-import-method=copy`.
The release build rejects isolated top-level dependency links before invoking
Next.js. Normal development installs need not change.

After compilation and asset copying, `materialize-standalone.mjs` copies into a
new staging directory. Dependency aliases may resolve only inside the standalone
tree or this checkout's installed dependencies. Escaping, dangling, cyclic, and
non-dependency links fail closed. The resulting tree must pass the unchanged
no-links inventory before becoming `.next/standalone`; original compiler output
is retained as `.next/standalone-raw`. Only the final standalone directory is
packaged, hashed and signed, never the raw sibling. Failed staging is preserved;
retry in a fresh checkout. Inputs must remain under trusted exclusive control;
this does not defend against concurrent malicious filesystem mutation.

Every run writes `output/release-gates/release-gate-<UTC timestamp>.json` with the exact Git commit, branch, duration, and each check result. `CODE_ONLY_PASS` is useful during development but is not a deployable result. Only `PASS` may be attached to the release record.

The System Authorizer reviews the full result, the attended acceptance record, the recent restoration rehearsal, open incidents, and rollback target before signing release approval. A failed or incomplete check cannot be converted to a pass by editing the JSON file; rerun the gate after remediation.

## Continuous-integration parity

The GitHub code-gate job installs dependencies with the same hoisted, copied
layout required by the release build and invokes `release-gate.ps1 -CodeOnly`
instead of independently repeating its build steps. This prevents CI from
passing a linked dependency tree that the Windows release packager would later
reject. The workflow retains the exact `CODE_ONLY_PASS` or `FAIL` JSON result as
a 30-day build artifact bound to the Git commit. The artifact is engineering
evidence only; it does not replace the full attended `PASS` record or System
Authorizer approval.
