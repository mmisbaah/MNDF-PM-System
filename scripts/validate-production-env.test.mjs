import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

test('candidate validation cannot be masked by inherited variables', () => {
  const root = mkdtempSync(join(tmpdir(), 'tracker-config-test-'));
  const validator = fileURLToPath(new URL('./validate-production-env.mjs', import.meta.url));
  const valid = {
    NODE_ENV: 'production', DATABASE_URL: 'postgresql://runtime:unique-runtime-fixture@localhost/db',
    AUDIT_DATABASE_URL: 'postgresql://audit:unique-audit-fixture@localhost/db',
    MFA_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64'),
    EVIDENCE_STORAGE_ROOT: join(root, 'evidence'), EVIDENCE_QUARANTINE_ROOT: join(root, 'quarantine'),
    HOSTNAME: '127.0.0.1', PORT: '3100', PRODUCTION_PUBLIC_URL: 'https://tracker.test',
  };
  for (const [index, name] of ['AUTH_JWT_SECRET', 'GRIEVANCE_CRON_SECRET', 'EVIDENCE_SCANNER_SECRET', 'OPERATIONS_MONITOR_SECRET', 'AUDIT_EXPORT_HMAC_KEY'].entries()) valid[name] = `${index}`.repeat(40);
  const candidate = join(root, 'candidate.env');
  const write = entries => writeFileSync(candidate, Object.entries(entries).map(([k,v]) => `${k}='${v}'`).join('\n'));
  const run = (env, args = ['--config-file', candidate]) => spawnSync(process.execPath, [validator, ...args], { env, encoding: 'utf8' });
  try {
    write(valid);
    assert.equal(run({ NODE_ENV: 'development', HOSTNAME: '0.0.0.0', DATABASE_URL: 'invalid' }).status, 0);
    write({ ...valid, HOSTNAME: '0.0.0.0' });
    assert.equal(run(valid).status, 1, 'valid shell must not hide unsafe file binding');
    const missingSecret = { ...valid }; delete missingSecret.AUTH_JWT_SECRET;
    write(missingSecret);
    const missing = run(valid);
    assert.equal(missing.status, 1, 'shell secret must not fill missing file secret');
    assert.match(missing.stderr, /AUTH_JWT_SECRET/);
    assert.equal(run(valid, []).status, 0, 'legacy effective-environment mode remains supported');
    assert.equal(run(valid, ['--config-file', join(root, 'absent')]).status, 1);
    assert.equal(run(valid, ['--unknown']).status, 1);
    write({ ...valid, DATABASE_URL: 'private-fixture-not-a-url' });
    const invalid = run(valid);
    assert.equal(invalid.status, 1);
    assert.ok(!`${invalid.stdout}${invalid.stderr}`.includes('private-fixture-not-a-url'), 'invalid value must not leak');
  } finally {
    rmSync(root, { recursive: true, force: true }); // Only the mkdtemp fixture.
  }
});
