# Records lifecycle, legal holds, controlled exports, and disposal

Performance Tracker does not guess retention periods. Until the System Authorizer approves a finite policy version for a record class, records are preserved. The organization must approve periods for personnel, performance, activity, grievance, evidence, discipline, audit, security telemetry, export packages, and backups before requesting disposal.

Every policy is versioned. An approved version cannot be edited; it may only be retired when a replacement is approved. Every governance record carries `tenant_id`, forced row-level security, and immutable audit events.

## Legal holds

A hold may cover the tenant or a specific person, appraisal, complaint, or evidence object. A hold cannot be deleted or have its scope changed. Release requires an accountable user, timestamp, and reason. Any active hold blocks all disposal authorization for the tenant; this conservative pilot behavior prevents partial-scope mistakes.

## Exports

Ordinary users may view only reports already permitted by their role and assignment. Administrative, audit, grievance-case, and tenant-wide export packages require a controlled export request, stated purpose, a different approving account, a 24-hour approval expiry, encrypted output, and a SHA-256 manifest recorded on completion. Restricted comments must never enter an ordinary report export.

## Disposal

Disposal requires all of the following:

1. an approved finite retention policy for the record class;
2. no active legal hold;
3. a recorded cutoff and reason;
4. approval by the System Authorizer and Executive Officer from two distinct accounts;
5. a recent verified backup and sealed audit export;
6. execution by the controlled maintenance procedure; and
7. a signed disposal manifest containing counts and cryptographic hashes.

The web application records authorization but intentionally does not issue bulk `DELETE` commands. Core-record disposal must be implemented only after the organization approves actual retention periods and a table-specific deletion order. Complete tenant disposal continues to use the existing dual-authorized tenant deletion safeguard. Manual direct database deletion is prohibited.

Use `/api/records-governance` for policy, hold, export, and disposal authorization records. Only audit readers may view the full register; action-specific Commander or grievance authority is required for changes, and PostgreSQL independently verifies disposal authority roles.
