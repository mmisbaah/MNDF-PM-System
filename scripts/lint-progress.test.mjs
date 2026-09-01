import assert from "node:assert/strict";
import test from "node:test";
import { runWithProgress } from "./lint-progress.mjs";

test("reports elapsed time during synchronous child work and stops reporting on completion", async () => {
  const messages = [];
  const code = await runWithProgress(process.execPath, ["-e", "const end=Date.now()+200;while(Date.now()<end){}"], {
    intervalMs: 25, report: (message) => messages.push(message),
  });
  assert.equal(code, 0);
  assert.ok(messages.some((message) => message.includes("elapsed — ESLint is still running")));
  assert.match(messages.at(-1), /Completed successfully after \d+\.\d+s \(exit 0\)/);
  const count = messages.length;
  await new Promise((done) => setTimeout(done, 60));
  assert.equal(messages.length, count);
});

for (const exitCode of [1, 2]) {
  test(`preserves ESLint exit status ${exitCode}`, async () => {
    const messages = [];
    const code = await runWithProgress(process.execPath, ["-e", `process.exitCode=${exitCode}`], {
      report: (message) => messages.push(message),
    });
    assert.equal(code, exitCode);
    assert.match(messages.at(-1), new RegExp(`Failed after .*exit ${exitCode}`));
  });
}

test("reports launch failures and returns tooling-error status", async () => {
  const messages = [];
  const code = await runWithProgress("performance-tracker-nonexistent-lint-command", [], {
    report: (message) => messages.push(message),
  });
  assert.equal(code, 2);
  assert.ok(messages.some((message) => message.includes("Could not start ESLint")));
});
