// סביבת הרצה מינימלית לקוד ה-JS של תוסף "תיקון קוראים", ללא שינוי בקוד המקור.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

export const PLUGIN_JS = process.env.TIKKUN_PLUGIN_JS ?? 'C:/tikkun-korim-plugin/js';

// טבלת ישויות HTML מצומצמת — התוסף מפענח דרך textarea.value בדפדפן.
// הרשימה נבדקת מול הטקסט בפועל (ראה assertKnownEntities).
const NAMED = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'",
  nbsp: '\u00a0', thinsp: '\u2009', ensp: '\u2002', emsp: '\u2003',
  ndash: '\u2013', mdash: '\u2014', hellip: '\u2026',
  lsquo: '\u2018', rsquo: '\u2019', ldquo: '\u201c', rdquo: '\u201d',
  bull: '\u2022', middot: '\u00b7', shy: '\u00ad', deg: '\u00b0',
};

export function decodeEntities(s) {
  return s.replace(/&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/g, (m, body) => {
    if (body[0] === '#') {
      const code = body[1] === 'x' || body[1] === 'X'
        ? parseInt(body.slice(2), 16)
        : parseInt(body.slice(1), 10);
      if (!Number.isFinite(code) || code < 0 || code > 0x10ffff) return m;
      return String.fromCodePoint(code);
    }
    const v = NAMED[body];
    return v === undefined ? m : v;
  });
}

/// מדווח על ישויות שהמפענח המצומצם אינו מכיר — כדי שהפורט לדארט לא ישתנה בשקט.
export function unknownEntities(s) {
  const found = new Set();
  for (const m of s.matchAll(/&([a-zA-Z][a-zA-Z0-9]*);/g)) {
    if (NAMED[m[1]] === undefined) found.add(m[1]);
  }
  return [...found];
}

function fakeElement(tag) {
  const el = {
    tagName: (tag || 'div').toUpperCase(),
    _innerHTML: '',
    value: '',
    className: '',
    textContent: '',
    innerText: '',
    children: [],
    style: {},
    max: 0,
    classList: {
      _set: new Set(),
      add(...c) { c.forEach((x) => this._set.add(x)); },
      remove(...c) { c.forEach((x) => this._set.delete(x)); },
      contains(c) { return this._set.has(c); },
      toggle(c) { this._set.has(c) ? this._set.delete(c) : this._set.add(c); },
    },
    appendChild(child) { this.children.push(child); return child; },
    querySelectorAll() { return []; },
    querySelector() { return null; },
    addEventListener() {},
    removeEventListener() {},
    getBoundingClientRect() { return { top: 0, left: 0, width: 0, height: 0 }; },
    scrollTo() {},
    focus() {},
  };
  Object.defineProperty(el, 'innerHTML', {
    get() { return this._innerHTML; },
    set(v) {
      this._innerHTML = String(v);
      // textarea.value בדפדפן = התוכן אחרי פענוח ישויות.
      this.value = decodeEntities(String(v));
    },
  });
  return el;
}

/// יוצר context עם window/document/console מזויפים, ומריץ בו את הקבצים.
export function loadPluginScripts(files) {
  const documentStub = {
    createElement: (tag) => fakeElement(tag),
    getElementById: () => fakeElement('div'),
    querySelectorAll: () => [],
    querySelector: () => null,
    addEventListener() {},
    body: fakeElement('body'),
    documentElement: fakeElement('html'),
  };
  const sandbox = {
    window: {},
    document: documentStub,
    console: { log() {}, warn() {}, error() {}, info() {}, debug() {} },
    performance: { now: () => Date.now() },
    setTimeout, clearTimeout, setInterval, clearInterval,
    requestAnimationFrame: (cb) => setTimeout(cb, 0),
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
  };
  sandbox.globalThis = sandbox;
  sandbox.self = sandbox;
  const ctx = vm.createContext(sandbox);
  for (const f of files) {
    const code = fs.readFileSync(path.join(PLUGIN_JS, f), 'utf8');
    vm.runInContext(code, ctx, { filename: f });
  }
  return ctx;
}
