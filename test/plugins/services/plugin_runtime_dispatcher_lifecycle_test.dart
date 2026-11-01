import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_discard_policy.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';

class _Repo extends Fake implements PluginRegistryRepository {
  bool permission = true;

  @override
  Future<bool> getIsEnabled(String pluginId) async => true;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      this.permission;
}

class _Controller extends Fake implements InAppWebViewController {
  final List<String> calls = [];
  final List<String> evals = [];

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<void> pause() async => calls.add('pause');

  Completer<void>? resumeGate;

  @override
  Future<void> resume() async {
    calls.add('resume');
    await resumeGate?.future;
  }

  @override
  Future<void> setVisible({required bool visible}) async =>
      calls.add('visible:$visible');

  @override
  Future<void> setAllMediaPlaybackSuspended({required bool suspended}) async =>
      calls.add('media:$suspended');

  @override
  Future<void> setMemoryUsageTargetLevel(MemoryUsageTargetLevel level) async =>
      calls.add('memory:${level.name()}');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    evals.add(source);
    return null;
  }

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const <String, dynamic>{},
    ContentWorld? contentWorld,
  }) async {
    calls.add('callAsync');
    evals.add(functionBody);
    return CallAsyncJavaScriptResult(value: true);
  }

  bool delivered(String topic) => evals.any((e) => e.contains(topic));
}

class _Host implements PluginInstanceHost {
  int released = 0;
  int restored = 0;
  bool discardable = true;

  @override
  void releaseWebView() => released++;

  @override
  void restoreWebView() => restored++;

  @override
  bool get canDiscard => discardable;
}

const _pid = 'lifecycle.test.plugin';

PluginInstanceKey _key([String id = 'a']) => (pluginId: _pid, instanceId: id);

