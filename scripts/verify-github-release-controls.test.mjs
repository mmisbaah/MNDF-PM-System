import assert from "node:assert/strict";
import test from "node:test";
import { validateReleaseControls } from "./verify-github-release-controls.mjs";

const policy = {
  requiredStatusChecks: ["code-gate", "windows-deployment-guards", "Analyze JavaScript and TypeScript"],
  requireStrictStatusChecks: true,
  enforceAdministrators: true,
  minimumApprovingReviews: 1,
  dismissStaleReviews: true,
  requireLastPushApproval: true,
  requireConversationResolution: true,
  requireLinearHistory: true,
  requireSignedCommits: true,
  allowForcePushes: false,
  allowDeletions: false,
};

const protectedBranch = {
  required_status_checks: { strict: true, contexts: policy.requiredStatusChecks },
  enforce_admins: { enabled: true },
  required_pull_request_reviews: {
    required_approving_review_count: 1,
    dismiss_stale_reviews: true,
    require_last_push_approval: true,
  },
  required_conversation_resolution: { enabled: true },
  required_linear_history: { enabled: true },
  allow_force_pushes: { enabled: false },
  allow_deletions: { enabled: false },
};

test("accepts the complete release branch policy", () => {
  assert.deepEqual(validateReleaseControls(policy, protectedBranch, { enabled: true }), []);
});

test("reports every weakened release branch control", () => {
  const weak = structuredClone(protectedBranch);
  weak.required_status_checks = { strict: false, contexts: ["code-gate"] };
  weak.enforce_admins.enabled = false;
  weak.required_pull_request_reviews = null;
  weak.required_conversation_resolution.enabled = false;
  weak.required_linear_history.enabled = false;
  weak.allow_force_pushes.enabled = true;
  weak.allow_deletions.enabled = true;
  const failures = validateReleaseControls(policy, weak, { enabled: false });
  assert.equal(failures.length, 10);
  assert.match(failures.join("\n"), /missing required status check: windows-deployment-guards/);
  assert.match(failures.join("\n"), /signed commits are not required/);
});
