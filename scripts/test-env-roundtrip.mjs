// Receives dummy test data only. Never print configuration values on failure.
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { parseEnv } from 'node:util';

const { content, expected } = JSON.parse(readFileSync(0, 'utf8').replace(/^\uFEFF/, ''));
const parsed = parseEnv(content);
if (JSON.stringify(Object.keys(parsed).sort()) !== JSON.stringify(Object.keys(expected).sort())) throw new Error('Environment key set changed');
for (const key of Object.keys(expected)) {
  if (parsed[key] !== expected[key]) throw new Error(`Environment parser changed ${key}`);
}
const fixture = mkdtempSync(join(tmpdir(), 'tracker-env-roundtrip-'));
try {
  const file = join(fixture, 'fixture.env');
  writeFileSync(file, content, { mode: 0o600 });
  execFileSync(process.execPath, [`--env-file=${file}`, '-e', `
    const expected=JSON.parse(require('node:fs').readFileSync(0,'utf8'));
    for(const key of Object.keys(expected)) {
      if(process.env[key]!==expected[key]) throw new Error('Loader changed '+key);
    }
  `], { input: JSON.stringify(expected), env: {}, stdio: ['pipe', 'pipe', 'pipe'] });
  console.log('PASS Node parser and --env-file round trip');
} finally {
  // The only cleanup target is this newly created disposable fixture.
  rmSync(fixture, { recursive: true, force: true });
}
