import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_host_shortcuts.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';

/// מריץ את סקריפט ה-stub של התוסף ב-node עם `window` מזויף, מזריק את רשימת
/// הקיצורים, משגר אירועי keydown ומחזיר מה הועבר ל-Flutter. `null` = אין node.
Future<Map<String, dynamic>?> runStub(
  List<PluginHostShortcut> shortcuts,
  List<Map<String, Object>> events,
) async {
  ProcessResult? probe;
  try {
    probe = await Process.run('node', ['--version']);
  } on ProcessException {
    probe = null;
  }
  if (probe == null || probe.exitCode != 0) return null;

  final harness =
      '''
var calls = [];
// Node provides listener order/removal/cancellation; each DOM phase has its
// own EventTarget so the bubble phase sees additions made during capture.
var captureTarget = new EventTarget();
var bubbleTarget = new EventTarget();
var window = {
  addEventListener: function (type, cb, capture) {
    (capture ? captureTarget : bubbleTarget).addEventListener(type, cb);
  },
  removeEventListener: function (type, cb, capture) {
    (capture ? captureTarget : bubbleTarget).removeEventListener(type, cb);
  },
  dispatchEvent: function () {},
  flutter_inappwebview: {
    callHandler: function (name, arg) {
      calls.push({ name: name, arg: arg === undefined ? null : arg });
    }
  }
};
var CustomEvent = function () {};
$pluginSdkStubScript
${buildSetHostShortcutsScript(shortcuts)}
var pluginHandling = false;
captureTarget.addEventListener('keydown', function (e) {
  if (!e.pagePrevented) return;
  pluginHandling = true;
  e.preventDefault();
  pluginHandling = false;
});
function pluginWindowHandler(e) {
  if (!e.windowAction) return;
  e.pageHandled++;
  e.pageSawPrevented = e.defaultPrevented;
  pluginHandling = true;
  if (e.windowAction === 'stop') e.stopImmediatePropagation();
  else e.preventDefault();
  pluginHandling = false;
}
var events = ${jsonEncode(events)};
var results = events.map(function (ev) {
  if (ev.registerWindowHandler) {
    window.addEventListener('keydown', pluginWindowHandler);
  }
  var e = new Event('keydown', { bubbles: true, cancelable: true });
  Object.keys(ev).forEach(function (key) {
    if (key !== 'target') e[key] = ev[key];
  });
  e.composedPath = function () { return [ev.target || window]; };
  e.pageHandled = 0;
  e.pageSawPrevented = null;
  var hostPrevented = false;
  var hostStopped = false;
  e.preventDefault = function () {
    if (!pluginHandling) hostPrevented = true;
    Event.prototype.preventDefault.call(e);
  };
  e.stopImmediatePropagation = function () {
    if (!pluginHandling) hostStopped = true;
    Event.prototype.stopImmediatePropagation.call(e);
  };
  captureTarget.dispatchEvent(e);
  bubbleTarget.dispatchEvent(e);
  return { prevented: hostPrevented, stopped: hostStopped,
    defaultPrevented: e.defaultPrevented, pageHandled: e.pageHandled,
    pageSawPrevented: e.pageSawPrevented };
});
console.log(JSON.stringify({ calls: calls, results: results }));
''';
  final result = await Process.run('node', ['-e', harness]);
  if (result.exitCode != 0) {
    fail('node failed: ${result.stderr}');
  }
  return jsonDecode(result.stdout.toString().trim()) as Map<String, dynamic>;
}

