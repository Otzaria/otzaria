import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tools/tool_query.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TabsBloc bloc;
  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tempDir = await Directory.systemTemp.createTemp('tool_tab_dedupe_test');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('tabs');
    bloc = TabsBloc(repository: TabsRepository());
  });

  tearDown(() async {
    await bloc.close();
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ToolTab tool(String id) => ToolTab(toolId: id, title: id);
  TextBookTab book(String title) =>
      TextBookTab(book: TextBook(title: title), index: 0);

  test('OpenOrFocusTab על כלי פתוח ממקד ואינו מוסיף כרטיסיה', () async {
    final toolOpened = bloc.stream.firstWhere(
      (state) => state.tabs.length == 1 && state.currentTabIndex == 0,
    );
    bloc.add(OpenOrFocusTab(tool('builtin.calendar')));
    await toolOpened;

    final bookOpened = bloc.stream.firstWhere(
      (state) => state.tabs.length == 2 && state.currentTabIndex == 1,
    );
    bloc.add(AddTab(book('בראשית')));
    await bookOpened;

    final toolFocused = bloc.stream.firstWhere(
      (state) => state.tabs.length == 2 && state.currentTabIndex == 0,
    );
    bloc.add(OpenOrFocusTab(tool('builtin.calendar')));
    await toolFocused;

    expect(bloc.state.tabs.length, 2, reason: 'לא נפתחה כרטיסיה נוספת');
    expect(bloc.state.currentTabIndex, 0, reason: 'המיקוד עבר לכלי הקיים');
  });

  // כלי שנמצא כחלונית בטאב מפוצל: מעבר טאב לבדו היה משאיר את הפוקוס על
  // החלונית האחרת.
  test('תוסף בתוך טאב מפוצל — ממקד את החלונית עצמה', () async {
    final pluginPane = tool('com.example.plugin');
    final split = CombinedTab(rightTab: book('בראשית'), leftTab: pluginPane);
    final splitAdded = bloc.stream.firstWhere(
      (state) => state.tabs.length == 2 && state.currentTabIndex == 1,
    );
    bloc.add(AddTab(book('שמות')));
    bloc.add(AddTab(split));
    await splitAdded;

    final firstTabFocused = bloc.stream.firstWhere(
      (state) => state.currentTabIndex == 0,
    );
    bloc.add(SetCurrentTab(0));
    await firstTabFocused;

    final toolPaneFocused = bloc.stream.firstWhere(
      (state) =>
          state.currentTabIndex == 1 && identical(state.activePane, pluginPane),
    );
    bloc.add(OpenOrFocusTab(tool('com.example.plugin')));
    await toolPaneFocused;

    expect(bloc.state.tabs.length, 2);
    expect(bloc.state.currentTabIndex, 1);
    expect(bloc.state.activePane, same(pluginPane));
  });

  test('שחזור כרטיסיה סגורה אינו מכפיל תוסף שנפתח מחדש בינתיים', () async {
    final first = tool('com.example.plugin');
    bloc.add(AddTab(first));
    await pumpEventQueue();

    bloc.add(RemoveTab(first));
    await pumpEventQueue();
    expect(bloc.state.tabs, isEmpty);

    // המשתמש פתח אותו שוב מהמשגר, ורק אז לחץ Ctrl+Shift+T.
    bloc.add(OpenOrFocusTab(tool('com.example.plugin')));
    await pumpEventQueue();
    expect(bloc.state.tabs.length, 1);

    bloc.add(RestoreLastClosedTab());
    await pumpEventQueue();

    expect(bloc.state.tabs.length, 1, reason: 'ממקד את הקיים במקום להכפיל');
    expect((bloc.state.tabs.single as ToolTab).toolId, 'com.example.plugin');
  });

  test('שחזור כלי מובנה ממקד אותו כשהוא כבר פתוח', () async {
    final t = tool('builtin.gematria');
    bloc.add(AddTab(t));
    await pumpEventQueue();

    bloc.add(RemoveTab(t));
    await pumpEventQueue();
    expect(bloc.state.tabs, isEmpty);

    bloc.add(OpenOrFocusTab(tool('builtin.gematria')));
    await pumpEventQueue();
    expect(bloc.state.tabs.length, 1);

    bloc.add(RestoreLastClosedTab());
    await pumpEventQueue();

    expect(bloc.state.tabs.length, 1);
    expect((bloc.state.tabs.single as ToolTab).toolId, 'builtin.gematria');
  });

  test('CloneTab משכפל כלי מובנה', () async {
    final calendar = tool('builtin.calendar');
    bloc.add(AddTab(calendar));
    await pumpEventQueue();

    bloc.add(CloneTab(calendar));
    await pumpEventQueue();

    expect(bloc.state.tabs.whereType<ToolTab>().length, 2);
    expect(bloc.state.tabs[0], same(calendar));
    expect(bloc.state.tabs[1], isNot(same(calendar)));
  });

  test('CloneTab אינו משכפל תוסף', () async {
    final plugin = tool('com.example.plugin');
    bloc.add(AddTab(plugin));
    await pumpEventQueue();

    bloc.add(CloneTab(plugin));
    await pumpEventQueue();

    expect(bloc.state.tabs, [same(plugin)]);
  });

  test('פתיחה רגילה אינה מוסיפה מופע אחד עשר כשכל המופעים נוספים', () async {
    final extras = List.generate(
      10,
      (_) => ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        allowMultipleInstances: true,
      ),
    );
    for (final tab in extras) {
      bloc.add(AddTab(tab));
    }
    await pumpEventQueue();
    expect(bloc.state.tabs, hasLength(10));
    bloc.add(OpenOrFocusTab(tool('com.example.plugin')));
    await pumpEventQueue();
    expect(bloc.state.tabs, hasLength(10));
    expect(bloc.state.tabs, extras);
  });

  test('העברה לחלון מלא נדחית בלי לצרוך בעלות על הטאב', () async {
    for (var i = 0; i < 10; i++) {
      bloc.add(
        AddTab(
          ToolTab(
            toolId: 'com.example.plugin',
            title: 'תוסף',
            allowMultipleInstances: true,
          ),
        ),
      );
    }
    await pumpEventQueue();
    final incoming = _TrackedToolTab();
    addTearDown(incoming.dispose);
    expect(bloc.receiveTransferredTab(incoming), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(incoming.disposed, isFalse);
    expect(bloc.state.tabs, hasLength(10));
  });

  test('שחזור טאב שומר אותו בהיסטוריה כשהתוסף כבר בתקרה', () async {
    final tabs = List.generate(
      10,
      (_) => ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        allowMultipleInstances: true,
      ),
    );
    for (final tab in tabs) {
      bloc.add(AddTab(tab));
    }
    await pumpEventQueue();
    bloc.add(RemoveTab(tabs.last));
    await pumpEventQueue();
    final closed = bloc.recentlyClosedTabs.single;
    final replacement = ToolTab(
      toolId: 'com.example.plugin',
      title: 'מופע אחר',
      allowMultipleInstances: true,
    );
    bloc.add(AddTab(replacement));
    await pumpEventQueue();
    bloc.add(RestoreLastClosedTab());
    await pumpEventQueue();
    expect(bloc.state.tabs, hasLength(10));
    expect(bloc.recentlyClosedTabs, contains(same(closed)));
    bloc.add(RestoreClosedTab(closed));
    await pumpEventQueue();
    expect(bloc.state.tabs, hasLength(10));
    expect(bloc.recentlyClosedTabs, contains(same(closed)));
    bloc.add(RemoveTab(replacement));
    await pumpEventQueue();
    bloc.add(RestoreClosedTab(closed));
    await pumpEventQueue();
    expect(bloc.state.tabs, hasLength(10));
    expect(bloc.state.tabs, contains(same(closed)));
    expect(bloc.recentlyClosedTabs, isNot(contains(same(closed))));
  });

  test('החלפה בתקרה מותרת בלי גידול ודוחה מופע אחד עשר', () async {
    final tabs = List.generate(
      10,
      (_) => ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        allowMultipleInstances: true,
      ),
    );
    for (final tab in tabs) {
      bloc.add(AddTab(tab));
    }
    final other = book('ספר');
    bloc.add(AddTab(other));
    await pumpEventQueue();
    final replacement = ToolTab(
      toolId: 'com.example.plugin',
      title: 'מחליף',
      allowMultipleInstances: true,
    );
    bloc.add(ReplaceTab(oldTab: tabs.last, newTab: replacement));
    await pumpEventQueue();
    expect(bloc.state.tabs.whereType<ToolTab>(), hasLength(10));
    expect(bloc.state.tabs, contains(same(replacement)));
    final rejected = _TrackedToolTab();
    bloc.add(ReplaceTab(oldTab: other, newTab: rejected));
    await pumpEventQueue();
    expect(bloc.state.tabs.whereType<ToolTab>(), hasLength(10));
    expect(bloc.state.tabs, contains(same(other)));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(rejected.disposed, isTrue);
  });

  test('AdoptTab אינו עוקף תקרה של מופעים מוצמדים', () async {
    for (var i = 0; i < 10; i++) {
      bloc.add(
        AddTab(
          ToolTab(
            toolId: 'com.example.plugin',
            title: 'תוסף',
            allowMultipleInstances: true,
            isPinned: true,
          ),
        ),
      );
    }
    final other = book('ספר פתוח');
    bloc.add(AddTab(other));
    await pumpEventQueue();
    final incoming = _TrackedToolTab();
    bloc.add(AdoptTab(incoming));
    await pumpEventQueue();
    expect(bloc.state.tabs, contains(same(other)));
    expect(bloc.state.tabs.whereType<ToolTab>(), hasLength(10));
    expect(bloc.recentlyClosedTabs, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(incoming.disposed, isTrue);
  });

  test('חלונית צד אינה עוקפת את תקרת המופעים', () async {
    for (var i = 0; i < 10; i++) {
      bloc.add(
        AddTab(
          ToolTab(
            toolId: 'com.example.plugin',
            title: 'תוסף',
            allowMultipleInstances: true,
          ),
        ),
      );
    }
    final other = book('ספר פתוח');
    bloc.add(AddTab(other));
    await pumpEventQueue();
    final incoming = _TrackedToolTab();
    bloc.add(OpenTabInSidePane(incoming));
    await pumpEventQueue();
    expect(bloc.state.tabs, contains(same(other)));
    expect(bloc.state.tabs.whereType<ToolTab>(), hasLength(10));
    expect(bloc.state.tabs.whereType<CombinedTab>(), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(incoming.disposed, isTrue);
  });

  test('snapshot מלא נשמר גם מעל התקרה ופתיחה נוספת נדחית', () async {
    final saved = List.generate(
      11,
      (_) => ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        allowMultipleInstances: true,
      ),
    );
    bloc.add(ReplaceAllTabs(saved, 0));
    await pumpEventQueue();
    expect(bloc.state.tabs, saved);
    final incoming = _TrackedToolTab();
    bloc.add(AddTab(incoming));
    await pumpEventQueue();
    expect(bloc.state.tabs, saved);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(incoming.disposed, isTrue);
  });

  group('בקשת חיפוש לכלי שכבר פתוח', () {
    test('עוברת לטאב הקיים, והטאב הנכנס לא נוסף', () async {
      final existing = tool('builtin.gematria');
      bloc.add(AddTab(existing));
      await pumpEventQueue();

      final incoming = ToolTab(
        toolId: 'builtin.gematria',
        title: 'גימטריה',
        query: const ToolQuery('26'),
      );
      bloc.add(OpenOrFocusTab(incoming));
      await pumpEventQueue();

      expect(bloc.state.tabs, [same(existing)]);
      expect(existing.queryInbox.take()?.text, '26');
    });

    test('עוברת לחלונית הכלי בטאב מפוצל', () async {
      final pane = tool('builtin.biographies');
      bloc.add(AddTab(CombinedTab(rightTab: book('בראשית'), leftTab: pane)));
      await pumpEventQueue();

      bloc.add(
        OpenOrFocusTab(
          ToolTab(
            toolId: 'builtin.biographies',
            title: 'ביוגרפיות',
            query: const ToolQuery('רש"י'),
          ),
        ),
      );
      await pumpEventQueue();

      expect(pane.queryInbox.take()?.text, 'רש"י');
    });

    test('פתיחה בלי בקשה אינה מוחקת בקשה ממתינה', () async {
      final existing = ToolTab(
        toolId: 'builtin.gematria',
        title: 'גימטריה',
        query: const ToolQuery('26'),
      );
      bloc.add(AddTab(existing));
      await pumpEventQueue();

      bloc.add(OpenOrFocusTab(tool('builtin.gematria')));
      await pumpEventQueue();

      expect(existing.queryInbox.take()?.text, '26');
    });
  });
  test('RenameTab מעדכן כותרת של חלונית בטאב מפוצל ופולט מצב', () async {
    final pane = ToolTab(toolId: 'a.plugin', title: 'כלי');
    final opened = bloc.stream.firstWhere((state) => state.tabs.length == 1);
    bloc.add(
      AddTab(CombinedTab(rightTab: pane, leftTab: book('בראשית'))),
    );
    await opened;

    final renamed = bloc.stream.first;
    bloc.add(RenameTab(pane, 'קידוש החודש'));
    await renamed;

    expect(pane.title, 'קידוש החודש');
    expect(bloc.state.tabs.single, isA<CombinedTab>());
  });

  group('מופעים נוספים של תוסף (allowMultipleInstances)', () {
    const pluginId = 'com.example.plugin';
    ToolTab extra() => ToolTab(
      toolId: pluginId,
      title: pluginId,
      allowMultipleInstances: true,
    );

    test('מופע נוסף נפתח בכרטיסיה נפרדת ואינו מתמזג עם הראשי', () async {
      bloc.add(OpenOrFocusTab(tool(pluginId)));
      bloc.add(OpenOrFocusTab(extra()));
      bloc.add(OpenOrFocusTab(extra()));
      await pumpEventQueue();

      expect(bloc.state.tabs.length, 3);
    });

    test('פתיחה רגילה ממקדת את הראשי ואינה פותחת כרטיסיה נוספת', () async {
      bloc.add(OpenOrFocusTab(tool(pluginId)));
      bloc.add(OpenOrFocusTab(extra()));
      await pumpEventQueue();
      expect(bloc.state.currentTabIndex, 1);

      bloc.add(OpenOrFocusTab(tool(pluginId)));
      await pumpEventQueue();

      expect(bloc.state.tabs.length, 2);
      expect(bloc.state.currentTabIndex, 0);
    });

    test('כשנשארו רק מופעים נוספים פתיחה רגילה פותחת ראשי חדש', () async {
      bloc.add(OpenOrFocusTab(extra()));
      await pumpEventQueue();

      bloc.add(OpenOrFocusTab(tool(pluginId)));
      await pumpEventQueue();

      final tabs = bloc.state.tabs.whereType<ToolTab>().toList();
      expect(tabs.length, 2);
      expect(tabs.where((tab) => tab.dedupeKey != null).length, 1);
    });

    test('מופע נוסף עם insertAdjacent נכנס מיד אחרי הטאב הנוכחי', () async {
      final primary = tool(pluginId);
      final other = tool('com.example.other');
      final last = tool('com.example.last');
      for (final tab in [primary, other, last]) {
        bloc.add(OpenOrFocusTab(tab));
      }
      await pumpEventQueue();
      bloc.add(SetCurrentTab(0));
      await pumpEventQueue();
      expect(bloc.state.currentTabIndex, 0);

      final added = extra();
      bloc.add(OpenOrFocusTab(added, insertAdjacent: true));
      await pumpEventQueue();

      expect(bloc.state.tabs, [primary, added, other, last]);
      expect(bloc.state.currentTabIndex, 1);
    });

    test('בלי insertAdjacent המופע הנוסף נכנס בסוף השורה', () async {
      final primary = tool(pluginId);
      final other = tool('com.example.other');
      for (final tab in [primary, other]) {
        bloc.add(OpenOrFocusTab(tab));
      }
      await pumpEventQueue();
      bloc.add(SetCurrentTab(0));
      await pumpEventQueue();

      final added = extra();
      bloc.add(OpenOrFocusTab(added));
      await pumpEventQueue();

      expect(bloc.state.tabs, [primary, other, added]);
    });

    test('סגירת מופע אחד משאירה את האחרים', () async {
      final primary = tool(pluginId);
      final first = extra();
      final second = extra();
      for (final tab in [primary, first, second]) {
        bloc.add(OpenOrFocusTab(tab));
      }
      await pumpEventQueue();

      bloc.add(RemoveTab(first));
      await pumpEventQueue();

      expect(bloc.state.tabs, containsAll([primary, second]));
      expect(bloc.state.tabs, isNot(contains(first)));
    });
  });
}

class _TrackedToolTab extends ToolTab {
  _TrackedToolTab()
    : super(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        allowMultipleInstances: true,
      );
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
