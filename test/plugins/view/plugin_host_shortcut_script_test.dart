import 'dart:convert';
import 'dart:io';

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
var listeners = [];
var window = {
  addEventListener: function (type, cb, capture) {
    if (type === 'keydown') listeners.push(cb);
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
var events = ${jsonEncode(events)};
var results = events.map(function (ev) {
  // pagePrevented: מטפל של התוסף כבר קרא ל-preventDefault לפני שלב ה-bubble.
  var e = Object.assign({ stopped: false }, ev);
  e.defaultPrevented = !!ev.pagePrevented;
  var hostPrevented = false;
  e.preventDefault = function () { e.defaultPrevented = true; hostPrevented = true; };
  e.stopImmediatePropagation = function () { e.stopped = true; };
  listeners.forEach(function (cb) { cb(e); });
  return { prevented: hostPrevented, stopped: e.stopped };
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

  test('קיצורי עריכה נשארים לתוסף וניווט קבוע מועבר (issue #1336)', () async {
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

  for (final (label, shortcut, code, shift, isMac) in [
    ('ברירת מחדל', 'ctrl+w', 'KeyW', false, false),
    ('מותאם אישית', 'ctrl+shift+q', 'KeyQ', true, false),
    ('Mac', 'ctrl+w', 'KeyW', false, true),
  ]) {
    test('סגירת כרטיסייה משדות עריכה — $label (issue #3942)', () async {
      PluginHostShortcuts.isMacForTesting = isMac;
      final shortcuts = PluginHostShortcuts.build({
        'key-shortcut-close-tab': shortcut,
      });
      const targets = [
        {'tagName': 'INPUT', 'type': 'text'},
        {'tagName': 'TEXTAREA'},
        {'tagName': 'DIV', 'isContentEditable': true},
      ];
      final out = await runStub(shortcuts, [
        for (final target in targets)
          for (final guard in const [
            <String, Object>{},
            {'pagePrevented': true},
            {'repeat': true},
          ])
            {
              'code': code,
              'key': code == 'KeyW' ? 'w' : 'Q',
              'ctrlKey': !isMac,
              'metaKey': isMac,
              'shiftKey': shift,
              'target': target,
              ...guard,
            },
      ]);
      if (out == null) {
        markTestSkipped('node אינו מותקן');
        return;
      }
      expect(out['calls'], [
        for (final _ in targets)
          {'name': 'otzaria_host_shortcut', 'arg': 'key-shortcut-close-tab'},
      ]);
      expect(out['results'], [
        for (final _ in targets) ...[
          {'prevented': true, 'stopped': true},
          {'prevented': false, 'stopped': false},
          {'prevented': false, 'stopped': false},
        ],
      ]);
    });
  }

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
}
