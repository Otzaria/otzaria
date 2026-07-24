import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextBookBloc bloc;
  late TextBook book;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    book = TextBook(title: 'ספר בדיקה');
    bloc = TextBookBloc(
      repository: _FakeTextBookRepository(),
      initialState: TextBookInitial.named(book, 10, true, const []),
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  blocTest<TextBookBloc, TextBookState>(
    'ApplyFullBookContent מחליף preview בתוכן מלא ושומר searchText',
    build: () => bloc,
    seed: () => TextBookLoaded(
      book: book,
      content: const ['שורת preview 1', 'שורת preview 2'],
      fontSize: 20,
      showLeftPane: true,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [10],
      pinLeftPane: false,
      searchText: 'שלום',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    ),
    act: (bloc) => bloc.add(
      const ApplyFullBookContent(
        bookTitle: 'ספר בדיקה',
        content: ['שורה מלאה 1', 'שורה מלאה 2', 'שורה מלאה 3'],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((state) => state.content.length, 'content length', 3)
          .having((state) => state.searchText, 'searchText', 'שלום'),
    ],
  );

  TextBookLoaded buildLoadedState({
    required List<String> content,
    List<int> visibleIndices = const [0],
  }) => TextBookLoaded(
    book: book,
    content: content,
    fontSize: 20,
    showLeftPane: true,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: visibleIndices,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );

  group('SetTabVisibility', () {
    final longContent = List<String>.generate(
      3000,
      (i) => 'שורה $i',
      growable: false,
    );

    // החלת טווח אמיתי מוכיחה שטעינת-טווחים עובדת לספר — תנאי לשחרור תוכן.
    const proveRangeLoading = ApplyBookContentRanges(
      bookTitle: 'ספר בדיקה',
      ranges: [
        (startLine: 1000, totalLines: 3000, lines: ['שורה 1000']),
      ],
    );

    blocTest<TextBookBloc, TextBookState>(
      'הסתרת טאב משחררת תוכן מחוץ לחלון ושומרת אורך ואינדקסים',
      build: () => bloc,
      seed: () =>
          buildLoadedState(content: longContent, visibleIndices: const [1000]),
      act: (bloc) {
        bloc.add(proveRangeLoading);
        bloc.add(const SetTabVisibility(false));
      },
      expect: () => [
        isA<TextBookLoaded>(), // החלת הטווח המוכיח
        isA<TextBookLoaded>()
            .having((s) => s.content.length, 'content length', 3000)
            .having((s) => s.content[1000], 'שורה נראית נשמרת', 'שורה 1000')
            .having((s) => s.content[0], 'שורה רחוקה משוחררת', '')
            .having((s) => s.content[2500], 'שורה רחוקה משוחררת', ''),
      ],
    );

    blocTest<TextBookBloc, TextBookState>(
      'ספר במסלול preview (ללא טעינת-טווחים) אינו משוחרר בהסתרה',
      build: () => bloc,
      seed: () =>
          buildLoadedState(content: longContent, visibleIndices: const [1000]),
      act: (bloc) => bloc.add(const SetTabVisibility(false)),
      expect: () => const [],
    );

    blocTest<TextBookBloc, TextBookState>(
      'ספר קצר אינו משוחרר בהסתרה',
      build: () => bloc,
      seed: () => buildLoadedState(
        content: List<String>.generate(100, (i) => 'שורה $i'),
      ),
      act: (bloc) {
        bloc.add(
          const ApplyBookContentRanges(
            bookTitle: 'ספר בדיקה',
            ranges: [
              (startLine: 0, totalLines: 100, lines: ['שורה 0']),
            ],
          ),
        );
        bloc.add(const SetTabVisibility(false));
      },
      expect: () => [
        isA<TextBookLoaded>(), // החלת הטווח בלבד — אין emission שחרור
      ],
    );

    blocTest<TextBookBloc, TextBookState>(
      'אצוות חימום בתור אינן מוחלות בזמן שהטאב מוסתר',
      build: () => bloc,
      seed: () =>
          buildLoadedState(content: longContent, visibleIndices: const [1000]),
      act: (bloc) {
        bloc.add(proveRangeLoading);
        bloc.add(const SetTabVisibility(false));
        bloc.add(
          const ApplyBookContentRanges(
            bookTitle: 'ספר בדיקה',
            ranges: [
              (startLine: 0, totalLines: 3000, lines: ['תוכן שחזר']),
            ],
          ),
        );
      },
      expect: () => [
        isA<TextBookLoaded>(), // החלת הטווח המוכיח
        // emission השחרור — האצווה שאחריו נבלעת
        isA<TextBookLoaded>().having((s) => s.content[0], 'line 0', ''),
      ],
    );

    blocTest<TextBookBloc, TextBookState>(
      'אחרי חזרה לנראות אצוות תוכן שבות ומוחלות',
      build: () => bloc,
      seed: () =>
          buildLoadedState(content: longContent, visibleIndices: const [1000]),
      act: (bloc) async {
        bloc.add(proveRangeLoading);
        bloc.add(const SetTabVisibility(false));
        bloc.add(const SetTabVisibility(true));
        bloc.add(
          const ApplyBookContentRanges(
            bookTitle: 'ספר בדיקה',
            ranges: [
              (startLine: 0, totalLines: 3000, lines: ['תוכן שחזר']),
            ],
          ),
        );
      },
      expect: () => [
        isA<TextBookLoaded>(), // החלת הטווח המוכיח
        isA<TextBookLoaded>().having((s) => s.content[0], 'line 0', ''),
        isA<TextBookLoaded>().having(
          (s) => s.content[0],
          'line 0',
          'תוכן שחזר',
        ),
      ],
    );
  });

  blocTest<TextBookBloc, TextBookState>(
    'ApplyBookContentRanges מחיל כמה טווחים ב-emission יחיד',
    build: () => bloc,
    seed: () => TextBookLoaded(
      book: book,
      content: const ['שורה 0', 'שורה 1'],
      fontSize: 20,
      showLeftPane: true,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [0],
      pinLeftPane: false,
      searchText: '',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    ),
    act: (bloc) => bloc.add(
      const ApplyBookContentRanges(
        bookTitle: 'ספר בדיקה',
        ranges: [
          (startLine: 2, totalLines: 6, lines: ['שורה 2', 'שורה 3']),
          (startLine: 4, totalLines: 6, lines: ['שורה 4', 'שורה 5']),
        ],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((state) => state.content.length, 'content length', 6)
          .having((state) => state.content[3], 'line 3', 'שורה 3')
          .having((state) => state.content[5], 'line 5', 'שורה 5'),
    ],
  );
}
