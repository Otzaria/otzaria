(function () {
  'use strict';
  const listeners = new Map();
  const storage = new Map();
  const quota = 32 * 1024;
  let storedUnits = 0;
  Object.defineProperty(globalThis, 'window', { value: globalThis });
  globalThis.CustomEvent = class {
    constructor(type, options) {
      this.type = String(type);
      this.detail = options ? options.detail : null;
    }
  };
  globalThis.addEventListener = (type, callback) => {
    const list = listeners.get(type) || [];
    if (!list.includes(callback)) list.push(callback);
    listeners.set(type, list);
  };
  globalThis.removeEventListener = (type, callback) => {
    listeners.set(type, (listeners.get(type) || []).filter(item => item !== callback));
  };
  globalThis.dispatchEvent = event => {
    for (const callback of [...(listeners.get(event.type) || [])]) callback(event);
    return true;
  };
  Object.defineProperty(globalThis, 'localStorage', {
    value: Object.freeze({
      getItem: key => storage.get(String(key)) ?? null,
      setItem(key, value) {
        key = String(key);
        value = String(value);
        const previous = storage.get(key);
        const nextUnits = storedUnits + value.length - (previous?.length || 0) +
          (previous === undefined ? key.length : 0);
        if (nextUnits > quota) throw new Error('experiment.storage_quota');
        storage.set(key, value);
        storedUnits = nextUnits;
      },
      removeItem(key) {
        key = String(key);
        if (storage.has(key)) storedUnits -= key.length + storage.get(key).length;
        storage.delete(key);
      },
      clear() { storage.clear(); storedUnits = 0; },
      key: index => [...storage.keys()][index] ?? null,
      get length() { return storage.size; }
    })
  });
  globalThis.console = Object.freeze({
    log() {}, info() {}, debug() {}, warn() {}, error() {}
  });
})();
