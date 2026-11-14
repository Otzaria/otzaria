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
  }) async => BookContentRange(
    startLine: 0,
    endLine: _lineCount - 1,
    totalLines: _lineCount,
    lines: _lines,
  );
}

Link _link(int line, String path, String type) => Link(
  heRef: '$path $line',
  index1: line,
  path2: path,
  index2: line,
  connectionType: type,
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

  test('קישורי שורה נבחרת שורדים טעינת חלון רחוק', () async {
    final bloc = await _loadedBloc();
    final selectedLinks = [
      _link(1001, 'רשי.txt', LinkTypes.commentary),
      _link(1001, 'הפניה א.txt', 'reference'),
    ];
    final farReference = _link(2001, 'הפניה א.txt', 'reference');
    final seededLinks = [...selectedLinks, farReference];
    bloc.emit(
      (bloc.state as TextBookLoaded).copyWith(
        links: seededLinks,
        linksByLine: buildLinksByLineMap(seededLinks),
        selectedIndices: {1000},
        selectedIndex: 1000,
        visibleIndices: const [4000],
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
    expect(links, containsAll(selectedLinks));
    expect(links, isNot(contains(farReference)));
  });
}
