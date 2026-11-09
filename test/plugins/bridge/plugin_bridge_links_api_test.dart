import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _StubTabsBloc extends Mock implements TabsBloc {
  TabsState currentState = TabsState.initial();

  @override
  TabsState get state => currentState;
}

class _StubPluginRegistryRepository extends PluginRegistryRepository {
  bool? permissionGrant = true;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      permissionGrant;
}

/// מחליף את שכבת ה-DB: מחזיר קישורים/מפרשים מוגדרים מראש ולוכד את הטווח
/// שהאדפטר העביר, כדי לאמת את המרת ה-0-based.
class _StubTextBookRepository extends Mock implements TextBookRepository {
  List<Link> links = const [];
  List<CommentatorInfo> commentators = const [];
  Set<String> rare = const {};
  List<CommentatorInfo> rangeCommentators = const [];
  int? capturedStartIndex;
  int? capturedEndIndex;
  List<String>? capturedTargetBookTitles;
  int? capturedRangeStart;
  int? capturedRangeEnd;
  TextBook? capturedBook;

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    capturedBook = book;
    capturedStartIndex = startIndex;
    capturedEndIndex = endIndex;
    capturedTargetBookTitles = targetBookTitles?.toList();
    return links;
  }

  @override
  Future<({List<CommentatorInfo> commentators, Set<String> rare})>
  getCommentatorsDetailed(TextBook book) async =>
      (commentators: commentators, rare: rare);

  @override
  Future<List<CommentatorInfo>> getCommentatorsInLineRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    capturedRangeStart = startLine;
    capturedRangeEnd = endLine;
    return rangeCommentators;
  }
}

