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

const probeSource = readFileSync(new URL('../../integration_test/support/apple_font_probe_view.dart', import.meta.url), 'utf8');
const supportSource = readFileSync(new URL('../../integration_test/support/macos_font_probe.dart', import.meta.url), 'utf8');
const renderingBody = probeSource.match(/const appleFontProbeMeasureJs = r'''([\s\S]*?)''';/)[1];
const snapshotBody = supportSource.match(/const fontProbeFailureSnapshotJs = r'''([\s\S]*?)''';/)[1];
const settled = () => new Promise(resolve => setImmediate(resolve));

function renderingFixture({pendingFont = false, brokenCanvas = false, brokenCanvasAt = -1, count = 6, pixels} = {}) {
  const frames = [];
  const face = {family: 'Probe', weight: '400', status: 'loaded'};
  const fonts = new Set([face]);
  fonts.status = 'loaded';
  let releaseFont;
  let fontLoads = 0;
  const fontRequests = [];
  fonts.load = async (target, text) => {
    fontRequests.push({target, text});
    fontLoads++;
    if (pendingFont && fontLoads === 1) await new Promise(resolve => { releaseFont = resolve; });
    return [face];
  };
  const canvases = [];
  function canvas() {
    const index = canvases.length;
    const item = {rectangles: [], text: [], reads: [], measures: [], contexts: []};
    const context = {
      fillRect(...args) { item.rectangles.push({args, style: this.fillStyle}); },
      fillText(...args) { item.text.push({args, style: this.fillStyle, font: this.font, baseline: this.textBaseline}); },
      getImageData(...args) {
        item.reads.push(args);
        if (brokenCanvas || index === brokenCanvasAt) throw new Error('canvas read failed');
        return {data: pixels || new Uint8ClampedArray([0, 0, 0, 255, 255, 255, 255, 255])};
      },
      measureText(...args) { item.measures.push(args); return {width: 123}; },
    };
    item.getContext = (...args) => { item.contexts.push(args); return context; };
    canvases.push(item);
    return item;
  }
  const document = {
    __otzariaFontDocumentId: 'probe-document', __otzariaFontBootAttempt: 'probe-owner',
    fonts, visibilityState: 'visible', readyState: 'complete',
    createElement(tag) { return tag === 'canvas' ? canvas() : {style: {}}; },
    body: {appendChild() {}},
  };
  let clock = 0;
  const args = {
    document, window: {fontProbeBootCount: 1}, performance: {now: () => ++clock},
    specs: Array.from({length: count}, (_, i) => ({key: `sample-${i}`, family: 'Probe', weight: '400'})),
    requestAnimationFrame: callback => frames.push(callback),
    innerWidth: 320, innerHeight: 150, devicePixelRatio: 1, navigator: {userAgent: 'contract-fixture'},
  };
  const snapshot = () => run(snapshotBody, {...args, documentId: 'probe-document', owner: 'probe-owner'}).then(JSON.parse);
  return {args, frames, snapshot, canvases, fontRequests, releaseFont: () => releaseFont(), fontLoads: () => fontLoads};
}

test('a pending font load is visible before either animation frame', async () => {
  const f = renderingFixture({pendingFont: true});
  const result = run(renderingBody, f.args);
  await settled();
  const snapshot = await f.snapshot();
  assert.equal(snapshot.availability, 'captured');
  assert.equal(snapshot.renderingProgress.phase, 'font-load-started');
  assert.equal(snapshot.renderingProgress.events.at(-1).fontKey, 'sample-0');
  assert.equal(f.frames.length, 0);
  assert.equal(f.fontLoads(), 1);
  f.releaseFont();
  await settled();
  f.frames.shift()();
  f.frames.shift()();
  assert.equal((await result).samples.length, 6);
});

