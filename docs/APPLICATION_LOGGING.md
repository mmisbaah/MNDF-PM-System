# Application runtime logging

The production application task writes one UTF-8 runtime log per process start under `C:\PerformanceTracker\logs\application`. Each line has a UTC timestamp. Database URL passwords, bearer credentials, and common secret/password/token assignments are redacted before they are written.

The log directory is outside immutable releases and is protected by the production ACL procedure. It may contain operational paths, account identifiers, or error context, so access is limited to the service identity and authorized operations personnel. Never attach raw logs to an uncontrolled ticket or message.

Logs are classified as `SECURITY_TELEMETRY`. The application deliberately does not delete or overwrite them until the organization approves a finite retention policy and controlled disposal workflow. The five-minute monitor warns when the directory is missing, no runtime log exists, or preserved logs exceed 1 GiB. Operators must investigate growth and follow the approved retention/legal-hold process; they must not manually delete logs to silence the alert.

When investigating a failed start, correlate the newest application log with the Windows scheduled-task result, operations incident JSON, deployed commit, database health, and proxy log. Preserve the relevant files under legal hold before remediation when an incident is suspected.
