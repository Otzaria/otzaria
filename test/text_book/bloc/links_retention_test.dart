// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _lineCount = 6000;
const _linksPerLine = 4;

/// לכל שורה בחלון המבוקש: שני מפרשים ושתי הפניות.
class _WindowLinksRepository extends TextBookRepository {
  _WindowLinksRepository() : super(fileSystem: FileSystemData.instance);

  static final _lines = List.generate(_lineCount, (i) => 'שורה $i');

  @override
  Future<String> getBookContent(TextBook book) async => _lines.join('\n');
  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];
  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => [
    for (var i = startIndex; i <= endIndex && i < _lineCount; i++) ...[
      _link(i + 1, 'רשי.txt', LinkTypes.commentary),
      _link(i + 1, 'תוספות.txt', LinkTypes.commentary),
      _link(i + 1, 'הפניה א.txt', 'reference'),
      _link(i + 1, 'הפניה ב.txt', 'reference'),
    ],
  ];

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async => BookContentRange(
    startLine: 0,
    endLine: _lineCount - 1,
    totalLines: _lineCount,
    lines: _lines,
  );
}

Link _link(
  int line,
  String path,
  String type, {
  int baseProvenance = 0,
  String? heRef,
}) => Link(
  heRef: heRef ?? '$path $line',
  index1: line,
  path2: path,
  index2: line,
  connectionType: type,
  baseProvenance: baseProvenance,
);

