# Performance Tracker

Performance Tracker is a tenant-isolated personnel performance-management pilot built with Next.js and PostgreSQL. The target pilot launch is 1 January 2027, with December 2026 reserved for onboarding and isolated training data.

## Local development

1. Copy `.env.example` to `.env.local` and provide local-only secrets.
2. Install PostgreSQL 15 or newer and create an empty test database.
3. Apply migrations with `scripts/apply-migrations.ps1` using separate administrative and application database URLs.
4. Install dependencies with `pnpm install`.
5. Start the application with `pnpm dev`.

Never commit `.env.local`, database dumps, evidence objects, generated exports, or production identifiers.

## Verification

Run the following before creating a release:

```text
pnpm run typecheck
pnpm test
pnpm run build
pnpm run acceptance:smoke
```

Database security and restoration checks are documented in `database/README.md`, `docs/LAUNCH_READINESS.md`, and `docs/BACKUP_AND_RESTORE.md`.

## Deployment boundary

The web application must connect with the restricted runtime database role. Migration-owner, administrative, backup, JWT, MFA-encryption, scanner, and scheduled-job secrets must be stored outside the repository. Production deployment also requires TLS, private evidence storage, malware scanning, scheduled deadline processing, monitoring, and verified off-host backups.
