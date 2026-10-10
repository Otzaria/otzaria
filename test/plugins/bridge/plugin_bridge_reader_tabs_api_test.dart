import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
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

class _ReaderGrants extends PluginRegistryRepository {
  _ReaderGrants(this.names);
  final List<String> names;
  @override
  Future<List<String>> getGrantedPermissionNames(String pluginId) async =>
      names;
}

class _LoadedReaderBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _LoadedReaderBloc(TextBook book)
    : super(
        TextBookLoaded.initial(
          book: book,
          index: 0,
          showLeftPane: false,
          splitView: false,
        ),
      ) {
    on<UpdateFontSize>(
      (event, emit) => emit(
        (state as TextBookLoaded).copyWith(fontSize: event.fontSize),
      ),
    );
    on<UpdateVisibleIndecies>(
      (event, emit) => emit(
        (state as TextBookLoaded).copyWith(
          visibleIndices: event.visibleIndecies,
        ),
      ),
    );
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// מחסן טאבים ריק — Hive אינו פתוח בבדיקות.
class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      final name = invocation.memberName.toString();
      if (name.contains('save') ||
          name.contains('remap') ||
          name.contains('flush')) {
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
  TestWidgetsFlutterBinding.ensureInitialized();
  late TabsBloc tabsBloc;

  PluginBridgeAdapter buildAdapter({
    String? instanceId,
    TextBookTab? readerTab,
    bool userGesture = true,
    List<String> permissions = const ['reader.open'],
  }) => PluginBridgeAdapter(
    _plugin(permissions),
    instanceId: instanceId ?? 'fg',
    readerTab: readerTab,
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
      hasUserActivation: (_, _) async => userGesture,
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async => true,
    ),
    pluginRepository: _ReaderGrants(permissions),
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
    await PluginTextReaderRegistry.instance.select(_plugin(const []), false);
    await tabsBloc.close();
  });

  group('default text reader', () {
    final permissions = PluginTextReaderRegistry.requiredPermissions.toList();
    test(
      'navigation in the already active plugin book emits a fresh tabs state',
      () async {
        final bound = TextBookTab(
          book: TextBook(id: 77, title: 'ברכות'),
          index: 0,
        );
        await openTabs([bound]);
        await PluginTextReaderRegistry.instance.select(
          _plugin(permissions),
          true,
        );
        final previous = tabsBloc.state.updateCounter;
        tabsBloc.add(
          OpenOrFocusTab(
            TextBookTab(book: bound.book, index: 40),
            navigateToPositionIfReused: true,
            targetTitle: 'ברכות',
          ),
        );
        await waitFor((state) => state.updateCounter > previous);
        expect(tabsBloc.state.tabs.single, same(bound));
        expect(bound.index, 40);
      },
    );
    test(
      'explicit foreground gesture persists choice; deselection reverts',
      () async {
        final adapter = buildAdapter(permissions: permissions);
        await adapter.execute('reader', 'setDefaultTextReader', {
          'enabled': true,
        });
        expect(
          Settings.getValue<String>(PluginTextReaderRegistry.settingsKey),
          'test.plugin',
        );
        final result =
            await adapter.execute('reader', 'getDefaultTextReader', {}) as Map;
        expect(result['enabled'], true);
        expect(result['available'], true);
        await adapter.execute('reader', 'setDefaultTextReader', {
          'enabled': false,
        });
        expect(PluginTextReaderRegistry.instance.activePlugin, isNull);
      },
    );
    test(
      'background, missing gesture, missing actual grants and invalid boolean are rejected',
      () async {
        for (final adapter in [
          buildAdapter(instanceId: 'background', permissions: permissions),
          buildAdapter(userGesture: false, permissions: permissions),
          buildAdapter(),
        ]) {
          await expectLater(
            adapter.execute('reader', 'setDefaultTextReader', {
              'enabled': true,
            }),
            _codedError('error.forbidden'),
          );
        }
        await expectLater(
          buildAdapter(
            permissions: permissions,
          ).execute('reader', 'setDefaultTextReader', {'enabled': 'true'}),
          _codedError('error.invalid_params'),
        );
        expect(PluginTextReaderRegistry.instance.activePlugin, isNull);
      },
    );
    test(
      'location belongs to bound tab even when another book is focused',
      () async {
        final bound = textTab('ברכות'), focused = textTab('שבת');
        await openTabs([bound, focused], currentIndex: 1);
        await PluginTextReaderRegistry.instance.select(
          _plugin(permissions),
          true,
        );
        final adapter = buildAdapter(
          readerTab: bound,
          permissions: permissions,
        );
        await adapter.execute('reader', 'reportTextReaderLocation', {
          'index': 30,
          'ref': 'ברכות פרק ב',
        });
        expect(bound.index, 30);
        expect(bound.toJson()['initalIndex'], 30);
        expect(bound.currentTitle.value, 'ברכות פרק ב');
        expect(focused.index, 0);
        await expectLater(
          buildAdapter(
            readerTab: bound,
            permissions: permissions,
            instanceId: 'background',
          ).execute('reader', 'reportTextReaderLocation', {'index': 1}),
          _codedError('error.unavailable'),
        );
        await expectLater(
          adapter.execute('reader', 'reportTextReaderLocation', {'index': -1}),
          _codedError('error.invalid_params'),
        );
        await expectLater(
          buildAdapter(
            permissions: permissions,
          ).execute('reader', 'reportTextReaderLocation', {'index': 1}),
          _codedError('error.unavailable'),
        );
        PluginTextReaderRegistry.instance.useNative(bound);
        await expectLater(
          adapter.execute('reader', 'reportTextReaderLocation', {'index': 1}),
          _codedError('error.unavailable'),
        );
      },
    );
    test(
      'loaded native state is synchronized before tab persistence',
      () async {
        final book = TextBook(title: 'ברכות');
        final bound = TextBookTab(
          book: book,
          index: 0,
          blocOverride: _LoadedReaderBloc(book),
        );
        await openTabs([bound]);
        await PluginTextReaderRegistry.instance.select(
          _plugin(permissions),
          true,
        );
        await buildAdapter(
          readerTab: bound,
          permissions: permissions,
        ).execute('reader', 'reportTextReaderLocation', {'index': 50});
        expect(bound.index, 50);
        expect(bound.toJson()['initalIndex'], 50);
      },
    );
    test(
      'reused plugin reader tab keeps the navigation target during persistence',
      () async {
        final book = TextBook(id: 3860, title: 'משנה ברורה');
        final bound = TextBookTab(
          book: book,
          index: 0,
          blocOverride: _LoadedReaderBloc(book),
        );
        await openTabs([bound]);
        await PluginTextReaderRegistry.instance.select(
          _plugin(permissions),
          true,
        );
        final revision = tabsBloc.state.updateCounter;
        tabsBloc.add(
          OpenOrFocusTab(
            TextBookTab(book: book, index: 12122),
            navigateToPositionIfReused: true,
          ),
        );
        await waitFor((state) => state.updateCounter > revision);
        expect(bound.toJson()['initalIndex'], 12122);
        expect(bound.index, 12122);
        expect(
          (bound.bloc.state as TextBookLoaded).visibleIndices.first,
          12122,
        );
      },
    );
    test(
      'font preferences restore only in the bound foreground reader',
      () async {
        final book = TextBook(title: 'ברכות');
        final bound = TextBookTab(
          book: book,
          index: 0,
          blocOverride: _LoadedReaderBloc(book),
        );
        final other = textTab('שבת');
        await openTabs([bound, other], currentIndex: 1);
        await PluginTextReaderRegistry.instance.select(
          _plugin(permissions),
          true,
        );
        final adapter = buildAdapter(
          readerTab: bound,
          permissions: permissions,
        );
        final updated = bound.bloc.stream.firstWhere(
          (s) => s is TextBookLoaded && s.fontSize == 31,
        );
        await adapter.execute('reader', 'setTextReaderFontSize', {
          'fontSize': 31,
        });
        await updated;
        expect((bound.bloc.state as TextBookLoaded).fontSize, 31);
        for (final size in [double.nan, 13, 61, '31']) {
          await expectLater(
            adapter.execute('reader', 'setTextReaderFontSize', {
              'fontSize': size,
            }),
            _codedError('error.invalid_params'),
          );
        }
        await expectLater(
          buildAdapter(
            readerTab: bound,
            permissions: permissions,
            userGesture: false,
            instanceId: 'background',
          ).execute('reader', 'setTextReaderFontSize', {'fontSize': 30}),
          _codedError('error.unavailable'),
        );
        await expectLater(
          buildAdapter(
            permissions: permissions,
          ).execute('reader', 'setTextReaderFontSize', {'fontSize': 30}),
          _codedError('error.unavailable'),
        );
        PluginTextReaderRegistry.instance.useNative(bound);
        await expectLater(
          adapter.execute('reader', 'setTextReaderFontSize', {'fontSize': 30}),
          _codedError('error.unavailable'),
        );
      },
    );
    test('a replaced reader cannot update a formerly bound tab', () async {
      final bound = textTab('ברכות');
      await openTabs([bound]);
      final other = _plugin(permissions).copyWith(pluginId: 'other.reader');
      await PluginTextReaderRegistry.instance.select(other, true);
      await expectLater(
        buildAdapter(
          readerTab: bound,
          permissions: permissions,
        ).execute('reader', 'reportTextReaderLocation', {'index': 10}),
        _codedError('error.unavailable'),
      );
      await PluginTextReaderRegistry.instance.select(other, false);
      expect(bound.index, 0);
    });
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

    test('כרטיסיות כלים מופיעות ב-openTabs ונסגרות לפי האינדקס', () async {
      await openTabs([textTab('ברכות'), toolTab(), textTab('שבת')]);

      final adapter = buildAdapter();
      final state =
          await adapter.execute('reader', 'getCurrentState', {})
              as Map<String, dynamic>;
      final tabs = state['openTabs'] as List;
      expect(tabs.map((tab) => tab['bookId']), ['ברכות', 'גימטריה', 'שבת']);
      expect(tabs.map((tab) => tab['toolId']), [null, 'gematria', null]);

      await adapter.execute('reader', 'closeTab', {'index': 1});
      await waitFor((state) => state.tabs.length == 2);

      expect(titles(), ['ברכות', 'שבת']);
    });

    test('תוסף מזהה את הכרטיסייה שלו לפי isSelf וסוגר את עצמו', () async {
      final self = ToolTab(toolId: 'test.plugin', title: 'Test Plugin');
      await openTabs([
        ToolTab(toolId: 'test.plugin', title: 'מופע אחר'),
        self,
        textTab('ברכות'),
      ]);

      final adapter = buildAdapter(instanceId: self.instanceId);
      final state =
          await adapter.execute('reader', 'getCurrentState', {})
              as Map<String, dynamic>;
      final index = (state['openTabs'] as List).indexWhere(
        (tab) => tab['isSelf'] == true,
      );
      expect(index, 1);

      await adapter.execute('reader', 'closeTab', {'index': index});
      await waitFor((state) => state.tabs.length == 2);

      expect(titles(), ['מופע אחר', 'ברכות']);
    });

    test('אינדקס מחוץ לתחום מוחזר כשגיאת ארגומנטים', () async {
      await openTabs([textTab('ברכות'), toolTab()]);

      expect(
        () => buildAdapter().execute('reader', 'closeTab', {'index': 2}),
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

    test('כרטיסיית כלי ניתנת להפעלה לפי האינדקס', () async {
      await openTabs([
        toolTab(),
        textTab('ברכות'),
        textTab('שבת'),
      ], currentIndex: 2);

      await buildAdapter().execute('reader', 'activateTab', {'index': 0});
      await waitFor((state) => state.currentTabIndex == 0);

      expect(tabsBloc.state.currentTab?.title, 'גימטריה');
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
