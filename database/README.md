# MNDF PMS Pilot v1.0 database

These PostgreSQL 15+ migrations implement the tenant-isolated pilot data model.

## Apply in order

1. Apply `0000_deployment_roles.sql` as a database administrator with `CREATEROLE`.
2. Use `SET ROLE mndf_pms_migration_owner` and apply all numbered feature migrations (`0001` onward, excluding the runtime-grant migration `0010`) in numeric order.
3. Apply `0010_deployment_roles.sql` last as the database administrator so grants include every created object.

Use `scripts/apply-migrations.ps1` to enforce this ownership sequence. The application login role must be granted membership in `mndf_pms_runtime` and connect with that role active. It must not own tables or have `BYPASSRLS`.

The migration runner finishes with `database/tests/stage_1_1_gate.sql`, which fails deployment if tenant columns, forced RLS, restricted-comment grants, audit privileges, deployment roles, or relationship-authorization triggers are incorrectly configured.

Every application transaction must set the tenant and actor context before querying tenant-owned data:

```sql
BEGIN;
SET LOCAL app.tenant_id = '00000000-0000-0000-0000-000000000000';
SET LOCAL app.account_id = '00000000-0000-0000-0000-000000000000';
SET LOCAL app.request_id = '00000000-0000-0000-0000-000000000000';
-- tenant-scoped statements
COMMIT;
```

Do not use a connection-level `SET` with a pooled connection. Use `SET LOCAL` inside the same transaction as the queries.

## Security notes

- Composite foreign keys include `tenant_id`, preventing cross-tenant references.
- Row-level security is defense in depth; service code must still authorize roles, relationships, workflow states, and restricted-comment seniority.
- Evidence metadata is constrained to one single-page PDF or image per rating, no larger than 5 MiB. The object itself belongs in private object storage.
- Ratings 1, 2, and 5 are checked by a deferred constraint trigger. Insert the rating and evidence in the same transaction.
- An appraisal cannot progress to commander approval while related evidence has a malware status other than `CLEAN`.
- Template rows become immutable after a linked cycle leaves `DRAFT`.
- Confirmed activity versions are immutable; corrections create a new version.
- `audit_logs` is append-only and sealed with a serialized per-tenant SHA-256 chain. Production must run the encrypted, HMAC-signed off-host export described in `docs/AUDIT_LEDGER_RETENTION.md`.
- Permanent tenant deletion requires two recent, unrevoked authorizations from distinct accounts: the company commander and executive officer (the pilot's mapped second-tier deletion authority).
- Restricted comments are available only through `read_restricted_comments_for_complaint`, after complaint acceptance, to the first sergeant, executive officer, company commander, or an active case-specific officer. Grant the runtime role `EXECUTE` on this function but no direct `SELECT` privilege on restricted comment data.
- Authentication uses 15-minute signed access JWTs in HttpOnly cookies and rotating, server-stored seven-day refresh sessions.
- Commander, administrator, executive officer, first sergeant, and technical-operator roles require TOTP MFA before an elevated session is issued.
- Technical-operator accounts cannot hold ordinary unit roles. Exceptional recovery or incident access is recorded in both `operator_exception_requests` and the append-only audit log.
- Stage 2 self-assessments are tenant-scoped, editable only by the appraisee while the appraisal is in `DRAFT`, and become immutable when submitted.

## Deliberate application-level responsibilities

Some rules require policy context and remain in the service layer in addition to database enforcement:

- Determining whether a restricted-comment reader is senior to the author outside an accepted grievance case.
- Generating evaluator-chain snapshots from current appointments.
- Validating that a unit-specific criterion does not replace a mandatory baseline criterion.
- Evidence is uploaded through `/api/evidence`; the server verifies its signature, byte size, digest, and conservative PDF page count before issuing an upload ID. Only the scanner callback `/api/internal/evidence-scan`, authenticated with `EVIDENCE_SCANNER_SECRET`, may mark it `CLEAN`, `INFECTED`, or `FAILED`.
- Recomputing appraisal totals from final applicable criteria.
- Delivering queued grievance notifications through the configured notification transport. The database schedules and releases them and marks missed open cases overdue.
- Preventing sensitive content from appearing in emails, caches, logs, and ordinary reports.
