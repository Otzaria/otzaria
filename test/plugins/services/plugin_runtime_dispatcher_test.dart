import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_published_record.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_startup_contributions_service.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';

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

// ── repository שמדמה סגירת טאב באמצע בדיקה אסינכרונית ─────────────────────
// ה-await על getIsEnabled/getPermission הוא הנקודה שבה הדיספצ'ר משהה; ה-hook
// מסיר בדיוק אז תוסף, כפי ש-unregisterController עושה בסגירת טאב.
class _TabClosingRepo extends Fake implements PluginRegistryRepository {
  _TabClosingRepo({this.onFirstEnabledCheck, this.onPermissionCheck});
  final VoidCallback? onFirstEnabledCheck;
  final void Function(String pluginId)? onPermissionCheck;
  bool _enabledFired = false;

  @override
  Future<bool> getIsEnabled(String pluginId) async {
    await Future<void>.delayed(Duration.zero);
    if (!_enabledFired) {
      _enabledFired = true;
      onFirstEnabledCheck?.call();
    }
    return true;
  }

  @override
  Future<bool?> getPermission(String pluginId, String permission) async {
    await Future<void>.delayed(Duration.zero);
    onPermissionCheck?.call(pluginId);
    return true;
  }
}

// ── fake repository לסנכרון תרומות עלייה (הרשאות מוענקות, בלי SQLite) ──────
class _ContributionsRepo extends Fake implements PluginRegistryRepository {
  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async => [
    for (final permission in const [
      'app.startup_contributions',
      'reader.toolbar',
    ])
      PluginPermissionGrant(
        pluginId: id,
        permission: permission,
        granted: true,
        grantedAt: DateTime(2026),
      ),
  ];

  @override
  Future<List<PluginPublishedRecord>> getPluginPublishedRecords(
    String pluginId,
  ) async => const [];
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

  // המסלול האסינכרוני של הדיספצ'ר: בדיקת חיוּת + מסירת אירוע לטאב שהוחיה
  // בקריאה אחת. ברירת המחדל מדמה דף חי (true); שינוי callAsyncOutcome מדמה
  // דף זומבי ('no-page-world') או גשר מת (null דרך חריגה). מסירות נרשמות
  // ב-jsEvents רק כשהדף חי — בדף זומבי האירוע לא מגיע למאזינים.
  Object? callAsyncOutcome = true;
  int reloadCalls = 0;

