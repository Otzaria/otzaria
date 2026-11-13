import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

PathAccessException _lockedFile() => const PathAccessException(
  'כריתות סיכום.docx',
  OSError('The process cannot access the file', 32),
  'Cannot open file',
);

/// קובץ שנעול בידי תוכנה אחרת: גם התוכן וגם תוכן העניינים נכשלים.
class _LockedFileRepository extends TextBookRepository {
  _LockedFileRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
  }) async => throw _lockedFile();

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    throw _lockedFile();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDataRoot;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    tempDataRoot = Directory.systemTemp.createTempSync('toc-error-test-');
    AppPaths.debugOverrideDataRootPath(tempDataRoot.path);
  });

  tearDown(() {
    AppPaths.debugOverrideDataRootPath(null);
    if (tempDataRoot.existsSync()) tempDataRoot.deleteSync(recursive: true);
  });

  test('כשטעינת התוכן נכשלת, השגיאה של תוכן העניינים אינה נזרקת כלא-מטופלת '
      '(issue #4915)', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      final book = TextBook(title: 'כריתות סיכום', source: BookSource.user);
      final bloc = TextBookBloc(
        repository: _LockedFileRepository(),
        initialState: TextBookInitial.named(book, 0, false, const []),
      );

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );
      final error = await bloc.stream
          .firstWhere((s) => s is TextBookError)
          .timeout(const Duration(seconds: 10));
      expect((error as TextBookError).message, contains('Cannot open file'));

      // מחכים שתוכן העניינים ייכשל אחרי שהטעינה כבר הסתיימה בשגיאה.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await bloc.close();
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });
}