test('rendering still waits for both frames and snapshots distinguish each wait', async () => {
  const f = renderingFixture();
  let returned = false;
  const result = run(renderingBody, f.args).then(value => { returned = true; return value; });
  await settled();
  assert.equal((await f.snapshot()).renderingProgress.phase, 'frames-requested');
  assert.equal(f.frames.length, 1);
  assert.equal(f.fontLoads(), 6);
  assert.equal(returned, false);
  f.frames.shift()();
  await settled();
  const afterFirst = await f.snapshot();
  assert.equal(afterFirst.renderingProgress.phase, 'frame-1');
  assert.equal(returned, false);
  assert.equal(f.frames.length, 1);
  f.frames.shift()();
  const rendered = await result;
  assert.equal(rendered.renderingProgress.phase, 'completed');
  assert.equal(rendered.samples.length, 6);
  assert.ok(rendered.samples.every(sample => sample.inkPixels > 0));
  const phases = rendered.renderingProgress.events.map(event => event.phase);
  assert.equal(phases.filter(phase => phase === 'font-load-completed').length, 6);
  assert.equal(phases.filter(phase => phase === 'canvas-completed').length, 6);
  assert.deepEqual(phases.slice(-5), ['frame-1', 'frame-2', 'fallback-started', 'fallback-completed', 'completed']);
  assert.equal(afterFirst.renderingProgress.phase, 'frame-1');
  assert.ok(afterFirst.capturedAtEpochMilliseconds >= rendered.renderingProgress.startedAtEpochMilliseconds);
});

test('a canvas exception retains its stage and remains a rendering failure', async () => {
  const f = renderingFixture({brokenCanvas: true});
  await assert.rejects(run(renderingBody, f.args), /canvas read failed/);
  const snapshot = await f.snapshot();
  assert.equal(snapshot.renderingProgress.phase, 'canvas-started');
  assert.equal(snapshot.renderingProgress.events.at(-1).fontKey, 'sample-0');
  assert.equal(f.frames.length, 0);
});

test('a queued snapshot cannot read a new document or a replacement owner', async () => {
  for (const field of ['__otzariaFontDocumentId', '__otzariaFontBootAttempt']) {
    const f = renderingFixture();
    f.args.document[field] = 'replacement';
    Object.defineProperty(f.args.document, 'fonts', {get() { throw new Error('stale read'); }});
    assert.deepEqual(await f.snapshot(), {availability: 'stale-document'});
  }
});

test('a trace from an old owner cannot describe the current rendering', async () => {
  const f = renderingFixture();
  f.args.window.__otzariaFontProbeRendering = {
    documentId: 'probe-document', owner: 'old-owner', phase: 'completed',
  };
  const snapshot = await f.snapshot();
  assert.equal(snapshot.availability, 'trace-unavailable');
  assert.equal(snapshot.renderingProgress, null);
});

test('readback observers retain the complete bitmap and named or generic font semantics', async () => {
  const pixels = new Uint8ClampedArray(650 * 80 * 4);
  let expectedInk = 0;
  for (let pixel = 0; pixel < 650 * 80; pixel++) {
    const offset = pixel * 4;
    pixels[offset] = pixel % 3 === 0 ? 0 : 255;
    pixels[offset + 1] = pixel * 7 % 256;
    pixels[offset + 2] = pixel * 13 % 256;
    pixels[offset + 3] = 255;
    if (pixel % 3 === 0) expectedInk++;
  }
  // Independent wide-integer FNV reference: every RGBA byte contributes.
  let expectedHash = 2166136261n;
  for (const byte of pixels) expectedHash = ((expectedHash ^ BigInt(byte)) * 16777619n) & 0xffffffffn;
  const digest = expectedHash.toString(16);
  const selected = [
    {key: 'system-regular', family: 'System Probe', weight: '400'},
    {key: 'system-bold', family: 'System Probe', weight: '700'},
    {key: 'bundled-regular', family: 'FrankRuhlCLM', weight: '400'},
    {key: 'bundled-bold', family: 'FrankRuhlCLM', weight: '700'},
    {key: 'variable-light', family: 'Rubik', weight: '300'},
    {key: 'variable-bold', family: 'Rubik', weight: '700'},
  ];
  for (const count of [4, 6]) {
    const f = renderingFixture({count, pixels});
    f.args.specs = selected.slice(6 - count);
    const result = run(renderingBody, f.args);
    await settled();
    assert.equal(f.frames.length, 1);
    f.frames.shift()();
    assert.equal(f.frames.length, 1);
    f.frames.shift()();
    const rendered = await result;
    assert.equal(rendered.samples.length, count);
    assert.equal(f.canvases.length, count + 1);
    assert.deepEqual(f.fontRequests, f.args.specs.map(spec => ({
      target: spec.weight + ' 28px "' + spec.family + '"', text: 'אבג ABC 012',
    })));
    assert.deepEqual(rendered.samples.map(({key, family, weight}) => ({key, family, weight})), f.args.specs);
    for (const sample of [...rendered.samples, rendered.fallbackControl]) {
      assert.equal(sample.pixelHash, digest);
      assert.equal(sample.inkPixels, expectedInk);
      assert.equal(sample.width, 123);
    }
    const fonts = f.args.specs.map(spec => spec.weight + ' 28px "' + spec.family + '"');
    fonts.push('400 28px monospace');
    for (const [index, canvas] of f.canvases.entries()) {
      assert.equal(canvas.width, 650);
      assert.equal(canvas.height, 80);
      assert.deepEqual(canvas.contexts, [['2d', {willReadFrequently: true}]]);
      assert.deepEqual(canvas.rectangles, [{args: [0, 0, 650, 80], style: '#fff'}]);
      assert.deepEqual(canvas.text, [{args: ['שלום עולם אבגדה ABC 012345', 8, 8],
        style: '#000', font: fonts[index], baseline: 'top'}]);
      assert.deepEqual(canvas.reads, [[0, 0, 650, 80]]);
      assert.deepEqual(canvas.measures, [['שלום עולם אבגדה ABC 012345']]);
    }
    assert.equal(rendered.renderingProgress.droppedEvents, 0);
    assert.equal(rendered.renderingProgress.phase, 'completed');
  }
});

