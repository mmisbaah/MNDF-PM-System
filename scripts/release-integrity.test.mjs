import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { inventory, verifyPackage as verifyReleasePackage } from './release-integrity.mjs';

test('full inventory rejects modified, missing, added and unsafe package entries', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'tracker-integrity-'));
  const root = join(fixture, 'standalone');
  const scriptsRoot = join(fixture, 'scripts');
  const verifyPackage = (directory, manifest) => verifyReleasePackage(directory, manifest, scriptsRoot);
  try {
    await mkdir(root);
    await mkdir(scriptsRoot);
    const helpers = ['start-production.ps1', 'application-log-redaction.ps1', 'validate-production-env.mjs'];
    for (const name of helpers) await writeFile(join(scriptsRoot, name), 'original');
    await mkdir(join(root, 'assets'));
    for (const name of ['server.js', 'package.json', 'assets/client.js']) await writeFile(join(root, name), 'original');
    const manifest = { format: 'performance-tracker-release-package-v3', commit: 'a'.repeat(40), files: await inventory(root), scripts: await inventory(scriptsRoot, false) };
    await verifyPackage(root, manifest);
    await writeFile(join(root, 'release-manifest.json'), '{}');
    await writeFile(join(root, 'release-manifest.sig.json'), '{}');
    await verifyPackage(root, manifest); // Only these two root metadata files are excluded.
    await writeFile(join(root, 'assets/client.js'), 'tampered');
    await assert.rejects(verifyPackage(root, manifest), /integrity verification failed/);
    await writeFile(join(root, 'assets/client.js'), 'original');
    await writeFile(join(root, 'injected.js'), 'unexpected');
    await assert.rejects(verifyPackage(root, manifest), /file set differs/);
    await rm(join(root, 'injected.js'));
    await rm(join(root, 'assets/client.js'));
    await assert.rejects(verifyPackage(root, manifest), /file set differs/);
    await writeFile(join(root, 'assets/client.js'), 'original');
    for (const version of [1, 2]) await assert.rejects(verifyPackage(root, { ...manifest, format: `performance-tracker-release-package-v${version}` }), /version 3/);
    for (const path of ['../escape', '/absolute', 'C:/escape', 'assets\\escape', 'assets//escape', 'release-manifest.json']) {
      await assert.rejects(verifyPackage(root, { ...manifest, files: [...manifest.files, { path, sha256: 'a'.repeat(64) }] }), /Invalid/);
    }
    await assert.rejects(verifyPackage(root, { ...manifest, files: [...manifest.files, manifest.files[0]] }), /Invalid/);
    await symlink(join(root, 'assets'), join(root, 'redirect'), process.platform === 'win32' ? 'junction' : 'dir');
    await assert.rejects(verifyPackage(root, manifest), /symbolic link rejected/);
    await rm(join(root, 'redirect')); // Remove the link, never recursively traverse it.
    await verifyPackage(root, manifest);
    for (const name of helpers) {
      await writeFile(join(scriptsRoot, name), 'tampered');
      await assert.rejects(verifyPackage(root, manifest), /integrity verification failed/);
      await rm(join(scriptsRoot, name));
      await assert.rejects(verifyPackage(root, manifest), /file set differs/);
      await writeFile(join(scriptsRoot, name), 'original');
      await assert.rejects(verifyPackage(root, { ...manifest, scripts: manifest.scripts.filter(file => file.path !== name) }), /Required package entry/);
    }
    // No metadata exclusions in scripts: even a file named like the manifest is covered.
    await writeFile(join(scriptsRoot, 'release-manifest.json'), 'injected');
    await assert.rejects(verifyPackage(root, manifest), /file set differs/);
    await rm(join(scriptsRoot, 'release-manifest.json'));
    await assert.rejects(verifyReleasePackage(root, manifest), /scripts directory required/);
    await assert.rejects(verifyPackage(root, { ...manifest, scripts: undefined }), /Empty/);
    await assert.rejects(verifyPackage(root, { ...manifest, scripts: [...manifest.scripts, manifest.scripts[0]] }), /Invalid/);
    await symlink(root, join(scriptsRoot, 'redirect'), process.platform === 'win32' ? 'junction' : 'dir');
    await assert.rejects(verifyPackage(root, manifest), /symbolic link rejected/);
    await rm(join(scriptsRoot, 'redirect'));
    await verifyPackage(root, manifest);
  } finally {
    // fixture is exclusively the disposable directory returned by mkdtemp above.
    await rm(fixture, { recursive: true, force: true });
  }
});

test('CLI creation and verification require the release scripts and reject helper tampering', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'tracker-integrity-cli-'));
  const standalone = join(fixture, 'standalone');
  const scripts = join(fixture, 'scripts');
  const cli = fileURLToPath(new URL('./release-integrity.mjs', import.meta.url));
  const run = (...args) => spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
  try {
    await mkdir(standalone);
    await mkdir(scripts);
    for (const name of ['server.js', 'package.json']) await writeFile(join(standalone, name), 'fixture');
    for (const name of ['start-production.ps1', 'application-log-redaction.ps1', 'validate-production-env.mjs']) await writeFile(join(scripts, name), 'fixture');
    let result = run('create', standalone, scripts, 'b'.repeat(40));
    assert.equal(result.status, 0, result.stderr);
    result = run('verify', standalone, scripts);
    assert.equal(result.status, 0, result.stderr);
    await writeFile(join(scripts, 'validate-production-env.mjs'), 'changed');
    result = run('verify', standalone, scripts);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /integrity verification failed/);
    assert.notEqual(run('verify', standalone).status, 0);
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});
