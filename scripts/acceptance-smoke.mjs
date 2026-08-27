import assert from "node:assert/strict";

const baseUrl = (process.env.ACCEPTANCE_BASE_URL || "http://localhost:3100").replace(/\/$/, "");
const cookies = new Map();

async function request(path, init) {
  const headers = new Headers(init?.headers);
  if (cookies.size) headers.set("cookie", [...cookies].map(([name, value]) => `${name}=${value}`).join("; "));
  const response = await fetch(`${baseUrl}${path}`, { redirect: "manual", ...init, headers });
  const setCookies = typeof response.headers.getSetCookie === "function" ? response.headers.getSetCookie() : [response.headers.get("set-cookie")].filter(Boolean);
  for (const entry of setCookies) {
    const pair = entry.split(";", 1)[0];
    const separator = pair.indexOf("=");
    if (separator > 0) cookies.set(pair.slice(0, separator), pair.slice(separator + 1));
  }
  return { response, body: await response.text() };
}

const checks = [];
function passed(name) { checks.push({ name, status: "PASS" }); }

const home = await request("/");
assert.equal(home.response.status, 200);
assert.match(home.body, /Performance Tracker/);
for (const [name, value] of [
  ["x-frame-options", "DENY"],
  ["x-content-type-options", "nosniff"],
  ["referrer-policy", "no-referrer"],
  ["cross-origin-opener-policy", "same-origin"],
]) {
  assert.equal(home.response.headers.get(name), value, `${name} header`);
}
passed("branded shell and security headers");

const installation = await request("/api/installation");
assert.equal(installation.response.status, 200);
const installationBody = JSON.parse(installation.body);
assert.equal(installationBody.success, true);
assert.equal(installationBody.installation.configured, true);
passed("single-organization installation identity");

const health = await request("/api/health");
assert.equal(health.response.status, 200);
passed("database-backed health endpoint");

for (const path of ["/api/workspace", "/api/personnel", "/api/reports/operational"]) {
  const protectedResult = await request(path);
  assert.equal(protectedResult.response.status, 401, `${path} must reject anonymous access`);
}
passed("protected API authentication boundary");

const crossOrigin = await request("/api/auth/refresh", {
  method: "POST",
  headers: { origin: "https://untrusted.invalid" },
});
assert.equal(crossOrigin.response.status, 403);
passed("cross-origin state-changing request rejection");

const manifest = await request("/manifest.json");
assert.equal(manifest.response.status, 200);
assert.equal(JSON.parse(manifest.body).display, "standalone");
const worker = await request("/sw.js");
assert.equal(worker.response.status, 200);
assert.match(worker.body, /url\.pathname\.startsWith\("\/api\/"\)\) return/,
  "service worker must explicitly bypass API responses");
const shellAssets = worker.body.match(/SHELL_ASSETS\s*=\s*\[([^\]]*)\]/)?.[1] || "";
assert.doesNotMatch(shellAssets, /\/api\//, "API endpoints must not be shell-cache assets");
passed("PWA manifest and API-safe service worker");

const loginId = process.env.ACCEPTANCE_LOGIN_ID;
const password = process.env.ACCEPTANCE_PASSWORD;
if (loginId || password) {
  assert.ok(loginId && password, "ACCEPTANCE_LOGIN_ID and ACCEPTANCE_PASSWORD must be supplied together");
  const login = await request("/api/auth/login", {
    method: "POST",
    headers: { "content-type": "application/json", origin: baseUrl },
    body: JSON.stringify({ email: loginId, password }),
  });
  assert.equal(login.response.status, 200, "acceptance account must authenticate without MFA or a required password change");
  assert.equal(JSON.parse(login.body).next, "AUTHENTICATED");
  const identity = await request("/api/auth/me");
  assert.equal(identity.response.status, 200);
  assert.equal(JSON.parse(identity.body).authenticated, true);
  const workspace = await request("/api/workspace");
  assert.equal(workspace.response.status, 200, "authenticated acceptance account must load its tenant workspace");
  passed("authenticated tenant workspace boundary");
}

console.table(checks);
console.log(`Acceptance smoke passed: ${checks.length}/${checks.length}`);
