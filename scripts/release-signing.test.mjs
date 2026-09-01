import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const script = fileURLToPath(new URL('./release-signing.mjs', import.meta.url));
const passphrase = 'disposable-test-key-passphrase-only';
function run(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, ...args], { env: { ...process.env, RELEASE_SIGNING_KEY_PASSPHRASE: passphrase }, stdio: ['ignore', 'pipe', 'pipe'] });
    child.on('error', reject);
    child.stdout.resume(); child.stderr.resume(); // Do not log key material or values.
    child.on('close', code => resolve(code));
  });
}

test('signing outputs never overwrite existing files, including concurrent writers', async () => {
  const root = await mkdtemp(join(tmpdir(), 'tracker-signing-test-'));
  try {
    const privateKey = join(root, 'private.pem');
    const publicKey = join(root, 'public.pem');
    const same = join(root, 'same.pem');
    assert.notEqual(await run(['keygen', same, same]), 0);
    await assert.rejects(access(same), { code: 'ENOENT' });
    assert.equal(await run(['keygen', privateKey, publicKey]), 0);
    const privateBefore = await readFile(privateKey);
    const publicBefore = await readFile(publicKey);
    assert.notEqual(await run(['keygen', privateKey, publicKey]), 0);
    assert.deepEqual(await readFile(privateKey), privateBefore);
    assert.deepEqual(await readFile(publicKey), publicBefore);

    const manifests = [join(root, 'one.json'), join(root, 'two.json')];
    await Promise.all(manifests.map((path, i) => writeFile(path, JSON.stringify({ fixture: i }))));
    const signature = join(root, 'shared.sig');
    const outcomes = await Promise.all(manifests.map(path => run(['sign', path, privateKey, signature])));
    assert.equal(outcomes.filter(code => code === 0).length, 1, 'exactly one concurrent signer must succeed');
    const winner = outcomes.indexOf(0);
    assert.equal(await run(['verify', manifests[winner], signature, publicKey]), 0);
    assert.notEqual(await run(['verify', manifests[1 - winner], signature, publicKey]), 0);
    const signatureBefore = await readFile(signature);
    assert.notEqual(await run(['sign', manifests[1 - winner], privateKey, signature]), 0);
    assert.deepEqual(await readFile(signature), signatureBefore);

    // A public-output failure must not delete a newly created encrypted key.
    const orphan = join(root, 'preserved-private.pem');
    assert.notEqual(await run(['keygen', orphan, join(root, 'missing-parent', 'public.pem')]), 0);
    assert.match(await readFile(orphan, 'utf8'), /BEGIN ENCRYPTED PRIVATE KEY/);
    assert.deepEqual(await readFile(privateKey), privateBefore);
  } finally {
    await rm(root, { recursive: true, force: true }); // Exclusive mkdtemp fixture only.
  }
});
