import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const file = process.argv[2] || process.env.OPERATIONAL_READINESS_RECORD;
assert.ok(file, "Operational readiness record path is required");
const record = JSON.parse(await readFile(resolve(file), "utf8"));
const requiredScenarios = new Set([
  "MFA_ENROLLMENT",
  "ADMIN_AUTHORIZATION",
  "AUTHORIZER_HANDOVER",
  "FULL_APPRAISAL_GRIEVANCE_CORRECTION",
  "MOBILE_USABILITY",
  "EVIDENCE_QUARANTINE",
  "BACKUP_RESTORE",
]);

function requiredText(value, label) {
  assert.equal(typeof value, "string", `${label} is required`);
  const text = value.trim();
  assert.ok(text.length >= 2, `${label} is required`);
  assert.doesNotMatch(text, /replace[ _-]?me|tbd|todo|placeholder/i, `${label} still contains a placeholder`);
}

assert.equal(record.format, "performance-tracker-operational-readiness-v1");
requiredText(record.organizationName, "organizationName");
assert.equal(record.expectedPilotUsers, 40, "the v1 pilot expects exactly 40 users");
assert.ok(Number.isInteger(record.trainedUsers) && record.trainedUsers >= record.expectedPilotUsers, "all expected pilot users must complete training");

for (const field of ["systemAuthorizer", "systemAdministratorOperator", "technicalOperator", "incidentCoordinator"]) {
  requiredText(record.accountability?.[field], `accountability.${field}`);
}
for (const field of ["primary", "alternate", "afterHoursProcedure"]) {
  requiredText(record.support?.[field], `support.${field}`);
}

const scenarios = new Map((record.attendedScenarios || []).map((item) => [item.code, item]));
for (const code of requiredScenarios) {
  const scenario = scenarios.get(code);
  assert.ok(scenario, `attended scenario missing: ${code}`);
  assert.equal(scenario.status, "PASS", `attended scenario has not passed: ${code}`);
  requiredText(scenario.evidenceReference, `${code}.evidenceReference`);
}

assert.equal(record.openIncidents?.severity1, 0, "open severity-1 incidents block launch");
assert.equal(record.openIncidents?.severity2, 0, "open severity-2 incidents block launch");
requiredText(record.rollback?.owner, "rollback.owner");
assert.match(record.rollback?.targetCommit || "", /^[0-9a-f]{7,40}$/i, "rollback.targetCommit must be a Git commit");
const rollbackVerifiedAt = new Date(record.rollback?.verifiedAt);
assert.ok(Number.isFinite(rollbackVerifiedAt.getTime()), "rollback.verifiedAt must be an ISO timestamp");
requiredText(record.releaseSigning?.custodian, "releaseSigning.custodian");
assert.match(record.releaseSigning?.publicKeySha256 || "", /^(?!0{64})[0-9a-f]{64}$/i, "releaseSigning.publicKeySha256 must be the independently verified key fingerprint");
const signingKeyVerifiedAt = new Date(record.releaseSigning?.verifiedAt);
assert.ok(Number.isFinite(signingKeyVerifiedAt.getTime()), "releaseSigning.verifiedAt must be an ISO timestamp");
requiredText(record.approval?.systemAuthorizer, "approval.systemAuthorizer");
const approvedAt = new Date(record.approval?.approvedAt);
assert.ok(Number.isFinite(approvedAt.getTime()), "approval.approvedAt must be an ISO timestamp");
const ageDays = (Date.now() - approvedAt.getTime()) / 86_400_000;
assert.ok(ageDays >= 0 && ageDays <= 14, "System Authorizer approval must be no more than 14 days old");

console.log(JSON.stringify({
  status: "PASS",
  organizationName: record.organizationName,
  trainedUsers: record.trainedUsers,
  attendedScenariosPassed: requiredScenarios.size,
  approvedAt: approvedAt.toISOString(),
}, null, 2));