Future<TextBookBloc> _loadedBloc() async {
  await Settings.init(cacheProvider: MemoryCacheProvider());
  final bloc = TextBookBloc(
    repository: _WindowLinksRepository(),
    initialState: TextBookInitial.named(
      TextBook(title: 'ספר צפוף'),
      0,
      false,
      const [],
    ),
  );
  addTearDown(bloc.close);
  final loaded = bloc.stream.firstWhere(
    (s) => s is TextBookLoaded && s.links.isNotEmpty && !s.linksLoading,
  );
  bloc.add(
    const LoadContent(
      fontSize: 20,
      showSplitView: false,
      removeNikud: false,
      loadCommentators: false,
    ),
  );
  await loaded.timeout(const Duration(seconds: 10));
  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('קריאה לאורך הספר אינה צוברת את כל הקישורים שעברו', () async {
    final bloc = await _loadedBloc();
    const retainedLines =
        TextBookBloc.linkLookBehindLines +
        TextBookBloc.linkLookAheadLines +
        2 * TextBookBloc.linksRetainMarginLines +
        1;
    // שני מפרשים, ולכל אחד לכל היותר קישור קרוב מכל צד מחוץ לטווח.
    const bound = retainedLines * _linksPerLine + 2 * 2;
    var maxLinks = 0;
    for (var line = 300; line <= 5000; line += 300) {
      final reached = bloc.stream.firstWhere(
        (s) =>
            s is TextBookLoaded &&
            !s.linksLoading &&
            s.links.any(
              (l) => l.index1 == line + TextBookBloc.linkLookAheadLines + 1,
            ),
      );
      bloc.add(UpdateVisibleIndecies([line]));
      await reached.timeout(const Duration(seconds: 10));
      final links = (bloc.state as TextBookLoaded).links;
      if (links.length > maxLinks) maxLinks = links.length;
    }
    expect(maxLinks, lessThanOrEqualTo(bound));
    final state = bloc.state as TextBookLoaded;
    expect(
      state.linksByLine[5001]?.length,
      _linksPerLine,
      reason: 'השורות הנראות שומרות את כל הקישורים שלהן',
    );
  });

  test('קישורי שורה נבחרת ונראית שורדים, וגבולות הטווח נשמרים', () async {
    final bloc = await _loadedBloc();
    final selectedLinks = [
      _link(1001, 'רשי.txt', LinkTypes.commentary),
      _link(1001, 'הפניה א.txt', 'reference'),
    ];
    final visibleLink = _link(5001, 'הפניה א.txt', 'reference');
    // retainLines הוא 0-based; index1 הוא 1-based.
    final atFirst = _link(3801, 'הפניה א.txt', 'reference');
    final atLast = _link(4201, 'הפניה א.txt', 'reference');
    final outside = [
      _link(2001, 'הפניה א.txt', 'reference'),
      _link(3800, 'הפניה א.txt', 'reference'),
      _link(4202, 'הפניה א.txt', 'reference'),
    ];
    final seededLinks = [
      ...selectedLinks,
      visibleLink,
      atFirst,
      atLast,
      ...outside,
    ];
    bloc.emit(
      (bloc.state as TextBookLoaded).copyWith(
        links: seededLinks,
        linksByLine: buildLinksByLineMap(seededLinks),
        selectedIndices: {1000},
        selectedIndex: 1000,
        visibleIndices: const [5000],
      ),
    );
    final incoming = _link(4001, 'הפניה ב.txt', 'reference');
    final updated = bloc.stream.firstWhere(
      (s) => s is TextBookLoaded && s.links.contains(incoming),
    );
    bloc.add(UpdateLinks([incoming], retainLines: (start: 3800, end: 4200)));
    final links =
        ((await updated.timeout(const Duration(seconds: 10))) as TextBookLoaded)
            .links;
    expect(
      links,
      containsAll([...selectedLinks, visibleLink, atFirst, atLast]),
    );
    for (final link in outside) {
      expect(links, isNot(contains(link)));
    }
  });

  for (final change in ['בחירה', 'בחירה מרובה', 'גלילה']) {
    test('$change בזמן עיבוד קישורים משמרת את קישורי השורות החדשות', () async {
      final bloc = await _loadedBloc();
      final first = _link(1001, 'הפניה א.txt', 'reference', baseProvenance: 2);
      final second = _link(1002, 'הפניה ב.txt', 'reference');
      final obsolete = _link(2001, 'הפניה א.txt', 'reference');
      final ranged = Link(
        heRef: 'הפניה על טווח',
        index1: 950,
        index1End: 1050,
        path2: 'טווח.txt',
        index2: 1,
        connectionType: 'reference',
      );
      final anchors = [
        for (final type in [LinkTypes.commentary, LinkTypes.source])
          for (final line in [501, 1501, 3001]) _link(line, '$type.txt', type),
      ];
      final seededLinks = [first, second, obsolete, ranged, ...anchors];
      bloc.emit(
        (bloc.state as TextBookLoaded).copyWith(
          links: seededLinks,
          linksByLine: buildLinksByLineMap(seededLinks),
          visibleIndices: const [5000],
          showPageShapeView: true,
          selectedIndex: change == 'בחירה מרובה' ? 1001 : null,
          clearSelectedIndex: change != 'בחירה מרובה',
          selectedIndices: change == 'בחירה מרובה' ? {1001} : const {},
          clearSelectedIndices: change != 'בחירה מרובה',
        ),
      );
      final incoming =
          List.generate(
            1000,
            (i) => _link(4001, 'יעד $i.txt', 'reference'),
          )..insertAll(0, [
            _link(1001, 'הפניה א.txt', 'reference', heRef: 'קישור חלש'),
            _link(1002, 'הפניה ב.txt', 'reference', heRef: 'קישור נכנס'),
          ]);
      final finished = bloc.stream.firstWhere(
        (s) =>
            s is TextBookLoaded &&
            s.links.any((link) => link.path2 == incoming.last.path2),
      );
      bloc.add(UpdateLinks(incoming, retainLines: (start: 3800, end: 4200)));
      await Future<void>.delayed(Duration.zero);
      final changed = bloc.stream.firstWhere(
        (s) =>
            s is TextBookLoaded &&
            (change == 'גלילה'
                ? s.visibleIndices.first == 1000
                : s.selectedIndex == 1000),
      );
      bloc.add(
        change == 'גלילה'
            ? UpdateVisibleIndecies([1000, 1001])
            : UpdateSelectedIndex(1000, additive: change == 'בחירה מרובה'),
      );
      final during = await changed.timeout(const Duration(seconds: 10));
      expect(
        (during as TextBookLoaded).links,
        isNot(contains(predicate<Link>((l) => l.path2 == incoming.last.path2))),
        reason: 'הבחירה או הגלילה חייבות להתרחש בזמן ההמתנה ל-isolate',
      );
      final result =
          await finished.timeout(const Duration(seconds: 10)) as TextBookLoaded;
      expect(
        result.links.singleWhere((link) => link.path2 == first.path2).heRef,
        first.heRef,
        reason: 'קישור חזק שנשמר בהשלמה גובר על קישור נכנס חלש',
      );
      expect(
        result.links.singleWhere((link) => link.path2 == second.path2).heRef,
        'קישור נכנס',
        reason: 'באותו provenance הקישור הנכנס גובר על הקישור שנשמר בהשלמה',
      );
      final expected = change == 'בחירה'
          ? [first, ranged]
          : [first, second, ranged];
      for (final link in expected) {
        expect(
          result.linksByLine[link.index1]?.map(linkIdentityKey),
          contains(linkIdentityKey(link)),
        );
      }
      expect(
        result.visibleLinks.map(linkIdentityKey),
        unorderedEquals(expected.map(linkIdentityKey)),
      );
      expect(
        result.links.map(linkIdentityKey),
        isNot(contains(linkIdentityKey(obsolete))),
      );
      for (final type in [LinkTypes.commentary, LinkTypes.source]) {
        expect(
          CommentarySyncIndex(
            result.links.where((link) => link.connectionType == type),
          ).targetIndexFor(1000),
          500,
        );
      }
      expect(
        result.links.length,
        lessThanOrEqualTo(incoming.length + seededLinks.length - 1),
      );
    });
  }

  test('גלילה בתוך הטווח בזמן עיבוד מעדכנת את הקישורים הגלויים', () async {
    final bloc = await _loadedBloc();
    bloc.emit(
      (bloc.state as TextBookLoaded).copyWith(
        visibleIndices: const [5000],
        showPageShapeView: true,
        clearSelectedIndex: true,
        clearSelectedIndices: true,
      ),
    );
    final incoming = List.generate(
      1000,
      (i) => _link(4001, 'יעד $i.txt', 'reference'),
    );
    final finished = bloc.stream.firstWhere(
      (s) =>
          s is TextBookLoaded &&
          s.links.any((link) => link.path2 == incoming.last.path2),
    );
    bloc.add(UpdateLinks(incoming, retainLines: (start: 3800, end: 4200)));
    await Future<void>.delayed(Duration.zero);
    final scrolled = bloc.stream.firstWhere(
      (s) => s is TextBookLoaded && s.visibleIndices.first == 4000,
    );
    bloc.add(UpdateVisibleIndecies([4000]));
    final during = await scrolled.timeout(const Duration(seconds: 10));
    expect(
      (during as TextBookLoaded).links.any(
        (link) => link.path2 == incoming.last.path2,
      ),
      isFalse,
    );
    final result =
        await finished.timeout(const Duration(seconds: 10)) as TextBookLoaded;
    expect(
      result.visibleLinks.map(linkIdentityKey),
      unorderedEquals(incoming.map(linkIdentityKey)),
    );
  });

  test(
    'טעינת כל הקישורים לפרק (כרטיסיית המפרשים) אינה מפנה פרקים קודמים',
    () async {
      final bloc = await _loadedBloc();
      Future<void> loadAll(int line) async {
        final loaded = bloc.stream.firstWhere(
          (s) =>
              s is TextBookLoaded &&
              !s.linksLoading &&
              s.links.any((l) => l.index1 == line + 1),
        );
        bloc.add(LoadAllLinksForIndices([line]));
        await loaded.timeout(const Duration(seconds: 10));
      }

      await loadAll(2000);
      await loadAll(5000);
      final links = (bloc.state as TextBookLoaded).links;
      expect(
        links.where((l) => l.index1 == 2001 && l.path2 == 'הפניה א.txt'),
        isNotEmpty,
      );
    },
  );
}
