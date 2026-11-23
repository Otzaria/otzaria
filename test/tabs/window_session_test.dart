import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/multiview/window_event_log.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

ToolTab _tab(String title) => ToolTab(toolId: 'builtin.calendar', title: title);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_window_session_');
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    sessions = WindowSessionStore(database: database);
    TabsRepository.debugSessions = sessions;
  });

  tearDown(() async {
    MultiViewMode.debugOverride = false;
    TabsRepository.debugSessions = null;
    database.close();
    ProcessDuties.debugOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('החלון הראשון', () {
    test('שומר וטוען את המשבצת שלו', () async {
      const slot = UserStateSlot.main;
      expect(slot, 1, reason: 'הסשנים השמורים ממופתחים לפי משבצת 1');

      final repo = TabsRepository();
      await repo.saveTabs([_tab('לוח שנה')], 0);

      expect((await sessions.load(1))!.currentIndex, 0);
      expect(repo.loadTabs().single.title, 'לוח שנה');
    });
  });

  group('ייבוא מגיבוי', () {
    test('מקדם את דור הסשן — bloc שנבנה קודם לא ישמור', () async {
      final before = TabsRepository.sessionGeneration;
      await TabsRepository().importRaw({'tabs': <dynamic>[], 'currentTab': 0});
      expect(TabsRepository.sessionGeneration, before + 1);
    });
  });

  group('דחיסת סשנים ל"שחזר את כל החלונות"', () {
    test('מסדר את האחרים ברצף אחרי המארח ומחזיר את המשבצות', () async {
      const host = UserStateSlot.main;
      await TabsRepository().saveTabs([_tab('שלי')], 0);
      await sessions.save(
        host + 2,
        tabsJson: '[${_encoded('ב')}]',
        currentIndex: 0,
      );
      await sessions.save(
        host + 3,
        tabsJson: '[${_encoded('ג')}]',
        currentIndex: 0,
      );

      expect(await TabsRepository.compactWindowSessions(), [
        host + 1,
        host + 2,
      ]);
      expect((await sessions.load(host + 1))!.tabsJson, contains('ב'));
      expect((await sessions.load(host + 2))!.tabsJson, contains('ג'));
      expect(await sessions.load(host + 3), isNull);
      expect(TabsRepository().loadTabs().single.title, 'שלי');
    });

    test('כשלמארח אין סשן, הראשון שבתור הופך לשלו', () async {
      const host = UserStateSlot.main;
      await sessions.save(
        host + 1,
        tabsJson: '[${_encoded('א')}]',
        currentIndex: 0,
      );
      await sessions.save(
        host + 2,
        tabsJson: '[${_encoded('ב')}]',
        currentIndex: 0,
      );

      expect(await TabsRepository.compactWindowSessions(), [host + 1]);
      expect(TabsRepository().loadTabs().single.title, 'א');
      expect((await sessions.load(host + 1))!.tabsJson, contains('ב'));
    });

    test('אידמפוטנטי ואינו מייצר סשנים מעבר למספר המשבצות', () async {
      const host = UserStateSlot.main;
      await TabsRepository().saveTabs([_tab('שלי')], 0);
      for (var slot = 2; slot <= ViewWindowRegistry.maxWindows; slot++) {
        await sessions.save(slot, tabsJson: '[]', currentIndex: 0);
      }

      final first = await TabsRepository.compactWindowSessions();
      expect(first, hasLength(ViewWindowRegistry.maxWindows - 1));
      expect(await TabsRepository.compactWindowSessions(), first);
      expect(
        await sessions.loadAll(),
        hasLength(ViewWindowRegistry.maxWindows),
      );
      expect(first, isNot(contains(host)));
    });

    group('תקרת 8 חלונות, בכל מצב', () {
      test('התקרה היא של חלונות ה-Dart (8)', () async {
        expect(TabsRepository.maxWindowSlot, ViewWindowRegistry.maxWindows);
        MultiViewMode.debugOverride = true;
        expect(TabsRepository.maxWindowSlot, ViewWindowRegistry.maxWindows);
      });

      test('סשן במשבצת 7 נשאר חלון נפרד, ונדחס למשבצת פנויה', () async {
        await TabsRepository().saveTabs([_tab('שלי')], 0);
        for (final (slot, title) in [(3, 'ג'), (5, 'ה'), (6, 'ו'), (7, 'ז')]) {
          await sessions.save(
            slot,
            tabsJson: '[${_encoded(title)}]',
            currentIndex: 0,
          );
        }

        expect(await TabsRepository.compactWindowSessions(), [2, 3, 4, 5]);
        expect((await sessions.load(5))!.tabsJson, contains('ז'));
        expect((await sessions.load(4))!.tabsJson, contains('ו'));
        expect(await sessions.load(7), isNull);
      });

      test('כל 7 המשבצות של חלונות ה-Dart נשמרות', () async {
        await TabsRepository().saveTabs([_tab('שלי')], 0);
        for (var slot = 2; slot <= ViewWindowRegistry.maxWindows; slot++) {
          await sessions.save(
            slot,
            tabsJson: '[${_encoded('חלון $slot')}]',
            currentIndex: 0,
          );
        }

        final slots = await TabsRepository.compactWindowSessions();
        expect(slots, [for (var s = 2; s <= 8; s++) s]);
        expect((await sessions.load(8))!.tabsJson, contains('חלון 8'));
        expect(await sessions.loadAll(), hasLength(8));
      });
    });
  });

  test('ריבוי תצוגות משחזר את כל שמונת הסשנים בלי למחוק חלונות', () async {
    MultiViewMode.debugOverride = true;
    for (var slot = 1; slot <= ViewWindowRegistry.maxWindows; slot++) {
      await sessions.save(slot, tabsJson: '["$slot"]', currentIndex: 0);
    }
    expect(await TabsRepository.compactWindowSessions(), [2, 3, 4, 5, 6, 7, 8]);
    expect(await sessions.loadAll(), hasLength(ViewWindowRegistry.maxWindows));
    expect((await sessions.load(8))!.tabsJson, '["8"]');
  });

  /// שדרוג ממודל A לריבוי תצוגות, והחזרה אליו: אותה טבלה ואותן משבצות.
  group('מעבר בין מודל A לריבוי תצוגות', () {
    const bounds = '{"left":10,"top":20,"width":800,"height":600}';

    Future<void> modelASessions() async {
      await TabsRepository().saveTabs([_tab('ראשי')], 0);
      for (final slot in [2, 3, 4]) {
        await sessions.save(
          slot,
          tabsJson: '[${_encoded('חלון $slot')}]',
          currentIndex: 0,
        );
        await sessions.saveActiveWorkspace(slot, 'ws$slot');
        await sessions.saveBounds(slot, bounds);
      }
    }

    tearDown(() => MultiViewMode.debugOverride = false);

    test('שחזור כל החלונות: סשני 2-4 נשארים במקומם לחלונות ה-Dart', () async {
      MultiViewMode.debugOverride = true;
      expect(WindowTabsSession.current.slot, InProcessTabDrops.mainSlot);
      await modelASessions();

      final slots = await TabsRepository.compactWindowSessions();

      expect(slots, [2, 3, 4]);
      // חלון Dart חדש לא יתפוס משבצת ששמורה לשחזור.
      expect(ViewWindowRegistry().freeSlot(excluding: slots.toSet()), 5);
      for (final slot in slots) {
        final session = (await sessions.load(slot))!;
        expect(session.tabsJson, contains('חלון $slot'));
        expect(session.activeWorkspaceId, 'ws$slot');
        expect(session.boundsJson, bounds);
      }
      expect(TabsRepository().loadTabs().single.title, 'ראשי');
    });

    test('בלי שחזור כל החלונות: מאומצים לראשי', () async {
      MultiViewMode.debugOverride = true;
      await modelASessions();

      expect(await TabsRepository.adoptOrphanWindowSessions(), 3);
      expect(TabsRepository().loadTabs().map((t) => t.title), [
        'ראשי',
        'חלון 2',
        'חלון 3',
        'חלון 4',
      ]);
      expect(await sessions.loadAll(), hasLength(1));
    });

    test('הצירוף למארח שומר את הכרטיסיה הנוכחית והשולחן שלו', () async {
      const host = UserStateSlot.main;
      await TabsRepository().saveTabs([_tab('א'), _tab('ב')], 1);
      await sessions.saveActiveWorkspace(host, 'ws-main');
      for (final slot in [2, 6]) {
        await sessions.save(
          slot,
          tabsJson: '[${_encoded('חלון $slot')}]',
          currentIndex: 0,
        );
      }
      // תקרה 2: משבצת 2 נשארת, ו-3 ו-6 מצורפות לפי הסדר אחרי כרטיסיות המארח.
      await sessions.save(3, tabsJson: '[${_encoded('ג')}]', currentIndex: 0);

      expect(await sessions.compactAround(host, 2), [2]);
      final own = (await sessions.load(host))!;
      expect(own.currentIndex, 1);
      expect(own.activeWorkspaceId, 'ws-main');
      expect(
        TabsRepository().loadTabs().map((t) => t.title),
        ['א', 'ב', 'ג', 'חלון 6'],
      );
      expect((await sessions.load(2))!.tabsJson, contains('חלון 2'));
      expect(await sessions.loadAll(), hasLength(2));
    });
  });

  group('אימוץ סשנים יתומים', () {
    test('מצרף למשבצת המארח ומוחק את האחרות', () async {
      const host = UserStateSlot.main;
      await TabsRepository().saveTabs([_tab('של הראשון')], 0);
      await sessions.save(
        host + 1,
        tabsJson: '[${_encoded('יתום א')}]',
        currentIndex: 0,
      );
      await sessions.save(
        host + 2,
        tabsJson: '[${_encoded('יתום ב')}]',
        currentIndex: 0,
      );

      expect(await TabsRepository.adoptOrphanWindowSessions(), 2);
      expect(TabsRepository().loadTabs().map((t) => t.title), [
        'של הראשון',
        'יתום א',
        'יתום ב',
      ]);
      expect(await sessions.load(host + 1), isNull);
      expect(await sessions.load(host + 2), isNull);
    });

    test('אידמפוטנטי — הרצה שנייה אינה מכפילה', () async {
      const host = UserStateSlot.main;
      await sessions.save(
        host + 1,
        tabsJson: '[${_encoded('יתום')}]',
        currentIndex: 0,
      );

      expect(await TabsRepository.adoptOrphanWindowSessions(), 1);
      expect(await TabsRepository.adoptOrphanWindowSessions(), 0);
      expect(TabsRepository().loadTabs(), hasLength(1));
    });
  });

  group('אבחון כשלים בשחזור סשנים', () {
    setUp(() {
      final previous = WindowEventLog.instance;
      WindowEventLog.instance = WindowEventLog();
      addTearDown(() => WindowEventLog.instance = previous);
    });

    test('אימוץ: כשל SQLite מדווח לפי סוג בלבד', () async {
      await sessions.save(
        2,
        tabsJson: '[${_encoded('/documents/a.pdf')}]',
        currentIndex: 0,
      );
      (await database.database).execute('''
        CREATE TRIGGER reject_session BEFORE INSERT ON window_sessions
        BEGIN SELECT RAISE(ABORT, 'blocked'); END
      ''');

      expect(await TabsRepository.adoptOrphanWindowSessions(), 0);
      final event = WindowEventLog.instance.collect().single;
      expect(event['event'], 'adoptOrphansFailed');
      expect(event['error'], 'SqliteException');
      expect(await sessions.load(2), isNotNull);
    });

    test('דחיסה: כשל בפענוח כרטיסיות מדווח לפי סוג בלבד', () async {
      const tabsJson =
          '["/documents/a.pdf", "search needle", "quoted text"] invalid';
      const overflow = TabsRepository.maxWindowSlot + 1;
      for (var slot = 1; slot <= overflow; slot++) {
        await sessions.save(
          slot,
          tabsJson: slot == overflow ? tabsJson : '[]',
          currentIndex: 0,
        );
      }

      expect(await TabsRepository.compactWindowSessions(), isEmpty);
      final event = WindowEventLog.instance.collect().single;
      expect(event['event'], 'compactFailed');
      expect(event['error'], 'FormatException');
      expect((await sessions.load(overflow))?.tabsJson, tabsJson);
    });
  });
}

String _encoded(String title) =>
    '{"type":"ToolTab","toolId":"builtin.calendar","title":"$title"}';
