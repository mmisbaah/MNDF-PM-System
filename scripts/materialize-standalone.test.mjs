import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, symlink, rm, rename } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { materializeStandalone, checkReleaseDependencies } from './materialize-standalone.mjs';
import { inventory, verifyPackage } from './release-integrity.mjs';

async function fixture(run) {
  const root = await mkdtemp(join(tmpdir(), 'tracker-contained-'));
  try {
    const app = join(root, '.next', 'standalone');
    const deps = join(root, 'node_modules');
    await mkdir(join(app, 'node_modules'), { recursive: true }); await mkdir(deps);
    await writeFile(join(app, 'server.js'), 'module.exports = require("alias");');
    await writeFile(join(app, 'package.json'), '{}');
    await run({ root, app, deps });
  } finally { await rm(root, { recursive: true, force: true }); }
}
const link = (target, path) => symlink(target, path, process.platform === 'win32' ? 'junction' : 'dir');

test('materializes aliases, resolves dependencies without checkout, detects tampering', async () => fixture(async ({ root, app, deps }) => {
  await mkdir(join(deps, 'real'));
  await writeFile(join(deps, 'real', 'index.js'), 'module.exports = require("child");');
  await mkdir(join(app, 'node_modules', 'child'));
  await writeFile(join(app, 'node_modules', 'child', 'index.js'), 'module.exports = 42;');
  await link(join(deps, 'real'), join(app, 'node_modules', 'alias'));
  assert.equal((await materializeStandalone(root)).links, 1);
  const files = await inventory(app);
  await rename(deps, join(root, 'dependencies-hidden'));
  const result = spawnSync(process.execPath, ['-e', 'if(require(process.argv[1])!==42)process.exit(1)', join(app, 'server.js')], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const scripts = join(root, 'scripts'); await mkdir(scripts);
  for (const name of ['start-production.ps1', 'application-log-redaction.ps1', 'validate-production-env.mjs']) await writeFile(join(scripts, name), 'fixture');
  const manifest = { format: 'performance-tracker-release-package-v3', commit: 'a'.repeat(40), files, scripts: await inventory(scripts, false) };
  await verifyPackage(app, manifest, scripts);
  await writeFile(join(app, 'node_modules', 'alias', 'index.js'), 'tampered');
  await assert.rejects(verifyPackage(app, manifest, scripts), /integrity verification failed/);
}));

for (const kind of ['outside', 'cycle', 'asset', 'dangling']) {
  test(`rejects ${kind} links and preserves raw build`, async () => fixture(async ({ root, app, deps }) => {
    let target = join(root, 'outside');
    let location = join(app, 'node_modules', 'alias');
    if (kind === 'cycle') target = app;
    else if (kind === 'asset') { target = join(deps, 'real'); location = join(app, 'assets'); }
    if (kind !== 'cycle' && kind !== 'dangling') await mkdir(target);
    await link(target, location);
    await assert.rejects(materializeStandalone(root), /escapes|cycle|Non-dependency|ENOENT/);
    assert.equal(await readFile(join(app, 'server.js'), 'utf8'), 'module.exports = require("alias");');
    await assert.rejects(readFile(join(root, '.next', 'release-build-provenance.json')), /ENOENT/);
  }));
}

test('rejects isolated layout and existing staging output', async () => fixture(async ({ root, app, deps }) => {
  await mkdir(join(deps, '.pnpm', 'real'), { recursive: true });
  await link(join(deps, '.pnpm', 'real'), join(deps, 'alias'));
  await assert.rejects(checkReleaseDependencies(root), /node-linker=hoisted/);
  await rm(join(deps, 'alias'));
  await mkdir(join(root, '.next', 'standalone-contained'));
  await assert.rejects(materializeStandalone(root), /already exists/);
  assert.equal(await readFile(join(app, 'package.json'), 'utf8'), '{}');
}));
