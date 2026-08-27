import assert from "node:assert/strict";

const baseUrl = (process.env.SECURITY_BASE_URL || process.env.ACCEPTANCE_BASE_URL || "http://127.0.0.1:3100").replace(/\/$/, "");
const origin = new URL(baseUrl).origin;
const checks = [];

function pass(name) { checks.push({ name, status: "PASS" }); }
function assertNoSensitiveLeak(body, label) {
  assert.doesNotMatch(body, /postgres(?:ql)?:\/\/|password_hash|AUTH_JWT_SECRET|MFA_ENCRYPTION_KEY|GRIEVANCE_CRON_SECRET|EVIDENCE_SCANNER_SECRET|OPERATIONS_MONITOR_SECRET|AUDIT_EXPORT_HMAC_KEY/i, `${label} leaked sensitive implementation data`);
}
function assertNoStackTrace(body, label) {
  assert.doesNotMatch(body, /(?:at\s+[^\n]+\.(?:ts|tsx|js|mjs):\d+)|node_modules[\\/]/i, `${label} leaked a stack trace`);
}

function createClient(initial = new Map()) {
  const jar = new Map(initial);
  return {
    jar,
    async request(path, init = {}) {
      const headers = new Headers(init.headers);
      if (jar.size) headers.set("cookie", [...jar].map(([key, value]) => `${key}=${value}`).join("; "));
      const response = await fetch(`${baseUrl}${path}`, { ...init, headers, redirect: "manual" });
      const setCookies = typeof response.headers.getSetCookie === "function"
        ? response.headers.getSetCookie()
        : [response.headers.get("set-cookie")].filter(Boolean);
      for (const entry of setCookies) {
        const pair = entry.split(";", 1)[0];
        const separator = pair.indexOf("=");
        if (separator > 0) {
          const name = pair.slice(0, separator);
          const value = pair.slice(separator + 1);
          if (value) jar.set(name, value); else jar.delete(name);
        }
      }
      return { response, body: await response.text(), setCookies };
    },
  };
}

const anonymous = createClient();
const home = await anonymous.request("/");
assert.equal(home.response.status, 200);
for (const [header, expected] of [
  ["x-content-type-options", "nosniff"],
  ["x-frame-options", "DENY"],
  ["referrer-policy", "no-referrer"],
  ["cross-origin-opener-policy", "same-origin"],
  ["cross-origin-resource-policy", "same-origin"],
]) assert.equal(home.response.headers.get(header), expected, `${header} header`);
pass("browser security headers");

for (const path of ["/.env", "/.git/config", "/package.json", "/storage/evidence", "/server.js.map"]) {
  const result = await anonymous.request(path);
  assert.ok([404, 403].includes(result.response.status), `${path} must not be public`);
  assertNoSensitiveLeak(result.body, path);
}
pass("sensitive paths are not publicly served");

const health = await anonymous.request("/api/health");
assert.ok([200, 500].includes(health.response.status));
assertNoSensitiveLeak(health.body, "health response");
const healthBody = JSON.parse(health.body);
assert.deepEqual(Object.keys(healthBody), ["ok"], "public health response must remain minimal");
assert.equal(typeof healthBody.ok, "boolean");
pass("minimal public health disclosure");

for (const path of ["/api/workspace", "/api/personnel", "/api/organization/nodes", "/api/reports/operational", "/api/appraisals"]) {
  const result = await anonymous.request(path);
  assert.equal(result.response.status, 401, `${path} must reject anonymous access`);
  assertNoSensitiveLeak(result.body, path);
  assertNoStackTrace(result.body, path);
}
pass("anonymous protected-resource denial");

for (const [method, path] of [
  ["POST", "/api/internal/scheduled-jobs"],
  ["GET", "/api/internal/evidence-scan"],
  ["GET", "/api/internal/operations-health"],
]) {
  for (const authorization of [undefined, "Bearer invalid-regression-secret"]) {
    const headers = authorization ? { authorization } : {};
    const result = await anonymous.request(path, { method, headers });
    assert.ok([401, 404].includes(result.response.status), `${path} must reject or conceal an invalid internal credential`);
    assertNoSensitiveLeak(result.body, path);
    if (result.response.status !== 404) assertNoStackTrace(result.body, path);
  }
}
pass("internal service credential boundaries");

