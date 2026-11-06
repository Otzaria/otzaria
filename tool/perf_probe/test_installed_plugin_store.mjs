import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import test from 'node:test';

const sourceDirectory = process.env.INSTALLED_PROBE_STORE_SOURCE;
assert.ok(sourceDirectory, 'Set INSTALLED_PROBE_STORE_SOURCE to the verified pinned Store directory.');
const source = readFileSync(path.join(sourceDirectory, 'index.html'), 'utf8');
const restore = readFileSync(path.join(sourceDirectory, 'restore-state.js'), 'utf8');
const sha = text => createHash('sha256').update(text).digest('hex');
assert.equal(sha(source), 'c6495a41ffc31a8e4b23828b3537c40478d0aa7d45a3cf680534e4e0cd0fed2f');
assert.equal(sha(restore), 'f0324b025009e9594135b17b911366388959ab5398c0485ac11b0316cd59332f');
const probe = readFileSync(process.env.INSTALLED_PROBE_SCENARIO_SOURCE ||
  new URL('../../integration_test/installed_plugin_resource_probe_test.dart', import.meta.url), 'utf8');

function between(text, start, end) {
  const first = text.indexOf(start), last = text.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `Missing exact source section: ${start}`);
  return text.slice(first, last);
}

const chunks = [
  between(source, '  let allPlugins = [];', '  // storage.get/set'),
  between(source, '  async function renderCurrentView(options = {}) {', '  function setViewTitle('),
  between(source, '  const SORT_DATE_FIELD = ', '  // ── דף הבית האצור'),
  between(source, '  async function renderSearch(renderId) {', '  // ── תגיות'),
  between(source, "  document.getElementById('search').addEventListener('input'", '  loadPlugins();'),
];
const body = between(probe, '  Future<void> storeScenario() async {', '  Future<void> backgroundScenario()');
const evaluateScript = /evaluate\(\s*controller\(tab\)!,\s*'''([\s\S]*?)'''\s*,?\s*\)/g;
const scripts = [...body.matchAll(evaluateScript)].map(match => match[1]);
assert.equal(scripts.length, 2);
const [inputs, scroll] = scripts;
const read = between(probe, '  Future<Map<String, Object?>> storeRead(', '  Future<Map<String, Object?>> storeReady(')
  .matchAll(evaluateScript).next().value[1]
  .replace('${jsonEncode(token)}', JSON.stringify('owned-store-document'));

