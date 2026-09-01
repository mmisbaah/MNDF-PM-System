# Production secrets management

## Initial custody

Generate the environment file only on the organization-controlled host with `initialize-production-secrets.ps1`, while signed in as an authorized deployment administrator. The service identity receives read access; the named deployment-administrator group and invoking authorized operator receive full control; inherited access is removed. Database roles and passwords are provisioned separately by the database administrator and must be unique. Keep the environment file outside the repository, release directories, web root, logs, backups intended for application data, and support attachments.

Record only the secret name, custodian, creation date, next review date, and last rotation result. Never record values in tickets or readiness JSON. Back up the protected configuration only through the organization’s approved secrets-custody mechanism.

## Protected creation and publication

Provision the configuration folder first using the filesystem ACL procedure.
The initializer refuses missing or redirected parent folders and parent ACLs
that grant write/delete/ownership rights to identities outside the approved
administrator list. SYSTEM and local Administrators are included as custodians.
Review effective group memberships separately; this is not an effective-token
authorization audit.

The temporary file is created with its protected DACL already attached, before
secret bytes are written. The service receives read-only access. Validation runs
against that temporary file; successful validation is followed by a same-folder,
non-overwriting rename. Existing or concurrently created destination files are
never deleted by failure cleanup. Cleanup removes only this invocation's created
temporary file. A host crash may leave a protected `.secret-*.tmp` file for an
authorized custodian to review; do not collect it into diagnostic attachments.

`test-protected-secret-file.ps1` exercises protected staging, existing-file
preservation, validation failure, competing publication, cleanup and unsafe-parent
rejection using dummy content. Run it on Windows PowerShell and PowerShell Core.
No production secrets are needed. These tests do not replace a deployment-host
rehearsal using the actual service identity. Supply database credentials through
the approved secure operator session; avoid literal credentials in saved shell
history, transcripts or command-line automation.

## Rotation classes

### Candidate-file validation

Use `node scripts/validate-production-env.mjs --config-file <protected-file>`
to validate only the file's parsed values. The initializer uses this mode before
publication, so inherited shell credentials cannot mask missing/invalid file
settings. Diagnostics identify fields, not their secret values. A missing file
or invalid command option fails rather than falling back to the shell.

Startup validates both the file alone and the effective environment loaded by
Node. The existing no-argument validator still checks the effective process
environment for operational tooling. Node's normal inherited-variable precedence
has not been changed: two valid but different configurations can still differ.
Review the scheduled service account's environment for unintended overrides.
Run `node --test scripts/validate-production-env.test.mjs` for isolated regression
cases using dummy credentials; no database connection is made.

The initializer quotes environment-file values so `#`, surrounding whitespace,
and Windows path backslashes are not silently changed by Node's environment
loader. It rejects CR/LF/NUL, invalid variable names, and combinations of quotes
or escapes it cannot preserve exactly. For database URLs, percent-encode reserved
punctuation in the username/password components; do not encode the entire URL.
An environment-file quote does not replace URL encoding.

Run `scripts/test-serialize-production-env.ps1` to verify dummy values against
both Node's parser and a real `--env-file` child process. These tests use isolated
child environments and do not load or modify the installation's credentials.
This change affects newly initialized files only; existing environment files
are not rewritten automatically.

- `AUTH_JWT_SECRET`: rotate at least annually and after suspected disclosure. Rotation invalidates all sessions; announce a maintenance window and require sign-in again.
- Worker, scanner, monitor, and audit HMAC secrets: rotate at least annually, when the associated service identity changes, or after suspected disclosure. Update the protected file and its single dependent scheduled task together while user-facing service is in maintenance mode. Preserve retired audit HMAC keys in approved offline custody, labelled with their validity period, so historical sealed exports remain independently verifiable.
- Runtime and audit database passwords: rotate through the database administrator. Update and validate the protected file before revoking the old credential. The application and audit exporter must use different values.
- `MFA_ENCRYPTION_KEY`: do not replace directly. It encrypts enrolled MFA secrets. Rotation requires an approved application migration that decrypts with the old key, re-encrypts with the new key, verifies every record, and retains a controlled rollback key until acceptance is signed.

For any rotation, take a verified configuration-custody backup, stop affected services, change one secret class, run `validate-production-env.mjs`, restart only affected services, exercise their health check, and record the result. A failed validation or health check requires rollback; never weaken validation to complete a rotation.

## Incident response

Treat accidental console output, source-control inclusion, support-ticket inclusion, unauthorized file access, or unexplained authentication failures as suspected disclosure. Preserve audit and host evidence, contain the affected service, rotate the exposed class, invalidate sessions where applicable, verify dependent tasks, and follow `MONITORING_AND_INCIDENT_RESPONSE.md`.
