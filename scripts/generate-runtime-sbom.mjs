import { createHash } from "node:crypto";
import { lstat, readFile, readdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

function licenseValue(value) {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (value && typeof value === "object" && typeof value.type === "string") return value.type.trim();
  if (Array.isArray(value)) return value.map(licenseValue).filter(Boolean).join(" OR ");
  return undefined;
}

export async function createRuntimeSbom(standalonePath, commit, outputPath = join(standalonePath, "sbom.cdx.json")) {
  const root = resolve(standalonePath);
  const output = resolve(outputPath);
  if (!/^[0-9a-f]{40}$/.test(commit)) throw new Error("Full source commit required for SBOM generation");
  const rootStat = await lstat(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new Error("Regular standalone directory required");
  const packages = new Map();

  async function walk(directory, inNodeModules = false) {
    for (const name of (await readdir(directory)).sort()) {
      if (name === "sbom.cdx.json") continue;
      const path = join(directory, name);
      const stat = await lstat(path);
      if (stat.isSymbolicLink()) throw new Error(`SBOM input symbolic link rejected: ${path}`);
      if (stat.isDirectory()) {
        await walk(path, inNodeModules || name === "node_modules");
        continue;
      }
      if (!stat.isFile() || name !== "package.json" || (!inNodeModules && directory !== root)) continue;
      const bytes = await readFile(path);
      const value = JSON.parse(bytes);
      if (typeof value.name !== "string" || typeof value.version !== "string" || !value.name || !value.version) throw new Error(`Package identity missing: ${path}`);
      const key = `${value.name}\0${value.version}`;
      const digest = createHash("sha256").update(bytes).digest("hex");
      const existing = packages.get(key);
      if (existing && existing.hash !== digest) throw new Error(`Conflicting package metadata for ${value.name}@${value.version}`);
      packages.set(key, { name: value.name, version: value.version, license: licenseValue(value.license), hash: digest });
    }
  }
  await walk(root);
  const appBytes = await readFile(join(root, "package.json"));
  const app = JSON.parse(appBytes);
  if (app.name !== "performance-tracker" || typeof app.version !== "string") throw new Error("Standalone application package identity is invalid");
  packages.delete(`${app.name}\0${app.version}`);
  const components = [...packages.values()].sort((a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version)).map((item) => ({
    type: "library",
    "bom-ref": `npm:${item.name}@${item.version}`,
    name: item.name,
    version: item.version,
    hashes: [{ alg: "SHA-256", content: item.hash }],
    ...(item.license ? { licenses: [{ license: { name: item.license } }] } : {}),
  }));
  const document = {
    bomFormat: "CycloneDX",
    specVersion: "1.6",
    version: 1,
    metadata: {
      component: { type: "application", "bom-ref": `application:${app.name}@${app.version}`, name: app.name, version: app.version },
      properties: [{ name: "performance-tracker:source-commit", value: commit }],
    },
    components,
  };
  await writeFile(output, `${JSON.stringify(document, null, 2)}\n`, { flag: "wx" });
  return { components: components.length, output };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [standalone, commit, output] = process.argv.slice(2);
  if (!standalone || !commit) throw new Error("Usage: <standalone-directory> <commit> [output-path]");
  console.log(JSON.stringify(await createRuntimeSbom(standalone, commit, output)));
}
