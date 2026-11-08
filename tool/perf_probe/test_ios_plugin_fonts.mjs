import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';

const shared = readFileSync(new URL('../../integration_test/support/apple_font_probe_view.dart', import.meta.url), 'utf8');
const dataBody = shared.match(/Future<Map<String, Object\?>> loadFreshAppleDataSurvivorFont[\s\S]*?functionBody: r'''([\s\S]*?)'''/)[1];
const policyBody = shared.match(/const appleFontProbePolicyJs = r'''([\s\S]*?)''';/)[1];
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const run = (body, args) => new AsyncFunction(...Object.keys(args), body)(...Object.values(args));

function freshFixture({pending = false, reject = false} = {}) {
  let release;
  const fonts = new Set();
  const document = {__otzariaFontDocumentId: 'doc', __otzariaFontBootAttempt: 'owner', fonts};
  const created = [];
  class FontFace {
    constructor(family, source) { this.family = family; this.source = source; this.status = 'unloaded'; created.push(this); }
    async load() {
      if (pending) await new Promise(resolve => { release = resolve; });
      if (reject) throw Error('font rejected');
      this.status = 'loaded';
      return this;
    }
  }
  return {document, created, release: () => release(), args: {document, FontFace,
    documentId: 'doc', owner: 'owner', url: 'data:font/ttf;base64,fixture'}};
}

test('fresh data control creates, awaits and removes a new owned face', async () => {
  const f = freshFixture();
  const result = await run(dataBody, f.args);
  assert.deepEqual(result, {loaded: true, status: 'loaded'});
  assert.equal(f.created.length, 1);
  assert.match(f.created[0].source, /data:font\/ttf/);
  assert.equal(f.document.fonts.size, 0);
});

for (const key of ['__otzariaFontDocumentId', '__otzariaFontBootAttempt']) {
  test(`fresh face refuses stale ${key} before a load`, async () => {
    const f = freshFixture();
    f.document[key] = 'replacement';
    assert.deepEqual(await run(dataBody, f.args), {loaded: false, reason: 'stale-document'});
    assert.equal(f.created.length, 0);
  });
  test(`navigation changing ${key} during the load cannot pass`, async () => {
    const f = freshFixture({pending: true});
    const response = run(dataBody, f.args);
    assert.equal(f.document.fonts.size, 1);
    f.document[key] = 'replacement';
    f.release();
    assert.equal((await response).loaded, false);
    assert.equal(f.document.fonts.size, 0);
  });
}

test('a failed fresh face is removed and preserves the font rejection', async () => {
  const f = freshFixture({reject: true});
  await assert.rejects(run(dataBody, f.args), /font rejected/);
  assert.equal(f.document.fonts.size, 0);
});

test('policy diagnostics retain opaque file origin separately from CSP observations', async () => {
  const violations = [{directive: 'font-src', blockedUri: 'otzaria-plugin', disposition: 'enforce'}];
  const result = await run(policyBody, {
    document: {__otzariaFontDocumentId: 'doc', __otzariaFontBootAttempt: 'owner'},
    location: {href: 'file:///plugin.html', origin: 'null'},
    window: {isSecureContext: false, fontProbeViolations: violations, fontProbeDroppedViolations: 3},
  });
  assert.deepEqual(result, {href: 'file:///plugin.html', origin: 'null', secureContext: false,
    documentId: 'doc', owner: 'owner', violations, droppedViolations: 3});
});
