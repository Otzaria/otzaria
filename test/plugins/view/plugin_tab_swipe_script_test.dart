import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_tab_swipe_script.dart';
import 'package:otzaria/tabs/utils/tab_swipe_direction.dart';

/// מריץ את הסקריפט ב-node עם `window` מזויף ומשגר אירועי wheel לפי הסדר.
/// כל אירוע: `dx`, `dy`, `t` (מילישניות, מחליף את Date.now) ואופציונלית
/// `scroller` — מאפייני אלמנט גלילה שנמצא בנתיב האירוע. מחזיר את הארגומנטים
/// שהועברו ל-handler. `null` = אין node.
Future<List<dynamic>?> runSwipe(List<Map<String, Object?>> events) async {
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
var now = 0;
Date.now = function () { return now; };
var document = { documentElement: {}, body: {} };
var getComputedStyle = function (el) {
  return { overflowX: el.overflowX || 'visible', direction: el.direction || 'ltr' };
};
var window = {
  addEventListener: function (type, cb, opts) {
    if (type === 'wheel') listeners.push({ cb: cb, opts: opts });
  },
  flutter_inappwebview: {
    callHandler: function (name, arg) { calls.push({ name: name, arg: arg }); }
  }
};
${buildPluginTabSwipeScript().source}
var events = ${jsonEncode(events)};
events.forEach(function (ev) {
  now = ev.t;
  var path = ev.scroller ? [Object.assign({ nodeType: 1 }, ev.scroller)] : [];
  listeners.forEach(function (l) {
    l.cb({
      deltaX: ev.dx, deltaY: ev.dy, deltaMode: ev.mode || 0,
      ctrlKey: !!ev.ctrl, composedPath: function () { return path; }
    });
  });
});
console.log(JSON.stringify({ calls: calls, passive: listeners[0].opts.passive }));
''';
  final result = await Process.run('node', ['-e', harness]);
  if (result.exitCode != 0) fail('node failed: ${result.stderr}');
  final out = jsonDecode(result.stdout.toString().trim());
  expect(out['passive'], isTrue, reason: 'המאזין אינו חוסם את הגלילה');
  return (out['calls'] as List).map((c) {
    expect(c['name'], pluginTabSwipeHandlerName);
    return c['arg'];
  }).toList();
}

/// מחווה אופקית: [count] אירועים של [dx] כל אחד במרווח של 16ms מ-[start].
List<Map<String, Object?>> gesture(
  double dx, {
  int count = 10,
  int start = 0,
  double dy = 0,
  Map<String, Object?>? scroller,
}) => [
  for (var i = 0; i < count; i++)
    {'dx': dx, 'dy': dy, 't': start + i * 16, 'scroller': scroller},
];

void main() {
  group('buildPluginTabSwipeScript', () {
    test('מוזרק לפני קוד הדף וגם ל-iframes', () {
      final script = buildPluginTabSwipeScript();
      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.forMainFrameOnly, isFalse);
    });

    test('קורא ל-handler ש-Flutter מאזין לו', () {
      expect(
        buildPluginTabSwipeScript().source,
        contains("callHandler('$pluginTabSwipeHandlerName'"),
      );
    });

    test('החלקה אופקית מדווחת פעם אחת, בכיוון האצבעות', () async {
      final left = await runSwipe(gesture(20));
      if (left == null) return markTestSkipped('node לא זמין');
      expect(left, hasLength(1));
      // deltaX חיובי = אצבעות שמאלה = dx שלילי ב-Flutter.
      expect(left.single, lessThan(0));
      final right = await runSwipe(gesture(-20));
      expect(right, hasLength(1));
      expect(right!.single, greaterThan(0));
    });

    test('תנופת ההמשך של אותה מחווה אינה מדווחת שוב', () async {
      final calls = await runSwipe([
        ...gesture(20),
        // אותו רצף ממשיך, מרווחים קטנים מ-IDLE.
        ...gesture(5, count: 40, start: 200),
      ]);
      if (calls == null) return markTestSkipped('node לא זמין');
      expect(calls, hasLength(1));
    });

    test('מחווה חדשה אחרי הפסקה מדווחת שוב', () async {
      final calls = await runSwipe([
        ...gesture(20),
        ...gesture(-20, start: 2000),
      ]);
      if (calls == null) return markTestSkipped('node לא זמין');
      expect(calls, hasLength(2));
      expect(calls[0], lessThan(0));
      expect(calls[1], greaterThan(0));
    });

    test('מחווה קצרה מהסף אינה מדווחת', () async {
      final calls = await runSwipe(gesture(5, count: 4));
      if (calls == null) return markTestSkipped('node לא זמין');
      expect(calls, isEmpty);
    });

    test('גלילה אנכית עם סטייה אופקית קלה אינה מדווחת', () async {
      final calls = await runSwipe(gesture(8, dy: 40, count: 30));
      if (calls == null) return markTestSkipped('node לא זמין');
      expect(calls, isEmpty);
    });

    test('צביטת זום וגלגלת עכבר בשורות מתעלמים', () async {
      final calls = await runSwipe([
        for (var i = 0; i < 10; i++)
          {'dx': 20, 'dy': 0, 't': i * 16, 'ctrl': true},
        for (var i = 0; i < 10; i++)
          {'dx': 3, 'dy': 0, 't': 2000 + i * 16, 'mode': 1},
      ]);
      if (calls == null) return markTestSkipped('node לא זמין');
      expect(calls, isEmpty);
    });

    test('אלמנט שעוד יכול לגלול לכיוון המחווה שומר אותה לעצמו', () async {
      final calls = await runSwipe(
        gesture(
          20,
          scroller: {
            'overflowX': 'auto',
            'scrollWidth': 1000,
            'clientWidth': 400,
            'scrollLeft': 100,
          },
        ),
      );
      if (calls == null) return markTestSkipped('node לא זמין');
      expect(calls, isEmpty);
    });

    test('אלמנט שהגיע לקצה בכיוון המחווה מאפשר מעבר טאב', () async {
      final calls = await runSwipe(
        gesture(
          20,
          scroller: {
            'overflowX': 'auto',
            'scrollWidth': 1000,
            'clientWidth': 400,
            'scrollLeft': 600,
          },
        ),
      );
      if (calls == null) return markTestSkipped('node לא זמין');
      expect(calls, hasLength(1));
    });

    test('ב-RTL scrollLeft הוא בטווח שלילי — 0 הוא הקצה הימני', () async {
      final rtlScroller = {
        'overflowX': 'auto',
        'direction': 'rtl',
        'scrollWidth': 1000,
        'clientWidth': 400,
        'scrollLeft': 0,
      };
      // deltaX חיובי = גלילה ימינה: בקצה הימני אין לאן → עובר טאב.
      final atEdge = await runSwipe(gesture(20, scroller: rtlScroller));
      if (atEdge == null) return markTestSkipped('node לא זמין');
      expect(atEdge, hasLength(1));
      // deltaX שלילי = גלילה שמאלה: עוד יש תוכן → שייך לדף.
      final inward = await runSwipe(gesture(-20, scroller: rtlScroller));
      expect(inward, isEmpty);
    });

    test('תחילת המחווה אנכית — הבעלות נקבעת באירוע האופקי הראשון', () async {
      final calls = await runSwipe([
        {'dx': 0, 'dy': 30, 't': 0},
        ...gesture(20, start: 16),
      ]);
      if (calls == null) return markTestSkipped('node לא זמין');
      expect(calls, hasLength(1));
    });
  });

  group('swipeTargetTabIndex', () {
    int? target(double dx, int current, int count, TextDirection dir) =>
        swipeTargetTabIndex(
          currentIndex: current,
          tabCount: count,
          accumulatedDx: dx,
          textDirection: dir,
        );

    test('ב-RTL החלקה ימינה מתקדמת לטאב הבא, שמאלה לקודם', () {
      expect(target(50, 1, 4, TextDirection.rtl), 2);
      expect(target(-50, 1, 4, TextDirection.rtl), 0);
    });

    test('ב-LTR הכיוון הפוך', () {
      expect(target(50, 1, 4, TextDirection.ltr), 0);
      expect(target(-50, 1, 4, TextDirection.ltr), 2);
    });

    test('בקצוות אין גלישה', () {
      expect(target(50, 3, 4, TextDirection.rtl), isNull);
      expect(target(-50, 0, 4, TextDirection.rtl), isNull);
      expect(target(50, 0, 1, TextDirection.rtl), isNull);
    });

    test('dx אפס אינו מזיז', () {
      expect(target(0, 1, 4, TextDirection.rtl), isNull);
    });
  });
}
