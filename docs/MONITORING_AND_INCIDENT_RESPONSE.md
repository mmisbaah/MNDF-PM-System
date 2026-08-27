# Monitoring and incident response

Performance Tracker uses a loopback-only operations endpoint plus a five-minute Windows watchdog. The public `/api/health` endpoint reveals only application/database availability. Detailed operational state is available only through `/api/internal/operations-health` using the dedicated `OPERATIONS_MONITOR_SECRET`; the reverse proxy must continue blocking all `/api/internal/*` paths.

The detailed check covers:

- grievance-deadline, cycle-lifecycle, and recommendation worker freshness and recent failures;
- evidence uploads that have remained pending for more than ten minutes and recent scan failures;
- bursts of failed MFA attempts;
- restricted-data access and exceptional Technical Operator activity;
- application/database clock drift;
- latest encrypted backup and sealed audit-export success and age; and
- presence, enabled state, and last result of the required Windows scheduled tasks.

## Installation

Add a unique random `OPERATIONS_MONITOR_SECRET` of at least 32 characters to the protected production environment file. Install the monitor under the dedicated operations service account from an elevated PowerShell session:

```powershell
.\scripts\install-monitor-task.ps1 `
  -EnvironmentFile C:\PerformanceTracker\config\.env.production.local `
  -BackupLog C:\PerformanceTracker\backups\backup-operations.jsonl `
  -AlertDirectory C:\PerformanceTracker\logs\alerts
```

The monitor appends every check to `monitor-history.jsonl`. When attention is required it creates a timestamped incident JSON file and exits unsuccessfully, making the failure visible in Task Scheduler and the host monitoring system. Restrict the alert directory to the operations and security teams; it contains operational metadata but no appraisal content.

## Response procedure

1. Record the incident file, time, host, operator, and deployed commit.
2. If the application/database check fails, stop user activity at the reverse proxy and preserve logs before restarting services.
3. If deadline workers are stale, restore the worker and run it once manually; server timestamps keep cases open and visibly overdue until processing resumes.
4. If evidence scanning fails, keep pending files unavailable and restore Defender/scanner operation before accepting evidence.
5. Treat MFA bursts as a possible account attack. Review immutable authentication and audit records and revoke affected sessions when warranted.
6. Treat every exceptional operator or restricted-data event as review-required, even when authorized.
7. If backups are stale or failed, correct storage/key/database access and produce a newly verified off-host set before closing the incident.
8. Document cause, containment, recovery, affected period, approvals, and follow-up action. Do not include restricted appraisal content in infrastructure tickets.

During December onboarding, test each alert class deliberately in the disposable environment and confirm the responsible person can find, understand, acknowledge, and resolve it.