/// כמו [runStub], עם מסלול DOM מלא (window ← document ← שדה ← document ←
/// window), אירוע אמיתי (isTrusted) והמתנה אחרי סיום ההקשה. כל הרצה מתחילה
/// בדף נקי, ו-[scenario] בוחר את מאזיני התוסף. `null` = אין node.
Future<List<Map<String, dynamic>>?> runFieldPathStub(
  List<PluginHostShortcut> shortcuts,
  List<Map<String, Object>> runs,
) async {
  ProcessResult? probe;
  try {
    probe = await Process.run('node', ['--version']);
  } on ProcessException {
    probe = null;
  }
  if (probe == null || probe.exitCode != 0) return null;

  final harness =
      '''
function runOne(run) {
  var calls = [];
  var log = [];
  // לכל צומת EventTarget נפרד לכל שלב, כמו בדפדפן: מאזין שנוסף לצומת
  // שעוד לא הגיע תורו באותה הקשה נקרא, ומאזין לצומת הנוכחי לא.
  function node() {
    var capture = new EventTarget();
    var bubble = new EventTarget();
    var pick = function (opt) {
      return opt === true || (opt && opt.capture) ? capture : bubble;
    };
    return {
      addEventListener: function (t, cb, opt) { pick(opt).addEventListener(t, cb); },
      removeEventListener: function (t, cb, opt) { pick(opt).removeEventListener(t, cb); },
      capture: capture,
      bubble: bubble
    };
  }
  var window = node();
  window.dispatchEvent = function () {};
  window.flutter_inappwebview = {
    callHandler: function (name, arg) { calls.push(name + ':' + arg); }
  };
  var document = node();
  var field = node();
  field.tagName = run.target.tagName;
  field.type = run.target.type;
  field.isContentEditable = !!run.target.isContentEditable;
  var CustomEvent = function () {};
  (function () {
$pluginSdkStubScript
${buildSetHostShortcutsScript(shortcuts)}
  })();

  var pluginHandling = false;
  function dispatch(e) {
    var stopped = false;
    var hostPrevented = false;
    ['stopPropagation', 'stopImmediatePropagation'].forEach(function (name) {
      var stop = e[name];
      e[name] = function () {
        stopped = true;
        return stop.apply(e, arguments);
      };
    });
    var preventDefault = e.preventDefault;
    e.preventDefault = function () {
      if (!pluginHandling) hostPrevented = true;
      return preventDefault.apply(e, arguments);
    };
    e.composedPath = function () { return [field, document, window]; };
    var path = [window.capture, document.capture, field.bubble,
      document.bubble, window.bubble];
    for (var i = 0; i < path.length && !stopped && !e.cancelBubble; i++) path[i].dispatchEvent(e);
    // Chrome clears the native propagation flag after dispatch, before timers.
    var cancelBubbleDescriptor = Object.getOwnPropertyDescriptor(
      Event.prototype, 'cancelBubble');
    Object.defineProperty(e, 'cancelBubble', {
      configurable: true,
      get: function () { return false; },
      set: function (value) { cancelBubbleDescriptor.set.call(e, value); }
    });
    return hostPrevented;
  }
  function keydown(trusted) {
    var e = new Event('keydown', { bubbles: true, cancelable: true });
    Object.keys(run.key).forEach(function (k) { e[k] = run.key[k]; });
    if (trusted) Object.defineProperty(e, 'isTrusted', { value: true });
    return e;
  }
  function plugin(tag, action) {
    return function (e) {
      log.push(tag + (e.defaultPrevented ? ':sawPrevented' : ''));
      pluginHandling = true;
      if (action === 'stop') e.stopPropagation();
      else if (action === 'stopImmediate') e.stopImmediatePropagation();
      else if (action === 'cancelBubble') e.cancelBubble = true;
      else if (action === 'cancelBubbleThenFalse') { e.cancelBubble = true; e.cancelBubble = false; }
      else if (action === 'stopThenCancelBubbleFalse') { e.stopPropagation(); e.cancelBubble = false; }
      else if (action === 'immediateStopThenCancelBubbleFalse') { e.stopImmediatePropagation(); e.cancelBubble = false; }
      else if (action === 'prevent') e.preventDefault();
      pluginHandling = false;
    };
  }

  var s = run.scenario;
  if (s === 'fieldPrevents') field.addEventListener('keydown', plugin('field', 'prevent'));
  if (s === 'fieldStops') field.addEventListener('keydown', plugin('field', 'stop'));
  if (s === 'fieldCancelBubble') field.addEventListener('keydown', plugin('field', 'cancelBubble'));
  if (s === 'fieldCancelBubbleThenFalse') field.addEventListener('keydown', plugin('field', 'cancelBubbleThenFalse'));
  if (s === 'fieldStopThenCancelBubbleFalse') field.addEventListener('keydown', plugin('field', 'stopThenCancelBubbleFalse'));
  if (s === 'fieldImmediateStopThenCancelBubbleFalse') field.addEventListener('keydown', plugin('field', 'immediateStopThenCancelBubbleFalse'));
  if (s === 'windowSeesKey') window.addEventListener('keydown', plugin('window'));
  if (s === 'nestedListeners' || s === 'nestedListenersStop') {
    // רצף 1 מ-#5575: מאזין בשדה מוסיף מאזין ל-document, וזה מוסיף מאזין
    // ל-window באותה הקשה — אחרי שהמארח כבר סידר את המאזין שלו.
    field.addEventListener('keydown', function () {
      document.addEventListener('keydown', function () {
        window.addEventListener('keydown', plugin('window',
            s === 'nestedListeners' ? 'prevent' : 'stopImmediate'));
      });
    });
  }
  if (s === 'nestedDispatch') {
    // רצף 2 מ-#5575: מאזין בשדה משגר keydown פנימי סינכרוני, ואז רושם
    // מאזין ל-window עבור האירוע החיצוני.
    field.addEventListener('keydown', function (outer) {
      if (!outer.isTrusted) { log.push('inner'); return; }
      dispatch(keydown(false));
      window.addEventListener('keydown', function (e) {
        if (e === outer) plugin('window', 'prevent')(e);
      });
    });
  }
  var event = keydown(s !== 'untrusted');
  var hostPrevented = dispatch(event);
  return new Promise(function (resolve) {
    setTimeout(function () {
      resolve({ calls: calls, log: log, hostPrevented: hostPrevented,
        cancelBubble: event.cancelBubble });
    }, 20);
  });
}
Promise.all(${jsonEncode(runs)}.map(runOne)).then(function (results) {
  console.log(JSON.stringify(results));
});
''';
  final result = await Process.run('node', ['-e', harness]);
  if (result.exitCode != 0) {
    fail('node failed: ${result.stderr}');
  }
  return (jsonDecode(result.stdout.toString().trim()) as List)
      .cast<Map<String, dynamic>>();
}

