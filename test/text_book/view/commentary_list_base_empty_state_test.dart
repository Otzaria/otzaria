// טסט רגרסיה: כשאין תוכן מפרש זמין (בין אם אין קישורים בכלל, ובין אם יש
// קישורים אבל אף אחד מהם לא תואם למפרשים הנבחרים) יש להציג מסך ריק ידידותי
// ולא שגיאה קשיחה. פורום: https://otzaria.org/forum/topic/173, קומיט cf73a4d93.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
  });

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
  });

  group('CommentaryListBase - מסך ריק ידידותי כשאין תוכן מפרש', () {
    testWidgets('אין קישורי מפרשים בכלל לקטע - מוצג טקסט ידידותי ולא שגיאה', (
      tester,
    ) async {
      final bloc = _TestTextBookBloc(_stateWithoutLinks());
      addTearDown(() async => bloc.close());
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async => settingsBloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      expect(find.text('לא נמצאו מפרשים לקטע הנבחר'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    });

    testWidgets(
      'יש קישורי מפרשים אך אף אחד לא תואם למפרשים הנבחרים - מוצג טקסט ידידותי ולא שגיאה',
      (tester) async {
        final bloc = _TestTextBookBloc(_stateWithIrrelevantLinks());
        addTearDown(() async => bloc.close());
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(() async => settingsBloc.close());

        await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

        expect(find.text('לא נמצאו מפרשים מהנבחרים לקטע זה'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
      },
    );

    testWidgets(
      'יש קישורי מפרשים אך לא נבחרו מפרשים כלל - נפתחת בחירת מפרשים ולא שגיאה',
      (tester) async {
        final bloc = _TestTextBookBloc(_stateWithLinksNoActiveCommentators());
        addTearDown(() async => bloc.close());
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        addTearDown(() async => settingsBloc.close());

        await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

        expect(find.text('בחירת מפרשים'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
      },
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: const Scaffold(
          body: CommentaryListBase(
            openBookCallback: _noopOpenBook,
            fontSize: 18,
            showSearch: true,
            shrinkWrap: false,
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void _noopOpenBook(_) {}

TextBookLoaded _stateWithoutLinks() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

TextBookLoaded _stateWithIrrelevantLinks() {
  // הקישור קיים עבור מפרש אחר ("מפרש אחר"), שאינו נמצא ברשימת activeCommentators.
  final link = Link(
    heRef: 'בראשית א',
    index1: 1,
    path2: 'מפרש אחר.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה', 'מפרש אחר'],
    links: [link],
    visibleLinks: const [],
    linksByLine: {
      1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

TextBookLoaded _stateWithLinksNoActiveCommentators() {
  final link = Link(
    heRef: 'בראשית א',
    index1: 1,
    path2: 'מפרש בדיקה.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
    links: [link],
    visibleLinks: const [],
    linksByLine: {
      1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryProvider implements LibraryProvider {
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    return {'מפרש בדיקה|1|txt'};
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return true;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }
}
