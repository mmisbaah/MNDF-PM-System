import { createHash } from 'node:crypto';
import { readFile, writeFile, lstat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { verifyPackage } from './release-integrity.mjs';

export async function checkBuild(project, commit, record = false) {
  if (!/^[0-9a-f]{40}$/.test(commit ?? '')) throw new Error('Full source commit required');
  const next = join(project, '.next');
  if (!(await lstat(next)).isDirectory()) throw new Error('Redirected build directory rejected');
  const standalone = join(next, 'standalone');
  const manifestPath = join(standalone, 'release-manifest.json');
  if (!(await lstat(manifestPath)).isFile()) throw new Error('Redirected manifest rejected');
  const bytes = await readFile(manifestPath);
  const manifest = JSON.parse(bytes);
  if (manifest.commit !== commit) throw new Error('Build commit differs from current source commit; rebuild required');
  await verifyPackage(standalone, manifest, join(project, 'scripts'));
  const manifestSha256 = createHash('sha256').update(bytes).digest('hex');
  const receiptPath = join(next, 'release-build-provenance.json');
  if (record) {
    await writeFile(receiptPath, JSON.stringify({ format: 'performance-tracker-build-provenance-v1', commit, manifestSha256, completedAt: new Date().toISOString() }) + '\n', { flag: 'wx' });
  } else {
    if (!(await lstat(receiptPath)).isFile()) throw new Error('Redirected build receipt rejected');
    const receipt = JSON.parse(await readFile(receiptPath, 'utf8'));
    if (receipt.format !== 'performance-tracker-build-provenance-v1' || receipt.commit !== commit || receipt.manifestSha256 !== manifestSha256) throw new Error('Build receipt does not match source and manifest; rebuild required');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [command, project, commit] = process.argv.slice(2);
  if (!project || !['record', 'verify'].includes(command)) throw new Error('Usage: record|verify <project> <commit>');
  await checkBuild(resolve(project), commit, command === 'record');
  console.log(`Build provenance ${command} passed`);
}
