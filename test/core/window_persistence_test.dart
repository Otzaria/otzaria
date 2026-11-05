import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show Listenable, debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:window_manager/window_manager.dart' show TitleBarStyle;

import '../test_helpers/second_test_view.dart';
import '../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

void main() {
  // מסך ראשי 1920x1080 ומסך משני משמאלו, בפיקסלים פיזיים.
  const primary = Rect.fromLTWH(0, 0, 1920, 1040);
  const secondary = Rect.fromLTWH(-1920, 0, 1920, 1040);
  const strip = 32.0;

  bool reachable(Rect bounds, List<Rect> displays, {double extent = strip}) =>
      WindowPersistence.titleStripReachableOnAnyDisplay(
        bounds,
        displays,
        extent,
      );

  group('WindowPersistence.titleStripReachableOnAnyDisplay', () {
    test('חלון בתוך המסך הראשי — נגיש', () {
      const bounds = Rect.fromLTWH(100, 100, 1280, 720);
      expect(reachable(bounds, [primary]), isTrue);
    });

    test('גבולות חניה של חלון ממוזער (-32000) — לא נגישים', () {
      const bounds = Rect.fromLTWH(-32000, -32000, 420, 400);
      expect(reachable(bounds, [primary, secondary]), isFalse);
    });

    test('חלון על מסך משני שנותק — לא נגיש', () {
      const bounds = Rect.fromLTWH(-1800, 200, 1280, 720);
      expect(reachable(bounds, [primary]), isFalse);
      expect(reachable(bounds, [primary, secondary]), isTrue);
    });

    test('רק פינת החלון התחתונה על המסך — פס הכותרת בחוץ, לא נגיש', () {
      const bounds = Rect.fromLTWH(1888, -688, 1280, 720);
      expect(reachable(bounds, [primary]), isFalse);
    });

    test('פס הכותרת על המסך גם כשרוב החלון בחוץ — נגיש', () {
      const bounds = Rect.fromLTWH(1888, 1000, 1280, 720);
      expect(reachable(bounds, [primary]), isTrue);
    });

    test('פס הכותרת מעל קצה המסך העליון — לא ניתן לאחיזה, לא נגיש', () {
      const bounds = Rect.fromLTWH(100, -20, 1280, 720);
      expect(reachable(bounds, [primary]), isFalse);
    });

    test('חפיפה אופקית צרה מרצועת האחיזה — לא נגיש', () {
      const bounds = Rect.fromLTWH(1910, 100, 1280, 720);
      expect(reachable(bounds, [primary]), isFalse);
    });

    test('רצועה בקנה מידה פיזי (DPR 1.5) נבדקת לפי ההיקף שסופק', () {
      const bounds = Rect.fromLTWH(1876, 100, 1280, 720);
      expect(reachable(bounds, [primary], extent: strip * 1.5), isFalse);
      expect(reachable(bounds, [primary], extent: strip), isTrue);
    });

    test('רשימת מסכים ריקה — לא נגיש', () {
      const bounds = Rect.fromLTWH(100, 100, 1280, 720);
      expect(reachable(bounds, const []), isFalse);
    });
  });

  group('WindowPersistence.applyRestoredBounds', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    Future<_RecordingWindow> apply({required bool visible}) async {
      final window = _RecordingWindow(visible: visible);
      WindowPersistence.bindWindow(controller: window, geometry: window);
      await WindowPersistence.applyRestoredBounds();
      return window;
    }

    test('חלון מוסתר (עלייה רגילה) — הגבולות מוחלים', () async {
      final window = await apply(visible: false);
      expect(window.calls, isNotEmpty);
    });

    // hot restart: setBounds על חלון ממוקסם השאיר WS_MAXIMIZE עם מלבן קטן.
    test('חלון גלוי (main רץ שוב על חלון חי) — לא נוגעים בגבולות', () async {
      final window = await apply(visible: true);
      expect(window.calls, isEmpty);
    });
  });

  group('WindowPersistenceBinding — מופע לכל חלון', () {
    late Directory tmp;
    late UserStateDatabase database;
    late WindowSessionStore sessions;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('otzaria_window_persist_');
      database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
      await database.database;
      sessions = WindowSessionStore(database: database);
    });

    tearDown(() {
      database.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    WindowPersistenceBinding bindingFor(
      int? slot,
      Rect bounds, {
      double Function()? devicePixelRatio,
    }) {
      final window = _RecordingWindow(visible: true, bounds: bounds);
      return WindowPersistenceBinding(
        controller: window,
        geometry: window,
        slot: () => slot,
        sessions: sessions,
        devicePixelRatio: devicePixelRatio,
      );
    }

    Future<Rect?> savedBounds(int slot) async {
      final bounds = WindowBounds.decode(
        (await sessions.load(slot))?.boundsJson,
      );
      if (bounds == null) return null;
      return Rect.fromLTWH(
        bounds.left!,
        bounds.top!,
        bounds.width!,
        bounds.height!,
      );
    }

    for (final currentDpr in [1.0, 2.0]) {
      test(
        'macOS משחזר גבולות שמורים בנקודות עם DPR ישן 2 ל-$currentDpr',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          await Settings.init(cacheProvider: MemoryCacheProvider());
          await Settings.setValue(SettingsRepository.keyLibraryPath, tmp.path);
          const saved = WindowBounds(
            left: -1600,
            top: 100,
            width: 800,
            height: 600,
            dpr: 2,
          );
          await sessions.saveBounds(1, saved.encode());
          final window = _RecordingWindow(visible: false);
          final persistence = WindowPersistenceBinding(
            controller: window,
            geometry: window,
            slot: () => 1,
            sessions: sessions,
            devicePixelRatio: () => currentDpr,
          );
          await persistence.restoreIfAny();
          await persistence.applyRestoredBounds();
          expect(
            window.appliedBounds,
            const Rect.fromLTWH(-1600, 100, 800, 600),
          );
        },
      );
    }

    test('כל חלון שומר את הגבולות שלו לשורה שלו', () async {
      const a = Rect.fromLTWH(10, 20, 800, 600);
      const b = Rect.fromLTWH(900, 40, 640, 480);
      bindingFor(1, a).scheduleSave();
      bindingFor(2, b).scheduleSave();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(await savedBounds(1), a);
      expect(await savedBounds(2), b);
    });

    test('מצב splash של חלון אחד אינו חוסם שמירה של אחר', () async {
      const b = Rect.fromLTWH(900, 40, 640, 480);
      final first = bindingFor(1, const Rect.fromLTWH(0, 0, 500, 500))
        ..splashMode = true;
      first.scheduleSave();
      bindingFor(2, b).scheduleSave();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(await savedBounds(1), isNull);
      expect(await savedBounds(2), b);
    });

    test('חלון בלי משבצת אינו שומר', () async {
      bindingFor(null, const Rect.fromLTWH(0, 0, 500, 500)).scheduleSave();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(await sessions.loadAll(), isEmpty);
    });

    test('כל חלון שומר את ה-DPR של התצוגה שלו', () async {
      const bounds = Rect.fromLTWH(10, 20, 800, 600);
      bindingFor(1, bounds, devicePixelRatio: () => 1.5).scheduleSave();
      bindingFor(2, bounds, devicePixelRatio: () => 2).scheduleSave();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      double? savedDpr(WindowSession? session) =>
          WindowBounds.decode(session?.boundsJson)?.dpr;
      expect(savedDpr(await sessions.load(1)), 1.5);
      expect(savedDpr(await sessions.load(2)), 2);
    });

    test('ה-DPR נקרא מהתצוגה של החלון בכל שמירה', () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      final view = SecondTestView(binding.platformDispatcher.views.first)
        ..devicePixelRatio = 1.75;
      final window = _RecordingWindow(
        visible: true,
        bounds: const Rect.fromLTWH(10, 20, 800, 600),
      );
      final persistence = WindowPersistenceBinding(
        controller: window,
        geometry: window,
        slot: () => 1,
        sessions: sessions,
        view: view,
      );
      Future<double?> saveAndReadDpr() async {
        persistence.scheduleSave();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return WindowBounds.decode((await sessions.load(1))?.boundsJson)?.dpr;
      }

      expect(await saveAndReadDpr(), 1.75);
      view.devicePixelRatio = 1.25;
      expect(await saveAndReadDpr(), 1.25);
    });

    test('כשל דיסק בשמירת הגבולות נרשם ואינו שגיאה לא מטופלת', () async {
      AppPaths.debugOverrideDataRootPath(tmp.path);
      addTearDown(() => AppPaths.debugOverrideDataRootPath(null));
      final window = _RecordingWindow(
        visible: true,
        bounds: const Rect.fromLTWH(10, 20, 800, 600),
      );
      final persistence = WindowPersistenceBinding(
        controller: window,
        geometry: window,
        slot: () => 1,
        sessions: _FailingBoundsStore(database: database),
      );
      final unhandled = <Object>[];
      await runZonedGuarded(() async {
        persistence.scheduleSave();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }, (error, _) => unhandled.add(error));

      expect(unhandled, isEmpty);
      final log = File('${tmp.path}/logs/errors.txt').readAsStringSync();
      expect(log, contains('שמירת גבולות החלון נכשלה'));
      expect(log, contains('disk I/O error'));
    });
  });
}

