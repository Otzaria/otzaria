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
}
