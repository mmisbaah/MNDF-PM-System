import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { lstat, readdir, readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const metadata = new Set(['release-manifest.json', 'release-manifest.sig.json']);
export async function inventory(root, excludeMetadata = true) {
  const files = [];
  async function walk(directory, prefix = '') {
    if (!(await lstat(directory)).isDirectory()) throw new Error('Package directories must not be symbolic links');
    for (const name of (await readdir(directory)).sort()) {
      const relative = prefix + name;
      const path = join(directory, name);
      const stat = await lstat(path);
      if (stat.isSymbolicLink()) throw new Error(`Package symbolic link rejected: ${relative}`);
      if (stat.isDirectory()) { await walk(path, `${relative}/`); continue; }
      if (!stat.isFile()) throw new Error(`Unsupported package entry: ${relative}`);
      if (excludeMetadata && metadata.has(relative)) continue;
      const hash = createHash('sha256');
      for await (const chunk of createReadStream(path)) hash.update(chunk);
      files.push({ path: relative, sha256: hash.digest('hex') });
    }
  }
  await walk(resolve(root));
  return files;
}

async function verifyTree(root, files, required, excludeMetadata) {
  if (!Array.isArray(files) || files.length === 0) throw new Error('Empty package inventory');
  const expected = new Map();
  for (const file of files) {
    if (!file || typeof file.path !== 'string' || file.path.includes('\\') || file.path.includes(':') || file.path.split('/').some(part => !part || part === '.' || part === '..') || (excludeMetadata && metadata.has(file.path)) || expected.has(file.path) || !/^[0-9a-f]{64}$/.test(file.sha256)) throw new Error('Invalid package inventory entry');
    expected.set(file.path, file.sha256);
  }
  if (required.some(path => !expected.has(path))) throw new Error('Required package entry points missing');
  const actual = await inventory(root, excludeMetadata);
  if (actual.length !== expected.size) throw new Error('Package file set differs from signed inventory');
  for (const file of actual) {
    if (expected.get(file.path) !== file.sha256) throw new Error(`Package integrity verification failed: ${file.path}`);
  }
}

export async function verifyPackage(root, manifest, scriptsRoot) {
  if (manifest.format !== 'performance-tracker-release-package-v3' || !/^[0-9a-f]{40}$/.test(manifest.commit)) throw new Error('A version 3 full-package manifest is required');
  if (!scriptsRoot) throw new Error('Release scripts directory required');
  await verifyTree(root, manifest.files, ['server.js', 'package.json', 'sbom.cdx.json'], true);
  await verifyTree(scriptsRoot, manifest.scripts, ['start-production.ps1', 'application-log-redaction.ps1', 'validate-production-env.mjs'], false);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [command, root, scriptsRoot, commit] = process.argv.slice(2);
  if (!root || !scriptsRoot) throw new Error('Usage: create <standalone> <release-scripts> <commit> | verify <standalone> <release-scripts>');
  const manifestPath = join(root, 'release-manifest.json');
  if (command === 'create') {
    if (!/^[0-9a-f]{40}$/.test(commit ?? '')) throw new Error('Full Git commit required');
    const manifest = { format: 'performance-tracker-release-package-v3', commit, preparedAt: new Date().toISOString(), files: await inventory(root), scripts: await inventory(scriptsRoot, false) };
    await verifyPackage(root, manifest, scriptsRoot);
    await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  } else if (command === 'verify') {
    await verifyPackage(root, JSON.parse(await readFile(manifestPath, 'utf8')), scriptsRoot);
  } else throw new Error('Command must be create or verify');
  console.log(`Full package integrity ${command} succeeded`);
}
