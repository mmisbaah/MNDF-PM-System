# Performance Tracker pilot launch gate

Target production start: **1 January 2027**. December 2026 is onboarding and parallel testing; all December test records must be marked as training data.

## Automated release gate

Run these checks against a disposable copy of the production schema before every release:

1. `pnpm run typecheck`
2. `pnpm test`
3. `pnpm run build`
4. `database/tests/stage_1_1_gate.sql`
5. `database/tests/runtime_rls_smoke.sql` inside a transaction that is rolled back
6. `scripts/backup-postgres.ps1`, followed by `scripts/verify-restore.ps1` into an empty database
7. Authenticated browser regression for Authorizer, Administrator, evaluator, appraisee, and grievance roles

A release fails if any check fails.

## Security controls to verify

- The application database connection uses the restricted runtime role; migration and backup credentials are never supplied to the web process.
- Every operational table contains `tenant_id`, has forced row-level security, and blocks cross-tenant reads and writes.
- Access cookies are HTTP-only, SameSite Strict, Secure in production, and access tokens expire after 15 minutes.
- Refresh tokens rotate on every use. Reuse or a revoked session is rejected.
- Commander, Executive Officer, First Sergeant, Administrator, and Technical Operator accounts have MFA enrolled.
- The dedicated Administrator has only personnel provisioning and report collection permissions, plus a current seven-day authorization grant.
- The Technical Operator has no ordinary personnel, appraisal, grievance, or report-reading permission. Exceptional recovery activity is audit recorded.
- Restricted-comment access is case-specific and every view/export is audit logged.
- Audit rows cannot be directly inserted, updated, or deleted by the runtime role.
- Initial unauthenticated organization setup is closed after installation and is reachable only from the host/private network.
- Browser responses include anti-framing, MIME-sniffing, referrer, cross-origin, and device-permission security headers.

## Infrastructure prerequisites

- Terminate TLS at the organization-controlled reverse proxy and redirect all HTTP traffic to HTTPS.
- Store JWT, MFA encryption, cron, database, and backup secrets outside the repository with restricted operating-system permissions.
- Restrict PostgreSQL to the application host/private network. Do not expose port 5432 publicly.
- Keep encrypted backups on a separate device or storage location. Perform and record at least one restoration rehearsal before onboarding.
- Configure system time synchronization; MFA and all grievance/correction deadlines depend on accurate server time.
- Configure malware scanning for evidence uploads and prevent unscanned evidence from becoming accepted appraisal evidence.
- Configure notifications and monitor failed deadline jobs, backup jobs, authentication failures, and security-recovery activity.

## December acceptance scenarios

- Build the real organization hierarchy with dummy unique IDs and pilot login IDs.
- Exercise authorizer succession, including the outgoing authorizer's three-day read/export-only handover.
- Exercise Administrator approval, MFA, seven-day authorization, and revocation after an eligible operator appointment changes.
- Complete one full appraisal from initialization through acknowledgement, complaint, correction, and closure.
- Verify ratings 1, 2, and 5 cannot be saved without justification and valid evidence.
- Confirm restricted comments never appear in ordinary reports or PDFs.
- Confirm December training records do not appear in 2027 production reports or eligibility calculations.
- Confirm each quarterly cycle closes 25 calendar days after its quarter ends.
- Complete a backup, destructive test-database loss simulation, and verified restore.

The System Authorizer signs the release record only after all automated gates and acceptance scenarios pass. Any waiver must state the owner, risk, mitigation, and expiry date.
