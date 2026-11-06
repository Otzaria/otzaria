import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const dart = readFileSync(new URL('../../../integration_test/support/apple_plugin_activity_fixture.dart', import.meta.url), 'utf8');
const script = dart.match(/<script>([\s\S]*?)<\/script>/)[1];

function fixture() {
  let wall = 1000;
  const listeners = new Map();
  const intervals = [], timeouts = [], frames = [];
  const sdk = new Map();
  const context = {
    Date: {now: () => wall}, Math,
    performance: {now: () => wall - 1000, timeOrigin: 1000},
    document: {hidden: false, visibilityState: 'visible'},
    setInterval: callback => intervals.push(callback),
    setTimeout: callback => timeouts.push(callback),
    requestAnimationFrame: callback => frames.push(callback),
    Otzaria: new Proxy({}, {get(_, name) {
      assert.equal(name, 'on', 'Fixture must not send SDK RPC during quiet');
      return (topic, callback) => sdk.set(topic, callback);
    }}),
    addEventListener: (topic, callback) => listeners.set(topic, callback),
  };
  context.window = context;
  vm.runInNewContext(script, context);
  const fire = (topic, detail) => listeners.get(topic)({detail});
  fire('plugin.boot', {app: {runMode: 'background', instanceId: 'background'}});
  return {probe: context.appleActivity, intervals, timeouts, frames, sdk, fire,
    emit: (topic, event) => listeners.get(topic)(event),
    advance: value => {wall = value;},
    snapshot: () => JSON.parse(JSON.stringify(context.appleActivity.read()))};
}

test('local async, interval and rAF are independent of SDK RPC', async () => {
  const f = fixture();
  f.probe.arm('quiet');
  f.advance(1400);
  f.intervals[0]();
  f.frames.shift()();
  f.timeouts.shift()();
  await new Promise(resolve => setImmediate(resolve));
  const s = f.snapshot();
  for (const name of ['interval', 'raf', 'localAsync']) {
    assert.equal(s.streams[name].total, 1);
    assert.equal(s.streams[name].callbacks[0].wallMs, 1400);
  }
  assert.equal(s.boot.runMode, 'background');
});

test('execution timestamp, not a scheduled deadline, labels a delayed callback', () => {
  const f = fixture();
  f.probe.arm('quiet');
  f.advance(90000); // Simulate a queued callback finally running on resume.
  f.intervals[0]();
  assert.equal(f.snapshot().streams.interval.callbacks[0].wallMs, 90000);
});

test('bounded callback journal reports dropped records and preserves totals', () => {
  const f = fixture();
  for (let i = 0; i < 32770; i++) f.intervals[0]();
  const s = f.snapshot().streams.interval;
  assert.equal(s.callbacks.length, 32768);
  assert.equal(s.total, 32770);
  assert.equal(s.dropped, 2);
});

test('app command is received through the real SDK listener contract', () => {
  const f = fixture();
  f.probe.arm('quiet');
  f.sdk.get('reader.context_menu_item_clicked')({probeNonce: 'after-quiet'});
  assert.equal(f.snapshot().commands[0].nonce, 'after-quiet');
  assert.equal(f.snapshot().bootCount, 1);
  const token = f.snapshot().documentToken;
  const state = f.snapshot().stateCanary;
  assert.ok(state.includes('/local-state/quiet/1'));
  f.probe.arm('second');
  assert.equal(f.snapshot().documentToken, token);
  assert.notEqual(f.snapshot().stateCanary, state);
});

test('duplicate boot and runtime errors remain observable', () => {
  const f = fixture();
  f.fire('plugin.boot', {app: {runMode: 'background'}});
  assert.equal(f.snapshot().bootCount, 2);
  assert.notEqual(fixture().snapshot().documentToken, f.snapshot().documentToken);
  f.emit('error', {message: 'native fixture error'});
  assert.equal(f.snapshot().errors[0], 'native fixture error');
  for (let i = 0; i < 256; i++) f.emit('unhandledrejection', {reason: 'failure'});
  assert.equal(f.snapshot().errors.length, 256);
  assert.equal(f.snapshot().droppedErrors, 1);
});
