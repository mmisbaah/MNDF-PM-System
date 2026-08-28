# HTTPS and reverse-proxy boundary

The Next.js process listens only on `127.0.0.1:3100`. Authorized clients reach Performance Tracker through an organization-controlled HTTPS reverse proxy. PostgreSQL and the Next.js port must not be exposed to client networks or the public Internet.

Start from `deploy/Caddyfile.example`, replace the hostname, and use either an organization-issued certificate or Caddy's internal CA with its root certificate installed on every approved device. HTTP must redirect to HTTPS. The proxy must suppress its `Server` header, publish HSTS for at least one year, and return `404` for `/api/internal/*` without forwarding those requests.

Set `PRODUCTION_PUBLIC_URL` to the HTTPS origin. Before release, run:

```powershell
$env:PRODUCTION_PUBLIC_URL = "https://tracker.organization.example"
npm run tls:verify
```

The verifier fails closed when the certificate is untrusted, hostname validation fails, TLS is older than 1.2, the certificate has fewer than `TLS_MIN_CERTIFICATE_DAYS` remaining, HTTP does not redirect to the same HTTPS host, HSTS is insufficient, the server header leaks, or an internal route is externally reachable. The attended release gate runs this automatically against `-AcceptanceBaseUrl`.

Also enforce host firewall rules: clients may reach only the proxy's HTTPS port; only the proxy host may reach the loopback application port; PostgreSQL is restricted to the application/operations hosts. Record the firewall review and certificate renewal owner in the operational-readiness evidence.
