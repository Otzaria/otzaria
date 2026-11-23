import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../helpers/memory_settings_cache.dart';

const _totalLines = 6000;

/// רושם את בקשות טעינת הטווח — כך נמדד אם החימום ברקע פעיל.
class _CountingRepository extends TextBookRepository {
  _CountingRepository() : super(fileSystem: FileSystemData.instance);

  final _lines = List.generate(_totalLines, (i) => 'שורה $i');
  final requestedEnds = <int>[];

  @override
  Future<List<String>> getBookLines(TextBook book) async {
    final content = await getBookContent(book);
    return content.isEmpty ? const [] : content.split('\n');
  }

  @override
  Future<String> getBookContent(TextBook book) async => _lines.join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async {
    requestedEnds.add(endLine);
    final start = startLine.clamp(0, _totalLines - 1);
    final end = endLine.clamp(start, _totalLines - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: _totalLines,
      lines: _lines.sublist(start, end + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];
}

Future<void> _waitFor(bool Function() condition, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('לא התקיים בזמן: $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// התצוגה המקדימה פתוחה כברירת מחדל ונשמרת בזיכרון: חימום היה טוען בה את
/// הספר כולו ומחזיק אותו כל ההפעלה, גם כשהיא מוסתרת.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingRepository repository;
  late TextBookBloc bloc;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final book = TextBook(title: 'ספר בדיקה');
    repository = _CountingRepository();
    bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 0, false, const []),
    );
    buildPreviewTextTab(book: book, targetIndex: null, blocOverride: bloc);
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    await _waitFor(() => bloc.state is TextBookLoaded, 'מצב טעון');
  });

  tearDown(() async {
    await bloc.close();
  });

  test('התצוגה המקדימה אינה מחממת את הספר כולו ברקע', () async {
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // החימום מבקש מקטעים של 640 שורות מעבר לחלון הפתיחה (שורות 0–260).
    expect(repository.requestedEnds, everyElement(lessThan(640)));
  });

  test('גלילה רחוקה עדיין טוענת את הטווח הנראה לפי דרישה', () async {
    bloc.add(const UpdateVisibleIndecies([5000]));

    await _waitFor(() {
      final state = bloc.state;
      return state is TextBookLoaded &&
          state.content.length == _totalLines &&
          state.content[5000] == 'שורה 5000';
    }, 'השורה הנראית נטענה');
  });
}
