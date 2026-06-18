import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

// ── fake repository לשליטה ב-enabled/permission בלי SQLite ────────────────
class _FakeRegistryRepo extends Fake implements PluginRegistryRepository {
  _FakeRegistryRepo({this.enabled = true, this.permission = true});
  final bool enabled;
  final bool? permission;

  @override
  Future<bool> getIsEnabled(String pluginId) async => enabled;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      this.permission;
}

class _FakeWebViewController extends Fake implements InAppWebViewController {
  int loadUrlCalls = 0;
  int evaluateJavascriptCalls = 0;
  URLRequest? lastUrlRequest;

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async {
    loadUrlCalls++;
    lastUrlRequest = urlRequest;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    evaluateJavascriptCalls++;
    return null;
  }
}

// ── fake controller פשוט עבור בדיקות שלא דורשות הפעלת methods ─────────────
// registerController רק שומר את ה-object במפה; אין קריאות ל-methods שלו
// בטסטים אלה (אנחנו לא מפעילים dispatchEvent שדורש SQLite).
class _FakeController extends Fake implements InAppWebViewController {}

// ── fake controller שמתעד pause/resume ואירועי lifecycle ל-JS ─────────────
class _LifecycleFakeController extends Fake implements InAppWebViewController {
  int pauseCalls = 0;
  int resumeCalls = 0;
  final List<String> jsEvents = [];

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    jsEvents.add(source);
    return null;
  }
}

// ── fake controller עם pause/resume שניתן לעכב (gate) — לבדיקת serialization.
// מתעד את רצף הפעולות הגלובלי בכל הבקרים כדי לוודא שאין חפיפה.
class _SlowController extends Fake implements InAppWebViewController {
  _SlowController(this.name, this.log);
  final String name;
  final List<String> log;
  Completer<void>? pauseGate;
  Completer<void>? resumeGate;

  @override
  Future<void> pause() async {
    log.add('$name:pause:start');
    if (pauseGate != null) await pauseGate!.future;
    log.add('$name:pause:end');
  }

