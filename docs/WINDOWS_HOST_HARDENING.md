# Windows production-host hardening

Performance Tracker relies on the host operating system for the final network and time boundary. Before release, run `scripts/verify-windows-host.ps1` from an elevated authorized operations PowerShell session on the intended application host.

The verifier fails when the Next.js or PostgreSQL port is absent or listens on a non-loopback address, any Windows Firewall profile is disabled, Windows Time is stopped or unsynchronized, or the application, scheduling, scanning, backup, audit-export, or monitoring task is missing or disabled.

```powershell
.\scripts\verify-windows-host.ps1
```

If PostgreSQL is intentionally hosted on a separate private database host, pass `-DatabasePort 0` on the application host, run an equivalent network check on the database host, and retain both outputs as release evidence. The full release gate exposes this setting as `-LocalDatabasePort 0`. Do not expose port 5432 to client networks. Firewall rules should permit HTTPS only from approved client networks and management access only from approved operations hosts.

The attended release gate invokes this check automatically. A failed clock check blocks launch because MFA, grievance deadlines, correction authorizations, audit chronology, and certificate validation depend on correct system time.
