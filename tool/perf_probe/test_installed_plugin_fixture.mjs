import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import vm from 'node:vm';
import test from 'node:test';

const dart = readFileSync(new URL('../../integration_test/support/installed_plugin_fixture.dart', import.meta.url), 'utf8');
const html = dart.match(/const installedPluginProbeHtml = r'''([\s\S]*?)''';/)[1];
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const flush = async () => { for (let i = 0; i < 12; i++) await new Promise(resolve => setImmediate(resolve)); };

function document({ restore, runMode = 'foreground', acknowledge = true, pending } = {}) {
  const calls = [], listeners = new Map();
  const elements = { text: { value: '' }, scroll: { scrollTop: 0 } };
  const window = { addEventListener: (name, callback) => listeners.set(name, callback) };
  const Otzaria = { _booted: true, async call(method, args) {
    calls.push({ method, args });
    if (method === 'ui.showConfirm' && pending) return pending;
    return { success: true, data: method === 'plugin.setRestoreState' ? acknowledge : true };
  } };
  vm.runInNewContext(script, {
    window, document: { getElementById: id => elements[id], visibilityState: 'visible' },
    navigator: { userAgent: 'Node fixture contract, not native WebView evidence' },
    crypto: webcrypto, Uint32Array, TextEncoder, Otzaria,
  });
  listeners.get('plugin.boot')({ detail: { plugin: { id: 'fixture' }, app: { runMode }, restore } });
  return { probe: window.installedPluginProbe, calls, elements, listeners };
}

test('fixture uses injected host SDK, accepts acknowledgement and restores only on boot', async () => {
  const first = document(); await flush();
  assert.equal(first.probe.read().ready, true);
  first.probe.command('one', 'state', { text: 'saved input', scrollTop: 400 }); await flush();
  const state = first.calls.at(-1).args.state;
  const next = document({ restore: { reason: 'discarded', state } }); await flush();
  assert.deepEqual(JSON.parse(JSON.stringify(next.probe.read().view)), { version: 1, text: 'saved input', scrollTop: 400 });
  assert.notEqual(next.probe.read().documentToken, first.probe.read().documentToken);
  assert.equal(next.probe.read().bootCount, 1);
  assert.equal(next.calls[0].method, 'plugin.setRestoreState');
  assert.equal(next.probe.read().boot.restore.reason, 'discarded');
});

test('failed snapshot acknowledgement does not claim readiness', async () => {
  const fixture = document({ acknowledge: false }); await flush();
  assert.equal(fixture.probe.read().ready, false);
  assert.match(fixture.probe.read().error, /acknowledgement/);
});

test('guard commands use real SDK method names and a genuinely pending Promise', async () => {
  let resolve;
  const pending = new Promise(done => { resolve = done; });
  const fixture = document({ pending }); await flush();
  for (const [name, args] of [['noSnapshot', {}], ['unsaved', {value:true}], ['service', {value:true}], ['busy', {}]]) {
    fixture.probe.command(name, name, args); await flush();
    assert.equal(fixture.probe.read().acks[name].ok, true);
  }
  assert.equal(fixture.calls[1].args.state, null);
  assert.deepEqual(fixture.calls.slice(2).map(call => call.method), ['ui.setUnsavedChanges', 'reader.addContextMenuItem', 'ui.showConfirm']);
  assert.equal(fixture.probe.read().busyPending, true);
  resolve({ success:true, data:{ confirmed:false } }); await flush();
  assert.equal(fixture.probe.read().busyPending, false);
  assert.equal(fixture.probe.read().busyResult.confirmed, false);
});

test('background fixture does not claim a foreground restore snapshot', async () => {
  const fixture = document({ runMode: 'background' }); await flush();
  assert.equal(fixture.probe.read().ready, true);
  assert.equal(fixture.calls.length, 0);
  fixture.probe.command('done', 'backgroundDone'); await flush();
  assert.equal(fixture.calls[0].method, 'plugin.backgroundDone');
});

test('quiet document installs no heartbeat, animation or polling timer', async () => {
  assert.doesNotMatch(script, /setTimeout|setInterval|requestAnimationFrame/);
  const fixture = document(); await flush();
  const before = fixture.calls.length;
  await new Promise(resolve => setTimeout(resolve, 30));
  assert.equal(fixture.calls.length, before);
});
