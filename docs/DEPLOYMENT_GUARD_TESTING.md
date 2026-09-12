# Deployment stop-guard regression tests

Run `powershell.exe -NoProfile -File scripts/test-deployment-task-guards.ps1`.
The code gate also runs this suite on a Windows runner using Windows PowerShell.

The eight cases cover immediate and delayed shutdown, stop permission failure,
task query failure, listener query failure, running and queued task timeouts,
and a stopped task with an orphan listener. An unrelated database listener must
not prevent a successful application stop. OS commands are mocked: this suite
does not stop real tasks or alter application data.

Promotion and rollback now require a successful task stop followed by both a
non-running/non-queued task state and a released application port. Query errors
fail closed. The guard makes at most 30 observations with 29 one-second delays
(time spent in OS calls is additional). It never kills an unknown process.

A rollback attempt starts with status `ROLLBACK_FAILED`; only restored health
changes that to `ROLLED_BACK`. If rollback cannot stop the application, the
previous junction remains available for operator recovery. Do not delete it.

## Remaining verification

These tests do not prove Task Scheduler child-process termination, real junction
switching, signed-package validation, or HTTP health recovery. Before deployment,
rehearse promotion and failed-health rollback on a disposable Windows host with
the actual service account. Also test an occupied port and denied task-stop
permission, confirming the current junction remains unchanged. Record evidence
before marking production deployment verified.

Use `scripts/run-promotion-rollback-rehearsal.ps1` for the attended lifecycle test. Supply three distinct integrity-signed staging releases: a healthy baseline, the healthy candidate under review, and a valid package deliberately configured to fail its health check. The runner refuses production paths, initializes and verifies the baseline, promotes the candidate through `promote-release.ps1`, requires the third promotion to fail, confirms that `CurrentLink` returned to the healthy candidate, and requires a terminal `ROLLED_BACK` journal record. It writes a separate versioned JSON evidence record outside the mutable release links.

Before installing any rehearsal package, run `scripts/verify-staging-host.ps1` from an elevated session. Pass the exact expected computer name and `-ConfirmDisposableHost`. The verifier rejects production paths, an existing rehearsal root, redirected path ancestors, non-NTFS storage, inadequate free space, a conflicting application listener, or existing production scheduled tasks. Its versioned readiness record is written with exclusive creation outside the rehearsal root so cleanup cannot erase the evidence.

After staging the three releases, create the approval input with `scripts/new-promotion-rehearsal-plan.ps1`. The generator verifies every detached signature and complete package, requires three distinct source commits, binds the exact staging host, paths, release trust key and release-evidence hashes, and creates a non-overwriting plan valid for no more than 14 days. Record its printed SHA-256 independently. Pass the plan and that digest to `run-promotion-rollback-rehearsal.ps1`; the runner rejects expired, cross-host, substituted, or modified release sets.

Create the deliberately unhealthy third package with `scripts/new-unhealthy-rehearsal-release.ps1` and the rehearsal-only release key. Its minimal server returns HTTP 503, and its `rehearsal-only.json` marker is covered by the signed full-package inventory. The plan generator and runner require that marker for the failure role and forbid it for baseline or candidate. A marked package is test material, not a deployable Performance Tracker release; never sign it with the production release key or include it in an installer.

Use `scripts/new-staging-rehearsal-bundle.ps1` to assemble the three releases, public rehearsal trust key, exact operational tools, operator guide and evidence checklist for transfer to the disposable host. The builder rejects redirected trees and common secret-bearing filenames, verifies every signature and full inventory before copying, marks the portable manifest as rehearsal-only, and hashes every bundled file. Transfer no private key, environment file, database credential, or production approval with this bundle.
