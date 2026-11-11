import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const dart = readFileSync(new URL('../../integration_test/support/webview_probe_fixture.dart', import.meta.url), 'utf8');
const source = dart.match(/<script>([\s\S]*?)<\/script>/)[1];

function page({ scrollToApplies = true } = {}) {
  const frames = new Map(), intervals = new Map(), events = new Map(), replies = [];
  const draft = { value: '' };
  let next = 0;
  const context = {
    document: {
      getElementById: () => draft, visibilityState: 'visible', readyState: 'complete',
      body: { scrollHeight: 12000 },
      documentElement: { scrollHeight: 12032 },
      scrollingElement: { tagName: 'HTML', scrollHeight: 12032, clientHeight: 700 },
    },
    innerHeight: 700,
    navigator: { userAgent: 'fixture-test' },
    requestAnimationFrame: (f) => { frames.set(++next, f); return next; },
    cancelAnimationFrame: (id) => frames.delete(id),
    setInterval: (f) => { intervals.set(++next, f); return next; },
    clearInterval: (id) => intervals.delete(id),
    scrollY: 0,
    scrollTo: (_, y) => { if (scrollToApplies) context.scrollY = y; },
    scrollBy: (_, y) => context.scrollY += y,
    addEventListener: (name, f) => events.set(name, f),
    flutter_inappwebview: { callHandler(name, json) {
      assert.equal(name, 'otzariaWebViewResourceProbe');
      replies.push(JSON.parse(json));
      return Promise.resolve(null);
    } },
  };
  context.window = context;
  vm.runInNewContext(source, context);
  return {
    replies, frames, intervals, events,
    command(id, action, value) { context.otzariaWebViewProbe.command({ id, action, value }); },
    framesAfter(count) {
      for (let i = 0; i < count; i++) {
        const batch = [...frames.values()]; frames.clear();
        for (const f of batch) f(i * 16);
      }
    },
    tick() { for (const f of intervals.values()) f(); },
  };
}

test('idle has no timers, animation publisher or unsolicited bridge traffic', () => {
  const p = page();
  p.framesAfter(120); p.tick();
  assert.equal(p.frames.size, 0);
  assert.equal(p.intervals.size, 0);
  assert.deepEqual(p.replies, []);
  p.command(1, 'snapshot');
  assert.equal(p.replies.length, 1);
  assert.equal(p.replies[0].value.schemaVersion, 1);
});

test('visible readiness waits for two frames and answers exactly once', () => {
  const p = page(); p.command(7, 'paint');
  p.framesAfter(1); assert.equal(p.replies.length, 0);
  p.framesAfter(1); assert.equal(p.replies[0].id, 7);
  p.framesAfter(30); assert.equal(p.replies.length, 1);
});

test('scroll reports the final position after all sixty frame steps', () => {
  const p = page(); p.command(3, 'scroll');
  p.framesAfter(59); assert.equal(p.replies.length, 0);
  p.framesAfter(1);
  assert.equal(p.replies.length, 1);
  assert.equal(p.replies[0].value.scrollY, 60 * 24);
  assert.equal(p.frames.size, 0);
});

test('a new page restores a Hebrew draft, revision and scroll', () => {
  const old = page(); old.command(1, 'draft', 'טיוטה עם גרשיים " ושורה\nנוספת');
  old.command(2, 'scroll'); old.framesAfter(60);
  const saved = old.replies.at(-1).value;
  const fresh = page(); fresh.command(1, 'restore', saved); fresh.framesAfter(2);
  for (const key of ['schemaVersion', 'revision', 'draft', 'scrollY']) {
    assert.deepEqual(fresh.replies[0].value[key], saved[key]);
  }
  assert.equal(fresh.replies[0].value.ticks, 0);
});

test('restore diagnostics distinguish applied scroll from a native delayed/ignored scroll', () => {
  const snapshot = { schemaVersion: 1, draft: 'טיוטה', revision: 2, scrollY: 1440 };
  for (const applies of [true, false]) {
    const p = page({ scrollToApplies: applies });
    p.command(5, 'restore', snapshot);
    p.framesAfter(2);
    assert.equal(p.replies.length, 1);
    const result = p.replies[0].value;
    assert.equal(result.scrollY, applies ? 1440 : 0);
    assert.equal(result.restoreDiagnostics.expectedScrollY, 1440);
    assert.equal(result.restoreDiagnostics.immediateScrollY, applies ? 1440 : 0);
    assert.equal(result.restoreDiagnostics.scrollHeight, 12032);
    assert.equal(result.restoreDiagnostics.innerHeight, 700);
    assert.equal(result.restoreDiagnostics.documentReadyState, 'complete');
    assert.equal(result.draft, snapshot.draft);
  }
});

test('bad snapshot versions and values fail without changing the draft', () => {
  for (const patch of [{ schemaVersion: 2 }, { revision: -1 }, { draft: 1 }, { scrollY: -1 }, { scrollY: Infinity }]) {
    const p = page();
    p.command(1, 'restore', { schemaVersion: 1, revision: 0, draft: 'bad', scrollY: 0, ...patch });
    assert.equal(p.replies.length, 1);
    assert.match(p.replies[0].error, /Invalid fixture snapshot/);
    p.command(2, 'snapshot'); assert.equal(p.replies[1].value.draft, '');
  }
});

test('repeated heartbeat starts reuse a single interval and frame callback', () => {
  const p = page();
  for (let i = 1; i <= 5; i++) p.command(i, 'heartbeat');
  assert.equal(p.frames.size, 1);
  assert.equal(p.intervals.size, 1);
  p.framesAfter(300);
  for (let i = 0; i < 100; i++) p.tick();
  assert.equal(p.replies.length, 5);
  p.command(6, 'stop');
  assert.equal(p.replies.at(-1).value.ticks, 100);
  assert.equal(p.replies.at(-1).value.frames, 300);
  assert.equal(p.frames.size, 0);
  assert.equal(p.intervals.size, 0);
});

test('pagehide clears the observer work without sending a message', () => {
  const p = page(); p.command(1, 'heartbeat'); p.events.get('pagehide')();
  p.framesAfter(10); p.tick();
  assert.equal(p.frames.size, 0);
  assert.equal(p.intervals.size, 0);
  assert.equal(p.replies.length, 1);
});

test('instances have independent state, queues and counters', () => {
  const a = page(), b = page();
  a.command(1, 'draft', 'a'); a.command(2, 'heartbeat'); a.tick();
  b.command(1, 'snapshot');
  assert.equal(b.replies[0].value.draft, '');
  assert.equal(b.replies[0].value.ticks, 0);
  assert.equal(b.frames.size, 0);
  assert.equal(b.intervals.size, 0);
});

test('concurrent asynchronous commands keep their correlation IDs', () => {
  const p = page(); p.command(1, 'scroll'); p.command(2, 'paint');
  p.framesAfter(2); assert.deepEqual(p.replies.map(r => r.id), [2]);
  p.framesAfter(58); assert.deepEqual(p.replies.map(r => r.id), [2, 1]);
});

test('unknown commands return a bounded error reply and leave the page usable', () => {
  const p = page(); p.command(1, 'invalid');
  assert.match(p.replies[0].error, /Unknown fixture command/);
  p.command(2, 'snapshot'); assert.equal(p.replies.length, 2);
  assert.equal(p.replies[1].error, undefined);
});
