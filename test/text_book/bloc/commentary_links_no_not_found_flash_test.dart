import 'dart:async';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _commentator = 'רש"י על ספר בדיקה';

/// ספר עם מפרש יחיד; הקישורים אליו מוחזרים רק כשהוא ברשימת היעדים.
class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async =>
      List.generate(40, (i) => 'שורה $i').join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final lines = List.generate(40, (i) => 'שורה $i');
    final start = startLine.clamp(0, lines.length - 1);
    final end = endLine.clamp(start, lines.length - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: lines.length,
      lines: lines.sublist(start, end + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<({List<String> all, Set<String> rare})> getCommentatorsWithRarity(
    TextBook book,
  ) async {
    // רשימת המפרשים נטענת מה-DB ואיטית מטעינת הקישורים לחלון הנראה.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return (all: const [_commentator], rare: const <String>{});
  }

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final wanted =
        targetBookTitles == null || targetBookTitles.contains(_commentator);
    if (!wanted) return const [];
    return [
      for (var line = startIndex; line <= endIndex; line++)
        Link(
          heRef: '$_commentator $line',
          index1: line + 1,
          path2: 'מפרשים/$_commentator',
          index2: line + 1,
          connectionType: 'commentary',
        ),
    ];
  }
}

bool _hasRelevantCommentaryLinks(TextBookLoaded state) {
  return state.visibleIndices.any((idx) {
    final lineLinks = state.linksByLine[idx + 1];
    if (lineLinks == null) return false;
    return lineLinks.any(
      (link) => state.activeCommentators.contains(
        utils.getTitleFromPath(link.path2),
      ),
    );
  });
}

/// התנאי שבו חלונית המפרשים מציגה "לא נמצאו מפרשים" (commentary_list_base):
/// הטעינה הסתיימה ואין קישור מהמפרשים הפעילים לשורות הנראות.
bool _panelSaysNotFound(TextBookLoaded state) =>
    !state.linksLoading && !_hasRelevantCommentaryLinks(state);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test(
    'פתיחת ספר בלי בחירת מפרשים: אין מצב "לא נמצאו מפרשים" בין הטעינה לתוצאות '
    '(issue #1130)',
    () async {
      final book = TextBook(title: 'ספר בדיקה', source: BookSource.user);
      final bloc = TextBookBloc(
        repository: _Repository(),
        initialState: TextBookInitial.named(
          book,
          10,
          false,
          const [],
        ),
        scrollController: ItemScrollController(),
        positionsListener: ItemPositionsListener.create(),
      );
      addTearDown(bloc.close);

      final loadedStates = <TextBookLoaded>[];
      final done = Completer<void>();
      final sub = bloc.stream.listen((state) {
        if (state is! TextBookLoaded) return;
        loadedStates.add(state);
        if (!done.isCompleted &&
            state.activeCommentators.isNotEmpty &&
            !state.linksLoading &&
            _hasRelevantCommentaryLinks(state)) {
          done.complete();
        }
      });
      addTearDown(sub.cancel);

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: true,
        ),
      );
      await done.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('המפרשים לא הוצגו כלל'),
      );

      // מרגע שהחלונית הציגה "טוען מפרשים..." היא חייבת להישאר בטעינה עד
      // שיש תוצאות — כל מצב "לא נמצאו" באמצע הוא ההבזק שדווח.
      final firstLoading = loadedStates.indexWhere((s) => s.linksLoading);
      expect(firstLoading, isNonNegative, reason: 'צפוי מצב "טוען מפרשים..."');
      final flashes = loadedStates
          .skip(firstLoading)
          .takeWhile(
            (s) => s.activeCommentators.isEmpty || _panelSaysNotFound(s),
          )
          .where(_panelSaysNotFound)
          .toList();
      expect(
        flashes,
        isEmpty,
        reason:
            'לפני שהמפרשים נבחרו נטענו קישורים בלי יעדים והחלונית הציגה '
            '"לא נמצאו מפרשים" (issue #1130)',
      );
    },
  );
}
