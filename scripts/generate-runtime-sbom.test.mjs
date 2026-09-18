import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createRuntimeSbom } from "./generate-runtime-sbom.mjs";

test("creates a deterministic, path-free runtime CycloneDX inventory", async () => {
  const fixture = await mkdtemp(join(tmpdir(), "tracker-sbom-"));
  try {
    await mkdir(join(fixture, "node_modules", "example"), { recursive: true });
    await writeFile(join(fixture, "package.json"), JSON.stringify({ name: "performance-tracker", version: "0.1.0" }));
    await writeFile(join(fixture, "node_modules", "example", "package.json"), JSON.stringify({ name: "example", version: "1.2.3", license: "MIT" }));
    const result = await createRuntimeSbom(fixture, "a".repeat(40));
    assert.equal(result.components, 1);
    const text = await readFile(result.output, "utf8");
    const sbom = JSON.parse(text);
    assert.equal(sbom.bomFormat, "CycloneDX");
    assert.equal(sbom.specVersion, "1.6");
    assert.equal(sbom.components[0].name, "example");
    assert.equal(sbom.components[0].licenses[0].license.name, "MIT");
    assert.equal(text.includes(fixture), false);
    await assert.rejects(createRuntimeSbom(fixture, "a".repeat(40)), /EEXIST/);
  } finally { await rm(fixture, { recursive: true, force: true }); }
});

test("rejects linked dependency input", async () => {
  const fixture = await mkdtemp(join(tmpdir(), "tracker-sbom-link-"));
  const outside = await mkdtemp(join(tmpdir(), "tracker-sbom-outside-"));
  try {
    await writeFile(join(fixture, "package.json"), JSON.stringify({ name: "performance-tracker", version: "0.1.0" }));
    await writeFile(join(outside, "package.json"), JSON.stringify({ name: "outside", version: "1.0.0" }));
    await mkdir(join(fixture, "node_modules"));
    await symlink(outside, join(fixture, "node_modules", "outside"), process.platform === "win32" ? "junction" : "dir");
    await assert.rejects(createRuntimeSbom(fixture, "b".repeat(40)), /symbolic link rejected/);
  } finally {
    await rm(fixture, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