class _FailingBoundsStore extends WindowSessionStore {
  _FailingBoundsStore({super.database});

  @override
  Future<void> saveBounds(int slot, String? boundsJson) async {
    throw const FileSystemException('disk I/O error');
  }
}

class _RecordingWindow implements AppWindowController, AppWindowGeometry {
  _RecordingWindow({required this.visible, this.bounds = Rect.zero});

  final bool visible;
  final Rect bounds;
  final List<String> calls = [];
  Rect? appliedBounds;

  @override
  AppWindowId get id => AppWindowId.primary;
  @override
  Future<bool> isVisible() async => visible;
  @override
  Future<void> center() async => calls.add('center');
  @override
  Future<void> setBounds(Rect bounds) async {
    appliedBounds = bounds;
    calls.add('setBounds');
  }

  @override
  Future<void> setSize(Size size) async => calls.add('setSize');

  @override
  Future<void> close() async {}
  @override
  Future<void> quitApplication() async {}
  @override
  Future<void> focus() async {}
  @override
  Future<Rect> getBounds() async => bounds;
  @override
  Future<bool> isFullScreen() async => false;
  @override
  Listenable get stateChanges => Listenable.merge(const []);
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<bool> isMinimized() async => false;
  @override
  Future<void> maximize() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> setFullScreen(bool value) async {}
  @override
  Future<void> setMinimumSize(Size size) async {}
  @override
  Future<void> setProgressBar(double progress) async {}
  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) async {}
  @override
  Future<void> show() async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> unmaximize() async {}
}