InstalledPlugin _buildInstalledPlugin({List<String> permissions = const []}) {
  return InstalledPlugin(
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
}

/// adapter פיקטיבי לבדיקת מיפוי ההרשאות בלבד — execute לא אמור להיקרא
/// כשההרשאה חסרה.
class _FakeAdapter implements PluginBridgeAdapter {
  @override
  Future<T> withWindowDependencies<T>(
    Future<T> Function() action, {
    String? domain,
    String? rpcAction,
  }) => action();

  int executeCalls = 0;

  @override
  Future<dynamic> execute(
    String domain,
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    executeCalls++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// אחסון הגדרות בזיכרון — [FileSystemData] נבנה דרך `DataRepository.instance`
/// ודורש `Settings` מאותחל.

void main() {
  late _StubTextBookRepository repository;
  late _StubTabsBloc tabsBloc;
  late PluginBridgeAdapter adapter;
  late TextBook book;

  PluginBridgeAdapter buildAdapter({
    Future<({List<LinkTargetSummary> targets, int maxSourceLine})?> Function(
      String title,
      int categoryId,
    )?
    linkTargetsSummaryProvider,
    Future<String> Function(Link link)? linkContentLoader,
    Future<BookProtection> Function(Book book)? bookProtectionResolver,
  }) {
    return PluginBridgeAdapter(
      _buildInstalledPlugin(),
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
        textBookRepository: repository,
        linkTargetsSummaryProvider: linkTargetsSummaryProvider,
        linkContentLoader: linkContentLoader,
        bookProtectionResolver:
            bookProtectionResolver ?? (_) async => BookProtection.none,
      ),
      pluginRepository: _StubPluginRegistryRepository(),
    );
  }

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    repository = _StubTextBookRepository();
    tabsBloc = _StubTabsBloc();
    book = TextBook(title: 'בראשית', categoryId: 7, fileType: 'txt');
    final category = Category(
      title: 'תנ״ך',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [book],
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    DataRepository.instance.library = Future.value(library);
    adapter = buildAdapter();
  });

  group('library.getLinks', () {
    test(
      'ממיר 1-based פנימי ל-0-based ב-wire ומעביר את הטווח כמות שהוא',
      () async {
        repository.links = [
          Link(
            heRef: 'רש״י על בראשית א, א',
            index1: 6,
            path2: 'רש״י על בראשית',
            index2: 11,
            index2End: 13,
            connectionType: 'COMMENTARY',
            targetCategoryId: 42,
          ),
        ];

        final result =
            await adapter.execute('library', 'getLinks', {
                  'bookId': 'בראשית',
                  'startLine': 5,
                  'endLine': 9,
                })
                as Map<String, dynamic>;

        expect(repository.capturedStartIndex, 5);
        expect(repository.capturedEndIndex, 9);
        expect(result['truncated'], isFalse);
        final links = result['links'] as List;
        expect(links, hasLength(1));
        final link = links.single as Map<String, dynamic>;
        expect(link['sourceLine'], 5);
        expect(link['targetLine'], 10);
        expect(link['targetLineEnd'], 12);
        expect(link['targetTitle'], 'רש״י על בראשית');
        expect(link['isCommentary'], isTrue);
        expect(link['targetCategoryId'], 42);
      },
    );

    test('קישור הפניה מסומן isCommentary=false', () async {
      repository.links = [
        Link(
          heRef: 'שולחן ערוך',
          index1: 1,
          path2: 'שולחן ערוך',
          index2: 2,
          connectionType: 'REFERENCE',
        ),
      ];

      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
              })
              as Map<String, dynamic>;

      final link = (result['links'] as List).single as Map<String, dynamic>;
      expect(link['isCommentary'], isFalse);
    });

    test('חלון של יותר מ-200 שורות נדחה כ-error.invalid_params', () async {
      expect(
        () => adapter.execute('library', 'getLinks', {
          'bookId': 'בראשית',
          'startLine': 0,
          'endLine': 200,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('חלון של 200 שורות בדיוק מתקבל', () async {
      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 199,
              })
              as Map<String, dynamic>;

      expect(result['links'], isEmpty);
    });

    test('endLine קטן מ-startLine נדחה', () async {
      expect(
        () => adapter.execute('library', 'getLinks', {
          'bookId': 'בראשית',
          'startLine': 10,
          'endLine': 9,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('startLine שלילי נדחה כ-error.invalid_params', () async {
      expect(
        () => adapter.execute('library', 'getLinks', {
          'bookId': 'בראשית',
          'startLine': -1,
          'endLine': 5,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('מעל 2,000 רשומות — התשובה נחתכת ומסומנת truncated', () async {
      repository.links = [
        for (var i = 0; i < 2001; i++)
          Link(
            heRef: 'רש״י $i',
            index1: 1,
            path2: 'רש״י על בראשית',
            index2: i + 1,
            connectionType: 'COMMENTARY',
          ),
      ];

      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
              })
              as Map<String, dynamic>;

      expect(result['truncated'], isTrue);
      expect(result['links'] as List, hasLength(2000));
    });

    test('connectionTypes מסנן לפי סוג מנורמל', () async {
      repository.links = [
        Link(
          heRef: 'a',
          index1: 1,
          path2: 'תרגום אונקלוס',
          index2: 1,
          connectionType: 'TARGUM',
        ),
        Link(
          heRef: 'b',
          index1: 1,
          path2: 'רש״י על בראשית',
          index2: 1,
          connectionType: 'COMMENTARY',
        ),
      ];

      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
                'connectionTypes': ['targum'],
              })
              as Map<String, dynamic>;

      final links = result['links'] as List;
      expect(links, hasLength(1));
      expect(
        (links.single as Map<String, dynamic>)['targetTitle'],
        'תרגום אונקלוס',
      );
    });

    test('targetTitlePrefixes מסנן לפי תחילית הכותרת', () async {
      repository.links = [
        Link(
          heRef: 'a',
          index1: 1,
          path2: 'הערות על בראשית',
          index2: 1,
          connectionType: 'COMMENTARY',
        ),
        Link(
          heRef: 'b',
          index1: 1,
          path2: 'רש״י על בראשית',
          index2: 1,
          connectionType: 'COMMENTARY',
        ),
      ];

      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
                'targetTitlePrefixes': ['הערות '],
              })
              as Map<String, dynamic>;

      final links = result['links'] as List;
      expect(links, hasLength(1));
      expect(
        (links.single as Map<String, dynamic>)['targetTitle'],
        'הערות על בראשית',
      );
    });

    test('targetTitles ו-targetTitlePrefixes יחד — איחוד', () async {
      repository.links = [
        for (final title in const [
          'הערות על בראשית',
          'רש״י על בראשית',
          'תרגום אונקלוס',
        ])
          Link(
            heRef: title,
            index1: 1,
            path2: title,
            index2: 1,
            connectionType: 'COMMENTARY',
          ),
      ];

      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
                'targetTitles': ['רש״י על בראשית'],
                'targetTitlePrefixes': ['הערות '],
              })
              as Map<String, dynamic>;

      final titles = [
        for (final link in result['links'] as List)
          (link as Map<String, dynamic>)['targetTitle'],
      ];
      expect(titles, ['הערות על בראשית', 'רש״י על בראשית']);
    });

    test('attached book with a shared title is chosen by source', () async {
      final attached = TextBook(
        id: 5,
        title: book.title,
        categoryId: 7,
        source: BookSource.attached('lib-a'),
      );
      final library = await DataRepository.instance.library;
      library.subCategories.single.books.add(attached);
      repository.links = [
        Link(
          heRef: 'ref',
          index1: 1,
          path2: 'target',
          index2: 1,
          connectionType: 'COMMENTARY',
          targetSource: BookSource.attached('lib-a'),
        ),
      ];

      await adapter.execute('library', 'getLinks', {
        'bookId': book.title,
        'startLine': 0,
        'endLine': 1,
      });
      expect(repository.capturedBook?.source, BookSource.official);

      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': book.title,
                'source': 'attached',
                'startLine': 0,
                'endLine': 1,
              })
              as Map<String, dynamic>;
      expect(repository.capturedBook?.source, BookSource.attached('lib-a'));
      final link = (result['links'] as List).single as Map<String, dynamic>;
      expect(link['targetSource'], 'd:lib-a');
      expect(link['targetIsUserBook'], isFalse);

      final byUid =
          await adapter.execute('library', 'getLinks', {
                'bookUid': 'db:lib-a:5',
                'startLine': 0,
                'endLine': 1,
              })
              as Map<String, dynamic>;
      expect(byUid['links'], hasLength(1));
      expect(repository.capturedBook, same(attached));
    });
  });

  group('library.getLinks includeAnchors', () {
    tearDown(() {
      BookNotesRepository.instance
        ..debugLoader = null
        ..clear();
    });

    Link anchored(int start, int end, {String path = 'רש״י על בראשית'}) => Link(
      heRef: '$path א, א',
      index1: 1,
      path2: path,
      index2: 1,
      connectionType: 'LINKER',
      anchorStart: start,
      anchorEnd: end,
    );

    test('העוגן מוחזר בטקסט השמור; עוגן שכולו בגוף הערה מושמט', () async {
      // השורה המלאה: 3 תווים, גוף של 3 תווים ב-[3,6), ואז השאר.
      BookNotesRepository.instance
        ..clear()
        ..debugLoader = (title, {categoryId, required source}) async =>
            (BookNotesBuilder()..add(0, 0, null, 'אבג', charPos: 3)).build();
      repository.links = [anchored(5, 8), anchored(3, 6, path: 'תוספות')];

      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
                'includeAnchors': true,
              })
              as Map<String, dynamic>;

      final links = (result['links'] as List).cast<Map<String, dynamic>>();
      expect(links.first['anchor'], {'start': 3, 'end': 5, 'label': null});
      expect(links.last.containsKey('anchor'), isFalse);
    });

    test('כשל בטעינת ההערות מכשיל את הקריאה', () async {
      BookNotesRepository.instance
        ..clear()
        ..debugLoader = (title, {categoryId, required source}) async =>
            throw StateError('גוף שאינו מתפענח');
      repository.links = [anchored(5, 8)];

      await expectLater(
        adapter.execute('library', 'getLinks', {
          'bookId': 'בראשית',
          'startLine': 0,
          'endLine': 0,
          'includeAnchors': true,
        }),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('library.getLineNotes', () {
    tearDown(() {
      BookNotesRepository.instance
        ..debugLoader = null
        ..clear();
    });

    test('מחזיר את הערות הטווח לפי שורה, 0-based, בסדר הקריאה', () async {
      BookNotesRepository.instance
        ..clear()
        ..debugLoader = (title, {categoryId, required source}) async =>
            (BookNotesBuilder()
                  ..add(0, 0, '*', 'הערה ראשונה', charPos: 3)
                  ..add(2, 0, null, 'בלי סמן')
                  ..add(2, 1, '*', 'שנייה בשורה', charPos: 9)
                  ..add(5, 0, '*', 'מחוץ לטווח', charPos: 1))
                .build();

      final result =
          await adapter.execute('library', 'getLineNotes', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 3,
              })
              as Map<String, dynamic>;

      expect(result['notes'], [
        {
          'line': 0,
          'noteIndex': 0,
          'marker': '*',
          'charPos': 3,
          'body': 'הערה ראשונה',
        },
        {
          'line': 2,
          'noteIndex': 0,
          'marker': null,
          'charPos': -1,
          'body': 'בלי סמן',
        },
        {
          'line': 2,
          'noteIndex': 1,
          'marker': '*',
          'charPos': 9,
          'body': 'שנייה בשורה',
        },
      ]);
    });

    test('ספר בלי טבלת הערות — רשימה ריקה', () async {
      BookNotesRepository.instance
        ..clear()
        ..debugLoader = (title, {categoryId, required source}) async =>
            BookNotes.empty;

      final result =
          await adapter.execute('library', 'getLineNotes', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
              })
              as Map<String, dynamic>;
      expect(result['notes'], isEmpty);
    });

    test('חלון רחב מ-200 שורות או הפוך — invalid_params', () async {
      await expectLater(
        adapter.execute('library', 'getLineNotes', {
          'bookId': 'בראשית',
          'startLine': 0,
          'endLine': 200,
        }),
        throwsA(
          predicate((e) => e.toString().contains('error.invalid_params')),
        ),
      );
      await expectLater(
        adapter.execute('library', 'getLineNotes', {
          'bookId': 'בראשית',
          'startLine': 3,
          'endLine': 2,
        }),
        throwsA(
          predicate((e) => e.toString().contains('error.invalid_params')),
        ),
      );
    });

    test('ספר שלא נמצא — not_found', () async {
      await expectLater(
        adapter.execute('library', 'getLineNotes', {
          'bookId': 'אין ספר כזה',
          'startLine': 0,
          'endLine': 0,
        }),
        throwsA(predicate((e) => e.toString().contains('error.not_found'))),
      );
    });
  });

  group('library.getRawLinks', () {
    test('מחזיר את הקישור בחמשת מפתחות links.json, 1-based', () async {
      repository.links = [
        Link(
          heRef: 'רש״י על בראשית א, א',
          index1: 6,
          path2: 'רש״י על בראשית',
          index2: 11,
          connectionType: 'COMMENTARY',
          // שדות שקיימים רק במסד — אינם חלק מהפורמט.
          targetCategoryId: 42,
          targetFileType: 'txt',
          targetSource: BookSource.user,
          index2End: 13,
          anchorStart: 4,
        ),
      ];

      final result =
          await adapter.execute('library', 'getRawLinks', {
                'bookId': 'בראשית',
                'startLine': 5,
                'endLine': 9,
              })
              as Map<String, dynamic>;

      expect(repository.capturedStartIndex, 5);
      expect(repository.capturedEndIndex, 9);
      expect(result['truncated'], isFalse);
      expect((result['links'] as List).single, {
        'heRef_2': 'רש״י על בראשית א, א',
        'line_index_1': 6,
        'path_2': 'רש״י על בראשית',
        'line_index_2': 11,
        'Conection Type': 'COMMENTARY',
      });
    });

    test('בלי טווח — נסרקות 1000 השורות הראשונות', () async {
      final result =
          await adapter.execute('library', 'getRawLinks', {'bookId': 'בראשית'})
              as Map<String, dynamic>;

      expect(repository.capturedStartIndex, 0);
      expect(repository.capturedEndIndex, 999);
      expect(result['startLine'], 0);
      expect(result['endLine'], 999);
    });

    test('חלון של יותר מ-1000 שורות נדחה כ-error.invalid_params', () async {
      await expectLater(
        adapter.execute('library', 'getRawLinks', {
          'bookId': 'בראשית',
          'startLine': 500,
          'endLine': 99999,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('חלון של 1000 שורות בדיוק מתקבל', () async {
      final result =
          await adapter.execute('library', 'getRawLinks', {
                'bookId': 'בראשית',
                'startLine': 500,
                'endLine': 1499,
              })
              as Map<String, dynamic>;

      expect(repository.capturedEndIndex, 1499);
      expect(result['endLine'], 1499);
    });

    for (final only in const ['startLine', 'endLine']) {
      test('$only לבדו נדחה — הטווח חובה יחד', () async {
        await expectLater(
          adapter.execute('library', 'getRawLinks', {
            'bookId': 'בראשית',
            only: 10,
          }),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('error.invalid_params'),
            ),
          ),
        );
      });
    }

    test('טווח שנכנס בחלון נשמר כמות שהוא', () async {
      final result =
          await adapter.execute('library', 'getRawLinks', {
                'bookId': 'בראשית',
                'startLine': 10,
                'endLine': 20,
              })
              as Map<String, dynamic>;

      expect(repository.capturedEndIndex, 20);
      expect(result['endLine'], 20);
    });

    test('endLine קטן מ-startLine נדחה', () async {
      await expectLater(
        adapter.execute('library', 'getRawLinks', {
          'bookId': 'בראשית',
          'startLine': 10,
          'endLine': 9,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('startLine שלילי נדחה כ-error.invalid_params', () async {
      await expectLater(
        adapter.execute('library', 'getRawLinks', {
          'bookId': 'בראשית',
          'startLine': -1,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('מעל 10,000 רשומות — התשובה נחתכת ומסומנת truncated', () async {
      repository.links = [
        for (var i = 0; i < 10001; i++)
          Link(
            heRef: 'רש״י $i',
            index1: 1,
            path2: 'רש״י על בראשית',
            index2: i + 1,
            connectionType: 'COMMENTARY',
          ),
      ];

      final result =
          await adapter.execute('library', 'getRawLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
              })
              as Map<String, dynamic>;

      expect(result['truncated'], isTrue);
      expect(result['links'] as List, hasLength(10000));
    });

    test('targetTitles עובר ל-SQL וגם מסנן בזיכרון', () async {
      repository.links = [
        Link(
          heRef: 'a',
          index1: 1,
          path2: 'רש״י על בראשית',
          index2: 1,
          connectionType: 'COMMENTARY',
        ),
        // ה-SQL מחזיר גם קישורים שאינם מפרשים אף כשיש פילטר; המסנן בזיכרון
        // הוא זה שהופך את targetTitles לרשימת-היתר אמיתית בגבול ה-API.
        Link(
          heRef: 'b',
          index1: 1,
          path2: 'שולחן ערוך',
          index2: 1,
          connectionType: 'REFERENCE',
        ),
      ];

      final result =
          await adapter.execute('library', 'getRawLinks', {
                'bookId': 'בראשית',
                'targetTitles': ['רש״י על בראשית'],
              })
              as Map<String, dynamic>;

      expect(repository.capturedTargetBookTitles, ['רש״י על בראשית']);
      final links = result['links'] as List;
      expect(links, hasLength(1));
      expect(
        (links.single as Map<String, dynamic>)['path_2'],
        'רש״י על בראשית',
      );
    });

    test(
      'עם targetTitlePrefixes אין צמצום ב-SQL — הסינון כולו בזיכרון',
      () async {
        repository.links = [
          Link(
            heRef: 'a',
            index1: 1,
            path2: 'הערות על בראשית',
            index2: 1,
            connectionType: 'COMMENTARY',
          ),
          Link(
            heRef: 'b',
            index1: 1,
            path2: 'שולחן ערוך',
            index2: 1,
            connectionType: 'REFERENCE',
          ),
        ];

        final result =
            await adapter.execute('library', 'getRawLinks', {
                  'bookId': 'בראשית',
                  'targetTitles': ['רש״י על בראשית'],
                  'targetTitlePrefixes': ['הערות '],
                })
                as Map<String, dynamic>;

        // צמצום לפי targetTitles לבדו היה מפיל את התאמות התחילית.
        expect(repository.capturedTargetBookTitles, isNull);
        final links = result['links'] as List;
        expect(links, hasLength(1));
        expect(
          (links.single as Map<String, dynamic>)['path_2'],
          'הערות על בראשית',
        );
      },
    );

    test('connectionTypes מסנן לפי סוג מנורמל', () async {
      repository.links = [
        Link(
          heRef: 'a',
          index1: 1,
          path2: 'תרגום אונקלוס',
          index2: 1,
          connectionType: 'TARGUM',
        ),
        Link(
          heRef: 'b',
          index1: 1,
          path2: 'רש״י על בראשית',
          index2: 1,
          connectionType: 'COMMENTARY',
        ),
      ];

      final result =
          await adapter.execute('library', 'getRawLinks', {
                'bookId': 'בראשית',
                'connectionTypes': ['targum'],
              })
              as Map<String, dynamic>;

      final links = result['links'] as List;
      expect(links, hasLength(1));
      expect((links.single as Map<String, dynamic>)['path_2'], 'תרגום אונקלוס');
    });

    test('ספר לא מוכר → error.not_found', () async {
      await expectLater(
        adapter.execute('library', 'getRawLinks', {'bookId': 'לא קיים'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.not_found'),
          ),
        ),
      );
    });
  });

  // הסינון והחיתוך משותפים ל-getLinks ול-getRawLinks דרך _filterLinkRecords.
  // הבדיקות כאן מקבעות את השורות שריפקטור-חילוץ מזיז, בשני המסלולים יחד.
  group('הסינון המשותף של getLinks/getRawLinks', () {
    /// קורא לשתי המתודות על אותו קלט ומחזיר את שתי רשימות התוצאה.
    Future<({List<dynamic> links, List<dynamic> rawLinks})> callBoth(
      Map<String, dynamic> args,
    ) async {
      final links =
          await adapter.execute('library', 'getLinks', {
                'startLine': 0,
                'endLine': 0,
                ...args,
              })
              as Map<String, dynamic>;
      final rawLinks =
          await adapter.execute('library', 'getRawLinks', {
                'startLine': 0,
                'endLine': 0,
                ...args,
              })
              as Map<String, dynamic>;
      return (
        links: links['links'] as List,
        rawLinks: rawLinks['links'] as List,
      );
    }

    test('path2 עם תיקייה וסיומת מצטמצם לכותרת לצורך הסינון', () async {
      repository.links = [
        Link(
          heRef: 'a',
          index1: 1,
          path2: 'אוצריא/תנך/רש״י על בראשית.txt',
          index2: 1,
          connectionType: 'COMMENTARY',
        ),
      ];

      final result = await callBoth({
        'bookId': 'בראשית',
        'targetTitles': ['רש״י על בראשית'],
      });

      // getLinks פולט את הכותרת המצומצמת; getRawLinks את path_2 כמות שהוא.
      expect(result.links, hasLength(1));
      expect(
        (result.links.single as Map<String, dynamic>)['targetTitle'],
        'רש״י על בראשית',
      );
      expect(result.rawLinks, hasLength(1));
      expect(
        (result.rawLinks.single as Map<String, dynamic>)['path_2'],
        'אוצריא/תנך/רש״י על בראשית.txt',
      );
    });

    test('connectionTypes תופס גם סוג שצורתו הקנונית שונה', () async {
      // EXPLICATION מנורמל לעצמו אך צורתו הקנונית היא ELUCIDATION; בלי ענף
      // canonicalType סינון לפי 'elucidation' היה מפיל אותו בשקט.
      repository.links = [
        Link(
          heRef: 'a',
          index1: 1,
          path2: 'ביאור',
          index2: 1,
          connectionType: LinkTypes.explication,
        ),
        Link(
          heRef: 'b',
          index1: 1,
          path2: 'רש״י על בראשית',
          index2: 1,
          connectionType: LinkTypes.commentary,
        ),
      ];

      final result = await callBoth({
        'bookId': 'בראשית',
        'connectionTypes': [LinkTypes.elucidation],
      });

      expect(result.links, hasLength(1));
      expect(
        (result.links.single as Map<String, dynamic>)['targetTitle'],
        'ביאור',
      );
      expect(result.rawLinks, hasLength(1));
      expect(
        (result.rawLinks.single as Map<String, dynamic>)['path_2'],
        'ביאור',
      );
    });

    test('קישור שסונן אינו צורך מהמכסה', () async {
      // 2,000 קישורים שנפסלים + 1 שעובר: אם בדיקת המכסה תעבור מעל הסינון,
      // התשובה תחזור ריקה ומסומנת truncated.
      repository.links = [
        for (var i = 0; i < 2000; i++)
          Link(
            heRef: 'x$i',
            index1: 1,
            path2: 'שולחן ערוך',
            index2: i + 1,
            connectionType: 'REFERENCE',
          ),
        Link(
          heRef: 'y',
          index1: 1,
          path2: 'רש״י על בראשית',
          index2: 1,
          connectionType: 'COMMENTARY',
        ),
      ];

      final result = await callBoth({
        'bookId': 'בראשית',
        'targetTitles': ['רש״י על בראשית'],
      });

      expect(result.links, hasLength(1));
      expect(result.rawLinks, hasLength(1));
    });

    // בדיקת המכסה יושבת *אחרי* הסינון: קישור שנפסל אינו יכול להצית truncated.
    // בדיקה על getLinks בלבד (מכסה 2,000 ולא 10,000) — הקוד משותף.
    test('truncated נשאר false כשכל מה שאחרי המכסה מסונן ממילא', () async {
      repository.links = [
        for (var i = 0; i < 2000; i++)
          Link(
            heRef: 'y$i',
            index1: 1,
            path2: 'רש״י על בראשית',
            index2: i + 1,
            connectionType: 'COMMENTARY',
          ),
        Link(
          heRef: 'z',
          index1: 1,
          path2: 'שולחן ערוך',
          index2: 1,
          connectionType: 'REFERENCE',
        ),
      ];

      final result =
          await adapter.execute('library', 'getLinks', {
                'bookId': 'בראשית',
                'startLine': 0,
                'endLine': 0,
                'targetTitles': ['רש״י על בראשית'],
              })
              as Map<String, dynamic>;

      expect(result['links'] as List, hasLength(2000));
      expect(result['truncated'], isFalse);
    });

    test('שתי המתודות בוחרות את אותה קבוצת קישורים ובאותו סדר', () async {
      repository.links = [
        Link(
          heRef: 'a',
          index1: 1,
          path2: 'תרגום אונקלוס',
          index2: 3,
          connectionType: LinkTypes.targum,
        ),
        Link(
          heRef: 'b',
          index1: 1,
          path2: 'שולחן ערוך',
          index2: 4,
          connectionType: LinkTypes.reference,
        ),
        Link(
          heRef: 'c',
          index1: 1,
          path2: 'רש״י על בראשית',
          index2: 5,
          connectionType: LinkTypes.commentary,
        ),
      ];

      final result = await callBoth({
        'bookId': 'בראשית',
        'targetTitles': ['תרגום אונקלוס', 'רש״י על בראשית'],
      });

      expect(
        [
          for (final link in result.links)
            (link as Map<String, dynamic>)['targetHeRef'],
        ],
        ['a', 'c'],
      );
      expect(
        [
          for (final link in result.rawLinks)
            (link as Map<String, dynamic>)['heRef_2'],
        ],
        ['a', 'c'],
      );
    });
  });

  group('library.getCommentators', () {
    test('מחזיר שם, מחבר, מונה ודגל נדירות', () async {
      repository.commentators = const [
        CommentatorInfo(title: 'רש״י על בראשית', author: 'רש״י', linkCount: 50),
        CommentatorInfo(title: 'ספר נדיר', linkCount: 2),
      ];
      repository.rare = const {'ספר נדיר'};

      final result =
          await adapter.execute('library', 'getCommentators', {
                'bookId': 'בראשית',
              })
              as Map<String, dynamic>;

      final commentators = result['commentators'] as List;
      expect(commentators, hasLength(2));
      expect((commentators.first as Map)['author'], 'רש״י');
      expect((commentators.first as Map)['linkCount'], 50);
      expect((commentators.first as Map)['isRare'], isFalse);
      expect((commentators.last as Map)['isRare'], isTrue);
      expect((commentators.last as Map).containsKey('author'), isFalse);
    });

    test('טווח שורות עובר ל-selectCommentatorsByLineRange כ-0-based', () async {
      repository.rangeCommentators = const [
        CommentatorInfo(title: 'רש״י על בראשית', linkCount: 3),
      ];

      final result =
          await adapter.execute('library', 'getCommentators', {
                'bookId': 'בראשית',
                'startLine': 4,
                'endLine': 12,
              })
              as Map<String, dynamic>;

      expect(repository.capturedRangeStart, 4);
      expect(repository.capturedRangeEnd, 12);
      expect((result['commentators'] as List), hasLength(1));
    });

    test('titlePrefixes מסנן לפי תחילית שם המפרש', () async {
      repository.commentators = const [
        CommentatorInfo(title: 'הערות על בראשית', linkCount: 10),
        CommentatorInfo(title: 'הגהות הב״ח על בראשית', linkCount: 4),
        CommentatorInfo(title: 'רש״י על בראשית', linkCount: 50),
      ];

      final result =
          await adapter.execute('library', 'getCommentators', {
                'bookId': 'בראשית',
                'titlePrefixes': ['הערות ', 'הגהות '],
              })
              as Map<String, dynamic>;

      final titles = [
        for (final c in result['commentators'] as List) (c as Map)['title'],
      ];
      expect(titles, ['הערות על בראשית', 'הגהות הב״ח על בראשית']);
    });

    test('startLine בלי endLine נדחה', () async {
      expect(
        () => adapter.execute('library', 'getCommentators', {
          'bookId': 'בראשית',
          'startLine': 4,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('ספר לא מוכר → error.not_found', () async {
      expect(
        () => adapter.execute('library', 'getCommentators', {
          'bookId': 'ספר שאינו קיים',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.not_found'),
          ),
        ),
      );
    });
  });

  group('library.getLinkTargetsSummary', () {
    test('עוטף את הסיכום וממיר את maxSourceLine ל-0-based', () async {
      final localAdapter = buildAdapter(
        linkTargetsSummaryProvider: (title, categoryId) async => (
          targets: const [
            LinkTargetSummary(
              targetTitle: 'רש״י על בראשית',
              connectionType: 'COMMENTARY',
              linkCount: 120,
            ),
          ],
          maxSourceLine: 900,
        ),
      );

      final result =
          await localAdapter.execute('library', 'getLinkTargetsSummary', {
                'bookId': 'בראשית',
              })
              as Map<String, dynamic>;

      expect(result['maxSourceLine'], 899);
      final targets = result['targets'] as List;
      expect((targets.single as Map)['linkCount'], 120);
    });

    test(
      'targetTitlePrefixes מסנן יעדים; maxSourceLine נשאר של הספר',
      () async {
        final localAdapter = buildAdapter(
          linkTargetsSummaryProvider: (title, categoryId) async => (
            targets: const [
              LinkTargetSummary(
                targetTitle: 'הערות על בראשית',
                connectionType: 'COMMENTARY',
                linkCount: 12,
              ),
              LinkTargetSummary(
                targetTitle: 'רש״י על בראשית',
                connectionType: 'COMMENTARY',
                linkCount: 120,
              ),
            ],
            maxSourceLine: 900,
          ),
        );

        final result =
            await localAdapter.execute('library', 'getLinkTargetsSummary', {
                  'bookId': 'בראשית',
                  'targetTitlePrefixes': ['הערות '],
                })
                as Map<String, dynamic>;

        final targets = result['targets'] as List;
        expect((targets.single as Map)['targetTitle'], 'הערות על בראשית');
        expect(result['maxSourceLine'], 899);
      },
    );
  });

  group('library.getLinkContent', () {
    test('טוען תוכן לכל פריט לפי הסדר וממיר ל-1-based', () async {
      final requested = <int>[];
      final localAdapter = buildAdapter(
        linkContentLoader: (link) async {
          requested.add(link.index2);
          return 'תוכן ${link.index2}';
        },
      );

      final result =
          await localAdapter.execute('library', 'getLinkContent', {
                'links': [
                  {'targetTitle': 'רש״י על בראשית', 'targetLine': 0},
                  {'targetTitle': 'רש״י על בראשית', 'targetLine': 4},
                ],
              })
              as Map<String, dynamic>;

      expect(requested, [1, 5]);
      final items = result['items'] as List;
      expect((items.first as Map)['content'], 'תוכן 1');
      expect((items.last as Map)['content'], 'תוכן 5');
    });

    test('מפרש עם הגבלת מו"ל מוחזר כ-forbidden בלי לטעון תוכן', () async {
      final requested = <String>[];
      final localAdapter = buildAdapter(
        linkContentLoader: (link) async {
          requested.add(link.path2);
          return 'תוכן';
        },
        bookProtectionResolver: (book) async => book.title == 'מפרש מוגן'
            ? const BookProtection(level: 1)
            : BookProtection.none,
      );

      final result =
          await localAdapter.execute('library', 'getLinkContent', {
                'links': [
                  {'targetTitle': 'מפרש מוגן', 'targetLine': 0},
                  {'targetTitle': 'רש״י על בראשית', 'targetLine': 0},
                ],
              })
              as Map<String, dynamic>;

      final items = result['items'] as List;
      expect(items.first, {'error': 'forbidden'});
      expect((items.last as Map)['content'], 'תוכן');
      expect(requested, ['רש״י על בראשית']);
    });

    test('כשל בטעינה מוחזר כ-not_found באותו מקום ברשימה', () async {
      final localAdapter = buildAdapter(
        linkContentLoader: (link) async => throw StateError('missing'),
      );

      final result =
          await localAdapter.execute('library', 'getLinkContent', {
                'links': [
                  {'targetTitle': 'רש״י על בראשית', 'targetLine': 0},
                ],
              })
              as Map<String, dynamic>;

      expect((result['items'] as List).single, {'error': 'not_found'});
    });

    test('יותר מ-25 פריטים נדחה כ-error.invalid_params', () async {
      expect(
        () => adapter.execute('library', 'getLinkContent', {
          'links': [
            for (var i = 0; i < 26; i++)
              {'targetTitle': 'רש״י על בראשית', 'targetLine': i},
          ],
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });

    test('25 פריטים בדיוק מתקבלים', () async {
      final localAdapter = buildAdapter(
        linkContentLoader: (link) async => 'ok',
      );

      final result =
          await localAdapter.execute('library', 'getLinkContent', {
                'links': [
                  for (var i = 0; i < 25; i++)
                    {'targetTitle': 'רש״י על בראשית', 'targetLine': i},
                ],
              })
              as Map<String, dynamic>;

      expect((result['items'] as List), hasLength(25));
    });

    test('רשימה ריקה נדחית', () async {
      expect(
        () => adapter.execute('library', 'getLinkContent', {'links': []}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
    });
  });

  group('reader.getActiveCommentators', () {
    test('מחזיר null כשאין טאב קריאה', () async {
      final result = await adapter.execute(
        'reader',
        'getActiveCommentators',
        const {},
      );
      expect(result, isNull);
    });
  });

  group('מיפוי ההרשאות של ה-API החדש', () {
    for (final entry in const {
      'library.getCommentators': pluginLinksReadPermission,
      'library.getLinks': pluginLinksReadPermission,
      'library.getRawLinks': pluginLinksReadPermission,
      'library.getLinkTargetsSummary': pluginLinksReadPermission,
      'library.getLinkContent': 'library.content.read',
      'library.getLineNotes': 'library.content.read',
      'reader.getActiveCommentators': 'reader.open',
    }.entries) {
      test('${entry.key} דורשת ${entry.value}', () async {
        final fakeAdapter = _FakeAdapter();
        final denied = PluginBridgeHandler(
          _buildInstalledPlugin(),
          adapter: fakeAdapter,
          registry: _StubPluginRegistryRepository(),
        );

        final response =
            await denied.handleRpcForTesting([
                  {'method': entry.key, 'payload': const {}},
                ])
                as Map<String, dynamic>;

        expect(response['success'], isFalse);
        expect(response['error']['code'], 'permission_denied');
        expect(response['error']['message'], contains(entry.value));
        expect(fakeAdapter.executeCalls, 0);

        // ההצהרה הנכונה במניפסט פותחת את הקריאה.
        final allowed = PluginBridgeHandler(
          _buildInstalledPlugin(permissions: [entry.value]),
          adapter: fakeAdapter,
          registry: _StubPluginRegistryRepository(),
        );
        final ok =
            await allowed.handleRpcForTesting([
                  {'method': entry.key, 'payload': const {}},
                ])
                as Map<String, dynamic>;
        expect(ok['success'], isTrue);
        expect(fakeAdapter.executeCalls, 1);
      });
    }

    test('apiCallToPermissionHint מתעד את השיטות החדשות', () {
      expect(
        apiCallToPermissionHint['library.getLinks'],
        pluginLinksReadPermission,
      );
      expect(
        apiCallToPermissionHint['library.getRawLinks'],
        pluginLinksReadPermission,
      );
      expect(
        apiCallToPermissionHint['library.getLinkContent'],
        'library.content.read',
      );
      expect(
        apiCallToPermissionHint['library.getLineNotes'],
        'library.content.read',
      );
      expect(pluginValidPermissions, contains(pluginLinksReadPermission));
    });
  });
}
