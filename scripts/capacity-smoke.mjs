import assert from "node:assert/strict";
import { performance } from "node:perf_hooks";

const baseUrl = (process.env.CAPACITY_BASE_URL || "http://127.0.0.1:3100").replace(/\/$/, "");
const virtualUsers = Number.parseInt(process.env.CAPACITY_VIRTUAL_USERS || "40", 10);
const durationSeconds = Number.parseInt(process.env.CAPACITY_DURATION_SECONDS || "60", 10);
const maximumP95Ms = Number.parseInt(process.env.CAPACITY_MAXIMUM_P95_MS || "3000", 10);
const maximumErrorRate = Number.parseFloat(process.env.CAPACITY_MAXIMUM_ERROR_RATE || "0.01");
const loginId = process.env.ACCEPTANCE_LOGIN_ID;
const password = process.env.ACCEPTANCE_PASSWORD;
const allowAnonymous = process.env.CAPACITY_ALLOW_ANONYMOUS === "true";

assert.ok(Number.isInteger(virtualUsers) && virtualUsers >= 1 && virtualUsers <= 200, "CAPACITY_VIRTUAL_USERS must be between 1 and 200");
assert.ok(Number.isInteger(durationSeconds) && durationSeconds >= 5 && durationSeconds <= 900, "CAPACITY_DURATION_SECONDS must be between 5 and 900");
assert.ok(Number.isFinite(maximumP95Ms) && maximumP95Ms >= 100, "CAPACITY_MAXIMUM_P95_MS is invalid");
assert.ok(Number.isFinite(maximumErrorRate) && maximumErrorRate >= 0 && maximumErrorRate <= 1, "CAPACITY_MAXIMUM_ERROR_RATE is invalid");
assert.ok((loginId && password) || allowAnonymous, "A dedicated ACCEPTANCE_LOGIN_ID and ACCEPTANCE_PASSWORD are required for the deployment capacity gate");

function cookieHeader(setCookies) {
  return setCookies.map((entry) => entry.split(";", 1)[0]).join("; ");
}

async function createSession() {
  if (!loginId || !password) return "";
  const response = await fetch(`${baseUrl}/api/auth/login`, {
    method: "POST",
    headers: { origin: new URL(baseUrl).origin, "content-type": "application/json" },
    body: JSON.stringify({ email: loginId, password }),
  });
  const body = await response.text();
  assert.equal(response.status, 200, "capacity account must authenticate without MFA or a required password change");
  assert.equal(JSON.parse(body).next, "AUTHENTICATED");
  const setCookies = typeof response.headers.getSetCookie === "function"
    ? response.headers.getSetCookie()
    : [response.headers.get("set-cookie")].filter(Boolean);
  const cookie = cookieHeader(setCookies);
  assert.match(cookie, /mndf_access=/, "capacity login did not issue an access cookie");
  return cookie;
}

const sessions = await Promise.all(Array.from({ length: virtualUsers }, () => createSession()));
const authenticatedPaths = ["/api/workspace", "/api/notifications", "/api/auth/me"];
const anonymousPaths = ["/", "/api/health", "/manifest.json"];
const paths = loginId ? authenticatedPaths : anonymousPaths;
const samples = [];
let failures = 0;
let completed = 0;
const deadline = performance.now() + durationSeconds * 1000;

async function worker(index) {
  let requestNo = 0;
  while (performance.now() < deadline) {
    const path = paths[(index + requestNo) % paths.length];
    const started = performance.now();
    try {
      const headers = sessions[index] ? { cookie: sessions[index] } : undefined;
      const response = await fetch(`${baseUrl}${path}`, { headers, redirect: "manual" });
      await response.arrayBuffer();
      samples.push(performance.now() - started);
      completed += 1;
      if (response.status < 200 || response.status >= 400) failures += 1;
    } catch {
      samples.push(performance.now() - started);
      completed += 1;
      failures += 1;
    }
    requestNo += 1;
  }
}

await Promise.all(Array.from({ length: virtualUsers }, (_, index) => worker(index)));
samples.sort((a, b) => a - b);
const percentile = (value) => samples[Math.min(samples.length - 1, Math.ceil(samples.length * value) - 1)] || 0;
const errorRate = completed ? failures / completed : 1;
const result = {
  format: "performance-tracker-capacity-v1",
  mode: loginId ? "AUTHENTICATED" : "ANONYMOUS_DIAGNOSTIC",
  virtualUsers,
  durationSeconds,
  requests: completed,
  failures,
  errorRate: Number(errorRate.toFixed(4)),
  requestsPerSecond: Number((completed / durationSeconds).toFixed(2)),
  latencyMs: {
    p50: Number(percentile(0.5).toFixed(1)),
    p95: Number(percentile(0.95).toFixed(1)),
    p99: Number(percentile(0.99).toFixed(1)),
    maximum: Number((samples.at(-1) || 0).toFixed(1)),
  },
  thresholds: { maximumP95Ms, maximumErrorRate },
};

console.log(JSON.stringify(result, null, 2));
assert.ok(completed >= virtualUsers, "capacity run did not complete at least one request per virtual user");
assert.ok(result.latencyMs.p95 <= maximumP95Ms, `p95 latency ${result.latencyMs.p95}ms exceeded ${maximumP95Ms}ms`);
assert.ok(errorRate <= maximumErrorRate, `error rate ${errorRate} exceeded ${maximumErrorRate}`);
