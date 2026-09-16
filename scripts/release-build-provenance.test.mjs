import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, copyFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { inventory } from './release-integrity.mjs';
import { checkBuild } from './release-build-provenance.mjs';

test('receipt binds commit and exact build inventory; missing/stale/tampered records fail', async () => {
  const root = await mkdtemp(join(tmpdir(), 'tracker-provenance-'));
  const standalone = join(root, '.next', 'standalone');
  const scripts = join(root, 'scripts');
  const commit = 'a'.repeat(40);
  try {
    await mkdir(standalone, { recursive: true }); await mkdir(scripts);
    for (const file of ['server.js', 'package.json']) await writeFile(join(standalone, file), 'original');
    for (const file of ['start-production.ps1', 'application-log-redaction.ps1', 'validate-production-env.mjs']) await writeFile(join(scripts, file), 'original');
    const manifest = { format: 'performance-tracker-release-package-v3', commit, files: await inventory(standalone), scripts: await inventory(scripts, false) };
    const manifestPath = join(standalone, 'release-manifest.json');
    await writeFile(manifestPath, JSON.stringify(manifest));
    await assert.rejects(checkBuild(root, commit), /ENOENT/);
    await checkBuild(root, commit, true);
    await checkBuild(root, commit);
    await assert.rejects(checkBuild(root, commit, true), /EEXIST/);
    await assert.rejects(checkBuild(root, 'b'.repeat(40)), /Build commit differs/);
    await writeFile(join(standalone, 'server.js'), 'tampered');
    await assert.rejects(checkBuild(root, commit), /integrity verification failed/);
    await writeFile(join(standalone, 'server.js'), 'original');
    await writeFile(manifestPath, JSON.stringify(manifest, null, 2));
    await assert.rejects(checkBuild(root, commit), /receipt does not match/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('release build uses a non-secret database placeholder only during compilation', async () => {
  const source = await readFile(fileURLToPath(new URL('release-build.ps1', import.meta.url)), 'utf8');
  assert.match(source, /if\(-not\$hadDatabaseUrl\)\{\$env:DATABASE_URL='postgresql:\/\/release_build_only@127\.0\.0\.1:1\/release_build'\}/);
  assert.match(source, /if\(\$hadDatabaseUrl\)\{\$env:DATABASE_URL=\$previousDatabaseUrl\}else\{Remove-Item Env:DATABASE_URL/);
});

test('real release orchestration rejects failed, reused and changed-source builds', { skip: process.platform !== 'win32' }, async () => {
  const root = await mkdtemp(join(tmpdir(), 'tracker-build-flow-'));
  const run = (command, args) => spawnSync(command, args, { cwd: root, encoding: 'utf8' });
  const git = (...args) => { const r = run('git', args); assert.equal(r.status, 0, r.stderr); return r.stdout.trim(); };
  const shell = process.env.PROVENANCE_TEST_SHELL || 'powershell';
  const ps = code => run(shell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "$ErrorActionPreference='Stop';" + code]);
  try {
    await mkdir(join(root, 'scripts')); await mkdir(join(root, 'public')); await mkdir(join(root, 'node_modules'));
    await copyFile(fileURLToPath(new URL('../.gitignore', import.meta.url)), join(root, '.gitignore'));
    await writeFile(join(root, 'public', 'asset.txt'), 'public');
    for (const file of ['release-build.ps1','prepare-standalone.ps1','release-source-check.ps1','release-integrity.mjs','release-build-provenance.mjs','materialize-standalone.mjs']) {
      await copyFile(fileURLToPath(new URL(file, import.meta.url)), join(root, 'scripts', file));
    }
    for (const file of ['start-production.ps1','application-log-redaction.ps1','validate-production-env.mjs']) await writeFile(join(root, 'scripts', file), 'fixture');
    git('init', '--quiet'); git('add', '.');
    const commit = () => git('-c','user.name=Fixture','-c','user.email=fixture@pilot.test','-c','commit.gpgsign=false','-c','core.hooksPath=disabled-hooks','commit','--quiet','-m','fixture');
    commit();
    let result = ps('function npm {$global:LASTEXITCODE=1}; & ./scripts/release-build.ps1');
    assert.notEqual(result.status, 0);
    await assert.rejects(readFile(join(root,'.next','release-build-provenance.json')), /ENOENT/);
    const fakeBuild = "function npm {New-Item -ItemType Directory -Force .next/standalone,.next/static | Out-Null; [IO.File]::WriteAllText((Join-Path (Get-Location) 'next-env.d.ts'),'// generated Next.js declarations'); [IO.File]::WriteAllText((Join-Path (Get-Location) '.next/standalone/server.js'),'fixture'); [IO.File]::WriteAllText((Join-Path (Get-Location) '.next/standalone/package.json'),'{}'); $global:LASTEXITCODE=0};";
    result = ps(fakeBuild + '& ./scripts/release-build.ps1; & ./scripts/prepare-standalone.ps1');
    assert.equal(result.status, 0, result.stdout + result.stderr);
    result = ps(fakeBuild + '& ./scripts/release-build.ps1');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /absent .next directory/);
    await writeFile(join(root,'public','asset.txt'),'new committed source'); git('add','.'); commit();
    result = ps('& ./scripts/prepare-standalone.ps1');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Build commit differs/);
  } finally { await rm(root, { recursive: true, force: true }); }
});
