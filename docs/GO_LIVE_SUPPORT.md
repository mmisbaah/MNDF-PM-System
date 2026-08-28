# Go-live support and decision governance

The organization must name a primary and alternate support contact, System Authorizer, Administrator operator, Technical Operator, and incident coordinator in the external operational-readiness record. These are accountable appointments or pilot login identities, not shared passwords.

## Severity and response

| Severity | Examples | Initial response target | Required action |
|---|---|---:|---|
| 1 — Critical | tenant isolation concern, restricted-data disclosure, database loss, widespread inability to authenticate | 15 minutes | stop affected access, preserve evidence, notify Authorizer and incident coordinator, consider rollback |
| 2 — High | appraisal approval blocked, deadline worker unavailable, evidence scanning unavailable, backup failure | 1 hour | contain the workflow, restore service, document affected deadlines and recovery |
| 3 — Normal | single-user issue, incorrect placement, usability problem without deadline risk | 1 working day | Administrator correction or planned defect handling |

Support records contain timestamps, route or feature, generic error text, affected pilot login IDs, deployed commit, containment, owner, and status. They must not contain passwords, MFA secrets, evidence, restricted comments, or appraisal narratives.

## Launch and rollback

The System Authorizer may approve launch only when the full release gate reports `PASS`, the operational-readiness validator passes, no severity-1 or severity-2 incident is open, a recent restore rehearsal exists, and a tested rollback commit and owner are recorded. Approval expires after 14 days.

During the first two weeks, review monitoring alerts, deadline jobs, malware scanning, backups, sealed audit exports, login failures, and support cases each day. Roll back when isolation, data integrity, authentication, or deadline processing cannot be safely restored within the applicable response target. Preserve the failed release’s logs and audit exports before rollback.

