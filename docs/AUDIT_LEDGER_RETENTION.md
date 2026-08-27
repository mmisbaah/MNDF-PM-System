# Tamper-evident audit ledger retention

Performance Tracker audit events are protected by four controls:

1. the runtime role cannot directly insert, update, or delete audit rows;
2. each tenant's rows form a serialized SHA-256 chain inside PostgreSQL;
3. the daily export is encrypted with the separately held backup public key and its manifest is authenticated with HMAC-SHA-256; and
4. the verified package is copied to a different volume or controlled network share for separately governed retention.

The hash chain detects database-row alteration, deletion, insertion, and reordering. The export signature and encrypted-object digest detect package tampering. Off-host storage must prevent the application service account from changing or deleting previously retained exports.

## Production setup

Create an `AUDIT_DATABASE_URL` for a non-login membership role that can read only tenant-scoped audit data and execute `verify_audit_hash_chain`. Add a unique `AUDIT_EXPORT_HMAC_KEY` of at least 32 random characters to the protected operations environment. It must differ from authentication, MFA, scanner, scheduler, and monitoring secrets.

Use the same public encryption key as the encrypted backup system, while retaining the private key offline. Install the daily export after the database backup:

```powershell
.\scripts\install-audit-export-task.ps1 `
  -EnvironmentFile C:\PerformanceTracker\config\.env.production.local `
  -PublicKeyFile D:\BackupKeys\performance-tracker-public.pem `
  -OffHostDirectory \\audit-retention\PerformanceTracker `
  -PostgresBinDirectory "C:\Program Files\PostgreSQL\17\bin" `
  -DailyTime "02:30"
```

The default retention is seven days locally and 365 days off-host. Production rejects an off-host path on the same volume. Configure immutable/WORM retention where available and restrict HMAC-key access to the audit-export service and designated verification officers.

## Independent verification

Copy one retained export, retrieve the encrypted private key and HMAC key under the approved custody procedure, and run:

```powershell
$env:BACKUP_PRIVATE_KEY_PASSPHRASE = "retrieved recovery passphrase"
$env:AUDIT_EXPORT_HMAC_KEY = "retrieved audit verification key"
.\scripts\verify-audit-export.ps1 `
  -ExportDirectory E:\AuditReview\audit-ledger-20260827T023000Z `
  -PrivateKeyFile E:\OfflineRecovery\performance-tracker-private.pem
```

Verification authenticates the signed manifest, validates the encrypted object hash and AES-GCM protection, checks tenant consistency, requires a chain value on every row, and matches row-count and identifier boundaries to the signed manifest. Before every export, PostgreSQL independently recomputes and verifies the database hash chain.

Review the audit export daily for restricted-comment access, emergency operator access, score changes, template changes, authorizer transfers, account administration, and pilot overrides. Never place decrypted audit exports in ordinary application logs, tickets, or shared folders.
