// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:collection';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  final requestedRanges = <({int startLine, int endLine})>[];

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    requestedRanges.add((startLine: startLine, endLine: endLine));
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextBookBloc bloc;
  late TextBook book;
  late _FakeTextBookRepository repository;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    book = TextBook(title: 'ספר בדיקה');
    repository = _FakeTextBookRepository();
    bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 10, true, const []),
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
    bool continuousReadingMode = false,
  }) => TextBookLoaded(
    book: book,
    content: content,
    supportsContinuousReadingMode: continuousReadingMode,
    continuousReadingMode: continuousReadingMode,
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

    test('מצב קריאה רציף משוחרר בהסתרה ופריסת הקריאה אינה זזה', () async {
      final toc = [
        for (var line = 0; line < 3000; line += 100)
          TocEntry(text: 'סימן $line', index: line),
      ];
      bloc.emit(
        buildLoadedState(
          content: longContent,
          visibleIndices: const [1050],
          continuousReadingMode: true,
        ).copyWith(tableOfContents: toc),
      );
      bloc.add(proveRangeLoading);
      final proven = await bloc.stream.first as TextBookLoaded;
      final layout = readingLayoutOf(proven);
      expect(layout.itemCount, 60);

      bloc.add(const SetTabVisibility(false));
      final released = await bloc.stream.first as TextBookLoaded;
      expect(released.content.length, 3000);
      expect(released.content[0], '');
      expect(released.content[1050], 'שורה 1050');
      expect(identical(readingLayoutOf(released), layout), isTrue);
    });

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

    test('הסתרה שומרת סנכרון מפרש דליל גם מחוץ לחלון', () async {
      // הקישורים של אדרת אליהו בבראשית מקיפים חלון שאין בו קישור קודם.
      final previous = Link(
        heRef: 'אדרת אליהו, בראשית, מב, ט, א',
        index1: 1309,
        index2: 355,
        path2: 'אדרת אליהו',
        connectionType: LinkTypes.commentary,
      );
      final next = Link(
        heRef: 'אדרת אליהו, בראשית, מח, יד, א',
        index1: 1515,
        index2: 358,
        path2: 'אדרת אליהו',
        connectionType: LinkTypes.commentary,
      );
      final links = [previous, next];
      final seeded = buildLoadedState(
        content: List.filled(1584, 'תוכן'),
        visibleIndices: const [1459],
      ).copyWith(links: links, linksByLine: buildLinksByLineMap(links));
      bloc.emit(seeded);
      bloc.add(const SetTabVisibility(false));
      await pumpEventQueue();
      final released = bloc.state as TextBookLoaded;
      expect(
        CommentarySyncHelper.getCommentaryTargetIndex(
          linksForCommentary: released.links,
          logicalMainIndex: 1459,
        ),
        354,
      );
      expect(released.links, links);
    });

    test('הסתרה שומרת את כל סוגי קישורי הסנכרון והמקור', () async {
      final links = [
        for (final type in [...LinkTypes.dependentTextTypes, LinkTypes.source])
          Link(
            heRef: type,
            index1: 1,
            index2: 10,
            path2: 'ספר $type',
            connectionType: type.toLowerCase(),
          ),
      ];
      bloc.emit(
        buildLoadedState(
          content: longContent,
          visibleIndices: const [1000],
        ).copyWith(links: links, linksByLine: buildLinksByLineMap(links)),
      );
      bloc.add(const SetTabVisibility(false));
      await pumpEventQueue();
      final released = bloc.state as TextBookLoaded;
      expect(released.links, links);
      expect(released.linksByLine[1], links);
    });

    test('הסתרת טאב משחררת קישורים שנצברו בגלילה מחוץ לחלון', () async {
      Link linkAt(int index1, {int? index1End}) => Link(
        heRef: 'מפרש $index1',
        index1: index1,
        index1End: index1End,
        path2: 'מפרש',
        index2: index1,
        connectionType: 'reference',
      );
      // קישור לכל שורה בספר, כמו אחרי גלילה מתחילתו ועד סופו.
      final links = [
        for (var line = 1; line <= 3000; line++) linkAt(line),
        linkAt(400, index1End: 900),
      ];
      final linksByLine = buildLinksByLineMap(links);
      final seeded =
          buildLoadedState(
            content: longContent,
            visibleIndices: const [1000],
          ).copyWith(
            links: links,
            linksByLine: linksByLine,
            selectedIndices: const {2500},
          );
      bloc.emit(seeded);

      bloc.add(const SetTabVisibility(false));
      await pumpEventQueue();
      final released = bloc.state as TextBookLoaded;

      expect(released.links.length, lessThan(links.length ~/ 5));
      expect(released.linksByLine[1], isNull);
      expect(released.linksByLine[1001], linksByLine[1001]);
      expect(released.linksByLine[2501], linksByLine[2501]);
      expect(released.linksByLine[880], linksByLine[880]);
      expect(released.visibleLinks, seeded.visibleLinks);
    });

    test('הסתרת טאב עם הרבה קישורים ובחירה גדולה: אותה תוצאה, בלי סריקה '
        'של הבחירה לכל קישור', () async {
      const types = ['reference', 'COMMENTARY', 'source', 'Related Passage'];
      final links = [
        for (var i = 0; i < 140000; i++)
          _CountingLink(
            index1: i % 3000 + 1,
            index1End: i % 7 == 0 ? i % 3000 + 4 : null,
            type: types[i % types.length],
          ),
      ];
      final selected = {for (var i = 2000; i < 2500; i++) i};
      const visible = 1000;
      const start = visible - TextBookBloc.linkLookBehindLines + 1;
      const end = visible + TextBookBloc.linkLookAheadLines + 1;
      final expected = [
        for (final link in links)
          if (LinkTypes.isDependentTextLink(link.connectionType) ||
              LinkTypes.isVirtualSource(link.connectionType) ||
              link.overlapsSourceLines(start, end) ||
              selected.any((i) => link.overlapsSourceLines(i + 1, i + 1)))
            link,
      ];
      bloc.emit(
        buildLoadedState(
          content: longContent,
          visibleIndices: const [visible],
        ).copyWith(
          links: links,
          linksByLine: buildLinksByLineMap(links),
          selectedIndices: selected,
        ),
      );
      _CountingLink.reset();

      bloc.add(const SetTabVisibility(false));
      await pumpEventQueue();
      final released = bloc.state as TextBookLoaded;

      expect(released.links, orderedEquals(expected));
      expect(released.links.length, lessThan(links.length));
      expect(_CountingLink.typeReads, lessThanOrEqualTo(links.length));
      expect(_CountingLink.overlapChecks, lessThanOrEqualTo(links.length));
    });
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
          .having((state) => state.content[5], 'line 5', 'שורה 5')
          .having(
            (state) => state.contentChanges?.fromVersion,
            'previous version',
            0,
          )
          .having((state) => state.contentChanges?.ranges, 'changed ranges', [
            (first: 0, last: 5),
          ]),
    ],
  );

  test('טווח זהה בספר מלא בודק רק את שורות הטווח', () async {
    const lineCount = 16384;
    const rangeSize = 640;
    final values = List<String>.generate(
      lineCount,
      (line) => line.isEven ? '' : 'שורה $line',
    );
    final tracked = _ReadCountingLines(values);
    bloc.emit(buildLoadedState(content: const []));

    final loaded = bloc.stream.firstWhere(
      (state) => state is TextBookLoaded && identical(state.content, tracked),
    );
    bloc.add(ApplyFullBookContent(bookTitle: book.title, content: tracked));
    await loaded;
    final full = bloc.state as TextBookLoaded;
    expect(full.loadedLineFlags?.length, lineCount);

    final start = lineCount - rangeSize;
    final tail = values.sublist(start);
    tracked.reads = 0;
    bloc.add(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: start,
        totalLines: lineCount,
        lines: tail,
      ),
    );
    await pumpEventQueue();

    expect(bloc.state, same(full));
    expect(tracked.reads, inInclusiveRange(1, rangeSize));
    expect((bloc.state as TextBookLoaded).contentVersion, full.contentVersion);

    // A genuine change must still emit, increment the revision, and keep
    // the previously published full-content object unchanged.
    final changed = List<String>.of(tail)..[0] = 'תוכן מעודכן';
    final updatedFuture = bloc.stream.firstWhere(
      (state) =>
          state is TextBookLoaded &&
          state.contentVersion == full.contentVersion + 1,
    );
    bloc.add(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: start,
        totalLines: lineCount,
        lines: changed,
      ),
    );
    final updated = await updatedFuture as TextBookLoaded;
    expect(updated.content[start], 'תוכן מעודכן');
    expect(updated.contentVersion, full.contentVersion + 1);
    expect(full.content[start], values[start]);
    expect(updated.loadedLineFlags?.every((loaded) => loaded), isTrue);
  });

  test('טווח זהה שומר שורה, בחירה, סימון ו-revision', () async {
    const original = ['א', 'ב', '', 'ד'];
    bloc.emit(buildLoadedState(content: const []));
    final fullFuture = bloc.stream.firstWhere(
      (state) => state is TextBookLoaded && state.content.length == 4,
    );
    bloc.add(
      ApplyFullBookContent(bookTitle: book.title, content: original),
    );
    final full = await fullFuture as TextBookLoaded;
    final selected = full.copyWith(
      selectedIndex: 2,
      selectedIndices: const {2},
      visibleIndices: const [2],
      permanentHighlightLine: 2,
      currentTitle: 'כותרת נבחרת',
    );
    bloc.emit(selected);

    bloc.add(
      ApplyBookContentRanges(
        bookTitle: book.title,
        ranges: const [
          (startLine: 0, totalLines: 4, lines: ['א', 'ב']),
          (startLine: 2, totalLines: 4, lines: ['', 'ד']),
        ],
      ),
    );
    await pumpEventQueue();
    expect(bloc.state, same(selected));
    expect((bloc.state as TextBookLoaded).contentVersion, full.contentVersion);
    expect((bloc.state as TextBookLoaded).selectedIndices, {2});

    final updatedFuture = bloc.stream.firstWhere(
      (state) =>
          state is TextBookLoaded &&
          state.contentVersion == selected.contentVersion + 1,
    );
    bloc.add(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 1,
        totalLines: 4,
        lines: const ['שורה מתוקנת'],
      ),
    );
    final updated = await updatedFuture as TextBookLoaded;
    expect(updated.content, ['א', 'שורה מתוקנת', '', 'ד']);
    expect(updated.contentChanges?.fromVersion, selected.contentVersion);
    expect(updated.contentChanges?.ranges, [(first: 1, last: 1)]);
    expect(updated.selectedIndex, 2);
    expect(updated.selectedIndices, {2});
    expect(updated.visibleIndices, [2]);
    expect(updated.permanentHighlightLine, 2);
    expect(updated.currentTitle, 'כותרת נבחרת');
    expect(selected.content, original);
  });

  test('שורה ריקה ללא דגל טעון עדיין מפעילה רענון', () async {
    bloc.emit(
      buildLoadedState(content: const ['א', '', 'ג']).copyWith(
        selectedIndex: 1,
        selectedIndices: const {1},
      ),
    );
    final before = bloc.state as TextBookLoaded;
    final updatedFuture = bloc.stream.firstWhere(
      (state) =>
          state is TextBookLoaded &&
          state.contentVersion == before.contentVersion + 1,
    );
    bloc.add(
      ApplyBookContentRange(
        bookTitle: book.title,
        startLine: 1,
        totalLines: 3,
        lines: const [''],
      ),
    );
    final updated = await updatedFuture as TextBookLoaded;
    expect(updated.content, before.content);
    expect(updated.isContentLineLoaded(1), isTrue);
    expect(updated.contentVersion, before.contentVersion + 1);
    expect(updated.selectedIndices, before.selectedIndices);
    expect(updated.contentChanges?.fromVersion, before.contentVersion);
  });

  test('אצווה שמשנה ואז משחזרת עדיין מגדילה revision', () async {
    const original = ['א', '', 'ג'];
    bloc.emit(buildLoadedState(content: const []));
    final fullFuture = bloc.stream.firstWhere(
      (state) => state is TextBookLoaded && state.content.length == 3,
    );
    bloc.add(
      ApplyFullBookContent(bookTitle: book.title, content: original),
    );
    final full = await fullFuture as TextBookLoaded;
    final updatedFuture = bloc.stream.firstWhere(
      (state) =>
          state is TextBookLoaded &&
          state.contentVersion == full.contentVersion + 1,
    );
    bloc.add(
      ApplyBookContentRanges(
        bookTitle: book.title,
        ranges: const [
          (startLine: 1, totalLines: 3, lines: ['תוכן זמני']),
          (startLine: 1, totalLines: 3, lines: ['']),
        ],
      ),
    );
    final updated = await updatedFuture as TextBookLoaded;
    expect(updated.content, original);
    expect(updated.contentVersion, full.contentVersion + 1);
    // Overlapping identical ranges are coalesced in ContentLineChanges.
    expect(updated.contentChanges?.ranges, [(first: 1, last: 1)]);
    expect(full.content, original);
  });

  test('פסקה רציפה שלא נטענה כולה מבקשת את כל טווח שורותיה', () async {
    // שורות 1..1999 בין שתי כותרות (נחתכות לפריטים); רק סביב שורה 1000 טעון.
    const lineCount = 2100;
    final toc = [
      TocEntry(text: 'פתיחה', index: 0),
      TocEntry(text: 'סיום', index: 2000),
    ];
    final layout = continuousReadingLayout(
      lineCount: lineCount,
      tableOfContents: toc,
    );
    final item = layout.itemForLine(1000);
    final flags = [
      for (var i = 0; i < lineCount; i++) i >= 990 && i <= 1010,
    ];
    bloc.emit(
      buildLoadedState(
        content: [
          for (var i = 0; i < lineCount; i++) flags[i] ? 'שורה $i' : '',
        ],
        visibleIndices: const [0],
        continuousReadingMode: true,
      ).copyWith(
        loadedLineFlags: flags,
        showLeftPane: false,
        tableOfContents: toc,
      ),
    );
    bloc.add(const UpdateVisibleIndecies([999, 1000, 1001]));
    await bloc.stream.first;
    await Future<void>.delayed(Duration.zero);

    expect(repository.requestedRanges, isNotEmpty);
    final requested = repository.requestedRanges.last;
    expect(layout.lineCountOf(item), greaterThan(21));
    expect(requested.startLine, lessThanOrEqualTo(layout.firstLineOf(item)));
    expect(requested.endLine, greaterThanOrEqualTo(layout.lastLineOf(item)));
  });
}

class _ReadCountingLines extends ListBase<String> {
  _ReadCountingLines(this._values);

  final List<String> _values;
  int reads = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('Read-only source');

  @override
  String operator [](int index) {
    reads++;
    return _values[index];
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('Read-only source');
}

class _CountingLink extends Link {
  _CountingLink({required super.index1, super.index1End, required this.type})
    : super(heRef: 'קישור', path2: 'ספר', index2: 1, connectionType: type);

  final String type;
  static int typeReads = 0;
  static int overlapChecks = 0;

  static void reset() => typeReads = overlapChecks = 0;

  @override
  String get connectionType {
    typeReads++;
    return type;
  }

  @override
  bool overlapsSourceLines(int first, int last) {
    overlapChecks++;
    return super.overlapsSourceLines(first, last);
  }
}
