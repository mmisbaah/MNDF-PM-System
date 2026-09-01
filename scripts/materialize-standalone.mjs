import { lstat, realpath, readdir, mkdir, copyFile, rename } from 'node:fs/promises';
import { constants } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { inventory } from './release-integrity.mjs';

function inside(root, path) {
  const rel = relative(root, path);
  return rel === '' || (!isAbsolute(rel) && rel !== '..' && !rel.startsWith(`..${sep}`));
}
async function regularDirectory(path) {
  const stat = await lstat(path);
  if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error(`Regular directory required: ${path}`);
}
// A flat release installation keeps Node's upward dependency lookup valid after
// aliases are copied. Isolated pnpm links must not be silently flattened.
export async function checkReleaseDependencies(project) {
  const deps = join(resolve(project), 'node_modules');
  await regularDirectory(deps);
  async function check(directory) {
    for (const name of await readdir(directory)) {
      if (name.startsWith('.')) continue;
      const path = join(directory, name);
      const stat = await lstat(path);
      if (stat.isSymbolicLink()) throw new Error('Release dependencies must use pnpm --node-linker=hoisted in a fresh checkout');
      if (name.startsWith('@') && stat.isDirectory()) await check(path);
    }
  }
  await check(deps);
}

export async function materializeStandalone(project) {
  project = resolve(project);
  await regularDirectory(project);
  await checkReleaseDependencies(project);
  const next = join(project, '.next');
  const source = join(next, 'standalone');
  const stage = join(next, 'standalone-contained');
  const raw = join(next, 'standalone-raw');
  await regularDirectory(next);
  await regularDirectory(source);
  const canonicalSource = await realpath(source);
  const canonicalDeps = await realpath(join(project, 'node_modules'));
  for (const path of [stage, raw]) {
    try { await lstat(path); } catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    throw new Error(`Packaging destination already exists; preserved: ${path}`);
  }
  await mkdir(stage);
  let links = 0;
  async function copy(input, output, ancestors = new Set()) {
    const stat = await lstat(input);
    const canonical = await realpath(input);
    if (!inside(canonicalSource, canonical) && !inside(canonicalDeps, canonical)) throw new Error(`Dependency target escapes allowed roots: ${input}`);
    if (stat.isSymbolicLink()) {
      // Only dependency aliases may be materialized, never app/assets links.
      if (!relative(source, input).split(sep).includes('node_modules')) throw new Error(`Non-dependency link rejected: ${input}`);
      links++;
    }
    const actual = await lstat(canonical);
    if (actual.isDirectory()) {
      if (ancestors.has(canonical)) throw new Error(`Dependency link cycle rejected: ${input}`);
      const seen = new Set(ancestors); seen.add(canonical);
      await mkdir(output);
      for (const name of (await readdir(canonical)).sort()) await copy(join(canonical, name), join(output, name), seen);
    } else if (actual.isFile()) {
      await copyFile(canonical, output, constants.COPYFILE_EXCL);
    } else throw new Error(`Unsupported dependency entry: ${input}`);
  }
  // Failure leaves raw output untouched and the partial stage for diagnosis.
  for (const name of (await readdir(source)).sort()) await copy(join(source, name), join(stage, name));
  await inventory(stage); // Final artifact still permits no links whatsoever.
  await rename(source, raw);
  await rename(stage, source);
  return { links };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [command, project] = process.argv.slice(2);
  if (!project || !['check', 'materialize'].includes(command)) throw new Error('Usage: check|materialize <project>');
  if (command === 'check') await checkReleaseDependencies(project);
  else console.log(`Standalone dependencies materialized: ${JSON.stringify(await materializeStandalone(project))}`);
}
