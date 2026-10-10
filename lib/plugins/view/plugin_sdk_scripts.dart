// מוזרק ב-AT_DOCUMENT_START ושומר בתור קריאות Otzaria.on() עד ל-_boot.
const String _sdkStubCore = r'''
  var _queue = [];
  var _realSdk = null;
  var _notReadyStream = function () {
    return {
      next: function () {
        return Promise.reject(new Error('Otzaria SDK not ready yet'));
      },
      [Symbol.asyncIterator]: function () { return this; }
    };
  };

  window.Otzaria = {
    call: function (method, payload) {
      if (_realSdk) return _realSdk.call(method, payload);
      if (method === 'search.query' || method === 'network.fetchStream') {
        return _notReadyStream();
      }
      return Promise.reject(new Error('Otzaria SDK not ready yet'));
    },
    on: function (event, cb) {
      if (_realSdk) { _realSdk.on(event, cb); }
      else { _queue.push({ event: event, cb: cb }); }
    },
    off: function (event, cb) {
      if (_realSdk) _realSdk.off(event, cb);
    },
    /* Called by Flutter once the real SDK + boot payload are ready */
    _boot: function (sdk, payload) {
      _realSdk = sdk;
      // סמן חיוּת לדיספצ'ר: קיים רק ב-context שבו התוסף באמת רץ. context
      // טרי שנוצר אחרי השמדת ה-platform view מקבל את ה-stub מחדש אך לא את
      // ה-boot — והיעדר הדגל מזוהה בפינג ומפעיל reload.
      window.Otzaria._booted = true;
      // Re-register all listeners that were queued before boot
      _queue.forEach(function (item) { sdk.on(item.event, item.cb); });
      _queue = [];
      window.dispatchEvent(new CustomEvent('plugin.boot', { detail: payload }));
      window.dispatchEvent(new CustomEvent('plugin.ready', { detail: null }));
    }
  };

  // Block window.open for security
  window.open = function () {
    console.error('window.open is locked for security.');
    return null;
  };
''';

const String _hostShortcutsJs = r'''

  // מקשי מקלדת נבלעים ב-WebView ולא מגיעים ל-Flutter — מעבירים ESC (יציאה
  // ממסך מלא) ואת קיצורי הניווט של התוכנה (הרשימה מוזרקת מ-Flutter).
  window.__otzariaHostShortcuts = [];
  window.__otzariaSetHostShortcuts = function (list) {
    window.__otzariaHostShortcuts = Array.isArray(list) ? list : [];
  };
  window.__otzariaMatchHostShortcut = function (e, list) {
    for (var i = 0; i < list.length; i++) {
      var s = list[i];
      if (s.codes.indexOf(e.code) !== -1 &&
          !!e.ctrlKey === !!s.ctrl && !!e.shiftKey === !!s.shift &&
          !!e.altKey === !!s.alt && !!e.metaKey === !!s.meta) {
        return s;
      }
    }
    return null;
  };
  var _nonTextInputTypes = ['button', 'checkbox', 'radio', 'submit', 'reset',
    'range', 'color', 'file', 'image'];
  window.__otzariaIsEditableTarget = function (e) {
    var t = e.composedPath ? e.composedPath()[0] : e.target;
    if (!t) return false;
    if (t.isContentEditable) return true;
    if (t.tagName === 'TEXTAREA') return true;
    return t.tagName === 'INPUT' &&
        _nonTextInputTypes.indexOf(String(t.type).toLowerCase()) === -1;
  };
  window.addEventListener('keydown', function (e) {
    if (!window.flutter_inappwebview) return;
    if (e.key === 'Escape') {
      window.flutter_inappwebview.callHandler('otzaria_escape_pressed');
    }
  }, true);
  // שלב bubble: קיצור שהתוסף טיפל בו (preventDefault) נשאר שלו. בשדה עריכה
  // מועברים רק הקיצורים הקבועים, כדי לא לגנוב קיצורי עריכה (Ctrl+K, Ctrl+H).
  window.addEventListener('keydown', function (e) {
    if (!window.flutter_inappwebview || e.key === 'Escape') return;
    if (e.repeat || e.defaultPrevented) return;
    var match = window.__otzariaMatchHostShortcut(e, window.__otzariaHostShortcuts);
    if (!match) return;
    if (match.id.indexOf('fixed:') !== 0 && window.__otzariaIsEditableTarget(e)) {
      return;
    }
    e.preventDefault();
    e.stopImmediatePropagation();
    window.flutter_inappwebview.callHandler('otzaria_host_shortcut', match.id);
  });
''';

/// ה-stub של מופע רקע.
const String pluginBackgroundSdkStubScript =
    '(function () {\n$_sdkStubCore})();\n';

/// ה-stub של לשונית תוסף, שמעביר גם מקשים ל-Flutter.
const String pluginSdkStubScript =
    '(function () {\n$_sdkStubCore$_hostShortcutsJs})();\n';

