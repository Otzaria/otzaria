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
}
