import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

// רגרסיה לפי https://otzaria.org/forum/post/11182 (תוקן ב-c48fbe286):
// כשקבוצת מפרש חדשה מופיעה בזמן שהמצב הגלובלי מכווץ, היא הייתה מאותחלת
// מורחבת תמיד ("true" קשיח) במקום לפי _allExpanded, כך שכיווץ-הכל לא השפיע
// על מפרשים שנטענו רק אחרי הלחיצה (למשל אחרי מעבר שורה).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late _TestTextBookBloc textBookBloc;
  late _TestSettingsBloc settingsBloc;

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

    textBookBloc = _TestTextBookBloc(_loadedStateA());
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
  });

  tearDown(() async {
    await textBookBloc.close();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
  });

  testWidgets('קבוצת מפרש חדשה שנטענת אחרי כיווץ-הכל נשארת מכווצת', (
    tester,
  ) async {
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

    // הקבוצה הראשונה מוצגת פתוחה כברירת מחדל (_allExpanded=true).
    expect(find.textContaining('זהו פירוש לבדיקה'), findsOneWidget);
    expect(find.byTooltip('כווץ את כל המפרשים'), findsOneWidget);

    // לחיצה על "כווץ את כל המפרשים".
    await tester.tap(find.byTooltip('כווץ את כל המפרשים'));
    await tester.pumpAndSettle();

    expect(find.textContaining('זהו פירוש לבדיקה'), findsNothing);
    expect(find.byTooltip('הרחב את כל המפרשים'), findsOneWidget);

    // מעבר לשורה אחרת, שמציגה קבוצת מפרש חדשה (כותרת ספר שונה) שלא הייתה
    // קיימת קודם ב-_expansionStates.
    textBookBloc.emitStateForTest(_loadedStateB());
    await tester.pumpAndSettle();

    // הקבוצה החדשה חייבת להיטען מכווצת - זה בדיוק הבאג שתוקן: לפני התיקון
    // קבוצה חדשה תמיד אותחלה מורחבת, בלי קשר למצב הכיווץ הגלובלי.
    expect(find.text('מפרש בדיקה ב'), findsOneWidget);
    expect(find.textContaining('זהו פירוש לבדיקה'), findsNothing);
    expect(find.byTooltip('הרחב את כל המפרשים'), findsOneWidget);
  });

  testWidgets(
    'כיווץ שני מפרשים סמוכים בחלונית הצד משאיר את שניהם גלויים (issue #1976)',
    (tester) async {
      textBookBloc.emitStateForTest(_twoGroupsState());
      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: const Scaffold(
              body: TabbedCommentaryPanel(
                openBookCallback: _noopOpenBook,
                fontSize: 18,
                showSearch: true,
                showSplitView: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final title in ['מפרש בדיקה', 'מפרש בדיקה ב']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }

      expect(find.text('מפרש בדיקה').hitTestable(), findsOneWidget);
      expect(find.text('מפרש בדיקה ב').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('בנייה מחדש עם אותם קישורים לא מחזירה את שלד הטעינה (perf)', (
    tester,
  ) async {
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

    // הכיווץ בונה מחדש עם אותה רשימת קישורים; future קיבוץ חדש היה מציג
    // שלד טעינה בפריים הבא במקום הכותרת.
    await tester.tap(find.text('מפרש בדיקה'));
    await tester.pump();
    expect(find.text('מפרש בדיקה'), findsOneWidget);
  });
}

void _noopOpenBook(dynamic _) {}

TextBookLoaded _twoGroupsState() {
  final links = [
    for (final title in ['מפרש בדיקה', 'מפרש בדיקה ב'])
      Link(
        heRef: 'בראשית א',
        index1: 1,
        path2: '$title.txt',
        index2: 1,
        connectionType: 'COMMENTARY',
        targetCategoryId: 1,
        targetFileType: 'txt',
      ),
  ];
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: true,
    activeCommentators: const ['מפרש בדיקה', 'מפרש בדיקה ב'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה', 'מפרש בדיקה ב'],
    links: links,
    visibleLinks: const [],
    linksByLine: {1: links},
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

TextBookLoaded _loadedStateA() {
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
    content: const ['שורה א', 'שורה ב'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה', 'מפרש בדיקה ב'],
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

// אותו תוכן ("ספר בדיקה"), אבל מפרש חדש בשורה השנייה - כותרת ספר שונה, כך
// שנוצר מפתח-קבוצה (groupKey) חדש שלא היה קודם ב-_expansionStates.
TextBookLoaded _loadedStateB() {
  final link = Link(
    heRef: 'בראשית ב',
    index1: 2,
    path2: 'מפרש בדיקה ב.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה ב'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה', 'מפרש בדיקה ב'],
    links: [link],
    visibleLinks: const [],
    linksByLine: {
      2: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [1],
    selectedIndex: 1,
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

  void emitStateForTest(TextBookState state) => emit(state);

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
    BookSource preferSource = BookSource.official,
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return title == 'מפרש בדיקה';
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
