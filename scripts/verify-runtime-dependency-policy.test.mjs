import test from "node:test";
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { verifyRuntimeDependencyPolicy } from "./verify-runtime-dependency-policy.mjs";

const hash = bytes => createHash("sha256").update(bytes).digest("hex");
async function setup(run) {
  const root = await mkdtemp(join(tmpdir(), "tracker-policy-"));
  try {
    const sbomPath = join(root, "sbom.json");
    const scanPath = join(root, "scan.json");
    const outputPath = join(root, "policy.json");
    const waiverDirectory = join(root, "waivers"); await mkdir(waiverDirectory);
    const keys = generateKeyPairSync("ed25519");
    const publicKeyPath = join(root, "public.pem");
    await writeFile(publicKeyPath, keys.publicKey.export({ type: "spki", format: "pem" }));
    const now = new Date("2026-09-18T04:00:00.000Z");
    const sbom = { bomFormat: "CycloneDX", specVersion: "1.6", components: [
      { "bom-ref": "npm:safe@1.0.0", licenses: [{ license: { name: "MIT" } }] },
      { "bom-ref": "npm:risky@2.0.0", licenses: [{ license: { name: "GPL-3.0-only" } }] },
    ] };
    const sbomBytes = Buffer.from(`${JSON.stringify(sbom)}\n`); await writeFile(sbomPath, sbomBytes);
    const scan = { format: "performance-tracker-runtime-vulnerability-scan-v1", sbomSha256: hash(sbomBytes), scannedAt: "2026-09-18T03:30:00.000Z", scanner: { name: "fixture-scanner", version: "1.0.0", databaseUpdatedAt: "2026-09-17T00:00:00.000Z" }, vulnerabilities: [{ id: "CVE-TEST-1", bomRef: "npm:risky@2.0.0", severity: "high" }] };
    await writeFile(scanPath, `${JSON.stringify(scan)}\n`);
    const addWaiver = async (name, type, target) => {
      const value = { format: "performance-tracker-dependency-waiver-v1", type, target, bomRef: "npm:risky@2.0.0", owner: "Security Owner", justification: "Accepted for the limited pilot", mitigation: "Network isolation and monitoring", expiresAt: "2026-10-01T00:00:00.000Z", sbomSha256: hash(sbomBytes) };
      const bytes = Buffer.from(`${JSON.stringify(value)}\n`); const path = join(waiverDirectory, `${name}.json`);
      await writeFile(path, bytes);
      await writeFile(join(waiverDirectory, `${name}.sig.json`), `${JSON.stringify({ format: "performance-tracker-release-signature-v1", algorithm: "Ed25519", manifestSha256: hash(bytes), signature: sign(null, bytes, keys.privateKey).toString("base64") })}\n`);
    };
    await run({ sbomPath, scanPath, outputPath, waiverDirectory, publicKeyPath, now, addWaiver });
  } finally { await rm(root, { recursive: true, force: true }); }
}

test("accepts fresh exact scan with signed, unexpired vulnerability and license waivers", async () => setup(async context => {
  await context.addWaiver("vulnerability", "VULNERABILITY", "CVE-TEST-1");
  await context.addWaiver("license", "LICENSE", "GPL-3.0-only");
  const result = await verifyRuntimeDependencyPolicy({ ...context, waiverPublicKeyPath: context.publicKeyPath });
  assert.equal(result.status, "PASS"); assert.equal(result.waivers.length, 2);
  assert.equal(JSON.parse(await readFile(context.outputPath, "utf8")).status, "PASS");
}));

test("fails closed for unwaived risk, stale evidence, tampering, and unused waivers", async () => setup(async context => {
  await assert.rejects(verifyRuntimeDependencyPolicy({ ...context, waiverPublicKeyPath: context.publicKeyPath }), /blocked release/);
  await context.addWaiver("unused", "VULNERABILITY", "CVE-NOT-PRESENT");
  await assert.rejects(verifyRuntimeDependencyPolicy({ ...context, waiverPublicKeyPath: context.publicKeyPath }), /Unused waiver/);
  const scan = JSON.parse(await readFile(context.scanPath, "utf8")); scan.scannedAt = "2026-09-10T00:00:00.000Z"; await writeFile(context.scanPath, `${JSON.stringify(scan)}\n`);
  await assert.rejects(verifyRuntimeDependencyPolicy({ ...context, waiverPublicKeyPath: context.publicKeyPath }), /24 hours/);
}));

test("rejects a tampered waiver signature", async () => setup(async context => {
  await context.addWaiver("vulnerability", "VULNERABILITY", "CVE-TEST-1");
  await writeFile(join(context.waiverDirectory, "vulnerability.sig.json"), "{}\n");
  await assert.rejects(verifyRuntimeDependencyPolicy({ ...context, waiverPublicKeyPath: context.publicKeyPath }), /Invalid waiver signature/);
}));
