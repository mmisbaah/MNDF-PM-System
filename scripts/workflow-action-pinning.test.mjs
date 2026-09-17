import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

const workflowDirectory = join(process.cwd(), ".github", "workflows");
const workflowFiles = ["code-gate.yml", "codeql.yml"];
const externalUse = /^\s*(?:-\s*)?uses:\s*([^\s#]+)(?:\s+#.*)?$/gm;
const pinnedAction = /^[^./][^@\s]*@[0-9a-f]{40}$/;

test("third-party workflow actions are pinned to immutable commits", () => {
  const violations = [];

  for (const file of workflowFiles) {
    const source = readFileSync(join(workflowDirectory, file), "utf8");
    for (const match of source.matchAll(externalUse)) {
      const reference = match[1];
      if (!reference.startsWith("./") && !pinnedAction.test(reference)) {
        const line = source.slice(0, match.index).split("\n").length;
        violations.push(`${file}:${line} ${reference}`);
      }
    }
  }

  assert.deepEqual(
    violations,
    [],
    `Mutable or malformed GitHub Action references:\n${violations.join("\n")}`,
  );
});
