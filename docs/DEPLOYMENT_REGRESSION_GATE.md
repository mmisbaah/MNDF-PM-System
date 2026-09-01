# Combined Windows deployment regression gate

From an approved PowerShell session at the repository root, run:

```powershell
.\scripts\deployment-regression-gate.ps1
```

Requires Windows and Node.js 22 or newer. Use the organization's approved script
execution/signing policy; this command does not change machine execution policy.
CI runs the same gate in Windows PowerShell and PowerShell Core after provisioning
Node 22. The full attended release gate also requires this suite; CodeOnly does
not imply that Windows checks ran.

Nine check groups cover PowerShell syntax, shutdown guards, deployment journal
history, filesystem ACLs, protected secret publication, environment serialization,
clean-source provenance, package/signature/configuration Node regressions, and the signature self-test.
The gate stops on a thrown error or nonzero native test exit. Its console output
ends with a JSON summary of completed checks, versions and timestamps. It does
not write secrets or a persistent report; retain approved CI/terminal evidence
with the release record.

Tests use disposable temporary files and dummy signing keys/configuration. Task
and listener operations are mocked. No real service is stopped, database is
accessed, or production release is changed. `productionRehearsal: false` explicitly
distinguishes regression success from attended deployment readiness.

A successful local run does not prove CI, the full application build, production
ACLs, installed service identities, live HTTPS, backup restoration or actual
promotion/rollback. Those remain separate requirements in the full release gate.
