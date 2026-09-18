import { createHash, verify } from "node:crypto";
import { lstat, readdir, readFile, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const allowedLicenses = new Set(["0BSD", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "BlueOak-1.0.0", "CC0-1.0", "ISC", "MIT", "Unlicense"]);
const severityRank = new Map([["none", 0], ["low", 1], ["medium", 2], ["high", 3], ["critical", 4]]);
const sha256 = bytes => createHash("sha256").update(bytes).digest("hex");
const parseDate = (value, label) => {
  const date = new Date(value);
  if (!value || Number.isNaN(date.valueOf())) throw new Error(`${label} must be a valid timestamp`);
  return date;
};
const cleanText = (value, label) => {
  if (typeof value !== "string" || !value.trim() || /[\u0000-\u001f]/.test(value)) throw new Error(`${label} is required`);
  return value.trim();
};

function verifyEnvelope(bytes, envelope, publicKey) {
  return envelope?.format === "performance-tracker-release-signature-v1"
    && envelope.algorithm === "Ed25519"
    && envelope.manifestSha256 === sha256(bytes)
    && verify(null, bytes, publicKey, Buffer.from(envelope.signature ?? "", "base64"));
}

function componentLicenses(component) {
  if (!Array.isArray(component.licenses) || component.licenses.length === 0) return [];
  return component.licenses.map(item => item?.license?.id ?? item?.license?.name).filter(value => typeof value === "string" && value.trim()).map(value => value.trim());
}

async function loadWaivers(directory, publicKey, sbomDigest, now) {
  const waivers = [];
  if (!directory) return waivers;
  const directoryStat = await lstat(directory);
  if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) throw new Error("Regular waiver directory required");
  for (const name of (await readdir(directory)).filter(name => name.endsWith(".json") && !name.endsWith(".sig.json")).sort()) {
    const path = join(directory, name);
    const signaturePath = `${path.slice(0, -5)}.sig.json`;
    for (const evidencePath of [path, signaturePath]) {
      const stat = await lstat(evidencePath);
      if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(`Regular waiver evidence required: ${name}`);
    }
    const bytes = await readFile(path);
    const signatureBytes = await readFile(signaturePath);
    const value = JSON.parse(bytes);
    if (!verifyEnvelope(bytes, JSON.parse(signatureBytes), publicKey)) throw new Error(`Invalid waiver signature: ${name}`);
    if (value.format !== "performance-tracker-dependency-waiver-v1" || !["VULNERABILITY", "LICENSE"].includes(value.type)) throw new Error(`Invalid waiver schema: ${name}`);
    for (const field of ["target", "bomRef", "owner", "justification", "mitigation"]) cleanText(value[field], `Waiver ${name} ${field}`);
    if (value.sbomSha256 !== sbomDigest) throw new Error(`Waiver is not bound to this SBOM: ${name}`);
    const expiry = parseDate(value.expiresAt, `Waiver ${name} expiry`);
    if (expiry <= now) throw new Error(`Waiver has expired: ${name}`);
    waivers.push({ ...value, file: basename(path), sha256: sha256(bytes), signatureSha256: sha256(signatureBytes) });
  }
  return waivers;
}

