import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

test('Next.js configuration disables framework disclosure and emits standalone output', async () => {
  const config = await readFile(fileURLToPath(new URL('../next.config.ts', import.meta.url)), 'utf8');
  assert.match(config, /output:\s*["']standalone["']/);
  assert.match(config, /poweredByHeader:\s*false/);
});
