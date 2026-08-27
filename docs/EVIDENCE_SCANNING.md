# Private evidence storage and Microsoft Defender scanning

Evidence is written to `EVIDENCE_STORAGE_ROOT` using a generated tenant/upload identifier, never the supplied filename. The application validates the signature, media type, size, single-page requirement, and SHA-256 digest before recording a pending upload. Pending evidence cannot be submitted as accepted appraisal evidence.

On the Windows pilot host, `scan-evidence-defender.ps1` polls the loopback-only internal queue, verifies the stored SHA-256 digest, invokes Microsoft Defender, and reports `CLEAN`, `INFECTED`, or `FAILED`. Scanner errors are retried with bounded backoff. Infected or integrity-mismatched objects are moved to `EVIDENCE_QUARANTINE_ROOT`.

Configure both roots outside the release/web directories and grant access only to the application/scanner service identity and security administrators. The quarantine directory must not be readable by ordinary application users.

The HTTPS reverse proxy must block `/api/internal/*`; the scanner connects directly to `http://127.0.0.1:3100`. Install the one-minute task with `install-evidence-scan-task.ps1` under the dedicated service identity. Store `EVIDENCE_SCANNER_SECRET` only in the protected environment file.

Before onboarding, confirm Defender real-time protection and signature updates are healthy, upload a harmless single-page test file, observe `PENDING → CLEAN`, and verify that a standard antivirus test signature is quarantined and never becomes attachable. Record the Defender engine/signature versions and test outcome.
