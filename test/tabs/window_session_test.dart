import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.windowsession';

ToolTab _tab(String title) => ToolTab(toolId: 'builtin.calendar', title: title);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  setUp(() async {
    WindowBus.namespace = _namespace;
    WindowRole.isSecondary = false;
    // ⚠️ בלי זה `UserStateSlot.current` נופל למשבצת החלון היחיד בלינוקס
    // (ה-CI), והבדיקה "בלי משבצת אינו כותב" הייתה ירוקה מסיבה שגויה.
    MultiWindowService.debugSupportedOverride = true;
    tmp = Directory.systemTemp.createTempSync('otzaria_window_session_');
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    sessions = WindowSessionStore(database: database);
    TabsRepository.debugSessions = sessions;
  });

  tearDown(() async {
    TabsRepository.debugSessions = null;
    MultiWindowService.debugSupportedOverride = null;
    database.close();
    WindowRole.isSecondary = false;
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('החלון הראשון', () {
    test('שומר וטוען את המשבצת שלו', () async {
      final slot = WindowBus.instance.register();
      expect(slot, 1, reason: 'המשבצת הראשונה הפנויה — כמו במיגרציה מ-Hive');

      final repo = TabsRepository();
      await repo.saveTabs([_tab('לוח שנה')], 0);

      expect((await sessions.load(1))!.currentIndex, 0);
      expect(repo.loadTabs().single.title, 'לוח שנה');
    });
  });

  group('חלון משני', () {
    test('כותב למשבצת שלו, ולא על הסשן של החלון הראשון', () async {
      // חלון ראשון חי שתופס את משבצת 1.
      final occupied = ReceivePort();
      ui.IsolateNameServer.registerPortWithName(
        occupied.sendPort,
        '$_namespace.1',
      );
      addTearDown(occupied.close);
      await sessions.save(
        1,
        tabsJson: '[${_encoded('של הראשון')}]',
        currentIndex: 0,
      );

      WindowRole.isSecondary = true;
      final slot = WindowBus.instance.register();
      expect(slot, 2);
      await TabsRepository().saveTabs([_tab('של המשני')], 0);

      expect((await sessions.load(1))!.tabsJson, contains('של הראשון'));
      expect((await sessions.load(2))!.tabsJson, contains('של המשני'));
    });

    test('משחזר את הסשן של המשבצת שלו — חלון שמת בלי סגירה מסודרת', () async {
      WindowRole.isSecondary = true;
      WindowBus.instance.register();
      final slot = WindowBus.instance.slot;
      expect(slot, isNotNull);

      await TabsRepository().saveTabs([_tab('נשמר')], 0);
      expect((await sessions.load(slot!)), isNotNull);
      expect(TabsRepository().loadTabs().single.title, 'נשמר');
    });

    test('בלי משבצת אינו כותב כלל', () async {
      WindowBus.instance.register();
      await TabsRepository().saveTabs([_tab('של הראשון')], 0);
      final hostSlot = WindowBus.instance.slot!;
      WindowBus.instance.unregister();

      WindowRole.isSecondary = true;
      await TabsRepository().saveTabs([_tab('לא אמור להישמר')], 0);

      final own = await sessions.load(hostSlot);
      expect(own!.tabsJson, contains('של הראשון'));
      expect(await sessions.loadAll(), hasLength(1));
    });

    test('discardWindowSession מוחק את הסשן', () async {
      WindowRole.isSecondary = true;
      WindowBus.instance.register();
      final slot = WindowBus.instance.slot!;
      final repo = TabsRepository();
      await repo.saveTabs([_tab('נסגר')], 0);
      await repo.discardWindowSession();

      expect(await sessions.load(slot), isNull);
    });
  });

  group('ייבוא מגיבוי', () {
    test('בלי משבצת אינו כותב לסשן של חלון אחר', () async {
      await sessions.save(
        1,
        tabsJson: '[${_encoded('של אחר')}]',
        currentIndex: 0,
      );
      WindowRole.isSecondary = true;

      await TabsRepository().importRaw({
        'tabs': ['x'],
        'currentTab': 0,
      });

      expect((await sessions.load(1))!.tabsJson, contains('של אחר'));
      expect(await TabsRepository().exportRaw(), isNull);
    });

    test('מקדם את דור הסשן — bloc שנבנה קודם לא ישמור', () async {
      WindowBus.instance.register();
      final before = TabsRepository.sessionGeneration;
      await TabsRepository().importRaw({'tabs': <dynamic>[], 'currentTab': 0});
      expect(TabsRepository.sessionGeneration, before + 1);
    });
  });

  group('דחיסת סשנים ל"שחזר את כל החלונות"', () {
    test('מסדר את האחרים ברצף אחרי המארח ומחזיר את המשבצות', () async {
      WindowBus.instance.register();
      final host = WindowBus.instance.slot!;
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
      WindowBus.instance.register();
      final host = WindowBus.instance.slot!;
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
      WindowBus.instance.register();
      final host = WindowBus.instance.slot!;
      await TabsRepository().saveTabs([_tab('שלי')], 0);
      for (var slot = 2; slot <= WindowBus.slotCount; slot++) {
        await sessions.save(slot, tabsJson: '[]', currentIndex: 0);
      }

      final first = await TabsRepository.compactWindowSessions();
      expect(first, hasLength(WindowBus.slotCount - 1));
      expect(await TabsRepository.compactWindowSessions(), first);
      expect(await sessions.loadAll(), hasLength(WindowBus.slotCount));
      expect(first, isNot(contains(host)));
    });
  });

  group('אימוץ סשנים יתומים', () {
    test('מצרף למשבצת המארח ומוחק את האחרות', () async {
      WindowBus.instance.register();
      final host = WindowBus.instance.slot!;
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
      WindowBus.instance.register();
      final host = WindowBus.instance.slot!;
      await sessions.save(
        host + 1,
        tabsJson: '[${_encoded('יתום')}]',
        currentIndex: 0,
      );

      expect(await TabsRepository.adoptOrphanWindowSessions(), 1);
      expect(await TabsRepository.adoptOrphanWindowSessions(), 0);
      expect(TabsRepository().loadTabs(), hasLength(1));
    });

    test('אינו רץ בחלון משני', () async {
      WindowBus.instance.register();
      final host = WindowBus.instance.slot!;
      await sessions.save(
        host + 1,
        tabsJson: '[${_encoded('יתום')}]',
        currentIndex: 0,
      );

      WindowRole.isSecondary = true;
      expect(await TabsRepository.adoptOrphanWindowSessions(), 0);
      expect(await sessions.load(host + 1), isNotNull);
    });
  });
}

String _encoded(String title) =>
    '{"type":"ToolTab","toolId":"builtin.calendar","title":"$title"}';
