import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
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
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
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

class _StubTabsBloc extends Mock implements TabsBloc {
  TabsState currentState = TabsState.initial();

  @override
  TabsState get state => currentState;
}

/// מחסן סימניות בזיכרון — עוקף את Hive, שאינו פתוח בבדיקות.
class _InMemoryBookmarkRepository extends BookmarkRepository {
  List<Bookmark> stored = [];

  @override
  Future<List<Bookmark>> loadBookmarks() async => stored;

  @override
  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    stored = bookmarks;
  }

  @override
  Future<void> clearBookmarks() async => stored = [];
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

TextBookTab _loadedTextTab({
  String title = 'ספר בדיקה לתוספים',
  List<String> available = const [],
  List<String> active = const [],
  bool pageShape = false,
}) {
  final tab = TextBookTab(book: TextBook(title: title), index: 1);
  tab.bloc.emit(
    TextBookLoaded.initial(
      book: tab.book,
      index: tab.index,
      showLeftPane: false,
      splitView: false,
    ).copyWith(
      content: const ['שורה א', 'שורה ב', 'שורה ג'],
      availableCommentators: available,
      activeCommentators: active,
      showPageShapeView: pageShape,
    ),
  );
  return tab;
}

void main() {
  late _StubTabsBloc tabsBloc;
  late BookmarkBloc bookmarkBloc;
  late _InMemoryBookmarkRepository bookmarkRepository;

  PluginBridgeAdapter buildAdapter() => PluginBridgeAdapter(
    _plugin(const ['reader.open', 'bookmarks.read', 'bookmarks.write']),
    dependencies: PluginBridgeDependencies(
      historyBloc: _MockHistoryBloc(),
      tabsBloc: tabsBloc,
      navigationBloc: _MockNavigationBloc(),
      calendarCubit: _MockCalendarCubit(),
      workspaceBloc: _MockWorkspaceBloc(),
      searchRepository: _MockSearchRepository(),
      personalNotesRepository: _MockPersonalNotesRepository(),
      bookOpenCoordinator: _MockBookOpenCoordinator(),
      bookmarkBloc: bookmarkBloc,
      themePayloadBuilder: () => <String, dynamic>{},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async => true,
    ),
    pluginRepository: PluginRegistryRepository(),
  );

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    tabsBloc = _StubTabsBloc();
    bookmarkRepository = _InMemoryBookmarkRepository();
    bookmarkBloc = BookmarkBloc(bookmarkRepository);
  });

  group('reader.getHighlightCapabilities', () {
    test('תצוגה משולבת — הדגשות, בחירה ותפריט הקשר בטקסט הראשי', () async {
      tabsBloc.currentState = TabsState(
        tabs: [_loadedTextTab()],
        currentTabIndex: 0,
      );
      final data =
          await buildAdapter().execute(
                'reader',
                'getHighlightCapabilities',
                {},
              )
              as Map<String, dynamic>;
      expect(data['surface'], 'combined');
      expect(data['highlights'], isTrue);
      expect(data['selection'], isTrue);
      expect(data['contextMenu'], ['mainText']);
    });

    test('צורת הדף מדווחת surface נפרד', () async {
      tabsBloc.currentState = TabsState(
        tabs: [_loadedTextTab(pageShape: true)],
        currentTabIndex: 0,
      );
      final data =
          await buildAdapter().execute(
                'reader',
                'getHighlightCapabilities',
                {},
              )
              as Map<String, dynamic>;
      expect(data['surface'], 'pageShape');
      expect(data['highlights'], isTrue);
    });

    test('ב-PDF אין הדגשות, בחירה ותפריט הקשר', () async {
      tabsBloc.currentState = TabsState(
        tabs: [
          PdfBookTab(
            book: PdfBook(title: 'ספר', path: 'a.pdf'),
            pageNumber: 1,
          ),
        ],
        currentTabIndex: 0,
      );
      final data =
          await buildAdapter().execute(
                'reader',
                'getHighlightCapabilities',
                {},
              )
              as Map<String, dynamic>;
      expect(data['surface'], 'pdf');
      expect(data['highlights'], isFalse);
      expect(data['selection'], isFalse);
      expect(data['contextMenu'], isEmpty);
    });

    test('ללא חלונית קריאה — surface null והכל כבוי', () async {
      final data =
          await buildAdapter().execute(
                'reader',
                'getHighlightCapabilities',
                {},
              )
              as Map<String, dynamic>;
      expect(data['surface'], isNull);
      expect(data['highlights'], isFalse);
    });
  });

  group('reader.scrollToSection', () {
    test('גולל את הספר הפתוח בלי לסמן כברירת מחדל', () async {
      final tab = _loadedTextTab();
      tabsBloc.currentState = TabsState(tabs: [tab], currentTabIndex: 0);

      final result = await buildAdapter().execute('reader', 'scrollToSection', {
        'sectionIndex': 2,
      });

      expect(result, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect((tab.bloc.state as TextBookLoaded).permanentHighlightLine, isNull);
    });

    test('highlight: true מסמן את הקטע', () async {
      final tab = _loadedTextTab();
      tabsBloc.currentState = TabsState(tabs: [tab], currentTabIndex: 0);

      await buildAdapter().execute('reader', 'scrollToSection', {
        'sectionIndex': 1,
        'highlight': true,
      });

      await Future<void>.delayed(Duration.zero);
      expect((tab.bloc.state as TextBookLoaded).permanentHighlightLine, 1);
    });

    test('ללא חלונית קריאה מחזיר false', () async {
      expect(
        await buildAdapter().execute('reader', 'scrollToSection', {
          'sectionIndex': 0,
        }),
        isFalse,
      );
    });

    test('sectionIndex שאינו מספר שלם אי-שלילי נדחה', () async {
      expect(
        () => buildAdapter().execute('reader', 'scrollToSection', {
          'sectionIndex': -1,
        }),
        _codedError('error.invalid_params'),
      );
      expect(
        () => buildAdapter().execute('reader', 'scrollToSection', {
          'sectionIndex': 'שתיים',
        }),
        _codedError('error.invalid_params'),
      );
    });
  });

  group('reader.setActiveCommentators', () {
    test('add ו-remove מצטברים על הבחירה הקיימת', () async {
      final tab = _loadedTextTab(
        available: const ['רש"י', 'רמב"ן', 'אבן עזרא'],
        active: const ['רש"י', 'רמב"ן'],
      );
      tabsBloc.currentState = TabsState(tabs: [tab], currentTabIndex: 0);

      final data =
          await buildAdapter().execute('reader', 'setActiveCommentators', {
                'add': ['אבן עזרא'],
                'remove': ['רמב"ן'],
              })
              as Map<String, dynamic>;

      expect(data['active'], ['רש"י', 'אבן עזרא']);
    });

    test('מפרש שאינו קיים בספר נדחה', () async {
      tabsBloc.currentState = TabsState(
        tabs: [
          _loadedTextTab(available: const ['רש"י']),
        ],
        currentTabIndex: 0,
      );
      expect(
        () => buildAdapter().execute('reader', 'setActiveCommentators', {
          'add': ['מפרש דמיוני'],
        }),
        _codedError('error.not_found'),
      );
    });

    test('בלי add ובלי remove — invalid_params', () async {
      tabsBloc.currentState = TabsState(
        tabs: [
          _loadedTextTab(available: const ['רש"י']),
        ],
        currentTabIndex: 0,
      );
      expect(
        () => buildAdapter().execute(
          'reader',
          'setActiveCommentators',
          <String, dynamic>{},
        ),
        _codedError('error.invalid_params'),
      );
    });

    test('ב-PDF מחזיר null — הבחירה אינה נתמכת לכתיבה', () async {
      tabsBloc.currentState = TabsState(
        tabs: [
          PdfBookTab(
            book: PdfBook(title: 'ספר', path: 'a.pdf'),
            pageNumber: 1,
          ),
        ],
        currentTabIndex: 0,
      );
      expect(
        await buildAdapter().execute('reader', 'setActiveCommentators', {
          'add': ['רש"י'],
        }),
        isNull,
      );
    });
  });

  group('bookmarks.*', () {
    Bookmark bookmark(String title, int index) => Bookmark(
      ref: '$title $index',
      book: TextBook(title: title),
      index: index,
    );

    test('list מחזיר את הסימניות של ה-bloc', () async {
      bookmarkBloc.emit(
        BookmarkState(bookmarks: [bookmark('בראשית', 3), bookmark('שמות', 1)]),
      );

      final data =
          await buildAdapter().execute('bookmarks', 'list', {'limit': 10})
              as List;

      expect(data, hasLength(2));
      expect((data.first as Map)['title'], 'בראשית');
      expect((data.first as Map)['index'], 3);
    });

    test('remove מוחק לפי זהות ו-index', () async {
      bookmarkBloc.emit(
        BookmarkState(
          bookmarks: [bookmark('בראשית', 3), bookmark('בראשית', 7)],
        ),
      );

      final removed = await buildAdapter().execute('bookmarks', 'remove', {
        'bookId': 'בראשית',
        'index': 7,
      });

      expect(removed, isTrue);
      expect(bookmarkBloc.state.bookmarks.single.index, 3);
    });

    test('remove ללא התאמה מחזיר false', () async {
      bookmarkBloc.emit(BookmarkState(bookmarks: [bookmark('בראשית', 3)]));
      expect(
        await buildAdapter().execute('bookmarks', 'remove', {
          'bookId': 'שמות',
        }),
        isFalse,
      );
      expect(bookmarkBloc.state.bookmarks, hasLength(1));
    });

    test('בלי מזהה ספר — invalid_params', () async {
      expect(
        () =>
            buildAdapter().execute('bookmarks', 'remove', <String, dynamic>{}),
        _codedError('error.invalid_params'),
      );
      expect(
        () => buildAdapter().execute('bookmarks', 'add', <String, dynamic>{}),
        _codedError('error.invalid_params'),
      );
    });

    test('remove — התאמה עם שמירה מוצלחת מחזיר true ומתמיד לדיסק', () async {
      bookmarkBloc.emit(BookmarkState(bookmarks: [bookmark('בראשית', 3)]));

      final removed = await buildAdapter().execute('bookmarks', 'remove', {
        'bookId': 'בראשית',
        'index': 3,
      });

      expect(removed, isTrue);
      expect(bookmarkRepository.stored, isEmpty);
    });

    test('ה-API אינו זמין כשה-bloc לא חובר', () async {
      final adapter = PluginBridgeAdapter(
        _plugin(const ['bookmarks.read']),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: tabsBloc,
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _MockCalendarCubit(),
          workspaceBloc: _MockWorkspaceBloc(),
          searchRepository: _MockSearchRepository(),
          personalNotesRepository: _MockPersonalNotesRepository(),
          bookOpenCoordinator: _MockBookOpenCoordinator(),
          themePayloadBuilder: () => <String, dynamic>{},
          showConfirmDialog: ({required title, required content}) async => true,
          showWarningDialog:
              ({required title, required content, required subtitle}) async =>
                  true,
        ),
        pluginRepository: PluginRegistryRepository(),
      );
      expect(
        () => adapter.execute('bookmarks', 'list', <String, dynamic>{}),
        _codedError('error.unavailable'),
      );
    });
  });

  group('tools.gematria', () {
    test('חישוב רגיל', () async {
      final data =
          await buildAdapter().execute('tools', 'gematria', {'text': 'אברהם'})
              as Map<String, dynamic>;
      expect(data['value'], 248);
      expect(data['method'], 'regular');
      expect(data['words'], 1);
    });

    test('withKolel מוסיף את מספר המילים', () async {
      final data =
          await buildAdapter().execute('tools', 'gematria', {
                'text': 'אברהם יצחק',
                'withKolel': true,
              })
              as Map<String, dynamic>;
      expect(data['words'], 2);
      expect(data['value'], 248 + 208 + 2);
    });

    test('method לא מוכר וטקסט ריק נדחים', () async {
      expect(
        () => buildAdapter().execute('tools', 'gematria', {
          'text': 'אברהם',
          'method': 'mystery',
        }),
        _codedError('error.invalid_params'),
      );
      expect(
        () => buildAdapter().execute('tools', 'gematria', {'text': '  '}),
        _codedError('error.invalid_params'),
      );
    });
  });

  group('tools.dictionary', () {
    test('מונח חסר או ארוך מדי נדחה', () async {
      expect(
        () =>
            buildAdapter().execute('tools', 'dictionary', <String, dynamic>{}),
        _codedError('error.invalid_params'),
      );
      expect(
        () => buildAdapter().execute('tools', 'dictionary', {
          'term': 'א' * 201,
        }),
        _codedError('error.invalid_params'),
      );
    });
  });
}