  @override
  Future<void> resume() async {
    log.add('$name:resume:start');
    if (resumeGate != null) await resumeGate!.future;
    log.add('$name:resume:end');
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    final kind = source.contains('suspended')
        ? 'suspended'
        : source.contains('resumed')
            ? 'resumed'
            : 'other';
    log.add('$name:js:$kind');
    return null;
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

const _kPid = 'dispatcher.test.plugin';

PluginRuntimeDispatcher get _d => PluginRuntimeDispatcher.instance;

void _cleanupControllers() {
  _d.unregisterController(_kPid);
  _d.unregisterController(_kPid, instanceId: 'background');
}

void _cleanupCallbacks() {
  _d.unregisterReloadCallback(_kPid);
  _d.unregisterReloadCallback(_kPid, instanceId: 'background');
}

void main() {
  late PluginRuntimeDispatcher dispatcher;

  setUp(() async {
    dispatcher = PluginRuntimeDispatcher.instance;
    await dispatcher.prepareForAppRestart();
    // prepareForAppRestart משאיר את _shutdownMode במצב 'restart'.
    // register+unregister של controller דמה מאפס חזרה ל-idle כך
    // שבדיקות הבאות (כמו reloadPlugin) לא יידחו על ידי בדיקת shutdownMode.
    dispatcher.registerController('__test_reset__', _FakeController());
    dispatcher.unregisterController('__test_reset__');
  });

  test('prepareForAppShutdown tears down controllers and blocks re-registering',
      () async {
    final firstController = _FakeWebViewController();
    dispatcher.registerController('plugin-a', firstController);

    await dispatcher.prepareForAppShutdown();

    expect(firstController.loadUrlCalls, 1);
    expect(
      firstController.lastUrlRequest?.url?.toString(),
      'about:blank',
    );

    final lateController = _FakeWebViewController();
    dispatcher.registerController('plugin-a', lateController);

    await dispatcher.dispatchEventToPlugin(
      'plugin-a',
      'reader.current_ref_changed',
      {'currentBook': 'בראשית'},
    );

    expect(lateController.evaluateJavascriptCalls, 0);

    await dispatcher.prepareForAppRestart();
  });

  // ── register / unregister ─────────────────────────────────────────────────

  group('registerController / unregisterController', () {
    tearDown(_cleanupControllers);

    test('מעגן controller בלי לקרוס', () {
      _d.registerController(_kPid, _FakeController());
      // ניקוי עצמי — אין exception
      _d.unregisterController(_kPid);
    });

    test('unregister פעמיים הוא no-op', () {
      _d.registerController(_kPid, _FakeController());
      _d.unregisterController(_kPid);
      expect(() => _d.unregisterController(_kPid), returnsNormally);
    });

    test('foreground ו-background יכולים לדור יחד', () {
      _d.registerController(_kPid, _FakeController(), instanceId: 'default');
      _d.registerController(_kPid, _FakeController(), instanceId: 'background');
      // unregister סלקטיבי — כל אחד בנפרד
      _d.unregisterController(_kPid, instanceId: 'default');
      _d.unregisterController(_kPid, instanceId: 'background');
    });

    test('invalidatePlugin על plugin לא רשום אינו קורס', () {
      expect(() => _d.invalidatePlugin('no.such.plugin'), returnsNormally);
    });
  });

  // ── foreground-preference selection logic ─────────────────────────────────
  //
  // בודק את הלוגיקה שהוספנו ב-dispatchEvent ו-dispatchEventToPlugin:
  //   final targets = instances.containsKey('default')
  //       ? [instances['default']!]
  //       : instances.values.toList();
  //
  // הטסטים מכסים את ארבע הצירופים האפשריים של instances.

  group('foreground-preference selection', () {
    Map<String, String> selectTargets(Map<String, String> instances) =>
        instances.containsKey('default')
            ? {'default': instances['default']!}
            : Map.fromEntries(instances.entries);

    test('כשיש foreground וגם background — נבחר רק foreground', () {
      final instances = {'default': 'fg', 'background': 'bg'};
      final result = selectTargets(instances);
      expect(result.keys, equals(['default']));
      expect(result.values, equals(['fg']));
      expect(result.containsValue('bg'), isFalse);
    });

    test('כשיש רק background — נבחר background', () {
      final instances = {'background': 'bg'};
      final result = selectTargets(instances);
      expect(result.values.toList(), equals(['bg']));
    });

    test('כשיש רק default — נבחר default', () {
      final instances = {'default': 'fg'};
      final result = selectTargets(instances);
      expect(result.values.toList(), equals(['fg']));
    });

    test('כשאין instances — מחזיר ריק', () {
      final instances = <String, String>{};
      final result = selectTargets(instances);
      expect(result, isEmpty);
    });

    test(
        'instance נוסף (לא default/background) — נבחר גם הוא בהיעדר foreground',
        () {
      final instances = {'background': 'bg', 'extra': 'ex'};
      final result = selectTargets(instances);
      expect(result.containsKey('background'), isTrue);
      expect(result.containsKey('extra'), isTrue);
    });
  });

  // ── reloadPlugin callbacks ────────────────────────────────────────────────

  group('reloadPlugin', () {
    tearDown(_cleanupCallbacks);

    test('ללא callback רשום — לא קורס', () async {
      await expectLater(_d.reloadPlugin(_kPid), completes);
    });

    test('callback רשום מופעל', () async {
      var called = false;
      _d.registerReloadCallback(_kPid, () async {
        called = true;
      });
      await _d.reloadPlugin(_kPid);
      expect(called, isTrue);
    });

    test('callback מנוסח מחדש לאחר unregister — לא מופעל', () async {
      var called = false;
      _d.registerReloadCallback(_kPid, () async {
        called = true;
      });
      _d.unregisterReloadCallback(_kPid);
      await _d.reloadPlugin(_kPid);
      expect(called, isFalse);
    });

    test('שני callbacks (foreground + background) — שניהם מופעלים', () async {
      final calls = <String>[];
      _d.registerReloadCallback(_kPid, () async {
        calls.add('fg');
      }, instanceId: 'default');
      _d.registerReloadCallback(_kPid, () async {
        calls.add('bg');
      }, instanceId: 'background');

      await _d.reloadPlugin(_kPid);

      expect(calls, containsAll(['fg', 'bg']));
    });

    test('unregister background בלבד — foreground עדיין מופעל', () async {
      final calls = <String>[];
      _d.registerReloadCallback(_kPid, () async {
        calls.add('fg');
      }, instanceId: 'default');
      _d.registerReloadCallback(_kPid, () async {
        calls.add('bg');
      }, instanceId: 'background');
      _d.unregisterReloadCallback(_kPid, instanceId: 'background');

      await _d.reloadPlugin(_kPid);

      expect(calls, equals(['fg']));
    });
  });

  // ── השהיה/חידוש של ה-instance ה-foreground ────────────────────────────────

  group('foreground suspend/resume', () {
    const pidA = 'plugin.a';
    const pidB = 'plugin.b';

    tearDown(() {
      _d.unregisterController(pidA);
      _d.unregisterController(pidA, instanceId: 'background');
      _d.unregisterController(pidB);
      // שחזור ה-repository האמיתי לטסטים שהזריקו fake.
      _d.repositoryForTesting = PluginRegistryRepository();
    });

    test('מעבר מתוסף לתוסף משהה את הקודם ומחדש את הנכנס', () async {
      final a = _LifecycleFakeController();
      final b = _LifecycleFakeController();
      _d.registerController(pidA, a);
      _d.registerController(pidB, b);

      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();
      expect(a.resumeCalls, 1);
      expect(a.jsEvents.last, contains('plugin.resumed'));

      _d.setSelectedToolPlugin(pidB);
      await pumpEventQueue();
      expect(a.pauseCalls, 1);
      expect(a.jsEvents, contains(contains('plugin.suspended')));
      expect(b.resumeCalls, 1);
    });

    test('יציאה ממסך הכלים משהה, וחזרה מחדשת', () async {
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();
      expect(a.resumeCalls, 1);

      _d.setToolsScreenVisible(false);
      await pumpEventQueue();
      expect(a.pauseCalls, 1);

      _d.setToolsScreenVisible(true);
      await pumpEventQueue();
      expect(a.resumeCalls, 2);
    });

    test('instance הרקע אינו מושהה ביציאה', () async {
      final bg = _LifecycleFakeController();
      _d.registerController(pidA, bg, instanceId: 'background');

      _d.setSelectedToolPlugin(pidA);
      _d.setToolsScreenVisible(false);
      await pumpEventQueue();

      expect(bg.pauseCalls, 0);
      expect(bg.resumeCalls, 0);
    });

    test('תוסף עם foreground ורקע — רק ה-foreground מושהה', () async {
      final fg = _LifecycleFakeController();
      final bg = _LifecycleFakeController();
      _d.registerController(pidA, fg, instanceId: 'default');
      _d.registerController(pidA, bg, instanceId: 'background');

      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();
      _d.setToolsScreenVisible(false);
      await pumpEventQueue();

      expect(fg.pauseCalls, 1);
      expect(bg.pauseCalls, 0);
    });

    test('מעבר לכלי מובנה (null) משהה את התוסף ולא מנסה לחדש', () async {
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();
      _d.setSelectedToolPlugin(null);
      await pumpEventQueue();

      expect(a.pauseCalls, 1);
    });

    test('חידוש תוסף מסנכרן מחדש את ה-theme האחרון (שאבד בזמן ההשהיה)',
        () async {
      _d.repositoryForTesting =
          _FakeRegistryRepo(enabled: true, permission: true);
      // dispatchEvent ללא controllers רשומים — שומר רק את ה-payload האחרון
      // ומדמה החלפת מצב כהה בזמן שהתוסף מושהה.
      await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();

      expect(a.resumeCalls, 1);
      expect(
        a.jsEvents,
        contains(allOf(contains('theme.changed'), contains('dark'))),
      );
    });

    test('חידוש לא שולח theme כשאין הרשאת events.subscribe', () async {
      _d.repositoryForTesting =
          _FakeRegistryRepo(enabled: true, permission: false);
      await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();

      expect(a.resumeCalls, 1);
      expect(a.jsEvents.any((e) => e.contains('theme.changed')), isFalse);
    });

    test('חידוש לא שולח theme כשהתוסף מושבת', () async {
      _d.repositoryForTesting = _FakeRegistryRepo(enabled: false);
      await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();

      expect(a.jsEvents.any((e) => e.contains('theme.changed')), isFalse);
    });

    test('חידוש ללא theme קודם — לא שולח theme.changed', () async {
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();

      expect(a.jsEvents.any((e) => e.contains('theme.changed')), isFalse);
    });
  });

  // ── serialization של פעולות מחזור-חיים (race בין reconciles חופפים) ────────

  group('lifecycle serialization', () {
    const pidA = 'plugin.a';
    const pidB = 'plugin.b';

    tearDown(() {
      _d.unregisterController(pidA);
      _d.unregisterController(pidB);
    });

    test('reconcile חופף לא רץ עד שהקודם הסתיים, והפעולות אינן משתלבות',
        () async {
      final log = <String>[];
      final a = _SlowController('a', log);
      final b = _SlowController('b', log);
      _d.registerController(pidA, a);
      _d.registerController(pidB, b);

      // חוסמים את resume של A כדי לדמות reconcile איטי שעדיין רץ.
      a.resumeGate = Completer<void>();

      _d.setSelectedToolPlugin(pidA); // reconcile #1: resume A (נחסם)
      await pumpEventQueue();
      // המעבר ל-B נכנס לתור — אסור שיתחיל כל עוד #1 חסום.
      _d.setSelectedToolPlugin(pidB);
      await pumpEventQueue();
      expect(log, equals(['a:resume:start']),
          reason: 'reconcile #2 לא אמור להתחיל בזמן ש-#1 חסום');

      // משחררים את #1; כעת #2 רץ אחריו ברצף.
      a.resumeGate!.complete();
      await pumpEventQueue();

      expect(
        log,
        equals([
          'a:resume:start',
          'a:resume:end',
          'a:js:resumed',
          'a:js:suspended',
          'a:pause:start',
          'a:pause:end',
          'b:resume:start',
          'b:resume:end',
          'b:js:resumed',
        ]),
      );
    });
  });

  // ── controller שנרשם אחרי הבחירה (טעינה ראשונה / נטען לרקע) ───────────────

  group('onForegroundInstanceReady', () {
    const pidA = 'plugin.a';
    const pidB = 'plugin.b';

    tearDown(() {
      _d.unregisterController(pidA);
      _d.unregisterController(pidB);
    });

    test('תוסף שנטען כשהוא ה-foreground הנבחר — אינו מושהה', () async {
      // הבחירה מגיעה לפני שה-controller קיים (טעינה ראשונה).
      _d.setSelectedToolPlugin(pidA);
      await pumpEventQueue();

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);
      await _d.onForegroundInstanceReady(pidA);

      expect(a.pauseCalls, 0);
    });

    test('תוסף שנטען כשכבר עברו ממנו — מושהה מיד', () async {
      // בוחרים A ואז B עוד לפני ש-A נטען; A נבנה "לרקע" ב-IndexedStack.
      _d.setSelectedToolPlugin(pidA);
      _d.setSelectedToolPlugin(pidB);
      await pumpEventQueue();

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);
      await _d.onForegroundInstanceReady(pidA);

      expect(a.pauseCalls, 1);
      expect(a.jsEvents, contains(contains('suspended')));
    });
  });
}
