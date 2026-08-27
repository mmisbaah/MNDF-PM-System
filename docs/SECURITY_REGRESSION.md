# Deployment security regression

`npm run security:regression` exercises the running application as an external client. It verifies security headers, minimal health disclosure, denial of sensitive paths, anonymous API protection, internal-service credential checks, same-origin enforcement, safe malformed-request handling, and exclusion of API data from the service-worker cache.

The full release gate also supplies a dedicated, non-MFA, least-privileged acceptance account. With `ACCEPTANCE_LOGIN_ID` and `ACCEPTANCE_PASSWORD` set, the suite additionally verifies authentication-cookie flags, protected tenant access, denial of administrative writes, refresh-token rotation, and refresh-token replay rejection. These credentials must belong only to the disposable release-gate database and must never be a real user or privileged account.

Run an anonymous local check with:

```powershell
$env:SECURITY_BASE_URL = "http://127.0.0.1:3100"
npm run security:regression
```

Deployment authorization requires `scripts/release-gate.ps1` without `-CodeOnly`; the anonymous-only mode is diagnostic and does not replace the authenticated gate.
