# Runtime dependency policy

The production decision must be based on the exact `sbom.cdx.json` generated
from the materialized standalone package, not only on the source lockfile.

`verify-runtime-dependency-policy.mjs` accepts a scanner-neutral JSON report that
contains the SHA-256 of that SBOM, scanner name and version, vulnerability database
update time, scan time, and findings identified by CycloneDX `bom-ref`. The scan
must be no more than 24 hours old and its database no more than seven days old.
Unknown components, duplicate findings, malformed severities, stale evidence, and
hash mismatches fail closed.

High and critical vulnerabilities are blocked. Runtime components must declare one
of the explicitly permitted licenses in the verifier. Undeclared, compound, or
unapproved licenses are blocked.

## Exceptions

Each exception is a JSON file with format
`performance-tracker-dependency-waiver-v1` and a sibling `.sig.json` Ed25519
signature made by `release-signing.mjs`. A waiver identifies exactly one finding
type, target, component `bom-ref`, SBOM SHA-256, accountable owner, justification,
mitigation, and expiry timestamp. Expired, invalid, duplicate, mismatched, and
unused waivers are rejected. Use a dedicated security-waiver signing key held
separately from the production release-signing key.

The successful output is
`performance-tracker-runtime-dependency-policy-v1`. It records the exact SBOM and
scan hashes plus the hashes and expiry dates of every accepted waiver. Preserve it
with release evidence. Never edit or reuse it for a different package.
