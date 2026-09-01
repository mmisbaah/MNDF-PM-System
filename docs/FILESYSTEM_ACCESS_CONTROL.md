# Production filesystem access control

Run `set-production-acls.ps1` from an elevated deployment session after creating the immutable release and before starting the application. It replaces each root directory's DACL (including unrelated explicit grants), disables inheritance, and grants only SYSTEM, local Administrators, the deployment-administrator group, the invoking deployment operator, and the dedicated application service account. Review and record existing ACLs before applying; the script does not create an ACL backup.

The application account receives read/execute access to releases and configuration, and modify access only to evidence, quarantine, and logs. It receives no general administrative permission. The configuration initializer separately restricts the environment file itself to read-only service access.

```powershell
.\scripts\set-production-acls.ps1 `
  -ReleaseDirectory C:\PerformanceTracker\releases\REPLACE_WITH_RELEASE_ID `
  -ConfigDirectory C:\PerformanceTracker\config `
  -EvidenceDirectory C:\PerformanceTracker\evidence `
  -QuarantineDirectory C:\PerformanceTracker\quarantine `
  -LogDirectory C:\PerformanceTracker\logs `
  -ServiceAccount 'DOMAIN\PerformanceTrackerService' `
  -DeploymentAdministrators 'DOMAIN\PerformanceTrackerDeployers'
```

The script refuses filesystem roots, missing releases, duplicate or overlapping data paths, redirected paths (junctions/symbolic links), empty identities, and non-elevated execution. Supply the physical release folder, not `current`, including via `-ProductionReleaseDirectory` on the attended release gate. The application account must be distinct from the deployment identities. Review any additional backup, scanner, or audit-export identities separately and grant only their required directories.

The attended release gate runs `verify-production-acls.ps1`. It blocks release when a protected root directory is missing, still inherits permissions, lacks service-account access, permits broad identities to access configuration/evidence/quarantine/logs, or permits broad write/delete/ownership rights elsewhere. It traverses existing child files and directories without following reparse points, detects broad child grants and service writes on read-only release/config content, and resolves identities by SID rather than localized names. Unreadable entries fail verification.

Existing explicit/protected child ACLs are not reset automatically. This preserves intentional restrictions on secrets; unsafe child rules must be reviewed and repaired before the gate passes. ACL provisioning is not transactional: if it fails, review the partial changes and rerun verification before starting the application.

Verification additionally requires `-ApprovedAdministrators` (a PowerShell string
array), or `-ProductionApprovedAdministrators` when running the release gate.
Supply the independently approved deployment groups **and each directly granted
operator identity**, including the operator retained by ACL provisioning. SYSTEM
and local Administrators are included as the platform's administrative principals.
The verifier never derives approval from existing ACLs or the current user.
Every explicit or inherited Allow entry on roots and child files/directories must
belong to that list or the dedicated service account—even read access on releases.
Empty lists, broad groups and service/administrator collisions are rejected.
Resolved approved SIDs are included in the verification result.

Do not add scanner/backup identities to the administrator list merely to pass:
that would treat them as administrators across all checked directories. Additional
non-administrative identities require a separately designed path-scoped policy.

Run `scripts/test-production-acls.ps1` on Windows for disposable-directory regression tests. These do not alter production folders. Effective access through nested group memberships, backup privileges, ownership, and all external scanner/backup identities still requires attended service-account review. Passing this verifier is not a full Windows authorization audit.
