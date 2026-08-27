# Backup, off-host retention, and restoration

Performance Tracker production backups are backup sets containing an encrypted PostgreSQL custom-format dump, an encrypted evidence archive, and a SHA-256 manifest. A backup is successful only after both encrypted components have been copied to a separate storage location and their destination hashes have been verified.

## One-time key preparation

Generate the 3072-bit RSA backup key pair on a secured operations computer:

```powershell
$env:BACKUP_PRIVATE_KEY_PASSPHRASE = "a long passphrase from the organization password vault"
node scripts/backup-crypto.mjs keygen D:\BackupKeys\performance-tracker-public.pem E:\OfflineRecovery\performance-tracker-private.pem
```

Only the public key belongs on the application host. Store the encrypted private key and its passphrase separately in approved offline custody. Never put either key or the passphrase in the repository. Test recovery access before relying on the key.

## Daily backup

The scheduled-task account requires `BACKUP_DATABASE_URL` for a read-capable PostgreSQL backup role. Run:

```powershell
.\scripts\backup-production.ps1 `
  -PublicKeyFile D:\BackupKeys\performance-tracker-public.pem `
  -OffHostDirectory \\backup-device\PerformanceTracker `
  -PostgresBinDirectory "C:\Program Files\PostgreSQL\17\bin"
```

The off-host target must be a different volume or controlled network share; the script rejects same-volume targets in production. Grant the backup account create/write access and deny ordinary application accounts access. The default policy keeps seven days locally and ninety days off-host. Retention deletion runs only after the newest off-host copy passes hash verification. A JSON-lines success/failure history is kept at `backups/backup-operations.jsonl`.

Install the daily 02:00 scheduled task from an elevated PowerShell session with `scripts/install-backup-task.ps1`. Configure `BACKUP_DATABASE_URL` in the scheduled-task service account environment, not in task arguments or source files.

## Restoration rehearsal

Use a copied off-host backup set, the offline private key, its passphrase, and an administrative URL targeting the local PostgreSQL server:

```powershell
$env:BACKUP_PRIVATE_KEY_PASSPHRASE = "value retrieved under recovery procedure"
$env:POSTGRES_ADMIN_URL = "postgresql://restore-operator:...@127.0.0.1:5432/postgres"
.\scripts\verify-production-restore.ps1 `
  -BackupSetDirectory E:\Rehearsal\performance-tracker-20260827T020000Z `
  -PrivateKeyFile E:\OfflineRecovery\performance-tracker-private.pem `
  -PostgresBinDirectory "C:\Program Files\PostgreSQL\17\bin"
```

The rehearsal verifies all encrypted-object hashes, authenticates and decrypts both components, validates the evidence archive, restores the database into a uniquely named disposable database, checks table, foreign-key, and row-level-security thresholds, and removes the disposable database. A timestamped JSON result is written under `.verification-backups`.

For a same-volume local rehearsal only, `backup-production.ps1` accepts `-AllowSameVolumeForRehearsal`. This flag must never be used by the production scheduled task.

Run and sign off a rehearsal after every migration, monthly during the pilot, and before launch. Record the backup-set identifier, operator, result file, duration, observed recovery time, and corrective action for any failure. Never rehearse into the production database.

## Recovery controls

- Keep at least one off-host copy inaccessible to the application host after the backup window (offline or immutable storage).
- Separate backup-key custody from routine application administration.
- Monitor scheduled-task exit status, missing daily backup sets, destination capacity, and restore-rehearsal failures.
- Periodically test loss of both the database and evidence directory; a database-only restore is incomplete.
- Do not consider synchronization to another folder on the same disk an off-host backup.
