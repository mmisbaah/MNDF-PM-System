# Backup and restoration runbook

Install the PostgreSQL client tools on the operations host. Set `DATABASE_URL` in the scheduled-task account's protected environment and run `backup-postgres.ps1`. It creates a compressed custom-format dump and SHA-256 manifest. Copy both to encrypted, access-controlled off-host storage.

Run `install-backup-task.ps1` from an elevated PowerShell session to register a daily 02:00 backup. Use `verify-restore.ps1` against a non-production server through `POSTGRES_ADMIN_URL`. Verification checks the checksum, restores into a uniquely named temporary database, checks tables, foreign keys, and RLS policies, then removes only that verified temporary database.

Run restoration verification after every migration and at least monthly. Retain scheduled-task logs and verification results with the backup inventory.
