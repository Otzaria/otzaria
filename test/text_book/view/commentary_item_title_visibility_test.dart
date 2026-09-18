// בדיקות להסתרת כותרת המקור המיותרת בלשונית הפרשנים (issue #896):
// הכותרת מוסתרת רק כשכל מקטעי הקבוצה מאותה שורת מקור והיעד הוא המקום
// הנקרא כעת; מקטע ממקום אחר, קבוצה רב-שורתית ואות-עוגן נשמרים.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:otzaria/text_book/utils/commentary_title_visibility.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('groupSharesSingleSource', () {
    Link link(int index1, {int index2 = 1}) => Link(
      heRef: 'מפרש בדיקה, ג ב',
      index1: index1,
      path2: 'מפרש בדיקה.txt',
      index2: index2,
      connectionType: 'commentary',
    );

    test('רשימה ריקה — false', () {
      expect(groupSharesSingleSource(const []), isFalse);
    });

    test('כל הקישורים מאותה שורת מקור — true', () {
      expect(
        groupSharesSingleSource([link(3), link(3, index2: 2)]),
        isTrue,
      );
    });

    test('שורות מקור שונות (כל הפרק / בחירה מרובה) — false', () {
      expect(groupSharesSingleSource([link(3), link(4)]), isFalse);
    });
  });

  group('commentaryTitleMatchesReadingLocation', () {
    test('יעד באותו מקום כמו שורת המקור — תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש"י על בכורות, ג ב',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isTrue,
      );
    });

    test('כתובת מקור שכוללת את שם הספר — תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש"י על בכורות, ג ב',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'בכורות, ג ב',
        ),
        isTrue,
      );
    });

    test('יעד במקום אחר (כמו הפניה לסימן אחר) — לא תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'מגן אברהם, סימן ב',
          targetBookTitle: 'מגן אברהם',
          sourceBookTitle: 'שולחן ערוך אורח חיים',
          sourceRef: 'סימן א',
        ),
        isFalse,
      );
    });

    test('קישור-טווח (סיומת "–") — לא תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש"י על בכורות, ג ב–ג',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isFalse,
      );
    });

    test('כותרת שאינה מתחילה בשם ספר היעד — לא תואם (הצג, בטוח)', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'תוספות בכורות, ג ב',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isFalse,
      );
    });

    test('כותרת ללא כתובת (שם הספר בלבד) — לא תואם', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש"י על בכורות',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isFalse,
      );
    });

    test('הבדלי גרשיים וניקוד אינם מפרים התאמה', () {
      expect(
        commentaryTitleMatchesReadingLocation(
          displayTitle: 'רש״י על בכורות, ג ב',
          targetBookTitle: 'רש"י על בכורות',
          sourceBookTitle: 'בכורות',
          sourceRef: 'ג ב',
        ),
        isTrue,
      );
    });
  });

  group('CommentaryListBase - הסתרת כותרת מקטע', () {
    setUpAll(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

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
      settingsBloc = _TestSettingsBloc(SettingsState.initial());
    });

    tearDown(() async {
      await settingsBloc.close();
      LibraryProviderManager.instance.resetForTesting();
    });

    testWidgets('יעד במקום הנקרא — הכותרת מוסתרת והתוכן מוצג', (tester) async {
      final link = _link(heRef: 'מפרש בדיקה, ג ב', index1: 1, index2: 1);
      final bloc = _TestTextBookBloc(_loadedState(links: [link]));
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      expect(find.text(_kFakeContent), findsOneWidget);
      expect(find.text('מפרש בדיקה, ג ב'), findsNothing);
    });

    testWidgets('יעד במקום אחר — הכותרת מוצגת', (tester) async {
      final link = _link(heRef: 'מפרש בדיקה, סימן ב', index1: 1, index2: 2);
      final bloc = _TestTextBookBloc(_loadedState(links: [link]));
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      expect(find.text('מפרש בדיקה, סימן ב'), findsOneWidget);
    });

    testWidgets('קבוצה מכמה שורות מקור — הכותרות מוצגות', (tester) async {
      final links = [
        _link(heRef: 'מפרש בדיקה, ג ב', index1: 1, index2: 3),
        _link(heRef: 'מפרש בדיקה, ד א', index1: 2, index2: 4),
      ];
      final bloc = _TestTextBookBloc(
        _loadedState(
          links: links,
          content: const ['שורה א', 'שורה ב'],
          visibleIndices: const [0, 1],
        ),
      );
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      expect(find.text('מפרש בדיקה, ג ב'), findsOneWidget);
      expect(find.text('מפרש בדיקה, ד א'), findsOneWidget);
    });

    testWidgets('עוגן-מילה עם כותרת מוסתרת — אות הסימון נשארת', (tester) async {
      final link = _link(
        heRef: 'מפרש בדיקה, ג ב',
        index1: 1,
        index2: 5,
        anchorStart: 0,
        anchorLabel: 'א',
      );
      final bloc = _TestTextBookBloc(_loadedState(links: [link]));
      addTearDown(() async => bloc.close());

      await _pump(tester, textBookBloc: bloc, settingsBloc: settingsBloc);

      expect(find.text('(א)'), findsOneWidget);
      expect(find.text('(א) מפרש בדיקה, ג ב'), findsNothing);
    });
  });
}

const _kFakeContent = 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';

Link _link({
  required String heRef,
  required int index1,
  required int index2,
  int? anchorStart,
  String? anchorLabel,
}) {
  return Link(
    heRef: heRef,
    index1: index1,
    path2: 'מפרש בדיקה.txt',
    index2: index2,
    connectionType: 'commentary',
    targetCategoryId: 1,
    targetFileType: 'txt',
    anchorStart: anchorStart,
    anchorLabel: anchorLabel,
  );
}

TextBookLoaded _loadedState({
  required List<Link> links,
  List<String> content = const ['שורה א'],
  List<int> visibleIndices = const [0],
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: content,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
    links: links,
    visibleLinks: const [],
    linksByLine: {
      for (final link in links) link.index1: [link],
    },
    // הכתובות של שורות המקור: שורה 1 = "ג ב", שורה 2 = "ד א".
    tableOfContents: [
      TocEntry(text: 'ג ב', index: 0),
      TocEntry(text: 'ד א', index: 1),
    ],
    removeNikud: false,
    visibleIndices: visibleIndices,
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
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
        child: Scaffold(
          body: CommentaryListBase(
            openBookCallback: (_) {},
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
    return _kFakeContent;
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
