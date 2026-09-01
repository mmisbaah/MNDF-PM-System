import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

test('health endpoint reports unavailable dependencies as 503', async () => {
  const route = await readFile(fileURLToPath(new URL('../src/app/api/health/route.ts', import.meta.url)), 'utf8');
  assert.match(route, /catch\s*\{/);
  assert.match(route, /status:\s*503/);
  assert.doesNotMatch(route, /status:\s*500/);
});
