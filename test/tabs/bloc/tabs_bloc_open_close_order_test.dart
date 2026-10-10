import 'dart:async';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

class _ControlledBook extends TextBook {
  _ControlledBook() : super(title: 'ספר אטי');

  final contents = Completer<List<TocEntry>>();
  final resolutionStarted = Completer<void>();

  @override
  Future<List<TocEntry>> get tableOfContents {
    if (!resolutionStarted.isCompleted) resolutionStarted.complete();
    return contents.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TabsBloc bloc;
  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tempDir = await Directory.systemTemp.createTemp('tabs_open_close_order');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('tabs');
    bloc = TabsBloc(repository: TabsRepository());
  });

  tearDown(() async {
    await bloc.close();
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('סגירת התוסף אחרי פתיחת ספר אינה משאירה רגע בלי טאבים', () async {
    final plugin = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
    bloc.add(AddTab(plugin));
    await bloc.stream.firstWhere((state) => state.tabs.length == 1);

    final emitted = <TabsState>[];
    final subscription = bloc.stream.listen(emitted.add);
    addTearDown(subscription.cancel);

    final book = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
    bloc.add(OpenOrFocusTab(book));
    bloc.add(RemoveTab(plugin));
    await bloc.stream
        .firstWhere(
          (state) => state.tabs.length == 1 && state.tabs.single == book,
        )
        .timeout(const Duration(seconds: 5));

    expect(
      emitted.where((state) => !state.hasOpenTabs),
      isEmpty,
      reason: 'מצב ריק מפעיל את המעבר לספרייה במסך העיון',
    );
  });

  test('פתיחה בתור מאחורי מיקוד תוסף אינה פולטת מצב ריק בסגירתו', () async {
    final plugin = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
    bloc.add(AddTab(plugin));
    await bloc.stream.firstWhere((state) => state.tabs.length == 1);
    final emitted = <TabsState>[];
    final subscription = bloc.stream.listen(emitted.add);
    addTearDown(subscription.cancel);
    final slowBook = _ControlledBook();
    final book = TextBookTab(book: slowBook, index: 0);

    bloc.add(OpenOrFocusTab(ToolTab(toolId: plugin.toolId, title: 'תוסף')));
    bloc.add(OpenOrFocusTab(book));
    bloc.add(RemoveTab(plugin));
    await slowBook.resolutionStarted.future;
    slowBook.contents.complete([]);
    await bloc.stream
        .firstWhere(
          (state) => state.tabs.length == 1 && state.tabs.single == book,
        )
        .timeout(const Duration(seconds: 2));

    expect(emitted.where((state) => !state.hasOpenTabs), isEmpty);
  });

  test('סגירה משאירה טאב אחר בלי להמתין לפתיחת ספר אטי', () async {
    final plugin = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
    final survivor = ToolTab(toolId: 'survivor', title: 'טאב אחר');
    bloc.add(AddTab(plugin));
    bloc.add(AddTab(survivor));
    await bloc.stream.firstWhere((state) => state.tabs.length == 2);
    final slowBook = _ControlledBook();
    bloc.add(OpenOrFocusTab(TextBookTab(book: slowBook, index: 0)));
    await slowBook.resolutionStarted.future;
    bloc.add(RemoveTab(plugin));
    try {
      await bloc.stream
          .firstWhere((state) => !state.tabs.contains(plugin))
          .timeout(const Duration(seconds: 1));
      expect(bloc.state.tabs, [survivor]);
    } finally {
      slowBook.contents.complete([]);
    }
  });

  test('סגירה אינה ממתינה לפתיחה שנשלחה אחריה', () async {
    final plugin = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
    bloc.add(AddTab(plugin));
    await bloc.stream.firstWhere((state) => state.tabs.length == 1);
    final slowBook = _ControlledBook();
    final closed = bloc.stream.firstWhere((state) => !state.hasOpenTabs);
    bloc.add(OpenOrFocusTab(ToolTab(toolId: plugin.toolId, title: 'תוסף')));
    bloc.add(RemoveTab(plugin));
    bloc.add(OpenOrFocusTab(TextBookTab(book: slowBook, index: 0)));
    try {
      await closed.timeout(const Duration(seconds: 1));
    } finally {
      slowBook.contents.complete([]);
    }
  });

  test('שליחת אותו אירוע פתיחה פעמיים אינה משאירה סגירה תקועה', () async {
    final plugin = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
    bloc.add(AddTab(plugin));
    await bloc.stream.firstWhere((state) => state.tabs.length == 1);
    final opening = OpenOrFocusTab(
      ToolTab(toolId: 'survivor', title: 'טאב אחר'),
    );
    bloc.add(opening);
    bloc.add(opening);
    bloc.add(RemoveTab(plugin));
    await bloc.stream
        .firstWhere((state) => !state.tabs.contains(plugin))
        .timeout(const Duration(seconds: 2));
    expect(bloc.state.tabs.single.title, 'טאב אחר');
  });

  test('כשל ברזולוציית הכותרת אינו חוסם את סגירת התוסף', () async {
    final plugin = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
    bloc.add(AddTab(plugin));
    await bloc.stream.firstWhere((state) => state.tabs.length == 1);
    final slowBook = _ControlledBook();
    final book = TextBookTab(book: slowBook, index: 0);
    bloc.add(OpenOrFocusTab(book));
    bloc.add(RemoveTab(plugin));
    await slowBook.resolutionStarted.future;
    slowBook.contents.completeError(StateError('אין תוכן עניינים'));
    await bloc.stream
        .firstWhere(
          (state) => state.tabs.length == 1 && state.tabs.single == book,
        )
        .timeout(const Duration(seconds: 2));
  });
}
