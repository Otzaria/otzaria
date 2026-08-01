import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

/// כרטיסיית כלי חייבת להיות יחידה: `PluginRuntimeDispatcher` ממפתח controller
/// לפי מזהה תוסף, ושני מופעי WebView לאותו תוסף דורסים זה את רישום זה.
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
    // כל אירוע נצרך בנפרד: OpenOrFocusTab ו-AddTab רשומים בטרנספורמרים
    // נפרדים ולכן אינם מובטחים לרוץ בסדר ההוספה.
    bloc.add(OpenOrFocusTab(tool('builtin.calendar')));
    await pumpEventQueue();
    bloc.add(AddTab(book('בראשית')));
    await pumpEventQueue();
    expect(bloc.state.tabs.length, 2);
    expect(bloc.state.currentTabIndex, 1);

    bloc.add(OpenOrFocusTab(tool('builtin.calendar')));
    await pumpEventQueue();

    expect(bloc.state.tabs.length, 2, reason: 'לא נפתחה כרטיסיה נוספת');
    expect(bloc.state.currentTabIndex, 0, reason: 'המיקוד עבר לכלי הקיים');
  });

  test('כלים שונים נפתחים ככרטיסיות נפרדות', () async {
    final toolsOpened = bloc.stream.firstWhere(
      (state) => state.tabs.length == 2 && state.currentTabIndex == 1,
    );
    bloc.add(OpenOrFocusTab(tool('builtin.calendar')));
    bloc.add(OpenOrFocusTab(tool('builtin.gematria')));
    await toolsOpened;
    expect(bloc.state.tabs.length, 2);
  });

  // כלי שנמצא כחלונית בטאב מפוצל: מעבר טאב לבדו היה משאיר את הפוקוס על
  // החלונית האחרת.
  test('כלי בתוך טאב מפוצל — ממקד את החלונית עצמה', () async {
    final calendarPane = tool('builtin.calendar');
    final split = CombinedTab(rightTab: book('בראשית'), leftTab: calendarPane);
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
          state.currentTabIndex == 1 &&
          identical(state.activePane, calendarPane),
    );
    bloc.add(OpenOrFocusTab(tool('builtin.calendar')));
    await toolPaneFocused;

    expect(bloc.state.tabs.length, 2);
    expect(bloc.state.currentTabIndex, 1);
    expect(bloc.state.activePane, same(calendarPane));
  });

  test('שחזור כרטיסיה סגורה אינו מכפיל כלי שנפתח מחדש בינתיים', () async {
    final first = tool('builtin.notes');
    bloc.add(AddTab(first));
    await pumpEventQueue();

    bloc.add(RemoveTab(first));
    await pumpEventQueue();
    expect(bloc.state.tabs, isEmpty);

    // המשתמש פתח אותו שוב מהמשגר, ורק אז לחץ Ctrl+Shift+T.
    bloc.add(OpenOrFocusTab(tool('builtin.notes')));
    await pumpEventQueue();
    expect(bloc.state.tabs.length, 1);

    bloc.add(RestoreLastClosedTab());
    await pumpEventQueue();

    expect(bloc.state.tabs.length, 1, reason: 'ממקד את הקיים במקום להכפיל');
    expect((bloc.state.tabs.single as ToolTab).toolId, 'builtin.notes');
  });

  test('שחזור כרטיסיית כלי כשאינה פתוחה — מוסיף אותה כרגיל', () async {
    final t = tool('builtin.gematria');
    bloc.add(AddTab(t));
    bloc.add(AddTab(book('בראשית')));
    await pumpEventQueue();

    bloc.add(RemoveTab(t));
    await pumpEventQueue();
    expect(bloc.state.tabs.length, 1);

    bloc.add(RestoreLastClosedTab());
    await pumpEventQueue();

    expect(bloc.state.tabs.length, 2);
    expect(bloc.state.tabs.whereType<ToolTab>().length, 1);
  });
}