for (const path of ["/api/auth/login", "/api/auth/refresh", "/api/auth/logout"]) {
  const result = await anonymous.request(path, {
    method: "POST",
    headers: { origin: "https://untrusted.invalid", "content-type": "application/json" },
    body: path.endsWith("login") ? JSON.stringify({ email: "nobody@example.invalid", password: "invalid" }) : undefined,
  });
  assert.equal(result.response.status, 403, `${path} must reject a cross-origin mutation`);
  assertNoSensitiveLeak(result.body, path);
  assertNoStackTrace(result.body, path);
}
pass("same-origin enforcement for every authentication mutation");

const malformed = await anonymous.request("/api/auth/login", {
  method: "POST",
  headers: { origin, "content-type": "application/json" },
  body: "{",
});
assert.equal(malformed.response.status, 400);
assertNoSensitiveLeak(malformed.body, "malformed login response");
assertNoStackTrace(malformed.body, "malformed login response");
pass("malformed-request fail-safe response");

const worker = await anonymous.request("/sw.js");
assert.equal(worker.response.status, 200);
assert.match(worker.body, /url\.pathname\.startsWith\("\/api\/"\)\) return/);
assert.doesNotMatch(worker.body.match(/SHELL_ASSETS\s*=\s*\[([^\]]*)\]/)?.[1] || "", /\/api\//);
pass("service worker excludes private API data");

const loginId = process.env.ACCEPTANCE_LOGIN_ID;
const password = process.env.ACCEPTANCE_PASSWORD;
if (loginId || password) {
  assert.ok(loginId && password, "ACCEPTANCE_LOGIN_ID and ACCEPTANCE_PASSWORD must be supplied together");
  const authenticated = createClient();
  const login = await authenticated.request("/api/auth/login", {
    method: "POST",
    headers: { origin, "content-type": "application/json" },
    body: JSON.stringify({ email: loginId, password }),
  });
  assert.equal(login.response.status, 200, "security account must be non-MFA and have no pending password change");
  assert.equal(JSON.parse(login.body).next, "AUTHENTICATED");
  for (const cookie of login.setCookies) {
    assert.match(cookie, /;\s*HttpOnly/i, "authentication cookies must be HttpOnly");
    assert.match(cookie, /;\s*SameSite=Strict/i, "authentication cookies must use SameSite=Strict");
    if (baseUrl.startsWith("https://")) assert.match(cookie, /;\s*Secure/i, "HTTPS authentication cookies must be Secure");
  }
  assert.ok(authenticated.jar.has("mndf_access") && authenticated.jar.has("mndf_refresh"), "login must issue access and refresh cookies");

  for (const [path, body] of [
    ["/api/personnel", {}],
    ["/api/organization/nodes", {}],
    ["/api/templates", {}],
  ]) {
    const result = await authenticated.request(path, {
      method: "POST",
      headers: { origin, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    assert.equal(result.response.status, 403, `${path} must deny the unprivileged acceptance account`);
    assertNoSensitiveLeak(result.body, path);
  }
  pass("authenticated least-privilege boundary");

  const beforeRefresh = new Map(authenticated.jar);
  const refresh = await authenticated.request("/api/auth/refresh", { method: "POST", headers: { origin } });
  assert.equal(refresh.response.status, 200);
  assert.notEqual(authenticated.jar.get("mndf_refresh"), beforeRefresh.get("mndf_refresh"), "refresh token must rotate");
  const replay = await createClient(beforeRefresh).request("/api/auth/refresh", { method: "POST", headers: { origin } });
  assert.equal(replay.response.status, 401, "a rotated refresh token must not be reusable");
  pass("refresh rotation and replay denial");
} else {
  console.warn("Authenticated checks skipped: provide the dedicated ACCEPTANCE_LOGIN_ID and ACCEPTANCE_PASSWORD in the full release gate.");
}

console.table(checks);
console.log(`Security regression passed: ${checks.length}/${checks.length}`);
