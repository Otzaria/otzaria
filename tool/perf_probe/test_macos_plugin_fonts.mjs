import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';

const source = readFileSync(new URL('../../lib/plugins/services/plugin_font_bootstrap.dart', import.meta.url), 'utf8');
const script = name => {
  const match = source.match(new RegExp(`const ${name} = r'''([\\s\\S]*?)''';`));
  assert.ok(match, name);
  return match[1];
};
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const run = (body, args) => new AsyncFunction(...Object.keys(args), body)(...Object.values(args));
const installBody = script('pluginStrictFontInstallJs');

function fixture({blockedStyle = false, outcome = 'loaded'} = {}) {
  const fonts = new Set();
  const styles = [];
  let loads = 0;
  let pending;
  const document = {
    __otzariaFontDocumentId: 'document-1',
    __otzariaFontBootAttempt: 'owner-1',
    __otzariaFontDocument: {id: 'owner-1', style: null},
    fonts,
    createElement() {
      const face = {family: 'Probe', weight: '400', status: 'unloaded'};
      const style = {
        face, removed: false, sheet: null, setAttribute() {},
        remove() { this.removed = true; fonts.delete(face); },
      };
      styles.push(style);
      return style;
    },
    head: {appendChild(style) {
      if (!blockedStyle) {
        style.sheet = {cssRules: [{}]};
        fonts.add(style.face);
      }
    }},
  };
  fonts.load = async () => {
    loads++;
    const style = styles.at(-1);
    if (outcome === 'empty') return [];
    if (outcome === 'unloaded') return [style.face];
    if (outcome === 'foreign') return [{family: 'Unrelated', status: 'loaded'}];
    if (outcome === 'blocked' ||
        (outcome === 'data-only' && !style.textContent.includes('data:'))) {
      throw new Error('font-src');
    }
    if (outcome === 'pending') await new Promise(resolve => { pending = resolve; });
    style.face.status = 'loaded';
    return [style.face];
  };
  const args = {
    document, owner: 'owner-1', documentId: 'document-1',
    css: '@font-face{src:url(otzaria-plugin://probe/font)}',
    targets: ['16px "Probe"'], timeoutMs: 20,
    deadlineMs: Date.now() + 2000, keepOnFailure: false,
  };
  return {document, styles, args, loads: () => loads, resolve: () => pending?.()};
}

for (const outcome of ['empty', 'unloaded', 'foreign']) {
  test(`${outcome} cannot claim a loaded FontFace`, async () => {
    const f = fixture({outcome});
    const result = await run(installBody, f.args);
    assert.equal(result.ready, false);
    assert.equal(result.reason, 'missing-loaded-face');
    assert.equal(f.styles[0].removed, true);
  });
}

test('loaded owned FontFace succeeds', async () => {
  const f = fixture();
  const result = await run(installBody, f.args);
  assert.equal(result.ready, true);
  assert.equal(result.faces[0].status, 'loaded');
  assert.equal(f.styles[0].removed, false);
});

test('blocked inline style is explicit and never mistaken for data fallback success', async () => {
  const f = fixture({blockedStyle: true});
  for (const css of [f.args.css, '@font-face{src:url(data:font/ttf;base64,AA)}']) {
    const result = await run(installBody, {...f.args, css, keepOnFailure: true});
    assert.equal(result.ready, false);
    assert.equal(result.reason, 'style-blocked');
  }
  assert.equal(f.loads(), 0);
  assert.ok(f.styles.every(s => s.removed));
});

test('font-src data: rejects scheme and permits verified data fallback', async () => {
  const f = fixture({outcome: 'data-only'});
  const scheme = await run(installBody, f.args);
  assert.equal(scheme.reason, 'font-load-failed');
  assert.equal(f.styles[0].removed, true);
  const data = await run(installBody, {
    ...f.args, css: '@font-face{src:url(data:font/ttf;base64,AA)}', keepOnFailure: true,
  });
  assert.equal(data.ready, true);
  assert.equal(f.styles[1].removed, false);
});

test('pending font loading settles within the bound and releases scheme style', async () => {
  const f = fixture({outcome: 'pending'});
  const result = await run(installBody, f.args);
  assert.equal(result.reason, 'font-timeout');
  assert.equal(result.ready, false);
  assert.equal(f.styles[0].removed, true);
  f.resolve();
});

test('completion from a previous document never removes its replacement style', async () => {
  const f = fixture({outcome: 'pending'});
  const pending = run(installBody, {...f.args, timeoutMs: 1000});
  const replacement = {removed: false, remove() { this.removed = true; }};
  f.document.__otzariaFontDocument = {id: 'owner-2', style: replacement};
  f.document.__otzariaFontDocumentId = 'document-2';
  f.resolve();
  const result = await pending;
  assert.equal(result.reason, 'stale-document');
  assert.equal(f.styles[0].removed, true);
  assert.equal(replacement.removed, false);
});

test('a queued binding or installation cannot cross a navigation', async () => {
  const f = fixture();
  const current = f.document.__otzariaFontDocument;
  f.document.__otzariaFontDocumentId = 'document-2';
  for (const body of [script('_beginDocumentJs'), installBody]) {
    const result = await run(body, f.args);
    assert.equal(result.reason, 'stale-document');
    assert.equal(f.document.__otzariaFontDocument, current);
  }
  assert.equal(f.styles.length, 0);
});

test('document ownership survives a failed stylesheet binding', async () => {
  const f = fixture();
  delete f.document.__otzariaFontBootAttempt;
  f.document.__otzariaFontDocument.style = {
    remove() { throw new Error('native binding failed'); },
  };
  const claim = await run(script('_claimDocumentJs'), f.args);
  assert.equal(claim.ready, true);
  assert.equal(claim.documentId, 'document-1');
  assert.equal(f.document.__otzariaFontBootAttempt, 'owner-1');
  await assert.rejects(run(script('_beginDocumentJs'), f.args), /native binding failed/);
  assert.equal(f.document.__otzariaFontBootAttempt, 'owner-1');
});

test('missing or malformed document identity cannot claim an attempt', async () => {
  for (const marker of [undefined, null, '', 42]) {
    const f = fixture();
    f.document.__otzariaFontDocumentId = marker;
    f.document.__otzariaFontBootAttempt = 'newer-owner';
    const result = await run(script('_claimDocumentJs'), f.args);
    assert.equal(result.ready, false);
    assert.equal(result.reason, 'document-marker-unavailable');
    assert.equal(f.document.__otzariaFontBootAttempt, 'newer-owner');
  }
});

test('a newer claim in the same document fences pending older work', async () => {
  const f = fixture({outcome: 'pending'});
  const pending = run(installBody, {...f.args, timeoutMs: 1000});
  const claim = await run(script('_claimDocumentJs'), {...f.args, owner: 'owner-2'});
  assert.equal(claim.ready, true);
  const lateBinding = await run(script('_beginDocumentJs'), f.args);
  assert.equal(lateBinding.reason, 'stale-document');
  f.resolve();
  assert.equal((await pending).reason, 'stale-document');
  assert.equal(f.styles[0].removed, true);
  assert.equal(f.document.__otzariaFontBootAttempt, 'owner-2');
});

test('expired native queue entries perform no DOM work', async () => {
  const f = fixture();
  for (const body of [script('_claimDocumentJs'), script('_beginDocumentJs'), installBody]) {
    const result = await run(body, {...f.args, deadlineMs: Date.now() - 1});
    assert.equal(result.reason, 'expired');
  }
  assert.equal(f.styles.length, 0);
});
