import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/plugins/services/plugin_tab_info.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TabsBloc bloc;
  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tempDir = await Directory.systemTemp.createTemp('set_plugin_tab_info_test');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('tabs');
    bloc = TabsBloc(repository: TabsRepository());
  });

  tearDown(() async {
    await bloc.close();
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ToolTab plugin() => ToolTab(
    toolId: 'com.example.plugin',
    title: 'שני טורים',
    allowMultipleInstances: true,
  );

  Future<void> open(OpenedTab tab, int expectedCount) async {
    final opened = bloc.stream.firstWhere(
      (state) => state.tabs.length == expectedCount,
    );
    bloc.add(AddTab(tab));
    await opened;
  }

  test('SetPluginTabInfo מעדכן כותרת וטולטיפ ופולט state חדש', () async {
    final tab = plugin();
    await open(tab, 1);

    final updated = bloc.stream.firstWhere(
      (state) => (state.tabs.single as ToolTab).title == 'בראשית א',
    );
    bloc.add(
      SetPluginTabInfo(
        tab,
        PluginTabInfoUpdate.parse({'title': 'בראשית א', 'tooltip': 'בראשית'}),
      ),
    );
    final state = await updated;

    final shown = state.tabs.single as ToolTab;
    expect(shown.title, 'בראשית א');
    expect(shown.tooltipOverride, 'בראשית');
  });

  test('טאב שאינו פתוח (נסגר בינתיים) — האירוע מתעלם', () async {
    final open1 = plugin();
    final closed = plugin();
    await open(open1, 1);

    bloc.add(
      SetPluginTabInfo(closed, PluginTabInfoUpdate.parse({'title': 'חדש'})),
    );
    // אירוע נוסף שנעבד אחרי הראשון (המעבד סדרתי) מבטיח שהראשון כבר טופל.
    final marker = bloc.stream.firstWhere((s) => s.tabs.length == 2);
    bloc.add(AddTab(plugin()));
    await marker;

    expect(closed.title, 'שני טורים');
    expect(open1.title, 'שני טורים');
  });

  test('חלונית בתוך טאב מפוצל מתעדכנת', () async {
    final pane = plugin();
    final split = CombinedTab(
      rightTab: TextBookTab(book: TextBook(title: 'בראשית'), index: 0),
      leftTab: pane,
    );
    await open(split, 1);

    bloc.add(
      SetPluginTabInfo(pane, PluginTabInfoUpdate.parse({'title': 'בפיצול'})),
    );
    final TabsState state = await bloc.stream.firstWhere(
      (s) => pane.title == 'בפיצול',
    );
    expect(state.tabs, hasLength(1));
    expect(pane.title, 'בפיצול');
  });
  test('RenameTab מעדכן את כותרת הבסיס גם כשההתאמה שווה לשם החדש', () async {
    final tab = plugin()..title = 'כלי';
    await open(tab, 1);
    final info = bloc.stream.firstWhere((state) => tab.titleOverride != null);
    bloc.add(
      SetPluginTabInfo(tab, PluginTabInfoUpdate.parse({'title': 'שני טורים'})),
    );
    await info;
    bloc.add(RenameTab(tab, 'שני טורים'));
    final reset = bloc.stream.firstWhere((state) => tab.titleOverride == null);
    bloc.add(SetPluginTabInfo(tab, PluginTabInfoUpdate.parse({'title': null})));
    await reset;
    expect(tab.baseTitle, 'שני טורים');
    expect(tab.title, 'שני טורים');
  });
}
