# Production deployment — Windows private-network pilot

## Architecture

Use one organization-controlled Windows host. Caddy is the only network-facing process and serves HTTPS. Next.js listens only on `127.0.0.1:3100`. PostgreSQL listens on loopback when colocated, or on a restricted private address when hosted separately. Port 5432 must never be exposed publicly.

## Accounts and directories

Create a dedicated non-administrator Windows service account. Grant it read/execute access to the release directory and modify access only to `C:\PerformanceTracker\logs` and the private evidence directory. Do not run the web process as a personal user, LocalSystem, or a PostgreSQL administrator.

Recommended layout:

```text
C:\PerformanceTracker\releases\<release-id>
C:\PerformanceTracker\config\.env.production.local
C:\PerformanceTracker\evidence
C:\PerformanceTracker\logs
```

The configuration and evidence directories must not be inside the Git checkout or web root.

## Database

Create distinct PostgreSQL logins for administration/migrations, the application runtime, and backups. Apply migrations with `scripts/apply-migrations.ps1`. Supply only the restricted runtime URL to the web process. Confirm that the runtime user has no `BYPASSRLS`, does not own tables, and inherits `mndf_pms_runtime`.

## Build and package

From the reviewed release commit:

```powershell
pnpm install --frozen-lockfile
pnpm run typecheck
pnpm test
pnpm run build
.\scripts\prepare-standalone.ps1
```

Before switching the service path, run the full release-candidate procedure in `docs/RELEASE_GATE.md`. The generated gate result must report `PASS`; a development-only code gate is not deployment authorization.

Create the protected environment with independent cryptographic values and a restrictive ACL. Supply pre-created restricted database URLs; URL-encode reserved characters in passwords.

```powershell
.\scripts\initialize-production-secrets.ps1 `
  -PublicUrl "https://tracker.organization.example" `
  -OutputPath C:\PerformanceTracker\config\.env.production.local `
  -DatabaseUrl $env:PERFORMANCE_TRACKER_RUNTIME_URL `
  -AuditDatabaseUrl $env:PERFORMANCE_TRACKER_AUDIT_URL `
  -EvidenceStorageRoot C:\PerformanceTracker\evidence `
  -EvidenceQuarantineRoot C:\PerformanceTracker\quarantine `
  -ServiceAccount 'DOMAIN\PerformanceTrackerService' `
  -DeploymentAdministrators 'DOMAIN\PerformanceTrackerDeployers'
```

The initializer refuses to overwrite an existing file, never prints secret values, applies the ACL, and runs configuration validation. Independently verify the ACL and then run:

```powershell
node --env-file=C:\PerformanceTracker\config\.env.production.local scripts\validate-production-env.mjs
```

Follow `docs/SECRETS_MANAGEMENT.md` for custody and rotation. Never copy the production file back into a release directory.

## HTTPS and network boundary

Install Caddy as a Windows service and adapt `deploy/Caddyfile.example`. Allow inbound TCP 443 only from the approved organization network. Do not create an inbound rule for port 3100. Limit PostgreSQL access to the application host. Redirect or block plaintext HTTP.

If public certificate issuance is unavailable, use Caddy internal TLS and distribute its root certificate through the organization's managed device process. Never ask users to bypass certificate warnings.

## Application service

Install the application startup task from an elevated deployment PowerShell session. Windows prompts for the dedicated, non-administrator service-account credential; the installer passes it directly to Task Scheduler and never writes it to a file or process command argument.

```powershell
$serviceCredential = Get-Credential 'DOMAIN\PerformanceTrackerService'
.\scripts\install-application-task.ps1 `
  -ProjectDirectory C:\PerformanceTracker\releases\<release-id> `
  -EnvironmentFile C:\PerformanceTracker\config\.env.production.local `
  -ServiceCredential $serviceCredential
```

The task starts at boot, uses the release directory as its working directory, prevents duplicate instances, and retries a failed process five times at one-minute intervals. Reinstall the task when switching its immutable release path. The service account must have `Log on as a batch job`, read/execute access to the release and configuration, and only the data-directory permissions described above.

After startup, verify `https://<approved-name>/api/health` returns HTTP 200. Install the sealed audit export from `docs/AUDIT_LEDGER_RETENTION.md`, then install `scripts/install-monitor-task.ps1` and follow `docs/MONITORING_AND_INCIDENT_RESPONSE.md` to detect process/database outages, authentication failures, deadline-worker staleness, scanner failures, sensitive access, clock drift, backup failures, and stale audit exports.

## Release and rollback

Deploy each Git commit into a new immutable release directory. Stop the service, apply forward-compatible migrations, switch the service path to the new release, start it, and run the authenticated smoke test. Keep the previous application release for rollback. Database rollback requires a tested restoration plan; never reverse migrations casually.

Record the deployed commit, migration number, deployment operator, approval, database backup identifier, health-check result, and rollback decision in the release log.
