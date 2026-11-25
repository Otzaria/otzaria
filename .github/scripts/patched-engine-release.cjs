'use strict';

const { createHash } = require('node:crypto');
const { existsSync, readFileSync, readdirSync } = require('node:fs');
const path = require('node:path');

function selectRelease(root, arch, engineRevision) {
  if (!['x64', 'arm64'].includes(arch)) {
    throw new Error(`Unsupported Windows engine architecture: ${arch}`);
  }
  const directory = path.join(root, '.github/otzaria-engine');
  const manifest = JSON.parse(readFileSync(path.join(directory, 'releases.json'), 'utf8'));
  if (manifest.schema !== 1 || manifest.engineRevision !== engineRevision) {
    throw new Error('The engine release manifest does not match the Flutter SDK revision.');
  }

  const patchDirectory = path.join(directory, 'patches');
  const entries = existsSync(patchDirectory)
    ? readdirSync(patchDirectory, { withFileTypes: true }).filter(entry => entry.name.endsWith('.patch'))
    : [];
  const patches = entries.map(entry => entry.name).sort();
  for (const entry of entries) {
    if (!entry.isFile()) throw new Error(`Expected a regular patch file: ${entry.name}`);
    const expected = manifest.patchSha256?.[entry.name];
    const actual = createHash('sha256')
      .update(readFileSync(path.join(patchDirectory, entry.name))).digest('hex');
    if (actual !== expected) {
      throw new Error(`No verified engine build matches patch ${entry.name} (sha256 ${actual}).`);
    }
  }

  const matches = manifest.releases.filter(release =>
    Array.isArray(release.patches) &&
    JSON.stringify([...release.patches].sort()) === JSON.stringify(patches));
  if (matches.length !== 1) {
    throw new Error(`Expected exactly one verified release for patch set: ${patches.join(', ') || '(none)'}.`);
  }
  const release = matches[0];
  const sha256 = release.sha256?.[arch];
  if (!/^[0-9a-f]{64}$/.test(sha256 ?? '') ||
      !/^https:\/\/github\.com\/[^/]+\/[^/]+\/releases\/download\/[^/]+$/.test(release.url ?? '')) {
    throw new Error(`Invalid pinned release URL or ${arch} checksum for the selected engine.`);
  }
  return { releaseUrl: release.url, sha256, patches };
}

module.exports = { selectRelease };

if (require.main === module) {
  try {
    if (process.argv.length !== 4) {
      throw new Error('Usage: node patched-engine-release.cjs <x64|arm64> <engine-revision>');
    }
    console.log(JSON.stringify(selectRelease(path.resolve(__dirname, '../..'), process.argv[2], process.argv[3])));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
