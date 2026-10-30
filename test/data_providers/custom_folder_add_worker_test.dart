import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    temp = await Directory.systemTemp.createTemp('custom-add-worker-');
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(temp.path, 'data'));
  });

  tearDown(() async {
    await UserBooksDatabaseHolder.instance.close();
    DatabaseLibraryProvider.instance.clearCache();
    AppPaths.debugOverrideDataRootPath(null);
    await temp.delete(recursive: true);
  });

  test(
    'הוספה ללא מסד רשמי שומרת נתיבים נפרדים ומדלגת על תיקייה מוסתרת',
    () async {
      final repo = await UserBooksDatabaseHolder.instance.repository;
      final bloc = CustomFoldersBloc(addLibraryEvent: (_) {});
      addTearDown(bloc.close);
      for (final root in ['a/books', 'b/books']) {
        final dir = Directory(p.join(temp.path, root))
          ..createSync(recursive: true);
        File(
          p.join(dir.path, 'same.txt'),
        ).writeAsStringSync('<h1>Heading</h1>');
        final hidden = Directory(p.join(dir.path, '.backup'))..createSync();
        File(p.join(hidden.path, 'hidden.txt')).writeAsStringSync('hidden');
        final finished = bloc.stream.firstWhere(
          (s) => !s.isSyncing && (s.message != null || s.error != null),
        );
        bloc.add(AddCustomFolder(dir.path));
        final state = await finished;
        expect(state.error, isNull);
        expect(state.message, '1 ספרים נוספו, 0 עודכנו');
      }
      final books = await repo.getAllBooksLean();
      expect(books, hasLength(2));
      expect(
        books.map((b) => b.filePath),
        unorderedEquals([
          p.join(temp.path, 'a/books/same.txt'),
          p.join(temp.path, 'b/books/same.txt'),
        ]),
      );
      for (final book in books) {
        expect((await repo.getBookToc(book.id)).map((e) => e.text), [
          'Heading',
        ]);
      }
    },
  );

  test('הוספת PDF שומרת את ה-outline במסד לצורך חיפוש מקורות', () async {
    Pdfrx.cacheDirectoryPath = temp.path;
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
    await pdfrxFlutterInitialize();
    final repo = await UserBooksDatabaseHolder.instance.repository;
    final folder = Directory(p.join(temp.path, 'pdfs'))..createSync();
    final objects = [
      '<< /Type /Catalog /Pages 2 0 R /Outlines 4 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>',
      '<< /Type /Outlines /First 5 0 R /Last 5 0 R /Count 1 >>',
      '<< /Title (Chapter One) /Parent 4 0 R /Dest [3 0 R /Fit] >>',
    ];
    final pdf = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(pdf.length);
      pdf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xref = pdf.length;
    pdf.write('xref\n0 6\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    pdf.write('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF');
    File(p.join(folder.path, 'book.pdf')).writeAsStringSync(pdf.toString());
    final bloc = CustomFoldersBloc(addLibraryEvent: (_) {});
    addTearDown(bloc.close);
    final finished = bloc.stream.firstWhere(
      (s) => !s.isSyncing && (s.message != null || s.error != null),
    );
    bloc.add(AddCustomFolder(folder.path));
    final state = await finished;
    expect(state.error, isNull);
    final book = (await repo.getAllBooksLean()).single;
    final toc = await repo.getBookToc(book.id);
    expect(toc.map((e) => e.text), ['Chapter One']);
    expect(toc.single.lineIndex, 1);
  });

  test('המתנה לכותב בזמן הוספה אינה חוסמת את isolate הממשק', () async {
    final repo = await UserBooksDatabaseHolder.instance.repository;
    final dir = Directory(p.join(temp.path, 'books'))..createSync();
    File(p.join(dir.path, 'book.txt')).writeAsStringSync('<h1>Heading</h1>');
    final writer = sqlite.sqlite3.open(repo.database.path);
    writer.execute('BEGIN IMMEDIATE');
    var released = false;
    addTearDown(() {
      if (!released) writer.execute('ROLLBACK');
      writer.close();
    });
    final elapsed = Stopwatch()..start();
    final release = Timer(const Duration(milliseconds: 300), () {
      writer.execute('ROLLBACK');
      released = true;
    });
    addTearDown(release.cancel);
    final result = await DatabaseLibraryProvider.instance
        .scanAndAddExternalBooksFromFolder(dir.path, 'books', repo);
    expect(released, isTrue);
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
    expect(result.fatalError, isNull);
    expect(result.addedBooks, 1);
    expect(await repo.getAllBooksLean(), hasLength(1));
  });
}
