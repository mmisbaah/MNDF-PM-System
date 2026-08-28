# Production secrets management

## Initial custody

Generate the environment file only on the organization-controlled host with `initialize-production-secrets.ps1`, while signed in as an authorized deployment administrator. The service identity receives read access; the named deployment-administrator group and invoking authorized operator receive full control; inherited access is removed. Database roles and passwords are provisioned separately by the database administrator and must be unique. Keep the environment file outside the repository, release directories, web root, logs, backups intended for application data, and support attachments.

Record only the secret name, custodian, creation date, next review date, and last rotation result. Never record values in tickets or readiness JSON. Back up the protected configuration only through the organization’s approved secrets-custody mechanism.

## Rotation classes

- `AUTH_JWT_SECRET`: rotate at least annually and after suspected disclosure. Rotation invalidates all sessions; announce a maintenance window and require sign-in again.
- Worker, scanner, monitor, and audit HMAC secrets: rotate at least annually, when the associated service identity changes, or after suspected disclosure. Update the protected file and its single dependent scheduled task together while user-facing service is in maintenance mode. Preserve retired audit HMAC keys in approved offline custody, labelled with their validity period, so historical sealed exports remain independently verifiable.
- Runtime and audit database passwords: rotate through the database administrator. Update and validate the protected file before revoking the old credential. The application and audit exporter must use different values.
- `MFA_ENCRYPTION_KEY`: do not replace directly. It encrypts enrolled MFA secrets. Rotation requires an approved application migration that decrypts with the old key, re-encrypts with the new key, verifies every record, and retains a controlled rollback key until acceptance is signed.

For any rotation, take a verified configuration-custody backup, stop affected services, change one secret class, run `validate-production-env.mjs`, restart only affected services, exercise their health check, and record the result. A failed validation or health check requires rollback; never weaken validation to complete a rotation.

## Incident response

Treat accidental console output, source-control inclusion, support-ticket inclusion, unauthorized file access, or unexplained authentication failures as suspected disclosure. Preserve audit and host evidence, contain the affected service, rotate the exposed class, invalidate sessions where applicable, verify dependent tasks, and follow `MONITORING_AND_INCIDENT_RESPONSE.md`.
