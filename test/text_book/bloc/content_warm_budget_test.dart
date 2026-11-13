import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _totalLines = 2100;
const _firstImageLine = 2000;

/// ספר שסופו תמונות מוטמעות כבדות, כמו "שלח תשלח" (#5033). מחרוזת אחת
/// משותפת לכל השורות, כך שהבדיקה עצמה אינה תופסת זיכרון.
final _heavyImageLine =
    '<img src="data:image/png;base64,${'A' * (4 * 1024 * 1024)}">';

String _line(int index) =>
    index >= _firstImageLine ? _heavyImageLine : 'שורה $index';

class _HeavyImagesRepository extends TextBookRepository {
  _HeavyImagesRepository() : super(fileSystem: FileSystemData.instance);

  final requestedLines = <int>{};

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
  }) async {
    final start = startLine.clamp(0, _totalLines - 1);
    final end = endLine.clamp(start, _totalLines - 1);
    final lines = <String>[];
    var chars = 0;
    for (var i = start; i <= end; i++) {
      final line = _line(i);
      lines.add(line);
      requestedLines.add(i);
      chars += line.length;
      if (maxChars != null && chars >= maxChars) break;
    }
    return BookContentRange(
      startLine: start,
      endLine: start + lines.length - 1,
      totalLines: _totalLines,
      lines: lines,
    );
  }
}

void main() {
  late _HeavyImagesRepository repository;
  late TextBookBloc bloc;
  final book = TextBook(title: 'ספר תמונות');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    repository = _HeavyImagesRepository();
    bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 0, true, const []),
    );
  });

  tearDown(() => bloc.close());

  testWidgets('חימום התוכן ברקע אינו טוען את כל התמונות המוטמעות לזיכרון', (
    tester,
  ) async {
    bloc.emit(
      TextBookLoaded(
        book: book,
        content: List<String>.filled(_totalLines, ''),
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
    );
    bloc.add(
      ApplyBookContentRanges(
        bookTitle: book.title,
        ranges: [
          (
            startLine: 0,
            totalLines: _totalLines,
            lines: [for (var i = 0; i < 100; i++) _line(i)],
          ),
        ],
      ),
    );
    await tester.pump();
    // טאב שחוזר לחזית מפעיל את החימום.
    bloc.add(const SetTabVisibility(false));
    bloc.add(const SetTabVisibility(true));
    // הבלוק נוצר מחוץ ל-FakeAsync, ולכן ההשהיות שבחימום רצות בזמן אמיתי.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    final content = (bloc.state as TextBookLoaded).content;
    final loadedImages = content.where((line) => line.length > 1000).length;
    final heavyRequested = repository.requestedLines
        .where((line) => line >= _firstImageLine)
        .length;

    // הטקסט שלפני התמונות מחומם כרגיל.
    expect(content[_firstImageLine - 1], 'שורה ${_firstImageLine - 1}');
    expect(loadedImages, lessThan(_totalLines - _firstImageLine));
    expect(heavyRequested, lessThan(_totalLines - _firstImageLine));
  });
}
