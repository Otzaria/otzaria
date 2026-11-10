import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  final book = TextBook(title: 'בישול ראשונים', fileType: 'txt');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test(
    'שורות החיפוש באות מהמקור של הקורא כשהוא טוען טווחים (issue #3234)',
    () async {
      // הקובץ שבדיסק נערך: שורה נוספה בראשו, והמסד עדיין במצבו הקודם.
      final repository = _FakeRepository(
        range: const ['כותרת', 'אסור מפני צרכו'],
        fileText: 'שורה חדשה\nכותרת\nאסור מפני צרכו',
      );

      final lines = await repository.getBookLines(book);

      expect(lines, ['כותרת', 'אסור מפני צרכו']);
      expect(lines.indexOf('אסור מפני צרכו'), 1);
    },
  );

  test('בלי טווחים (Markdown ודומיו) נטען התוכן המלא, כמו בקורא', () async {
    final repository = _FakeRepository(range: null, fileText: 'א\nב');

    expect(await repository.getBookLines(book), ['א', 'ב']);
  });
}

class _FakeRepository extends TextBookRepository {
  _FakeRepository({required this.range, required this.fileText})
    : super(fileSystem: FileSystemData.instance);

  final List<String>? range;
  final String fileText;

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final lines = range;
    if (lines == null) return null;
    return BookContentRange(
      startLine: 0,
      endLine: lines.length - 1,
      totalLines: lines.length,
      lines: lines,
    );
  }

  @override
  Future<String> getBookContent(TextBook book) async => fileText;
}
