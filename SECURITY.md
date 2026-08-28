# Security policy

## Reporting a vulnerability

Do not create a public issue containing a suspected vulnerability, credential, MFA secret, personal record, appraisal content, evidence, restricted comment, database URL, host address, or configuration file.

Report the issue privately to the organization’s designated Technical Operator and incident coordinator. Include only the affected version or commit, feature or route, reproduction steps using dummy data, observed impact, and safe diagnostic output. Do not include production records.

The incident coordinator must acknowledge critical reports within one hour, high-severity reports within four hours, and other reports within one working day. Follow the containment and evidence-preservation procedure in `docs/MONITORING_AND_INCIDENT_RESPONSE.md`.

## Supported versions

Only the currently approved production release is supported. Security fixes are applied to the release-candidate branch, pass the complete release gate, and are promoted through the documented rollback-capable deployment procedure. Dependencies and workflow actions are updated through reviewed pull requests; automated updates are never deployed without the same gates as application changes.
