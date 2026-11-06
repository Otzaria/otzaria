import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

class _BoundsSessions extends WindowSessionStore {
  String? bounds;
  Completer<void>? beforeRead;
  final reads = <int>[];
  final writes = <(int, String?)>[];

  @override
  Future<String?> loadBoundsJson(int slot) async {
    reads.add(slot);
    await beforeRead?.future;
    return bounds;
  }

  @override
  Future<WindowSession?> load(int slot) =>
      throw StateError('שמירת גבולות אינה זקוקה לכרטיסיות');

  @override
  Future<void> saveBounds(int slot, String? boundsJson) async {
    writes.add((slot, boundsJson));
    bounds = boundsJson;
  }
}

class _Window implements AppWindowController, AppWindowGeometry {
  bool minimized = false;
  bool maximized = false;
  bool fullscreen = false;
  int geometryReads = 0;
  final Rect bounds = const Rect.fromLTWH(40, 60, 900, 700);

  @override
  Future<bool> isMinimized() async => minimized;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<bool> isFullScreen() async => fullscreen;

  @override
  Future<Rect> getBounds() async {
    geometryReads++;
    return bounds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _BoundsSessions sessions;
  late _Window window;
  late WindowPersistenceBinding persistence;
  int? slot;

  setUp(() async {
    sessions = _BoundsSessions();
    window = _Window();
    slot = 2;
    persistence = WindowPersistenceBinding(
      controller: window,
      geometry: window,
      sessions: sessions,
      slot: () => slot,
      devicePixelRatio: () => 1.5,
    );
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue(SettingsRepository.keyLibraryPath, '/library');
  });

  testWidgets('חלון רגיל שומר גבולות ו-DPR דרך שליפת המטא־נתונים', (
    tester,
  ) async {
    persistence.scheduleSave();
    await tester.pump(const Duration(milliseconds: 401));
    final saved = WindowBounds.decode(sessions.writes.single.$2)!;
    expect(sessions.reads, [2]);
    expect(sessions.writes.single.$1, 2);
    expect(saved.toPhysical(), (left: 60, top: 90, width: 1350, height: 1050));
    expect(saved.dpr, 1.5);
    expect(saved.maximized, isFalse);
  });

  for (final fullscreen in [false, true]) {
    testWidgets('מצב מוגדל/מלא ($fullscreen) משמר גאומטריה רגילה', (
      tester,
    ) async {
      const previous = WindowBounds(
        left: 10,
        top: 20,
        width: 800,
        height: 600,
        dpr: 2,
      );
      sessions.bounds = previous.encode();
      window.fullscreen = fullscreen;
      window.maximized = !fullscreen;
      persistence.scheduleSave();
      await tester.pump(const Duration(milliseconds: 401));

      final saved = WindowBounds.decode(sessions.writes.single.$2)!;
      expect(saved.toPhysical(), previous.toPhysical());
      expect(saved.dpr, 2);
      expect(saved.maximized, !fullscreen);
      expect(window.geometryReads, 0);
    });
  }

  testWidgets('חלון ממוזער אינו קורא או שומר גבולות', (tester) async {
    window.minimized = true;
    persistence.scheduleSave();
    await tester.pump(const Duration(milliseconds: 401));
    expect(sessions.reads, isEmpty);
    expect(sessions.writes, isEmpty);
  });

  testWidgets('סגירת חלון בזמן שליפת הגבולות אינה יוצרת מחדש את השורה', (
    tester,
  ) async {
    sessions.beforeRead = Completer<void>();
    persistence.scheduleSave();
    await tester.pump(const Duration(milliseconds: 401));
    expect(sessions.reads, [2]);
    slot = null;
    sessions.beforeRead!.complete();
    await tester.pump();
    expect(sessions.writes, isEmpty);
  });

  test('גבולות חסרים או פגומים חוזרים להגדרות הישנות', () async {
    await Settings.setValue('window_bounds_left', 12.0);
    await Settings.setValue('window_bounds_top', 24.0);
    await Settings.setValue('window_bounds_width', 600.0);
    await Settings.setValue('window_bounds_height', 400.0);
    await Settings.setValue('window_bounds_dpr', 2.0);
    for (final raw in [null, '{invalid']) {
      sessions.bounds = raw;
      final saved = await persistence.loadSavedBounds();
      expect(saved.toPhysical(), (left: 24, top: 48, width: 1200, height: 800));
    }
    expect(sessions.reads, [2, 2]);
  });
}
