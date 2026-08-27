# Acceptance milestone results — 27 August 2026

## Result

The pre-December security and role-acceptance gate passed after remediation of one horizontal-authorization defect in operational reports.

## Verified automatically

- Appraisee, evaluator, Commander, dedicated Administrator, and Technical Operator permission boundaries.
- Mandatory MFA for all privileged pilot roles.
- Commander exclusion from ordinary evaluation and self-evaluation rejection.
- Tenant row-level security and blocked cross-tenant writes.
- Immutable audit generation for sensitive runtime writes.
- Protected API rejection without an authenticated session.
- Cross-origin rejection for state-changing authentication requests.
- PWA manifest, offline worker availability, and exclusion of API responses from offline caching.
- Production compilation and TypeScript validation.

## Defect corrected during this milestone

Operational report transitions previously checked only a broad role permission. A user with evaluator privileges could attempt to submit or confirm a report outside their assignment by supplying its identifier.

The corrected implementation now enforces all of the following in both the application service and PostgreSQL:

- Only an assigned evaluator or active senior supervisory leader can create a report for a person.
- Only the report creator can submit its draft.
- Only an assigned evaluator or active senior supervisory leader can confirm it.
- Status changes must follow `DRAFT → SUBMITTED → CONFIRMED`.
- Only the creator may edit or delete a draft.
- Confirmed reports remain immutable.

## Remaining attended acceptance tests

These require a human operator because they involve individual MFA devices, visual judgment, or real operational procedure:

- Each user enrolls and validates their own authenticator.
- Authorizer and Administrator complete the seven-day authorization ceremony.
- Users assess mobile readability and clarity of instructions using their actual devices.
- The unit performs the authorizer handover and confirms that the outgoing holder has read/export-only access for three days.
- The unit completes a backup-restoration rehearsal on a separate test database and signs the result.

No production data or official service identifiers are required for these tests.