test('ten independent rendering scripts keep every font and both frame waits', async () => {
  // This exercises JavaScript contracts only; actual platform hosts are tested in native CI.
  const fixtures = Array.from({length: 10}, (_, index) => {
    const f = renderingFixture();
    f.args.document.__otzariaFontDocumentId = 'document-' + index;
    f.args.document.__otzariaFontBootAttempt = 'owner-' + index;
    return f;
  });
  const completed = fixtures.map(() => false);
  const pending = fixtures.map((f, index) => run(renderingBody, f.args).then(result => {
    completed[index] = true;
    return result;
  }));
  await settled();
  assert.ok(fixtures.every(f => f.fontLoads() === 6 && f.frames.length === 1));
  fixtures[0].frames.shift()();
  fixtures[0].frames.shift()();
  await pending[0];
  assert.deepEqual(completed, [true, false, false, false, false, false, false, false, false, false]);
  assert.ok(fixtures.slice(1).every(f => f.args.window.__otzariaFontProbeRendering.phase === 'frames-requested'));
  for (const f of fixtures.slice(1)) {
    f.frames.shift()();
    f.frames.shift()();
  }
  const results = await Promise.all(pending);
  for (const [index, result] of results.entries()) {
    assert.equal(result.samples.length, 6);
    assert.equal(fixtures[index].canvases.length, 7);
    assert.equal(result.renderingProgress.owner, 'owner-' + index);
    assert.deepEqual(result.renderingProgress.events.filter(e => e.phase.startsWith('frame-')).map(e => e.phase),
      ['frame-1', 'frame-2']);
  }
});

test('a fallback readback failure stays failed after both frames', async () => {
  const f = renderingFixture({brokenCanvasAt: 6});
  const result = run(renderingBody, f.args);
  await settled();
  f.frames.shift()();
  f.frames.shift()();
  await assert.rejects(result, /canvas read failed/);
  assert.equal((await f.snapshot()).renderingProgress.phase, 'fallback-started');
  assert.equal(f.canvases.length, 7);
});

test('diagnostic event storage remains bounded without skipping rendering', async () => {
  const f = renderingFixture({count: 20});
  const result = run(renderingBody, f.args);
  await settled();
  f.frames.shift()();
  f.frames.shift()();
  const rendered = await result;
  assert.equal(rendered.samples.length, 20);
  assert.equal(rendered.renderingProgress.phase, 'completed');
  assert.equal(rendered.renderingProgress.events.length, 40);
  assert.ok(rendered.renderingProgress.droppedEvents > 0);
  assert.equal((await f.snapshot()).renderingProgress.events.length, 40);
});