PluginRuntimeDispatcher get _d => PluginRuntimeDispatcher.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repo repo;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await _d.prepareForAppRestart();
    _d.registerController('__reset__', _Controller());
    _d.unregisterController('__reset__');
    _d.resetVisibilityForTesting();
    repo = _Repo();
    _d.repositoryForTesting = repo;
    _d.invalidatePlugin(_pid);
    _d.clock = DateTime.now;
    _d.discardLimitsOverride = null;
  });

  tearDown(() {
    for (final id in ['a', 'b']) {
      _d.unregisterInstanceHost(_pid, instanceId: id);
      _d.unregisterController(_pid, instanceId: id);
      _d.unregisterReloadCallback(_pid, instanceId: id);
      PluginRestoreStateStore.instance.remove(_key(id));
    }
    _d.resetVisibilityForTesting();
    _d.repositoryForTesting = PluginRegistryRepository();
    _d.clock = DateTime.now;
    _d.discardLimitsOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  /// מופע שנטען כשהוא מוצג ואז הוסתר — מושהה ו-ready.
  Future<_Controller> suspended([String id = 'a', _Host? host]) async {
    final c = _Controller();
    _d.registerController(_pid, c, instanceId: id);
    if (host != null) _d.registerInstanceHost(_pid, host, instanceId: id);
    _d.setVisiblePluginInstances({_key(id)});
    await _d.onForegroundInstanceReady(_pid, instanceId: id);
    await pumpEventQueue();
    _d.setVisiblePluginInstances(const {});
    await pumpEventQueue();
    PluginRestoreStateStore.instance.set(_key(id), {'screen': id});
    c.evals.clear();
    c.calls.clear();
    return c;
  }

  group('תור אירועים למופע מושהה', () {
    test('אירועי מצב מתאחדים לפי מפתח ונמסרים ב-eval אחד ב-resume', () async {
      final c = await suspended();

      await _d.dispatchEvent('settings.changed', {'key': 'k1', 'newValue': 1});
      await _d.dispatchEvent('settings.changed', {'key': 'k2', 'newValue': 2});
      await _d.dispatchEvent('settings.changed', {'key': 'k1', 'newValue': 3});
      await _d.dispatchEvent('theme.changed', {'mode': 'dark'});
      expect(c.evals, isEmpty);

      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();

      final batches = c.evals.where((e) => e.contains('settings.changed'));
      expect(batches, hasLength(1));
      final batch = batches.single;
      expect(batch, contains('"newValue":3'));
      expect(batch, contains('"newValue":2'));
      expect(batch, isNot(contains('"newValue":1')));
      expect(batch, contains('theme.changed'));
      // ה-resumed קודם לאירועים שבתור.
      final resumedAt = c.evals.indexWhere((e) => e.contains('plugin.resumed'));
      expect(resumedAt, lessThan(c.evals.indexOf(batch)));
    });

    test('מושהה מקבל מצב גם כשמופע אחר של התוסף פעיל', () async {
      final b = await suspended('b');
      final a = _Controller();
      _d.registerController(_pid, a, instanceId: 'a');
      _d.setVisiblePluginInstances({_key('a')});
      await pumpEventQueue();
      a.evals.clear();

      await _d.dispatchEvent('navigation.changed', {'screen': 'library'});
      expect(a.delivered('navigation.changed'), isTrue);
      expect(b.evals, isEmpty);

      _d.setVisiblePluginInstances({_key('b')});
      await pumpEventQueue();
      expect(b.delivered('navigation.changed'), isTrue);
    });

    test('הרשאה שנשללה בזמן ההשהיה — לא נמסר ב-resume', () async {
      final c = await suspended();
      await _d.dispatchEvent('theme.changed', {'mode': 'dark'});
      repo.permission = false;
      _d.invalidatePlugin(_pid);

      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      expect(c.delivered('theme.changed'), isFalse);
    });

    test('חד-פעמי (sectionContentChanged) נכנס לתור חסום של 50', () async {
      final c = await suspended();
      for (var i = 0; i < 55; i++) {
        await _d.dispatchEvent('reader.sectionContentChanged', {'n': i});
      }
      expect(c.evals, isEmpty);

      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      final batch = c.evals.singleWhere(
        (e) => e.contains('reader.sectionContentChanged'),
      );
      expect(
        'reader.sectionContentChanged'.allMatches(batch).length,
        50,
      );
      expect(batch, isNot(contains('"n":4}')));
      expect(batch, contains('"n":54}'));
    });

    test('ניווט בכרטיסיית קורא מוסתרת אינו מעיר אותה', () async {
      final c = await suspended();
      for (final index in [3, 7]) {
        await _d.dispatchEventToPlugin(
          _pid,
          'reader.textReaderNavigate',
          {'currentIndex': index},
          instanceId: 'a',
          resumeForegroundIfNeeded: true,
        );
      }
      await pumpEventQueue();
      expect(c.count('resume'), 0);
      expect(c.count('callAsync'), 0);

      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      final batch = c.evals.singleWhere(
        (e) => e.contains('reader.textReaderNavigate'),
      );
      expect(batch, contains('"currentIndex":7'));
      expect(batch, isNot(contains('"currentIndex":3')));
    });

    test('לחיצה ממוקדת עדיין מעירה את הטאב המושהה', () async {
      final c = await suspended();
      await _d.dispatchEventToPlugin(
        _pid,
        'reader.context_menu_item_clicked',
        {'itemId': 'x'},
        instanceId: 'a',
      );
      await pumpEventQueue();
      expect(c.count('resume'), 1);
      expect(c.count('callAsync'), 1);
    });
  });

  group('שידור', () {
    test('payload שאינו ניתן לקידוד בלי יעדים — אין חריגה', () async {
      await _d.dispatchEvent('navigation.changed', {'x': Object()});
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      repo.permission = false;
      await _d.dispatchEvent('navigation.changed', {'x': Object()});
      expect(c.evals, isEmpty);
    });

    test('אירוע מצב לתוסף אחד אינו מגיע לתוסף אחר', () async {
      final mine = _Controller();
      final other = _Controller();
      _d.registerController(_pid, mine, instanceId: 'a');
      _d.registerController('other.plugin', other);
      addTearDown(() => _d.unregisterController('other.plugin'));

      await _d.dispatchStateEventToPlugin(
        _pid,
        'plugin.permissions_changed',
        {'permissions': <String>[]},
      );
      expect(mine.delivered('plugin.permissions_changed'), isTrue);
      expect(other.evals, isEmpty);
    });

    test('throttle לבחירה: מוביל ונגרר עם ה-payload האחרון', () {
      fakeAsync((async) {
        final c = _Controller();
        _d.registerController(_pid, c, instanceId: 'a');
        for (var i = 0; i < 10; i++) {
          unawaited(
            _d.dispatchEvent('reader.selection_changed', {'text': 't$i'}),
          );
          async.elapse(const Duration(milliseconds: 10));
        }
        async.flushMicrotasks();
        expect(
          c.evals.where((e) => e.contains('selection_changed')),
          hasLength(1),
        );
        expect(c.evals.single, contains('"t0"'));

        async.elapse(PluginRuntimeDispatcher.selectionThrottle);
        async.flushMicrotasks();
        final sent = c.evals.where((e) => e.contains('selection_changed'));
        expect(sent, hasLength(2));
        expect(sent.last, contains('"t9"'));

        async.elapse(const Duration(seconds: 1));
        expect(
          c.evals.where((e) => e.contains('selection_changed')),
          hasLength(2),
        );
      });
    });

    test('בחירה בלי מופעים אינה משאירה timer', () {
      fakeAsync((async) {
        unawaited(_d.dispatchEvent('reader.selection_changed', {'text': 't'}));
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('השהיה לפי פלטפורמה', () {
    test('Windows: LOW לפני pause, ו-NORMAL אחרי resume', () async {
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      _d.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      expect(c.calls, ['resume', 'memory:NORMAL', 'memory:LOW', 'pause']);
    });

    test('Linux: setVisible ועצירת מדיה', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      _d.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      expect(c.calls, [
        'visible:true',
        'media:false',
        'visible:false',
        'media:true',
      ]);
    });

    test('macOS: רק עצירת מדיה והאירועים', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      _d.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      expect(c.calls, ['media:false', 'media:true']);
      expect(c.delivered('plugin.suspended'), isTrue);
    });

    test('מזעור משהה, ושחזור מחדש', () async {
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      _d.setWindowMinimized(true);
      await pumpEventQueue();
      expect(c.count('pause'), 1);
      expect(_d.isInstanceShown(_key()), isFalse);
      _d.setWindowMinimized(false);
      await pumpEventQueue();
      expect(c.count('resume'), 2);
    });

    test('מובייל ברקע משהה', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      _d.setAppVisible(false);
      await pumpEventQueue();
      expect(c.count('pause'), 1);
      _d.setAppVisible(true);
      await pumpEventQueue();
      expect(c.count('resume'), 2);
    });

    test('פוקוס אחרי מזעור שומר על trustPageFocus: false', () async {
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      _d.setVisiblePluginInstances({_key()});
      await _d.onForegroundInstanceReady(_pid, instanceId: 'a');
      await pumpEventQueue();
      _d.setWindowMinimized(true);
      await pumpEventQueue();

      // המופע עדיין מושהה כשהבקשה מגיעה, ולכן היא נזכרת.
      await _d.restoreKeyboardFocusAfterWindowRestore(_pid, instanceId: 'a');
      c.evals.clear();
      _d.setWindowMinimized(false);
      await pumpEventQueue();

      // עדות הדף (document.hasFocus) אינה נבדקת — הבקשה דילגה עליה.
      expect(c.evals.any((e) => e.contains('document.hasFocus')), isFalse);
    });
  });

  group('שחרור ושחזור', () {
    test('פינוי מעבר לתקרה משחרר, וחזרה למופע מבקשת שחזור', () async {
      _d.discardLimitsOverride = const PluginDiscardLimits(
        maxLiveSuspended: 0,
        maxSuspendedAge: Duration(hours: 1),
      );
      final host = _Host();
      await suspended('a', host);
      PluginRestoreStateStore.instance.set(_key(), {'screen': 2});

      await _d.checkDiscard();
      expect(host.released, 1);
      expect(_d.controllerOf(_pid, instanceId: 'a'), isNull);

      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      expect(host.restored, 1);

      final next = _Controller();
      _d.registerController(_pid, next, instanceId: 'a');
      expect(
        _d.takeBootRestore(_pid, instanceId: 'a', firstBoot: false),
        {
          'reason': 'discarded',
          'state': {'screen': 2},
        },
      );
      await _d.onForegroundInstanceReady(_pid, instanceId: 'a');
      expect(_d.isInstanceShown(_key()), isTrue);
    });

    test('אירוע לטאב שלא נטען אינו מונע פינוי מופע אחר של אותו תוסף', () async {
      final launcher = PluginPageLauncher.instance;
      final keys = AppWindowKeys();
      String? opener(String pluginId) => 'b';
      launcher.registerInstanceOpener(
        keys,
        opener,
        hasOpenInstance: (key) => key == _key('b'),
      );
      addTearDown(() {
        launcher.unregisterInstanceOpener(keys, opener);
        launcher.markPageClosed(_pid, instanceId: 'b');
      });
      _d.discardLimitsOverride = const PluginDiscardLimits(
        maxLiveSuspended: 0,
        maxSuspendedAge: Duration(hours: 1),
      );
      final host = _Host();
      await suspended('a', host);
      launcher.openNewInstance(
        _pid,
        topic: 'plugin.page_opened',
        payload: const {'param': 'requested'},
        windowKeys: keys,
      );

      await _d.checkDiscard();

      expect(host.released, 1);
      expect(launcher.hasPendingFor(_pid, instanceId: 'b'), isTrue);
    });

    test('פינוי לפי גיל', () async {
      var now = DateTime(2026, 10, 21, 12);
      _d.clock = () => now;
      final host = _Host();
      await suspended('a', host);
      await _d.checkDiscard();
      expect(host.released, 0);
      now = now.add(const Duration(minutes: 61));
      await _d.checkDiscard();
      expect(host.released, 1);
    });

    test('מוחרגים אינם מפונים', () async {
      _d.discardLimitsOverride = const PluginDiscardLimits(
        maxLiveSuspended: 0,
        maxSuspendedAge: Duration.zero,
      );
      final host = _Host();
      await suspended('a', host);

      PluginUnsavedChangesRegistry.instance.set(_key(), hasChanges: true);
      await _d.checkDiscard();
      PluginUnsavedChangesRegistry.instance.removeInstance(_key());

      final endWork = _d.beginInstanceWork(_pid, instanceId: 'a');
      await _d.checkDiscard();
      endWork();

      PluginToolbarRegistry.instance.register(
        _pid,
        const PluginToolbarItem(id: 't', title: 'T', icon: 'apps_24_regular'),
        instanceId: 'a',
      );
      await _d.checkDiscard();
      PluginToolbarRegistry.instance.removeAll(_pid);

      host.discardable = false;
      await _d.checkDiscard();
      expect(host.released, 0);

      host.discardable = true;
      await _d.checkDiscard();
      expect(host.released, 1);
    });

    test('אירוע ממוקד למופע ששוחרר נמסר אחרי ה-boot של הדף החדש', () async {
      await suspended('a', _Host());
      _d.markInstanceReleased(
        _pid,
        instanceId: 'a',
        reason: PluginRestoreReason.crashed,
      );
      await _d.dispatchEventToPlugin(
        _pid,
        'search.fieldAction.invoked',
        {'sessionId': 's'},
        instanceId: 'a',
      );

      final next = _Controller();
      _d.registerController(_pid, next, instanceId: 'a');
      expect(
        _d.takeBootRestore(_pid, instanceId: 'a', firstBoot: false)?['reason'],
        'crashed',
      );
      _d.setVisiblePluginInstances({_key()});
      await _d.onForegroundInstanceReady(_pid, instanceId: 'a');
      expect(next.delivered('search.fieldAction.invoked'), isTrue);
    });

    test('טעינה חוזרת של דף קיים מדווחת reloaded גם בלי מצב', () {
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      expect(_d.takeBootRestore(_pid, instanceId: 'a', firstBoot: false), {
        'reason': 'reloaded',
        'state': null,
      });
    });

    test('מופע מוצג אינו מפונה גם כשהוא מסומן מושהה', () async {
      _d.discardLimitsOverride = const PluginDiscardLimits(
        maxLiveSuspended: 0,
        maxSuspendedAge: Duration.zero,
      );
      final host = _Host();
      await suspended('a', host);
      // החזרה לתצוגה רצה תחת המנעול; ה-resume נתקע ולכן הדגל עוד דלוק.
      final c = _d.controllerOf(_pid, instanceId: 'a')! as _Controller;
      c.resumeGate = Completer<void>();
      _d.setVisiblePluginInstances({_key()});
      await pumpEventQueue();
      final check = _d.checkDiscard();
      c.resumeGate!.complete();
      await check;
      expect(host.released, 0);
    });

    test('restore ב-boot: session רק כשיש מצב שמור, ואין לרקע', () {
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      expect(
        _d.takeBootRestore(_pid, instanceId: 'a', firstBoot: true),
        isNull,
      );
      PluginRestoreStateStore.instance.set(_key(), 'x');
      expect(
        _d.takeBootRestore(_pid, instanceId: 'a', firstBoot: true),
        {'reason': 'session', 'state': 'x'},
      );
      expect(
        _d.takeBootRestore(_pid, instanceId: 'a', firstBoot: false)?['reason'],
        'reloaded',
      );
    });

    test('isReleasedBy מזהה את הבעלים של מופע ששוחרר', () async {
      final owner = Object();
      final c = _Controller();
      _d.registerController(_pid, c, instanceId: 'a');
      _d.registerInstanceHost(_pid, _Host(), instanceId: 'a', token: owner);
      expect(_d.isReleasedBy(_pid, instanceId: 'a', token: owner), isFalse);
      _d.markInstanceReleased(
        _pid,
        instanceId: 'a',
        reason: PluginRestoreReason.discarded,
      );
      expect(_d.isReleasedBy(_pid, instanceId: 'a', token: owner), isTrue);
      expect(_d.isReleasedBy(_pid, instanceId: 'a', token: Object()), isFalse);
    });
  });
}