async function store({ acknowledge = true } = {}) {
  let now = 0, timerId = 0;
  const timers = new Map(), frames = [], snapshots = [], requests = [];
  class Element {
    constructor(id) {
      this.id = id; this.value = ''; this.checked = false; this.children = []; this.listeners = new Map();
      this.style = { display: 'block' }; this.classList = { add() {}, remove() {}, toggle() {} };
      this.clientHeight = 600; this.scrollHeight = 4000; this._scrollTop = 0;
    }
    set innerHTML(value) { this.children = []; }
    get innerHTML() { return ''; }
    set scrollTop(value) { this._scrollTop = Math.max(0, Math.min(value, this.scrollHeight - this.clientHeight)); }
    get scrollTop() { return this._scrollTop; }
    appendChild(child) { this.children.push(child); }
    addEventListener(name, callback) {
      if (!this.listeners.has(name)) this.listeners.set(name, []);
      this.listeners.get(name).push(callback);
    }
    dispatchEvent(event) {
      event.target = this; event.currentTarget = this;
      for (const callback of this.listeners.get(event.type) || []) callback(event);
      return true;
    }
  }
  const elements = new Map();
  const element = id => { if (!elements.has(id)) elements.set(id, new Element(id)); return elements.get(id); };
  element('status-filter').value = 'all'; element('sort-select').value = 'recommended';
  const catalog = Array.from({ length: 18 }, (_, index) => ({ id: String(index), name: `Fixture ${index}`, status: 'beta', fileUpdatedAt: '2026-01-01' }));
  const context = {
    TextEncoder, Event: class { constructor(type) { this.type = type; } },
    navigator: { userAgent: 'Controlled Store source contract, not native WebView evidence' },
    document: { getElementById: element, addEventListener() {}, hidden: false },
    localStorage: { getItem() { return null; }, setItem() {} },
    requestAnimationFrame: callback => { frames.push(callback); return frames.length; },
    setTimeout: (callback, delay) => { const id = ++timerId; timers.set(id, { callback, due: now + delay }); return id; },
    clearTimeout: id => timers.delete(id),
    hide: id => { element(id).style.display = 'none'; }, show: id => { element(id).style.display = 'block'; },
    getComputedStyle: value => value.style,
    API: 'https://otzaria.org/api/plugins', t: value => value, updateCatsBarActive() {}, hasCuratedHome: () => false,
    persistentSet: async () => {}, updateTagsToggle() {}, render: () => { element('grid').children = [...catalog]; },
    renderHome() {}, renderCategory: async () => {}, showDetail: async () => {}, setViewTitle() {},
    toCatalogList: list => list, withAppVersion: url => url, applyInstalledFilter: list => list, makeCard: item => ({ ...item }),
    apiFetch: async url => { requests.push({ now, url }); return { status: 200, body: JSON.stringify({ results: catalog }) }; },
    Otzaria: { _booted: true, call: async (method, data) => {
      assert.equal(method, 'plugin.setRestoreState');
      if (acknowledge) snapshots.push({ now, state: structuredClone(data.state) });
      return { success: true, data: acknowledge };
    } },
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(restore, context);
  for (const chunk of chunks) vm.runInContext(chunk, context);
  vm.runInContext("catalogReady = true; currentView = {type: 'all'}; restoreState.activate();", context);
  element('grid').children = [...catalog]; element('loading').style.display = 'none';
  const flush = async () => { for (let i = 0; i < 24; i++) await Promise.resolve(); };
  await flush();
  const harness = {
    snapshots, requests, element,
    read: () => JSON.parse(vm.runInContext(read, context)),
    scroll: () => JSON.parse(vm.runInContext(scroll, context)),
    async inputs() { vm.runInContext(inputs, context); await flush(); },
    async frame() { const current = frames.splice(0); for (const callback of current) callback(now); await flush(); },
    async advance(delta) {
      const until = now + delta;
      while (true) {
        const pending = [...timers].filter(([, timer]) => timer.due <= until).sort((a, b) => a[1].due - b[1].due);
        if (!pending.length) break;
        const [id, timer] = pending[0]; timers.delete(id); now = timer.due; timer.callback(); await flush();
      }
      now = until; await flush();
    },
    async settled() { await harness.advance(300); await harness.frame(); await harness.frame(); },
  };
  return harness;
}

test('accepted filters and a populated grid cannot skip the final debounced render and both frames', async () => {
  const value = await store();
  await value.inputs();
  assert.equal(value.element('grid').children.length, 18);
  assert.equal(value.element('loading').style.display, 'none');
  const accepted = value.snapshots.at(-1).state;
  assert.equal(accepted.search, 'Fixture'); assert.equal(accepted.sort, 'updated');
  assert.equal(accepted.status, 'beta'); assert.equal(accepted.hideInstalled, true);
  assert.equal(value.read().ready, false, 'Accepted filters are earlier than a settled view.');
  await value.frame(); await value.frame();
  assert.equal(value.read().ready, false, 'An earlier filter render cannot satisfy the later search.');
  await value.advance(299);
  assert.equal(value.read().ready, false);
  await value.advance(1);
  assert.equal(value.read().ready, false);
  await value.frame();
  assert.equal(value.read().ready, false, 'The second frame remains required.');
  await value.frame();
  assert.equal(value.read().ready, true);
  assert.equal(value.read().rendering.pendingScroll, null);
  assert.equal(value.requests.length, 1, 'Only the final filter configuration starts a search.');
  assert.match(value.requests[0].url, /q=Fixture.*status=beta/);
});

test('the exact probe scroll survives later frames and is accepted only after the Store debounce', async () => {
  const value = await store(); await value.inputs(); await value.settled();
  assert.equal(value.read().ready, true);
  const assigned = value.scroll();
  assert.deepEqual(assigned, {
    requestedScrollTop: 420, actualScrollTop: 420, scrollHeight: 4000, clientHeight: 600,
    documentToken: 'owned-store-document',
  });
  assert.equal(value.snapshots.at(-1).state.scrollTop, 0);
  await value.advance(149); assert.equal(value.snapshots.at(-1).state.scrollTop, 0);
  await value.advance(1); assert.equal(value.snapshots.at(-1).state.scrollTop, 420);
  await value.advance(300); await value.frame(); await value.frame();
  assert.equal(value.snapshots.at(-1).state.scrollTop, 420);
  assert.equal(value.read().view.scrollTop, 420);
});

test('clamped geometry is reported as observed rather than as the requested scroll', async () => {
  const value = await store(); await value.inputs(); await value.settled();
  value.read();
  value.element('app-content').scrollHeight = 600;
  const assigned = value.scroll();
  assert.equal(assigned.requestedScrollTop, 420); assert.equal(assigned.actualScrollTop, 0);
  assert.equal(assigned.scrollHeight, assigned.clientHeight);
  await value.advance(150);
  assert.equal(value.snapshots.at(-1).state.scrollTop, 0);
});

test('an absent pinned render state is observable and cannot be treated as ready', () => {
  const element = { value: '', checked: false, children: [{}], scrollTop: 0 };
  const context = {
    document: { getElementById: () => element }, getComputedStyle: () => ({ display: 'none' }),
    navigator: { userAgent: 'no Store script' }, Otzaria: { _booted: true },
  };
  context.window = context;
  const observed = JSON.parse(vm.runInNewContext(read, context));
  assert.equal(observed.ready, false);
  assert.equal(observed.rendering.pendingScroll, 'unavailable');
  assert.equal(observed.rendering.sequence, null);
});

test('render readiness does not invent an acknowledged restore snapshot', async () => {
  const value = await store({ acknowledge: false });
  await value.inputs(); await value.settled();
  assert.equal(value.read().ready, true);
  value.scroll(); await value.advance(150);
  assert.equal(value.snapshots.length, 0);
});
