import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/default_commentators.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:path/path.dart' as path;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

/// טעינת המפרשים זורקת; שאר הנתיבים מחזירים ספר קטן בלי קישורים.
class _FailingCommentatorsRepository extends TextBookRepository {
  _FailingCommentatorsRepository() : super(fileSystem: FileSystemData.instance);

  int commentatorCalls = 0;

  @override
  Future<String> getBookContent(TextBook book) async =>
      List.generate(10, (i) => 'שורה $i').join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final lines = List.generate(10, (i) => 'שורה $i');
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
    commentatorCalls++;
    throw const DbReadWorkerSuspended();
  }

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  final bereshit = TextBook(
    title: SeforimFixtureIds.bereshitTitle,
    source: BookSource.official,
    categoryId: SeforimFixtureIds.torahCategoryId,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-i3081-');
    final fixture = SeforimFixtureDb.create(
      tempDir,
      SeforimFixtureVariant.full,
    );
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      fixture,
    );
    // כמו חלון ממוחזר: החיבור נפתח ונסגר, ואיש לא פתח אותו מחדש.
    await SqliteDataProvider.instance.initialize();
    await SqliteDataProvider.instance.dispose();
  });

  tearDown(() async {
    TextBookBloc.logCommentatorsFailuresInDebug = false;
    await DbReadWorker.resumeAfterExternalWrite();
    await SqliteDataProvider.instance.dispose();
    DbReadWorker.disposeForTesting();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ב-Windows שחרור ה-handle אינו מיידי; ה-temp אינו הנבדק.
    }
  });

  test('חיבור סגור: רשימת המפרשים נטענת ואינה ריקה (#3081)', () async {
    expect(SqliteDataProvider.instance.isInitialized, isFalse);
    final repository = TextBookRepository(fileSystem: FileSystemData.instance);

    final result = await repository.getCommentatorsWithRarity(bereshit);

    expect(result.all, contains(SeforimFixtureIds.rashiTitle));
    expect(repository.isLibraryConnectionOpen, isTrue);
  });

  test('חיבור סגור: מפרשי ברירת המחדל נטענים (#3081)', () async {
    final defaults = await DefaultCommentators.fetchDefaults(bereshit);

    expect(
      defaults.commentators.map((c) => c.title),
      contains(SeforimFixtureIds.rashiTitle),
    );
  });

  test('worker מושהה: השאילתה עוברת לחיבור הראשי ולא נכשלת', () async {
    await SqliteDataProvider.instance.initialize();
    await DbReadWorker.suspendForExternalWrite();
    final repository = TextBookRepository(fileSystem: FileSystemData.instance);

    final result = await repository.getCommentatorsWithRarity(bereshit);

    expect(result.all, contains(SeforimFixtureIds.rashiTitle));
  });

  test('החלפת ספרייה בעיצומה: הטעינה ממתינה לפתיחה מחדש', () async {
    await SqliteDataProvider.instance.initialize();
    await SqliteDataProvider.instance.closeForExternalWrite();
    final repository = TextBookRepository(fileSystem: FileSystemData.instance);

    var done = false;
    final pending = repository
        .getCommentatorsWithRarity(bereshit)
        .whenComplete(() => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(done, isFalse, reason: 'אסור לקרוא בזמן הכתיבה החיצונית');

    await SqliteDataProvider.instance.reopenAfterExternalWrite();
    final result = await pending.timeout(const Duration(seconds: 10));
    expect(result.all, contains(SeforimFixtureIds.rashiTitle));
  });

  test('כשל בטעינת המפרשים נרשם ל-errors.txt עם ההקשר', () async {
    TextBookBloc.logCommentatorsFailuresInDebug = true;
    final repository = _FailingCommentatorsRepository();
    final book = TextBook(title: 'ספר בדיקה', source: BookSource.user);
    final bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 0, false, const []),
    );
    addTearDown(bloc.close);

    final log = File(
      path.join(tempDir.path, 'data_root', 'logs', 'errors.txt'),
    );
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: true,
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (repository.commentatorCalls < 1 || !log.existsSync()) {
      if (DateTime.now().isAfter(deadline)) fail('הכשל לא נרשם');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final text = log.readAsStringSync();
    expect('כשל בטעינת רשימת המפרשים'.allMatches(text).length, 1);
    expect(text, contains('ספר בדיקה'));
    expect(text, contains('DbReadWorkerSuspended'));
    expect(text, contains('libraryConnectionOpen'));
    expect(text, contains('secondaryWindow'));
  });
}
