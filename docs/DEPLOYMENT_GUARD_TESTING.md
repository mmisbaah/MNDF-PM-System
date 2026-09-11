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