void main() {
  setUp(() => PluginHostShortcuts.isMacForTesting = false);
  tearDown(() => PluginHostShortcuts.isMacForTesting = null);

  test(
    'קיצור ניווט מוגדר נתפס, נחסם מהדף ומועבר ל-Flutter לפי המזהה',
    () async {
      final shortcuts = PluginHostShortcuts.build({
        'key-shortcut-open-library-browser': 'ctrl+shift+q',
      });
      final out = await runStub(shortcuts, [
        {'code': 'KeyQ', 'key': 'Q', 'ctrlKey': true, 'shiftKey': true},
        // ברירת המחדל (ctrl+l) כבר אינה תקפה — המשתמש שינה אותה.
        {'code': 'KeyL', 'key': 'l', 'ctrlKey': true},
        // Ctrl+S נשאר לתוסף.
        {'code': 'KeyS', 'key': 's', 'ctrlKey': true},
        // repeat לא משוגר שוב.
        {
          'code': 'KeyQ',
          'key': 'Q',
          'ctrlKey': true,
          'shiftKey': true,
          'repeat': true,
        },
        {'code': 'Tab', 'key': 'Tab', 'ctrlKey': true},
        {'code': 'Escape', 'key': 'Escape'},
      ]);
      if (out == null) {
        markTestSkipped('node אינו מותקן');
        return;
      }
      final calls = (out['calls'] as List).cast<Map<String, dynamic>>();
      final results = (out['results'] as List).cast<Map<String, dynamic>>();

      expect(calls.map((c) => '${c['name']}:${c['arg']}'), [
        'otzaria_host_shortcut:key-shortcut-open-library-browser',
        'otzaria_host_shortcut:fixed:ctrl+tab',
        'otzaria_escape_pressed:null',
      ]);
      expect(results[0]['prevented'], isTrue);
      expect(results[0]['stopped'], isTrue);
      expect(results[1]['prevented'], isFalse);
      expect(results[2]['prevented'], isFalse);
      expect(results[3]['prevented'], isFalse);
      expect(results[5]['prevented'], isFalse, reason: 'ESC נשאר גם לדף');
    },
  );

  test('קיצור רשימת המקשים מכבד את התו, הספרון וקדימות העורך', () async {
    const id = 'key-shortcut-open-shortcuts-list';
    final shortcuts = PluginHostShortcuts.build({id: 'ctrl+slash'});
    final out = await runStub(shortcuts, [
      {'code': 'KeyQ', 'key': '/', 'ctrlKey': true},
      {'code': 'Slash', 'key': '.', 'ctrlKey': true},
      {'code': 'NumpadDivide', 'key': '/', 'ctrlKey': true},
      {
        'code': 'Slash',
        'key': '/',
        'ctrlKey': true,
        'target': {'tagName': 'TEXTAREA'},
      },
    ]);
    if (out == null) {
      markTestSkipped('node אינו מותקן');
      return;
    }
    final results = (out['results'] as List).cast<Map<String, dynamic>>();
    expect(results.map((r) => r['prevented']), [true, false, true, false]);
    final calls = (out['calls'] as List).cast<Map<String, dynamic>>();
    expect(calls.map((c) => c['arg']), [id, id]);
  });

  test('קיצורי עריכה נשארים בשדה והקבועים מועברים (issue #1336)', () async {
    final shortcuts = PluginHostShortcuts.build({});
    final out = await runStub(shortcuts, [
      // Ctrl+K בעורך — קיצור עריכה של התוסף, לא החלפת שולחן עבודה.
      {
        'code': 'KeyK',
        'key': 'k',
        'ctrlKey': true,
        'target': {'tagName': 'TEXTAREA'},
      },
      {
        'code': 'KeyK',
        'key': 'k',
        'ctrlKey': true,
        'target': {'tagName': 'DIV', 'isContentEditable': true},
      },
      {
        'code': 'KeyK',
        'key': 'k',
        'ctrlKey': true,
        'target': {'tagName': 'INPUT', 'type': 'text'},
      },
      // תיבת סימון אינה שדה עריכה.
      {
        'code': 'KeyK',
        'key': 'k',
        'ctrlKey': true,
        'target': {'tagName': 'INPUT', 'type': 'checkbox'},
      },
      {
        'code': 'Tab',
        'key': 'Tab',
        'ctrlKey': true,
        'target': {'tagName': 'TEXTAREA'},
      },
    ]);
    if (out == null) {
      markTestSkipped('node אינו מותקן');
      return;
    }
    final calls = (out['calls'] as List).cast<Map<String, dynamic>>();
    expect(calls.map((c) => c['arg']), [
      'key-shortcut-switch-workspace',
      'fixed:ctrl+tab',
    ]);
  });

  test('קיצור שהתוסף טיפל בו בעצמו נשאר שלו (issue #1336)', () async {
    final shortcuts = PluginHostShortcuts.build({});
    final out = await runStub(shortcuts, [
      {'code': 'KeyL', 'key': 'l', 'ctrlKey': true, 'pagePrevented': true},
      {'code': 'KeyL', 'key': 'l', 'ctrlKey': true},
    ]);
    if (out == null) {
      markTestSkipped('node אינו מותקן');
      return;
    }
    final calls = (out['calls'] as List).cast<Map<String, dynamic>>();
    final results = (out['results'] as List).cast<Map<String, dynamic>>();
    expect(calls.map((c) => c['arg']), ['key-shortcut-open-library-browser']);
    expect(results[0]['prevented'], isFalse);
    expect(results[1]['prevented'], isTrue);
  });

  group('חיפוש חדש משדה בתוסף (issue #2203)', () {
    const targets = <Map<String, Object>>[
      {'tagName': 'INPUT', 'type': 'text'},
      {'tagName': 'TEXTAREA'},
      {'tagName': 'DIV', 'isContentEditable': true},
    ];
    const searchId = 'key-shortcut-open-new-search';

    Future<Map<String, dynamic>> runRequiredStub(
      List<PluginHostShortcut> shortcuts,
      List<Map<String, Object>> events,
    ) async {
      final out = await runStub(shortcuts, events);
      expect(out, isNotNull, reason: 'node נדרש לבדיקת גשר המקלדת');
      return out!;
    }

    void expectSearchCalls(Map<String, dynamic> out, int count) {
      final calls = (out['calls'] as List).cast<Map<String, dynamic>>();
      expect(
        calls.map((call) => '${call['name']}:${call['arg']}'),
        List.filled(count, 'otzaria_host_shortcut:$searchId'),
      );
    }

    for (final isMac in [false, true]) {
      final modifier = isMac ? 'metaKey' : 'ctrlKey';
      final searchKey = <String, Object>{
        'code': 'KeyF',
        // פריסה עברית: ההתאמה היא למקש הפיזי ולא לתו המוקלד.
        'key': 'כ',
        modifier: true,
        'shiftKey': true,
      };

      testWidgets('ברירת המחדל עוברת מהגשר לצינור המקלדת: mac=$isMac', (
        tester,
      ) async {
        PluginHostShortcuts.isMacForTesting = isMac;
        final shortcuts = PluginHostShortcuts.build({});
        final out = await tester.runAsync(
          () => runRequiredStub(shortcuts, [
            for (final target in targets) {...searchKey, 'target': target},
          ]),
        );
        expectSearchCalls(out!, targets.length);
        expect(
          (out['results'] as List).map((result) => result['prevented']),
          everyElement(isTrue),
        );
        expect(
          (out['results'] as List).map((result) => result['stopped']),
          everyElement(isTrue),
        );

        var searches = 0;
        await tester.pumpWidget(
          CallbackShortcuts(
            bindings: {
              SingleActivator(
                LogicalKeyboardKey.keyF,
                control: !isMac,
                meta: isMac,
                shift: true,
              ): () =>
                  searches++,
            },
            child: const Focus(autofocus: true, child: SizedBox()),
          ),
        );
        await tester.pump();
        // כמו ה-handler של PluginTabPage: פענוח מזהה הגשר מול ההגדרות
        // הנוכחיות, ואז הזרקה אמיתית של מקשי Flutter.
        for (final call in out['calls'] as List) {
          final shortcut = shortcuts.singleWhere((s) => s.id == call['arg']);
          expect(PluginHostShortcuts.dispatch(shortcut), isTrue);
        }
        expect(searches, targets.length);
        expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
      });

      test('קיצור חיפוש מותאם וביטולו נשמרים בשדות: mac=$isMac', () async {
        PluginHostShortcuts.isMacForTesting = isMac;
        for (final shortcut in ['ctrl+shift+g', 'ctrl+b', 'f6']) {
          final customKey = shortcut == 'f6'
              ? <String, Object>{'code': 'F6', 'key': 'F6'}
              : <String, Object>{
                  'code': shortcut == 'ctrl+b' ? 'KeyB' : 'KeyG',
                  'key': shortcut == 'ctrl+b' ? 'נ' : 'ע',
                  modifier: true,
                  'shiftKey': shortcut != 'ctrl+b',
                };
          final out = await runRequiredStub(
            PluginHostShortcuts.build({searchId: shortcut}),
            [
              for (final target in targets) ...[
                {...searchKey, 'target': target},
                {...customKey, 'target': target},
              ],
            ],
          );
          expectSearchCalls(out, targets.length);
          expect(
            (out['results'] as List).map((result) => result['prevented']),
            [
              for (final _ in targets) ...[false, true],
            ],
          );
        }
        final disabled = await runRequiredStub(
          PluginHostShortcuts.build({searchId: ''}),
          [
            for (final target in targets) {...searchKey, 'target': target},
          ],
        );
        expect(disabled['calls'], isEmpty);
        expect(
          (disabled['results'] as List).map((result) => result['prevented']),
          everyElement(isFalse),
        );
      });

      test('מאזין window שנרשם אחרי המארח מקבל קדימות: mac=$isMac', () async {
        PluginHostShortcuts.isMacForTesting = isMac;
        for (final action in ['prevent', 'stop']) {
          final out = await runRequiredStub(PluginHostShortcuts.build({}), [
            // גם רישום אחרי אירוע קודם צריך להקדים את המארח באירוע הבא.
            {'code': 'KeyA', 'key': 'ש', 'target': targets.first},
            for (final target in targets)
              {
                ...searchKey,
                'target': target,
                'registerWindowHandler': true,
                'windowAction': action,
              },
          ]);
          expect(out['calls'], isEmpty);
          final results = (out['results'] as List).skip(1);
          expect(results.map((r) => r['pageHandled']), everyElement(1));
          expect(
            results.map((r) => r['pageSawPrevented']),
            everyElement(false),
          );
          expect(results.map((r) => r['prevented']), everyElement(false));
          expect(results.map((r) => r['stopped']), everyElement(false));
          expect(
            results.map((r) => r['defaultPrevented']),
            everyElement(action == 'prevent'),
          );
        }
      });

      test('קדימות התוסף, עריכה ומעבר טאבים נשמרים: mac=$isMac', () async {
        PluginHostShortcuts.isMacForTesting = isMac;
        final out = await runRequiredStub(PluginHostShortcuts.build({}), [
          for (final target in targets) ...[
            {...searchKey, 'target': target, 'pagePrevented': true},
            {...searchKey, 'target': target, 'repeat': true},
            {'code': 'KeyF', 'key': 'כ', 'target': target},
            for (final key in ['K', 'H', 'F'])
              {
                'code': 'Key$key',
                'key': key.toLowerCase(),
                modifier: true,
                'target': target,
              },
            {'code': 'Tab', 'key': 'Tab', 'ctrlKey': true, 'target': target},
          ],
        ]);
        final calls = (out['calls'] as List).cast<Map<String, dynamic>>();
        expect(
          calls.map((call) => '${call['name']}:${call['arg']}'),
          List.filled(targets.length, 'otzaria_host_shortcut:fixed:ctrl+tab'),
        );
        final expected = [
          for (final _ in targets) ...[
            false,
            false,
            false,
            false,
            false,
            false,
            true,
          ],
        ];
        expect(
          (out['results'] as List).map((result) => result['prevented']),
          expected,
        );
        expect(
          (out['results'] as List).map((result) => result['stopped']),
          expected,
        );
      });
    }
  });

  group('קיצורי לשוניות משדה בתוסף (issue #3942)', () {
    const targets = <String, Map<String, Object>>{
      'input': {'tagName': 'INPUT', 'type': 'text'},
      'textarea': {'tagName': 'TEXTAREA'},
      'contenteditable': {'tagName': 'DIV', 'isContentEditable': true},
    };

    for (final isMac in [false, true]) {
      final modifier = isMac ? 'metaKey' : 'ctrlKey';
      Map<String, Object> key(String code, {bool shift = false}) => {
        'code': code,
        'key': code == 'KeyW' ? "'" : 'א',
        modifier: true,
        'shiftKey': shift,
      };
      final closeTab = key('KeyW');

      for (final MapEntry(key: name, value: target) in targets.entries) {
        Future<List<Map<String, dynamic>>> run(
          List<Map<String, Object>> runs,
        ) async {
          PluginHostShortcuts.isMacForTesting = isMac;
          final out = await runFieldPathStub(PluginHostShortcuts.build({}), [
            for (final r in runs) {'target': target, ...r},
          ]);
          expect(out, isNotNull, reason: 'node נדרש לבדיקת גשר המקלדת');
          return out!;
        }

        test(
          'רצפי DOM מ-#5575: מאזין התוסף קודם למארח: $name mac=$isMac',
          () async {
            final out = await run([
              for (final scenario in [
                'nestedListeners',
                'nestedListenersStop',
                'nestedDispatch',
              ])
                {'key': closeTab, 'scenario': scenario},
            ]);
            expect(out.map((r) => r['calls']), everyElement(isEmpty));
            expect(out.map((r) => r['hostPrevented']), everyElement(isFalse));
            expect(out.map((r) => r['log']), [
              ['window'],
              ['window'],
              ['inner', 'window'],
            ]);
          },
        );

        test(
          'קיצורי לשוניות עוברים מהשדה אחרי הדף: $name mac=$isMac',
          () async {
            final out = await run([
              {'key': closeTab, 'scenario': 'none'},
              {'key': key('KeyW', shift: true), 'scenario': 'none'},
              {'key': key('KeyT', shift: true), 'scenario': 'none'},
              {'key': closeTab, 'scenario': 'windowSeesKey'},
              {'key': closeTab, 'scenario': 'fieldPrevents'},
              {'key': closeTab, 'scenario': 'fieldStops'},
              {'key': closeTab, 'scenario': 'fieldCancelBubble'},
              {'key': closeTab, 'scenario': 'fieldCancelBubbleThenFalse'},
              {'key': closeTab, 'scenario': 'fieldStopThenCancelBubbleFalse'},
              {
                'key': closeTab,
                'scenario': 'fieldImmediateStopThenCancelBubbleFalse',
              },
              {'key': closeTab, 'scenario': 'untrusted'},
              {
                'key': {...closeTab, 'repeat': true},
                'scenario': 'none',
              },
              // קיצור עריכה (Ctrl+K) נשאר בשדה.
              {'key': key('KeyK'), 'scenario': 'none'},
            ]);
            expect(out.map((r) => r['calls']), [
              ['otzaria_host_shortcut:key-shortcut-close-tab'],
              ['otzaria_host_shortcut:key-shortcut-close-all-tabs'],
              ['otzaria_host_shortcut:key-shortcut-restore-closed-tab'],
              ['otzaria_host_shortcut:key-shortcut-close-tab'],
              isEmpty,
              isEmpty,
              isEmpty,
              isEmpty,
              isEmpty,
              isEmpty,
              isEmpty,
              isEmpty,
              isEmpty,
            ]);
            expect(out[6]['cancelBubble'], isFalse);
            expect(out[7]['cancelBubble'], isFalse);
            // הדף רואה את ההקשה כפי שהיא; המארח לא חוסם אותה בשדה.
            expect(out[3]['log'], ['window']);
            expect(out.map((r) => r['hostPrevented']), everyElement(isFalse));
          },
        );
      }
    }
  });
}