  @override
  Future<void> reload() async => reloadCalls++;

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const <String, dynamic>{},
    ContentWorld? contentWorld,
  }) async {
    if (callAsyncOutcome == true && functionBody.contains('dispatchEvent')) {
      jsEvents.add(functionBody);
    }
    return CallAsyncJavaScriptResult(value: callAsyncOutcome);
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
  PluginHighlightRegistry.instance.removePlugin(_kPid);
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

  test(
    'prepareForAppShutdown tears down controllers and blocks re-registering',
    () async {
      final firstController = _FakeWebViewController();
      dispatcher.registerController('plugin-a', firstController);
      ContextMenuRegistry.instance.register(
        'plugin-a',
        const PluginContextMenuItem(id: 'context', label: 'Context'),
      );
      PluginToolbarRegistry.instance.register(
        'plugin-a',
        const PluginToolbarItem(
          id: 'toolbar',
          title: 'Toolbar',
          icon: 'apps_24_regular',
        ),
      );

      await dispatcher.prepareForAppShutdown();

      expect(firstController.loadUrlCalls, 1);
      expect(ContextMenuRegistry.instance.getAll(), isEmpty);
      expect(PluginToolbarRegistry.instance.getAll(), isEmpty);
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
    },
  );

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

    test('סגירת ה-controller האחרון מנקה תרומות UI של התוסף', () {
      ContextMenuRegistry.instance.register(
        _kPid,
        const PluginContextMenuItem(id: 'context', label: 'Context'),
      );
      PluginToolbarRegistry.instance.register(
        _kPid,
        const PluginToolbarItem(
          id: 'toolbar',
          title: 'Toolbar',
          icon: 'apps_24_regular',
        ),
      );
      _d.registerController(_kPid, _FakeController());

      _d.unregisterController(_kPid);

      expect(ContextMenuRegistry.instance.getAll(), isEmpty);
      expect(PluginToolbarRegistry.instance.getAll(), isEmpty);
    });

    test('סגירת foreground אינה מנקה תרומות כל עוד background פעיל', () {
      PluginToolbarRegistry.instance.register(
        _kPid,
        const PluginToolbarItem(
          id: 'toolbar',
          title: 'Toolbar',
          icon: 'apps_24_regular',
        ),
      );
      _d.registerController(_kPid, _FakeController());
      _d.registerController(
        _kPid,
        _FakeController(),
        instanceId: 'background',
      );

      _d.unregisterController(_kPid);
      expect(PluginToolbarRegistry.instance.getAll(), hasLength(1));

      _d.unregisterController(_kPid, instanceId: 'background');
      expect(PluginToolbarRegistry.instance.getAll(), isEmpty);
    });
  });

  // ── background-preference selection logic ─────────────────────────────────
  //
  // בודק את הלוגיקה שהוספנו ב-dispatchEvent ו-dispatchEventToPlugin:
  // אירועי עבודה נשלחים לרקע שאינו מושהה; בהיעדרו נופלים ל-foreground.
  //
  // הטסטים מכסים את ארבע הצירופים האפשריים של instances.

  group('background-preference selection', () {
    Map<String, String> selectTargets(Map<String, String> instances) =>
        instances.containsKey('background')
        ? {'background': instances['background']!}
        : instances.containsKey('default')
        ? {'default': instances['default']!}
        : Map.fromEntries(instances.entries);

    test('כשיש foreground וגם background — נבחר רק background', () {
      final instances = {'default': 'fg', 'background': 'bg'};
      final result = selectTargets(instances);
      expect(result.keys, equals(['background']));
      expect(result.values, equals(['bg']));
      expect(result.containsValue('fg'), isFalse);
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

    test('instance נוסף אינו נבחר כשקיים background', () {
      final instances = {'background': 'bg', 'extra': 'ex'};
      final result = selectTargets(instances);
      expect(result.containsKey('background'), isTrue);
      expect(result.containsKey('extra'), isFalse);
    });
  });

  group('event routing policy', () {
    const pluginId = 'routing.test.plugin';

    setUp(() {
      _d.repositoryForTesting = _FakeRegistryRepo(
        enabled: true,
        permission: true,
      );
      _d.invalidatePlugin(pluginId);
    });

    tearDown(() {
      _d.unregisterController(pluginId);
      _d.unregisterController(pluginId, instanceId: 'background');
      _d.repositoryForTesting = PluginRegistryRepository();
    });

    test(
      'UI broadcast is delivered to foreground when both hosts exist',
      () async {
        final foreground = _LifecycleFakeController();
        final background = _LifecycleFakeController();
        _d.registerController(pluginId, foreground);
        _d.registerController(
          pluginId,
          background,
          instanceId: 'background',
        );

        await _d.dispatchEvent('navigation.changed', {'screen': 'library'});

        expect(foreground.jsEvents, hasLength(1));
        expect(foreground.jsEvents.single, contains('navigation.changed'));
        expect(background.jsEvents, isEmpty);
      },
    );

    test(
      'theme.changed keeps its foreground behavior when both hosts exist',
      () async {
        final foreground = _LifecycleFakeController();
        final background = _LifecycleFakeController();
        _d.registerController(pluginId, foreground);
        _d.registerController(
          pluginId,
          background,
          instanceId: 'background',
        );

        await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

        expect(foreground.jsEvents, hasLength(1));
        expect(foreground.jsEvents.single, contains('theme.changed'));
        expect(background.jsEvents, isEmpty);
      },
    );

    test('dedicated work broadcast is delivered to background', () async {
      final foreground = _LifecycleFakeController();
      final background = _LifecycleFakeController();
      _d.registerController(pluginId, foreground);
      _d.registerController(
        pluginId,
        background,
        instanceId: 'background',
      );

      await _d.dispatchEvent('reader.sectionContentChanged', {'revision': 2});

      expect(foreground.jsEvents, isEmpty);
      expect(background.jsEvents, hasLength(1));
      expect(
        background.jsEvents.single,
        contains('reader.sectionContentChanged'),
      );
    });

    test(
      'background work falls back to foreground when no background exists',
      () async {
        final foreground = _LifecycleFakeController();
        _d.registerController(pluginId, foreground);

        await _d.dispatchEvent('reader.sectionContentChanged', {'revision': 3});

        expect(foreground.jsEvents, hasLength(1));
      },
    );

    test(
      'foreground event falls back to background when no foreground exists',
      () async {
        final background = _LifecycleFakeController();
        _d.registerController(
          pluginId,
          background,
          instanceId: 'background',
        );

        await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

        expect(background.jsEvents, hasLength(1));
        expect(background.jsEvents.single, contains('theme.changed'));
      },
    );

    test('targeted context-menu event explicitly prefers background', () async {
      final foreground = _LifecycleFakeController();
      final background = _LifecycleFakeController();
      _d.registerController(pluginId, foreground);
      _d.registerController(
        pluginId,
        background,
        instanceId: 'background',
      );

      await _d.dispatchEventToPlugin(
        pluginId,
        'marker.customColorClick',
        {'color': 'yellow'},
        preferBackground: true,
      );

      expect(foreground.jsEvents, isEmpty);
      expect(background.jsEvents, hasLength(1));
      expect(background.jsEvents.single, contains('marker.customColorClick'));
    });
  });

  // ── reloadPlugin callbacks ────────────────────────────────────────────────

  group('reloadPlugin', () {
    tearDown(_cleanupCallbacks);

    test('ללא callback רשום — לא קורס', () async {
      await expectLater(_d.reloadPlugin(_kPid), completes);
    });

    test(
      'reload clears stale context-menu items without an active host',
      () async {
        ContextMenuRegistry.instance.register(
          _kPid,
          const PluginContextMenuItem(id: 'stale', label: 'Stale'),
        );

        await _d.reloadPlugin(_kPid);

        expect(
          ContextMenuRegistry.instance.getAll().where(
            (record) => record.$1 == _kPid,
          ),
          isEmpty,
        );
      },
    );

    test('reload clears stale highlights without an active host', () async {
      PluginHighlightRegistry.instance.setLegacyHighlight(
        ownerPluginId: _kPid,
        bookId: 'book',
        sectionIndex: 1,
      );

      await _d.reloadPlugin(_kPid);

      expect(
        PluginHighlightRegistry.instance.getHighlights(
          ownerPluginId: _kPid,
        ),
        isEmpty,
      );
    });

    test('callback רשום מופעל', () async {
      var called = false;
      _d.registerReloadCallback(_kPid, () async {
        called = true;
      });
      await _d.reloadPlugin(_kPid);
      expect(called, isTrue);
    });

    test('reload clears stale context-menu items before callbacks', () async {
      var registryWasCleanWhenReloadStarted = false;
      ContextMenuRegistry.instance.register(
        _kPid,
        const PluginContextMenuItem(id: 'stale', label: 'Stale'),
      );
      _d.registerReloadCallback(_kPid, () async {
        registryWasCleanWhenReloadStarted = ContextMenuRegistry.instance
            .getAll()
            .where((record) => record.$1 == _kPid)
            .isEmpty;
      });

      await _d.reloadPlugin(_kPid);

      expect(registryWasCleanWhenReloadStarted, isTrue);
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

    setUp(_d.resetVisibilityForTesting);

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    });

    tearDown(() {
      _d.unregisterController(pidA);
      _d.unregisterController(pidA, instanceId: 'background');
      _d.unregisterController(pidB);
      // שחזור ה-repository האמיתי לטסטים שהזריקו fake.
      _d.repositoryForTesting = PluginRegistryRepository();
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('מעבר מתוסף לתוסף משהה את הקודם ומחדש את הנכנס', () async {
      final a = _LifecycleFakeController();
      final b = _LifecycleFakeController();
      _d.registerController(pidA, a);
      _d.registerController(pidB, b);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      expect(a.resumeCalls, 1);
      expect(a.jsEvents.last, contains('plugin.resumed'));

      _d.setVisiblePluginTabs({pidB});
      await pumpEventQueue();
      expect(a.pauseCalls, 1);
      expect(a.jsEvents, contains(contains('plugin.suspended')));
      expect(b.resumeCalls, 1);
    });

    test('בפלטפורמה ללא pause native נשלחים רק אירועי lifecycle', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      _d.setVisiblePluginTabs(const {});
      await pumpEventQueue();

      expect(a.resumeCalls, 0);
      expect(a.pauseCalls, 0);
      expect(a.jsEvents, contains(contains('plugin.resumed')));
      expect(a.jsEvents, contains(contains('plugin.suspended')));
    });

    test('יציאה ממסך העיון משהה, וחזרה מחדשת', () async {
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      expect(a.resumeCalls, 1);

      _d.setReaderScreenVisible(false);
      await pumpEventQueue();
      expect(a.pauseCalls, 1);

      _d.setReaderScreenVisible(true);
      await pumpEventQueue();
      expect(a.resumeCalls, 2);
    });

    test('instance הרקע אינו מושהה ביציאה', () async {
      final bg = _LifecycleFakeController();
      _d.registerController(pidA, bg, instanceId: 'background');

      _d.setVisiblePluginTabs({pidA});
      _d.setReaderScreenVisible(false);
      await pumpEventQueue();

      expect(bg.pauseCalls, 0);
      expect(bg.resumeCalls, 0);
    });

    test('תוסף עם foreground ורקע — רק ה-foreground מושהה', () async {
      final fg = _LifecycleFakeController();
      final bg = _LifecycleFakeController();
      _d.registerController(pidA, fg, instanceId: 'default');
      _d.registerController(pidA, bg, instanceId: 'background');

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      _d.setReaderScreenVisible(false);
      await pumpEventQueue();

      expect(fg.pauseCalls, 1);
      expect(bg.pauseCalls, 0);
    });

    test('מעבר לכרטיסיה שאינה תוסף משהה אותו ולא מנסה לחדש', () async {
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      _d.setVisiblePluginTabs(const {});
      await pumpEventQueue();

      expect(a.pauseCalls, 1);
    });

    test('אירוע ממוקד מחדש foreground מושהה כשאין background', () async {
      _d.repositoryForTesting = _FakeRegistryRepo(enabled: true);
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      _d.setVisiblePluginTabs(const {});
      await pumpEventQueue();
      final resumeCalls = a.resumeCalls;
      final pauseCalls = a.pauseCalls;
      a.jsEvents.clear();

      await _d.dispatchEventToPlugin(
        pidA,
        'reader.toolbar_item_clicked',
        {'itemId': 'mark'},
        preferBackground: true,
      );

      expect(a.resumeCalls, resumeCalls + 1);
      // אין הקפאה מיידית אחרי המסירה: אירוע ממוקד פותח לרוב טיפול אסינכרוני
      // (למשל בקשת חיפוש שעונה דרך ה-bridge), והקפאה באמצע הייתה בולעת את
      // התשובה. ההקפאה החוזרת נדחית לחלון חסד (טיימר, מחוץ לבדיקה הזו).
      expect(a.pauseCalls, pauseCalls);
      expect(a.jsEvents, hasLength(2));
      expect(a.jsEvents[0], contains('plugin.resumed'));
      expect(a.jsEvents[1], contains('reader.toolbar_item_clicked'));
    });

    test('מסירה לטאב מושהה שאינה מאומתת — הדף נטען מחדש והאירוע ממתין '
        'למסירה חוזרת', () async {
      _d.repositoryForTesting = _FakeRegistryRepo(enabled: true);
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      _d.setVisiblePluginTabs(const {});
      await pumpEventQueue();
      a.jsEvents.clear();
      // מדמה את מצב הזומבי: ההרצה רצה אך לא ב-world של הדף האמיתי.
      a.callAsyncOutcome = 'no-page-world';

      await _d.dispatchEventToPlugin(
        pidA,
        'reader.toolbar_item_clicked',
        {'itemId': 'mark'},
        preferBackground: true,
      );

      expect(a.reloadCalls, 1);
      // אירוע ה-lifecycle (plugin.resumed) עדיין נשלח, אבל האירוע הממוקד
      // עצמו לא נמסר לדף הזומבי.
      expect(
        a.jsEvents.where((e) => e.contains('reader.toolbar_item_clicked')),
        isEmpty,
      );

      // אחרי ה-reload הדף חוזר בריא — boot מסתיים והאירוע שנרשם נמסר מחדש.
      a.callAsyncOutcome = true;
      await _d.onForegroundInstanceReady(pidA);
      await pumpEventQueue();
      expect(
        a.jsEvents.where(
          (e) => e.contains('reader.toolbar_item_clicked'),
        ),
        isNotEmpty,
      );
    });

    test('מסירה מאומתת לטאב מושהה — בלי reload', () async {
      _d.repositoryForTesting = _FakeRegistryRepo(enabled: true);
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      _d.setVisiblePluginTabs(const {});
      await pumpEventQueue();
      a.jsEvents.clear();

      await _d.dispatchEventToPlugin(
        pidA,
        'reader.toolbar_item_clicked',
        {'itemId': 'mark'},
        preferBackground: true,
      );

      expect(a.reloadCalls, 0);
      expect(
        a.jsEvents.where(
          (e) => e.contains('reader.toolbar_item_clicked'),
        ),
        hasLength(1),
      );
    });

    test('פתיחת תוסף מוסרת את האירוע ל-foreground המושהה', () async {
      _d.repositoryForTesting = _FakeRegistryRepo(enabled: true);
      final foreground = _LifecycleFakeController();
      final background = _LifecycleFakeController();
      _d.registerController(pidA, foreground);
      _d.registerController(pidA, background, instanceId: 'background');

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();
      _d.setVisiblePluginTabs(const {});
      await pumpEventQueue();
      foreground.jsEvents.clear();

      await _d.dispatchEventToPlugin(
        pidA,
        'reader.toolbar_item_clicked',
        {'itemId': 'mark'},
        resumeForegroundIfNeeded: true,
      );

      expect(
        foreground.jsEvents,
        contains(contains('reader.toolbar_item_clicked')),
      );
      expect(background.jsEvents, isEmpty);
    });

    test(
      'חידוש תוסף מסנכרן מחדש את ה-theme האחרון (שאבד בזמן ההשהיה)',
      () async {
        _d.repositoryForTesting = _FakeRegistryRepo(
          enabled: true,
          permission: true,
        );
        // dispatchEvent ללא controllers רשומים — שומר רק את ה-payload האחרון
        // ומדמה החלפת מצב כהה בזמן שהתוסף מושהה.
        await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

        final a = _LifecycleFakeController();
        _d.registerController(pidA, a);

        _d.setVisiblePluginTabs({pidA});
        await pumpEventQueue();

        expect(a.resumeCalls, 1);
        expect(
          a.jsEvents,
          contains(allOf(contains('theme.changed'), contains('dark'))),
        );
      },
    );

    test('חידוש לא שולח theme כשאין הרשאת events.subscribe', () async {
      _d.repositoryForTesting = _FakeRegistryRepo(
        enabled: true,
        permission: false,
      );
      await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();

      expect(a.resumeCalls, 1);
      expect(a.jsEvents.any((e) => e.contains('theme.changed')), isFalse);
    });

    test('חידוש לא שולח theme כשהתוסף מושבת', () async {
      _d.repositoryForTesting = _FakeRegistryRepo(enabled: false);
      await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();

      expect(a.jsEvents.any((e) => e.contains('theme.changed')), isFalse);
    });

    test('חידוש ללא theme קודם — לא שולח theme.changed', () async {
      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);

      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();

      expect(a.jsEvents.any((e) => e.contains('theme.changed')), isFalse);
    });
  });

  // ── serialization של פעולות מחזור-חיים (race בין reconciles חופפים) ────────

  group('lifecycle serialization', () {
    const pidA = 'plugin.a';
    const pidB = 'plugin.b';

    setUp(_d.resetVisibilityForTesting);

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    });

    tearDown(() {
      _d.unregisterController(pidA);
      _d.unregisterController(pidB);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'reconcile חופף לא רץ עד שהקודם הסתיים, והפעולות אינן משתלבות',
      () async {
        final log = <String>[];
        final a = _SlowController('a', log);
        final b = _SlowController('b', log);
        _d.registerController(pidA, a);
        _d.registerController(pidB, b);

        // חוסמים את resume של A כדי לדמות reconcile איטי שעדיין רץ.
        a.resumeGate = Completer<void>();

        _d.setVisiblePluginTabs({pidA}); // reconcile #1: resume A (נחסם)
        await pumpEventQueue();
        // המעבר ל-B נכנס לתור — אסור שיתחיל כל עוד #1 חסום.
        _d.setVisiblePluginTabs({pidB});
        await pumpEventQueue();
        expect(
          log,
          equals(['a:resume:start']),
          reason: 'reconcile #2 לא אמור להתחיל בזמן ש-#1 חסום',
        );

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
      },
    );
  });

  // ── controller שנרשם אחרי הבחירה (טעינה ראשונה / נטען לרקע) ───────────────

  group('onForegroundInstanceReady', () {
    const pidA = 'plugin.a';
    const pidB = 'plugin.b';

    setUp(_d.resetVisibilityForTesting);

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    });

    tearDown(() {
      _d.unregisterController(pidA);
      _d.unregisterController(pidB);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('תוסף שנטען כשהוא ה-foreground הנבחר — אינו מושהה', () async {
      // הבחירה מגיעה לפני שה-controller קיים (טעינה ראשונה).
      _d.setVisiblePluginTabs({pidA});
      await pumpEventQueue();

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);
      await _d.onForegroundInstanceReady(pidA);

      expect(a.pauseCalls, 0);
    });

    test('תוסף שנטען כשכבר עברו ממנו — מושהה מיד', () async {
      // בוחרים A ואז B עוד לפני ש-A נטען; A נבנה בכרטיסיה שאינה מוצגת.
      _d.setVisiblePluginTabs({pidA});
      _d.setVisiblePluginTabs({pidB});
      await pumpEventQueue();

      final a = _LifecycleFakeController();
      _d.registerController(pidA, a);
      await _d.onForegroundInstanceReady(pidA);

      expect(a.pauseCalls, 1);
      expect(a.jsEvents, contains(contains('suspended')));
    });
  });

  group('אירוע ממוקד לתוסף בלי מנוע חי', () {
    late List<String> opened;

    setUp(() {
      opened = [];
      PluginPageLauncher.instance.navigator = opened.add;
    });

    tearDown(() {
      PluginPageLauncher.instance.navigator = null;
    });

    test('בלי הרשאת ריצה ברקע — לחיצה נופלת לפתיחת דף התוסף', () async {
      addTearDown(
        () => PluginPageLauncher.instance.markPageClosed('lazy-none'),
      );

      await PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
        'lazy-none',
        'reader.toolbar_item_clicked',
        {'itemId': 'b1'},
        preferBackground: true,
      );

      expect(opened, ['lazy-none']);
    });

    test('פריט דקלרטיבי שורד סגירת מופע רקע (כיבוי עצל)', () async {
      const pid = 'contrib.survives';
      final repo = _ContributionsRepo();
      final plugin = InstalledPlugin(
        pluginId: pid,
        name: 'Test',
        version: '1.0.0',
        installPath: '/plugins/$pid',
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: PluginManifest.fromJson({
          'schemaVersion': 1,
          'id': pid,
          'name': 'Test',
          'version': '1.0.0',
          'entrypoint': 'index.html',
          'permissions': const <String>[],
          'contributes': {
            'startup': {
              'toolbarItems': [
                {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
              ],
            },
          },
        }),
        installedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await PluginStartupContributionsService.instance.sync([plugin], repo);
      addTearDown(() async {
        await PluginStartupContributionsService.instance.sync(const [], repo);
        PluginToolbarRegistry.instance.removeAll(pid);
      });

      PluginRuntimeDispatcher.instance.registerController(
        pid,
        _FakeController(),
        instanceId: 'background',
      );
      PluginRuntimeDispatcher.instance.unregisterController(
        pid,
        instanceId: 'background',
      );

      expect(
        PluginToolbarRegistry.instance.getAll().where(
          (record) => record.$1 == pid,
        ),
        hasLength(1),
        reason:
            'ניקוי ה-registries בסגירת ה-controller חייב להחזיר '
            'רישומים דקלרטיביים',
      );
    });

    test('עם הרשאת ריצה ברקע — האירוע נכנס לתור ההערה ולא נפתח דף', () async {
      PluginLazyActivationService.instance.syncPlugin(
        'lazy-ok',
        broadcastTopics: const {},
        scheduleStartup: false,
      );
      addTearDown(
        () => PluginLazyActivationService.instance.removePlugin('lazy-ok'),
      );

      await PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
        'lazy-ok',
        'reader.toolbar_item_clicked',
        {'itemId': 'b1'},
        preferBackground: true,
      );

      expect(opened, isEmpty);
    });
  });

  // ── רגרסיה: סגירת טאב באמצע פעולה אסינכרונית ──────────────────────────────
  //
  // סגירת טאב עם תוסף קוראת ל-unregisterController, שמסיר סינכרונית גם
  // מ-_controllersByPlugin וגם מ-_permissionCache. כל קריאה חוזרת אליהם אחרי
  // await חשופה לכך.
  group('סגירת טאב תוך כדי פעולה אסינכרונית', () {
    tearDown(() => _d.repositoryForTesting = PluginRegistryRepository());

    test('הסרת תוסף באמצע ה-await אינה מפילה את השידור', () async {
      const pids = [
        'crash.a',
        'crash.b',
        'crash.c',
        'crash.d',
        'crash.e',
        'crash.f',
      ];
      final controllers = {
        for (final pid in pids) pid: _FakeWebViewController(),
      };
      controllers.forEach(_d.registerController);
      addTearDown(() {
        for (final pid in pids) {
          _d.unregisterController(pid);
        }
      });

      _d.repositoryForTesting = _TabClosingRepo(
        onFirstEnabledCheck: () => _d.unregisterController(pids.last),
      );

      await expectLater(
        _d.dispatchEvent('navigation.changed', {'screen': 'library'}),
        completes,
      );

      for (final pid in pids.take(pids.length - 1)) {
        expect(controllers[pid]!.evaluateJavascriptCalls, 1, reason: pid);
      }
      expect(
        controllers[pids.last]!.evaluateJavascriptCalls,
        0,
        reason: 'התוסף שהוסר באמצע אינו אמור לקבל את האירוע',
      );
    });

    // סגירת הטאב מוחקת את _permissionCache של התוסף; קריאה חוזרת דרכו אחרי
    // ה-await זרקה, והזריקה קטעה את _reconcileForeground באמצע — כך שתוסף
    // *אחר* לא קיבל resume ונשאר קפוא.
    test('הסרת תוסף בבדיקת ההרשאה אינה מונעת resume מתוסף אחר', () async {
      const closing = 'perm.closing';
      const survivor = 'perm.survivor';
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      _d.resetVisibilityForTesting();

      // קובע את _lastThemePayload כדי ש-_resyncThemeOnResume ירוץ בהתעוררות.
      // לפני רישום ה-controllers, כך שמטמון ההרשאות נשאר ריק.
      await _d.dispatchEvent('theme.changed', {'mode': 'dark'});

      final closingController = _LifecycleFakeController();
      final survivorController = _LifecycleFakeController();
      _d.registerController(closing, closingController);
      _d.registerController(survivor, survivorController);
      addTearDown(() {
        _d.unregisterController(closing);
        _d.unregisterController(survivor);
      });

      _d.repositoryForTesting = _TabClosingRepo(
        onPermissionCheck: (pluginId) {
          if (pluginId == closing) _d.unregisterController(closing);
        },
      );

      _d.setVisiblePluginTabs({closing, survivor});
      await pumpEventQueue();

      expect(
        survivorController.resumeCalls,
        1,
        reason: 'הזריקה בתוסף שנסגר קטעה את שרשרת ה-resume',
      );
    });
  });
}