String _fontFaceJs(String fontFaceJson) =>
    '''
  try {
    var __css = $fontFaceJson;
    if (__css) {
      var __style = document.createElement('style');
      __style.setAttribute('data-otzaria-fonts', '1');
      __style.appendChild(document.createTextNode(__css));
      (document.head || document.documentElement).appendChild(__style);
    }
  } catch (e) { console.error('font-face inject failed', e); }
''';

/// ה-SDK האמיתי, מוזרק אחרי הטעינה וקורא ל-_boot. [fontFaceJson] מזריק לפניו
/// את הגופנים של התוכנה.
String buildPluginBootScript({
  required String nonceJson,
  required String payloadJson,
  String? fontFaceJson,
}) =>
    '''
(function () {
${fontFaceJson == null ? '' : _fontFaceJs(fontFaceJson)}  var _ls = {};
  var _searchStreams = {};
  var _searchSequence = 0;
  var _searchEvent = '__otzaria.search.query.chunk';
  var _networkStreams = {};
  var _networkSequence = 0;
  var _networkEvent = '__otzaria.network.fetchStream.chunk';
  var rpc = function (method, payload) {
    return window.flutter_inappwebview.callHandler('otzaria_rpc', {
      method: method,
      payload: payload || {},
      nonce: $nonceJson
    });
  };
  window.addEventListener(_searchEvent, function (event) {
    var detail = event.detail || {};
    var stream = _searchStreams[detail.streamId];
    if (stream) stream.push(detail.chunk);
  });
  window.addEventListener(_networkEvent, function (event) {
    var detail = event.detail || {};
    var stream = _networkStreams[detail.streamId];
    if (stream) stream.push(detail.chunk);
  });
  var createRpcStream = function (method, payload, streams, streamId) {
    var maxQueuedChunks = 256;
    var queue = [];
    var waiters = [];
    var ended = false;
    var failure = null;
    var flush = function () {
      while (waiters.length && queue.length) {
        waiters.shift().resolve({ value: queue.shift(), done: false });
      }
      if (queue.length || !ended) return;
      while (waiters.length) {
        var waiter = waiters.shift();
        if (failure) waiter.reject(failure);
        else waiter.resolve({ value: undefined, done: true });
      }
    };
    var session = {
      push: function (chunk) {
        if (ended) return;
        if (queue.length >= maxQueuedChunks) {
          session.fail(new Error('Stream consumer is too slow'));
          void rpc(method, { __cancelStreamId: streamId });
          return;
        }
        queue.push(chunk);
        flush();
      },
      finish: function () {
        if (ended) return;
        ended = true;
        delete streams[streamId];
        flush();
      },
      fail: function (error) {
        if (ended) return;
        failure = error instanceof Error ? error : new Error(String(error));
        ended = true;
        delete streams[streamId];
        flush();
      }
    };
    streams[streamId] = session;
    var request = Object.assign({}, payload || {}, { __streamId: streamId });
    rpc(method, request).then(function (response) {
      if (!response || response.success !== true) {
        var message = response && response.error && response.error.message;
        session.fail(new Error(message || 'Stream failed'));
        return;
      }
      session.finish();
    }, session.fail);
    return {
      next: function () {
        if (queue.length) return Promise.resolve({ value: queue.shift(), done: false });
        if (ended) {
          return failure
            ? Promise.reject(failure)
            : Promise.resolve({ value: undefined, done: true });
        }
        return new Promise(function (resolve, reject) {
          waiters.push({ resolve: resolve, reject: reject });
        });
      },
      return: function () {
        if (!ended) {
          ended = true;
          delete streams[streamId];
          flush();
          void rpc(method, { __cancelStreamId: streamId });
        }
        return Promise.resolve({ value: undefined, done: true });
      },
      [Symbol.asyncIterator]: function () { return this; }
    };
  };
  var createSearchStream = function (payload) {
    var id = 'search_' + Date.now().toString(36) + '_' + (++_searchSequence).toString(36);
    return createRpcStream('search.query', payload, _searchStreams, id);
  };
  var createNetworkFetchStream = function (payload) {
    var id = 'network_' + Date.now().toString(36) + '_' + (++_networkSequence).toString(36);
    return createRpcStream('network.fetchStream', payload, _networkStreams, id);
  };
  var realSdk = {
    call: function (method, payload) {
      if (method === 'search.query') return createSearchStream(payload);
      if (method === 'network.fetchStream') return createNetworkFetchStream(payload);
      return rpc(method, payload);
    },
    on: function (event, cb) {
      if (!_ls[event]) _ls[event] = [];
      var w = function (e) { cb(e.detail); };
      _ls[event].push({ orig: cb, wrap: w });
      window.addEventListener(event, w);
    },
    off: function (event, cb) {
      var list = _ls[event];
      if (!list) return;
      for (var i = 0; i < list.length; i++) {
        if (list[i].orig === cb) {
          window.removeEventListener(event, list[i].wrap);
          list.splice(i, 1);
          break;
        }
      }
    }
  };
  window.Otzaria._boot(realSdk, $payloadJson);
})();
''';
