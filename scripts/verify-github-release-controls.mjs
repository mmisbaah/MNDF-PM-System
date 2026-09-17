import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const enabled = (value) => value?.enabled === true;

export function validateReleaseControls(policy, protection, signatures) {
  const failures = [];
  const checks = new Set([
    ...(protection.required_status_checks?.contexts ?? []),
    ...(protection.required_status_checks?.checks ?? []).map((item) => item.context),
  ]);
  const reviews = protection.required_pull_request_reviews;

  if (policy.requireStrictStatusChecks && protection.required_status_checks?.strict !== true) {
    failures.push("required status checks are not strict");
  }
  for (const required of policy.requiredStatusChecks) {
    if (!checks.has(required)) failures.push(`missing required status check: ${required}`);
  }
  if (policy.enforceAdministrators && !enabled(protection.enforce_admins)) {
    failures.push("administrators can bypass branch protection");
  }
  if (!reviews) {
    failures.push("pull-request reviews are not required");
  } else {
    if ((reviews.required_approving_review_count ?? 0) < policy.minimumApprovingReviews) {
      failures.push(`fewer than ${policy.minimumApprovingReviews} approving reviews are required`);
    }
    if (policy.dismissStaleReviews && reviews.dismiss_stale_reviews !== true) {
      failures.push("stale approvals are not dismissed");
    }
    if (policy.requireLastPushApproval && reviews.require_last_push_approval !== true) {
      failures.push("the last push does not require approval by another reviewer");
    }
  }

  const booleanRules = [
    ["requireConversationResolution", "required_conversation_resolution", "conversation resolution is not required"],
    ["requireLinearHistory", "required_linear_history", "linear history is not required"],
  ];
  for (const [policyKey, responseKey, message] of booleanRules) {
    if (policy[policyKey] && !enabled(protection[responseKey])) failures.push(message);
  }
  if (policy.requireSignedCommits && !enabled(signatures)) failures.push("signed commits are not required");
  if (!policy.allowForcePushes && enabled(protection.allow_force_pushes)) failures.push("force pushes are allowed");
  if (!policy.allowDeletions && enabled(protection.allow_deletions)) failures.push("branch deletion is allowed");
  return failures;
}

async function githubJson(url, token) {
  const response = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "performance-tracker-release-control-verifier",
    },
  });
  if (!response.ok) throw new Error(`GitHub API returned ${response.status} for ${url}`);
  return response.json();
}

async function main() {
  const policyPath = process.argv[2] ?? ".github/release-branch-policy.json";
  const policy = JSON.parse(await readFile(policyPath, "utf8"));
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error("GITHUB_TOKEN with read access to repository administration settings is required");
  if (!/^[^/]+\/[^/]+$/.test(policy.repository) || !policy.branch) throw new Error("Policy repository or branch is invalid");

  const root = `https://api.github.com/repos/${policy.repository}/branches/${encodeURIComponent(policy.branch)}/protection`;
  const protection = await githubJson(root, token);
  const signatures = await githubJson(`${root}/required_signatures`, token);
  const failures = validateReleaseControls(policy, protection, signatures);
  if (failures.length) throw new Error(`Release branch protection failed:\n- ${failures.join("\n- ")}`);
  console.log(JSON.stringify({
    format: "performance-tracker-release-branch-verification-v1",
    status: "PASS",
    repository: policy.repository,
    branch: policy.branch,
    verifiedAt: new Date().toISOString(),
  }));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
