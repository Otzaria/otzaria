'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { selectRelease } = require('./patched-engine-release.cjs');

const revision = 'deb287481e3ce9468f3434937ced4240a70539ca';
const sources = { 'windows-numpad.patch': 'keyboard patch\n', 'skia-style.patch': 'paragraph patch\n' };
const cases = [
  { patches: [], tag: 'a11y', x64: '1', arm64: '2' },
  { patches: ['windows-numpad.patch'], tag: 'numpad', x64: '3', arm64: '4' },
  { patches: ['skia-style.patch'], tag: 'paragraph', x64: '5', arm64: '6' },
  { patches: ['windows-numpad.patch', 'skia-style.patch'], tag: 'both', x64: '7', arm64: '8' },
];

function fixture(t, patches = []) {
  const root = mkdtempSync(path.join(tmpdir(), 'otzaria-engine-release-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const directory = path.join(root, '.github/otzaria-engine');
  const patchDirectory = path.join(directory, 'patches');
  mkdirSync(patchDirectory, { recursive: true });
  for (const name of patches) writeFileSync(path.join(patchDirectory, name), sources[name]);
  const manifest = {
    schema: 1,
    engineRevision: revision,
    patchSha256: Object.fromEntries(Object.entries(sources).map(([name, contents]) =>
      [name, createHash('sha256').update(contents).digest('hex')])),
    releases: cases.map(entry => ({
      patches: entry.patches,
      url: `https://github.com/Y-PLONI/flutter/releases/download/${entry.tag}`,
      sha256: { x64: entry.x64.repeat(64), arm64: entry.arm64.repeat(64) },
    })),
  };
  const manifestPath = path.join(directory, 'releases.json');
  const save = () => writeFileSync(manifestPath, JSON.stringify(manifest));
  save();
  return { root, patchDirectory, manifest, save };
}

for (const entry of cases) {
  for (const arch of ['x64', 'arm64']) {
    test(`${entry.tag} selects only its own ${arch} artifact`, t => {
      const { root } = fixture(t, entry.patches);
      assert.deepEqual(selectRelease(root, arch, revision), {
        releaseUrl: `https://github.com/Y-PLONI/flutter/releases/download/${entry.tag}`,
        sha256: entry[arch].repeat(64),
        patches: [...entry.patches].sort(),
      });
    });
  }
}

test('a changed patch cannot silently use an older binary', t => {
  const { root, patchDirectory } = fixture(t, ['windows-numpad.patch']);
  writeFileSync(path.join(patchDirectory, 'windows-numpad.patch'), 'different keyboard patch\n');
  assert.throws(() => selectRelease(root, 'x64', revision), /No verified engine build matches patch/);
});

test('an unregistered patch cannot silently use a released binary', t => {
  const { root, patchDirectory } = fixture(t);
  writeFileSync(path.join(patchDirectory, 'unknown.patch'), 'new patch\n');
  assert.throws(() => selectRelease(root, 'x64', revision), /No verified engine build matches patch unknown/);
});

test('a missing combined release does not fall back to a single fix', t => {
  const { root, manifest, save } = fixture(t, Object.keys(sources));
  manifest.releases.pop();
  save();
  assert.throws(() => selectRelease(root, 'x64', revision), /exactly one verified release/);
});

test('an ambiguous patch set cannot choose an arbitrary binary', t => {
  const { root, manifest, save } = fixture(t);
  manifest.releases.push(manifest.releases[0]);
  save();
  assert.throws(() => selectRelease(root, 'x64', revision), /exactly one verified release/);
});

test('a different SDK engine revision is rejected before installation', t => {
  const { root } = fixture(t);
  assert.throws(() => selectRelease(root, 'x64', 'different-engine'), /SDK revision/);
});

test('missing architecture checksums and non-release URLs are rejected', t => {
  const { root, manifest, save } = fixture(t);
  delete manifest.releases[0].sha256.arm64;
  save();
  assert.throws(() => selectRelease(root, 'arm64', revision), /checksum/);
  manifest.releases[0].url = 'http://github.com/Y-PLONI/flutter/releases/download/a11y';
  save();
  assert.throws(() => selectRelease(root, 'x64', revision), /release URL/);
});

test('unsupported architectures do not select an x64 binary', t => {
  const { root } = fixture(t);
  assert.throws(() => selectRelease(root, 'x86', revision), /Unsupported/);
});

test('Windows checkout must preserve the bytes of the pinned patches', () => {
  const attributes = readFileSync(path.join(__dirname, '../otzaria-engine/.gitattributes'), 'utf8');
  assert.match(attributes, /^patches\/\*\.patch text eol=lf$/m);
});