export async function verifyRuntimeDependencyPolicy({ sbomPath, scanPath, waiverDirectory, waiverPublicKeyPath, outputPath, now = new Date() }) {
  const sbomBytes = await readFile(sbomPath);
  const scanBytes = await readFile(scanPath);
  const sbom = JSON.parse(sbomBytes);
  const scan = JSON.parse(scanBytes);
  const sbomDigest = sha256(sbomBytes);
  if (sbom.bomFormat !== "CycloneDX" || sbom.specVersion !== "1.6" || !Array.isArray(sbom.components)) throw new Error("CycloneDX 1.6 runtime SBOM required");
  if (scan.format !== "performance-tracker-runtime-vulnerability-scan-v1" || scan.sbomSha256 !== sbomDigest || !Array.isArray(scan.vulnerabilities)) throw new Error("Vulnerability scan is not bound to this SBOM");
  cleanText(scan.scanner?.name, "Scanner name"); cleanText(scan.scanner?.version, "Scanner version");
  const scannedAt = parseDate(scan.scannedAt, "Scan timestamp");
  const databaseUpdatedAt = parseDate(scan.scanner?.databaseUpdatedAt, "Vulnerability database timestamp");
  const age = now - scannedAt;
  const databaseAge = now - databaseUpdatedAt;
  if (age < 0 || age > 24 * 60 * 60 * 1000) throw new Error("Vulnerability scan must be no more than 24 hours old");
  if (databaseAge < 0 || databaseAge > 7 * 24 * 60 * 60 * 1000) throw new Error("Vulnerability database must be no more than 7 days old");
  const components = new Map();
  for (const component of sbom.components) {
    const ref = cleanText(component["bom-ref"], "Component bom-ref");
    if (components.has(ref)) throw new Error(`Duplicate component bom-ref: ${ref}`);
    components.set(ref, component);
  }
  let publicKey;
  if (waiverDirectory) {
    const keyStat = await lstat(waiverPublicKeyPath);
    if (!keyStat.isFile() || keyStat.isSymbolicLink()) throw new Error("Regular waiver public key required");
    publicKey = await readFile(waiverPublicKeyPath);
  }
  const waivers = await loadWaivers(waiverDirectory, publicKey, sbomDigest, now);
  const used = new Set();
  const findWaiver = (type, target, bomRef) => {
    const matches = waivers.filter(item => item.type === type && item.target === target && item.bomRef === bomRef);
    if (matches.length > 1) throw new Error(`Multiple waivers match ${type} ${target} ${bomRef}`);
    if (matches[0]) used.add(matches[0].file);
    return matches[0];
  };
  const blocked = [];
  const seenFindings = new Set();
  for (const finding of scan.vulnerabilities) {
    const id = cleanText(finding.id, "Vulnerability ID");
    const bomRef = cleanText(finding.bomRef, `Vulnerability ${id} bom-ref`);
    const severity = String(finding.severity ?? "").toLowerCase();
    if (!components.has(bomRef)) throw new Error(`Vulnerability references an unknown component: ${bomRef}`);
    if (!severityRank.has(severity)) throw new Error(`Invalid vulnerability severity: ${id}`);
    const key = `${id}\0${bomRef}`;
    if (seenFindings.has(key)) throw new Error(`Duplicate vulnerability finding: ${id}`);
    seenFindings.add(key);
    if (severityRank.get(severity) >= severityRank.get("high") && !findWaiver("VULNERABILITY", id, bomRef)) blocked.push(`vulnerability ${id} (${severity}) in ${bomRef}`);
  }
  for (const [bomRef, component] of components) {
    const licenses = componentLicenses(component);
    if (licenses.length === 1 && allowedLicenses.has(licenses[0])) continue;
    const target = licenses.length ? licenses.join(" OR ") : "UNDECLARED";
    if (!findWaiver("LICENSE", target, bomRef)) blocked.push(`license ${target} in ${bomRef}`);
  }
  const unused = waivers.filter(item => !used.has(item.file));
  if (unused.length) throw new Error(`Unused waiver rejected: ${unused[0].file}`);
  if (blocked.length) throw new Error(`Dependency policy blocked release: ${blocked.join("; ")}`);
  const evidence = {
    format: "performance-tracker-runtime-dependency-policy-v1",
    status: "PASS",
    sbomSha256: sbomDigest,
    vulnerabilityScanSha256: sha256(scanBytes),
    evaluatedAt: now.toISOString(),
    scanner: scan.scanner,
    componentCount: components.size,
    vulnerabilityCount: scan.vulnerabilities.length,
    waivers: waivers.map(({ file, sha256, signatureSha256, type, target, bomRef, owner, expiresAt }) => ({ file, sha256, signatureSha256, type, target, bomRef, owner, expiresAt })),
  };
  await writeFile(outputPath, `${JSON.stringify(evidence, null, 2)}\n`, { flag: "wx" });
  return evidence;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [sbomPath, scanPath, waiverDirectory, waiverPublicKeyPath, outputPath] = process.argv.slice(2);
  if (!sbomPath || !scanPath || !outputPath) throw new Error("Usage: <sbom> <vulnerability-scan> <waiver-directory-or-> <waiver-public-key-or-> <output>");
  const useWaivers = waiverDirectory !== "-";
  if (useWaivers && (!waiverPublicKeyPath || waiverPublicKeyPath === "-")) throw new Error("Waiver public key required");
  console.log(JSON.stringify(await verifyRuntimeDependencyPolicy({ sbomPath, scanPath, waiverDirectory: useWaivers ? waiverDirectory : undefined, waiverPublicKeyPath: useWaivers ? waiverPublicKeyPath : undefined, outputPath })));
}
