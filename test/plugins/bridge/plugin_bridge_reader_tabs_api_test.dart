import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

/// מחסן טאבים ריק — Hive אינו פתוח בבדיקות.
class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      final name = invocation.memberName.toString();
      if (name.contains('save') || name.contains('remap')) {
        return Future<void>.value();
      }
      if (name.contains('loadTabs')) return <OpenedTab>[];
      if (name.contains('loadCurrentTabIndex')) return 0;
    }
    return null;
  }
}

InstalledPlugin _plugin(List<String> permissions) => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Test Plugin',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Matcher _codedError(String code) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'message', contains(code)),
);

void main() {
  late TabsBloc tabsBloc;

  PluginBridgeAdapter buildAdapter() => PluginBridgeAdapter(
    _plugin(const ['reader.open']),
    dependencies: PluginBridgeDependencies(
      historyBloc: _MockHistoryBloc(),
      tabsBloc: tabsBloc,
      navigationBloc: _MockNavigationBloc(),
      calendarCubit: _MockCalendarCubit(),
      workspaceBloc: _MockWorkspaceBloc(),
      searchRepository: _MockSearchRepository(),
      personalNotesRepository: _MockPersonalNotesRepository(),
      bookOpenCoordinator: _MockBookOpenCoordinator(),
      bookmarkBloc: BookmarkBloc(BookmarkRepository()),
      themePayloadBuilder: () => <String, dynamic>{},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async => true,
    ),
    pluginRepository: PluginRegistryRepository(),
  );

  TextBookTab textTab(String title) =>
      TextBookTab(book: TextBook(title: title), index: 0);

  ToolTab toolTab() => ToolTab(toolId: 'gematria', title: 'גימטריה');

  /// ממתין למצב שמקיים [test]. בודק קודם את המצב הנוכחי: הבלוק עשוי לפלוט
  /// עוד לפני שנרשמנו ל-stream, ואז המתנה בלבד הייתה נתקעת.
  Future<void> waitFor(bool Function(TabsState state) test) async {
    if (test(tabsBloc.state)) return;
    await tabsBloc.stream.firstWhere(test).timeout(const Duration(seconds: 5));
  }

  /// מציב את [tabs] בבלוק אמיתי, כדי שהפעולות יעברו דרך ה-handlers האמיתיים
  /// של RemoveTab/SetCurrentTab ולא דרך stub.
  Future<void> openTabs(List<OpenedTab> tabs, {int currentIndex = 0}) async {
    tabsBloc.add(ReplaceAllTabs(tabs, currentIndex));
    await waitFor((state) => state.tabs.length == tabs.length);
  }

  List<String> titles() =>
      tabsBloc.state.tabs.map((tab) => tab.title).toList(growable: false);

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    tabsBloc = TabsBloc(repository: _FakeTabsRepository());
  });

  tearDown(() async {
    await tabsBloc.close();
  });

  group('reader.closeTab', () {
    test('סוגר את הכרטיסייה שבאינדקס שהתוסף קיבל', () async {
      await openTabs([textTab('ברכות'), textTab('שבת'), textTab('עירובין')]);

      final result = await buildAdapter().execute('reader', 'closeTab', {
        'index': 1,
      });
      await waitFor((state) => state.tabs.length == 2);

      expect(result, isTrue);
      expect(titles(), ['ברכות', 'עירובין']);
    });

    test('כרטיסיית כלי פתוחה לפני היעד — נסגרת הכרטיסייה הנכונה', () async {
      // ToolTab אינו מופיע ב-openTabs, ולכן אינדקס 1 של התוסף הוא "שבת"
      // ולא "עירובין". אינדקס גולמי היה סוגר את הכרטיסייה הלא נכונה.
      await openTabs([
        textTab('ברכות'),
        toolTab(),
        textTab('שבת'),
        textTab('עירובין'),
      ]);

      final adapter = buildAdapter();
      final state =
          await adapter.execute('reader', 'getCurrentState', {})
              as Map<String, dynamic>;
      expect(
        (state['openTabs'] as List).map((tab) => tab['bookId']),
        ['ברכות', 'שבת', 'עירובין'],
      );

      await adapter.execute('reader', 'closeTab', {'index': 1});
      await waitFor((state) => state.tabs.length == 3);

      expect(titles(), ['ברכות', 'גימטריה', 'עירובין']);
    });

    test('אינדקס מחוץ לתחום מוחזר כשגיאת ארגומנטים', () async {
      await openTabs([textTab('ברכות'), toolTab()]);

      // שני טאבים פתוחים, אך רק אחד נראה לתוסף.
      expect(
        () => buildAdapter().execute('reader', 'closeTab', {'index': 1}),
        _codedError('error.invalid_params'),
      );
      expect(
        () => buildAdapter().execute('reader', 'closeTab', {'index': -1}),
        _codedError('error.invalid_params'),
      );
      expect(titles(), ['ברכות', 'גימטריה']);
    });

    test('אינדקס חסר מוחזר כשגיאת ארגומנטים', () async {
      await openTabs([textTab('ברכות')]);

      expect(
        () => buildAdapter().execute('reader', 'closeTab', {}),
        _codedError('error.invalid_params'),
      );
    });

    test('אינדקס שאינו שלם מוחזר כשגיאת ארגומנטים', () async {
      await openTabs([textTab('ברכות'), textTab('שבת')]);

      expect(
        () => buildAdapter().execute('reader', 'closeTab', {'index': 1.5}),
        _codedError('error.invalid_params'),
      );
      expect(titles(), ['ברכות', 'שבת']);
    });

    test('הכרטיסייה שנסגרה נכנסת לרשימת הנסגרות לאחרונה', () async {
      await openTabs([textTab('ברכות'), textTab('שבת')]);

      await buildAdapter().execute('reader', 'closeTab', {'index': 0});
      await waitFor((state) => state.tabs.length == 1);

      expect(
        tabsBloc.recentlyClosedTabs.map((tab) => tab.title),
        contains('ברכות'),
      );
    });
  });

  group('reader.activateTab', () {
    test('מפעיל את הכרטיסייה שבאינדקס שהתוסף קיבל', () async {
      await openTabs([textTab('ברכות'), textTab('שבת')], currentIndex: 0);

      final result = await buildAdapter().execute('reader', 'activateTab', {
        'index': 1,
      });
      await waitFor((state) => state.currentTabIndex == 1);

      expect(result, isTrue);
      expect(tabsBloc.state.currentTab?.title, 'שבת');
    });

    test('כרטיסיית כלי פתוחה לפני היעד — מופעלת הכרטיסייה הנכונה', () async {
      await openTabs([
        toolTab(),
        textTab('ברכות'),
        textTab('שבת'),
      ], currentIndex: 0);

      // אינדקס 1 של התוסף = "שבת", שהוא אינדקס 2 ב-TabsBloc.
      await buildAdapter().execute('reader', 'activateTab', {'index': 1});
      await waitFor((state) => state.currentTabIndex == 2);

      expect(tabsBloc.state.currentTab?.title, 'שבת');
    });

    test('אינדקס מחוץ לתחום מוחזר כשגיאת ארגומנטים', () async {
      await openTabs([textTab('ברכות')]);

      expect(
        () => buildAdapter().execute('reader', 'activateTab', {'index': 5}),
        _codedError('error.invalid_params'),
      );
      expect(tabsBloc.state.currentTabIndex, 0);
    });

    test('אינדקס שאינו שלם מוחזר כשגיאת ארגומנטים', () async {
      await openTabs([textTab('ברכות'), textTab('שבת')]);

      expect(
        () => buildAdapter().execute('reader', 'activateTab', {'index': 1.5}),
        _codedError('error.invalid_params'),
      );
      expect(tabsBloc.state.currentTabIndex, 0);
    });

    test('בלי כרטיסיות פתוחות כל אינדקס נדחה', () async {
      expect(
        () => buildAdapter().execute('reader', 'activateTab', {'index': 0}),
        _codedError('error.invalid_params'),
      );
    });
  });
}
