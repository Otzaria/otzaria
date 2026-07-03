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
    act: (bloc) => bloc.add(const ApplyFullBookContent(
      bookTitle: 'ספר בדיקה',
      content: ['שורה מלאה 1', 'שורה מלאה 2', 'שורה מלאה 3'],
    )),
    expect: () => [
      isA<TextBookLoaded>()
          .having((state) => state.content.length, 'content length', 3)
          .having((state) => state.searchText, 'searchText', 'שלום'),
    ],
  );

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
    act: (bloc) => bloc.add(const ApplyBookContentRanges(
      bookTitle: 'ספר בדיקה',
      ranges: [
        (startLine: 2, totalLines: 6, lines: ['שורה 2', 'שורה 3']),
        (startLine: 4, totalLines: 6, lines: ['שורה 4', 'שורה 5']),
      ],
    )),
    expect: () => [
      isA<TextBookLoaded>()
          .having((state) => state.content.length, 'content length', 6)
          .having((state) => state.content[3], 'line 3', 'שורה 3')
          .having((state) => state.content[5], 'line 5', 'שורה 5'),
    ],
  );
}
