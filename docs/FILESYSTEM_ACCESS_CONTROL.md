# Production filesystem access control

Run `set-production-acls.ps1` from an elevated deployment session after creating the immutable release and before starting the application. It removes inherited access and grants only SYSTEM, local Administrators, the deployment-administrator group, the invoking deployment operator, and the dedicated application service account.

The application account receives read/execute access to releases and configuration, and modify access only to evidence, quarantine, and logs. It receives no general administrative permission. The configuration initializer separately restricts the environment file itself to read-only service access.

```powershell
.\scripts\set-production-acls.ps1 `
  -ReleaseDirectory C:\PerformanceTracker\current `
  -ConfigDirectory C:\PerformanceTracker\config `
  -EvidenceDirectory C:\PerformanceTracker\evidence `
  -QuarantineDirectory C:\PerformanceTracker\quarantine `
  -LogDirectory C:\PerformanceTracker\logs `
  -ServiceAccount 'DOMAIN\PerformanceTrackerService' `
  -DeploymentAdministrators 'DOMAIN\PerformanceTrackerDeployers'
```

The script refuses filesystem roots, missing releases, duplicate data paths, empty identities, and non-elevated execution. Review any additional backup, scanner, or audit-export identities separately and grant only their required directories.

The attended release gate runs `verify-production-acls.ps1`. It blocks release when a protected directory is missing, still inherits permissions, lacks an explicit service-account rule, permits broad identities to access configuration/evidence/quarantine, or permits broad write/delete/ownership rights elsewhere.
