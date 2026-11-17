import 'dart:io' hide Link;
import 'dart:io' as io show Link;

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileSystemLibraryProvider bundled talmud bavli', () {
    late Directory tempDir;

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      tempDir = await Directory.systemTemp.createTemp('otzaria_fs_provider_');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        tempDir.path,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        'Otzaria',
      );
      FileSystemLibraryProvider.instance.resetForTesting();
    });

    tearDown(() async {
      FileSystemLibraryProvider.instance.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'loads Brakhot PDF from bundled talmud bavli folder at library root',
      () async {
        final talmudDir = Directory(
          path.join(
            tempDir.path,
            DatabaseConstants.talmudBavliFolderName,
          ),
        );
        await talmudDir.create(recursive: true);

        final pdfPath = path.join(talmudDir.path, 'ברכות.pdf');
        await File(pdfPath).writeAsBytes(const [37, 80, 68, 70]);

        final provider = FileSystemLibraryProvider.instance;
        await provider.initialize();

        final booksByCategory = await provider.loadBooks({});
        final talmudBooks =
            booksByCategory[DatabaseConstants.talmudBavliFolderName];

        expect(talmudBooks, isNotNull);
        expect(talmudBooks, hasLength(1));
        expect(talmudBooks!.single, isA<PdfBook>());
        expect(talmudBooks.single.title, 'ברכות');

        final keyToPath = await provider.keyToPath;
        final storageKey = BookCompositeKey.create(
          title: 'ברכות',
          categoryId: DatabaseConstants.talmudBavliFolderName.hashCode,
          fileType: 'pdf',
        ).toStorageKey();

        expect(keyToPath[storageKey], pdfPath);
      },
    );

    test('טעינה מקבילה מספקת נתיבים לקטלוג ולמפתחות ישנים', () async {
      final personalDir = Directory(
        path.join(tempDir.path, 'אוצריא', 'אישי', 'הלכה.מהדורה'),
      );
      await personalDir.create(recursive: true);
      final file = await File(
        path.join(personalDir.path, 'ספר.TXT'),
      ).writeAsString('טקסט');

      final provider = FileSystemLibraryProvider.instance;
      final physicalPathsFuture = provider.physicalKeyToPath;
      final catalogFuture = provider.loadBooks({});
      final book = (await catalogFuture)['הלכה']!.single;
      final physicalPaths = await physicalPathsFuture;
      final paths = await provider.keyToPath;

      expect(physicalPaths.values, [file.path]);
      expect(await provider.physicalKeyToPath, same(physicalPaths));
      expect(book.categoryPath, 'ספרים אישיים, הלכה');
      for (final categoryPath in [
        'ספרים אישיים, הלכה',
        'ספרים אישיים, הלכה.מהדורה',
      ]) {
        final key = BookCompositeKey.create(
          title: 'ספר',
          categoryId: categoryPath.hashCode,
          fileType: 'txt',
        ).toStorageKey();
        expect(paths[key], file.path);
      }
    });

    test('שם תצוגה זהה שומר נתיב מדויק לכל תיקייה', () async {
      final personalDir = path.join(tempDir.path, 'אוצריא', 'אישי');
      final expectedPaths = <String, String>{};
      for (final name in ['הלכה', 'הלכה.מהדורה']) {
        final dir = await Directory(path.join(personalDir, name)).create(
          recursive: true,
        );
        final file = await File(
          path.join(dir.path, 'ספר.txt'),
        ).writeAsString(name);
        final key = BookCompositeKey.create(
          title: 'ספר',
          categoryId: 'ספרים אישיים, $name'.hashCode,
          fileType: 'txt',
        ).toStorageKey();
        expectedPaths[key] = file.path;
      }

      final provider = FileSystemLibraryProvider.instance;
      final books = (await provider.loadBooks({}))['הלכה']!;
      final paths = await provider.keyToPath;

      expect(books, hasLength(2));
      expect(paths, expectedPaths);
      expect({
        for (final book in books)
          BookCompositeKey.fromBook(book)!.toStorageKey(): book.filePath,
      }, expectedPaths);
    });

    test('כינוי משותף שומר את ההתאמה מסוף הסריקה', () async {
      for (final name in ['הלכה.א', 'הלכה.ב']) {
        final dir = await Directory(
          path.join(tempDir.path, 'אוצריא', 'אישי', name),
        ).create(recursive: true);
        await File(path.join(dir.path, 'ספר.txt')).writeAsString(name);
      }
      final provider = FileSystemLibraryProvider.instance;
      final books = (await provider.loadBooks({}))['הלכה']!;
      final physicalPaths = await provider.physicalKeyToPath;
      final alias = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 'ספרים אישיים, הלכה'.hashCode,
        fileType: 'txt',
      ).toStorageKey();

      final paths = await provider.keyToPath;
      expect(paths[alias], physicalPaths.values.last);
      expect(books.map((book) => book.categoryId).toSet(), hasLength(2));
      for (final book in books) {
        final key = BookCompositeKey.fromBook(book)!.toStorageKey();
        expect(paths[key], book.filePath);
      }
    });

    test('סריקת ספרים בקישור סמלי מחזורי מסתיימת', () async {
      final personalDir = Directory(path.join(tempDir.path, 'אוצריא', 'אישי'));
      await personalDir.create(recursive: true);
      final file = await File(
        path.join(personalDir.path, 'ספר.txt'),
      ).writeAsString('טקסט');
      final link = await io.Link(path.join(personalDir.path, 'חזרה')).create(
        personalDir.path,
      );

      final provider = FileSystemLibraryProvider.instance;
      final books = await provider.loadBooks({});

      expect(books['ספרים אישיים']!.single.title, 'ספר');
      expect(books['חזרה']!.single.title, 'ספר');
      expect(
        (await provider.keyToPath).values,
        unorderedEquals([
          file.path,
          path.join(link.path, 'ספר.txt'),
        ]),
      );
    }, skip: Platform.isWindows);

    test('טעינה מחדש מסירה נתיב שנמחק ומוסיפה ספר חדש', () async {
      final personalDir = Directory(path.join(tempDir.path, 'אוצריא', 'אישי'));
      await personalDir.create(recursive: true);
      final before = await File(
        path.join(personalDir.path, 'לפני.txt'),
      ).writeAsString('טקסט');
      final provider = FileSystemLibraryProvider.instance;
      await provider.loadBooks({});
      expect((await provider.keyToPath).values, [before.path]);

      await before.delete();
      final after = await File(
        path.join(personalDir.path, 'אחרי.txt'),
      ).writeAsString('טקסט');
      final books = await provider.loadBooks({
        'אחרי': {'author': 'מחבר'},
      });

      expect(books['ספרים אישיים']!.single.title, 'אחרי');
      expect(books['ספרים אישיים']!.single.author, 'מחבר');
      expect((await provider.keyToPath).values, [after.path]);
    });

    test('סריקה שהחלה לפני איפוס אינה מעדכנת את מפת הספרייה החדשה', () async {
      final oldDir = Directory(path.join(tempDir.path, 'אוצריא', 'אישי'));
      await oldDir.create(recursive: true);
      final oldFile = await File(
        path.join(oldDir.path, 'ישן.txt'),
      ).writeAsString('טקסט');
      final newRoot = Directory(path.join(tempDir.path, 'ספרייה חדשה'));
      final newDir = Directory(path.join(newRoot.path, 'אוצריא', 'אישי'));
      await newDir.create(recursive: true);
      final newFile = await File(
        path.join(newDir.path, 'חדש.txt'),
      ).writeAsString('טקסט');

      final provider = FileSystemLibraryProvider.instance;
      final oldScan = provider.keyToPath;
      provider.resetRuntimeState();
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        newRoot.path,
      );

      expect((await oldScan).values, [oldFile.path]);
      expect((await provider.keyToPath).values, [newFile.path]);
    });

    test('תוכן קישור שומר טווחי שורות, CRLF ושורות ריקות', () async {
      final personalDir = Directory(path.join(tempDir.path, 'אוצריא', 'אישי'));
      await personalDir.create(recursive: true);
      await File(path.join(personalDir.path, 'ספר.txt')).writeAsString(
        'ראשונה\r\n\r\nשלישית\r\nרביעית\r\n',
      );
      final provider = FileSystemLibraryProvider.instance;
      await provider.initialize();
      await provider.loadBooks({});
      Future<List<LinkContentLine>> read(int start, [int? end]) =>
          provider.getLinkContentLines(
            Link(
              heRef: 'ספר',
              index1: 1,
              path2: 'ספר',
              index2: start,
              index2End: end,
              connectionType: 'reference',
            ),
          );

      expect(await read(2, 3), [
        (lineIndex: 1, content: ''),
        (lineIndex: 2, content: 'שלישית'),
      ]);
      expect(await read(3, 99), [
        (lineIndex: 2, content: 'שלישית'),
        (lineIndex: 3, content: 'רביעית'),
      ]);
      expect(await read(3, 1), [(lineIndex: 2, content: 'שלישית')]);
      expect(await read(1), [(lineIndex: 0, content: 'ראשונה')]);
      expect(await read(0), [
        (lineIndex: -1, content: 'שגיאה: אינדקס לא תקין'),
      ]);
      expect(await read(5), [
        (lineIndex: 4, content: 'שגיאה: אינדקס מחוץ לטווח'),
      ]);
    });

    test('מסווג TXT, DOCX ו-EPUB תאומים כסוגים נפרדים', () async {
      final personalDir = Directory(path.join(tempDir.path, 'אוצריא', 'אישי'));
      await personalDir.create(recursive: true);
      final txtPath = path.join(personalDir.path, 'ספר.txt');
      final docxPath = path.join(personalDir.path, 'ספר.docx');
      final epubPath = path.join(personalDir.path, 'ספר.epub');
      await File(txtPath).writeAsString('טקסט');
      await File(docxPath).writeAsBytes(const [1]);
      await File(epubPath).writeAsBytes(const [2]);

      final provider = FileSystemLibraryProvider.instance;
      await provider.initialize();
      final books = (await provider.loadBooks({}))['ספרים אישיים']!;

      expect(books.whereType<TextBook>().single.fileType, 'txt');
      expect(books.whereType<DocxBook>().single.fileType, 'docx');
      expect(books.whereType<EpubBook>().single.fileType, 'epub');
      expect(books.whereType<EpubBook>().single.path, epubPath);

      final categoryId = 'ספרים אישיים'.hashCode;
      final keyToPath = await provider.keyToPath;
      for (final entry in {
        'txt': txtPath,
        'docx': docxPath,
        'epub': epubPath,
      }.entries) {
        final key = BookCompositeKey.create(
          title: 'ספר',
          categoryId: categoryId,
          fileType: entry.key,
        ).toStorageKey();
        expect(keyToPath[key], entry.value);
      }
    });

    test('סורק תיקיות אישיות מקוננות ומזהה מסמכים לפי תוכן', () async {
      final nestedDir = Directory(
        path.join(tempDir.path, 'אוצריא', 'אישי', 'תיקייה', 'נושא'),
      );
      await nestedDir.create(recursive: true);
      final wordPath = path.join(nestedDir.path, 'מסמך.xml');
      await File(wordPath).writeAsString(
        '<?xml version="1.0"?>'
        '<w:wordDocument '
        'xmlns:w="http://schemas.microsoft.com/office/word/2003/wordml">'
        '<w:body/></w:wordDocument>',
      );
      await File(
        path.join(nestedDir.path, 'הגדרות.xml'),
      ).writeAsString('<?xml version="1.0"?><config/>');
      await File(path.join(nestedDir.path, 'גיבוי.wbk')).writeAsString('טקסט');

      final provider = FileSystemLibraryProvider.instance;
      final books = await provider.loadBooks({});

      final book = books['נושא']!.single;
      expect(book.title, 'מסמך');
      expect(book.fileType, 'xml');
      expect(book.categoryPath, 'ספרים אישיים, תיקייה, נושא');
      final key = BookCompositeKey.create(
        title: book.title,
        categoryId: book.categoryId!,
        fileType: 'xml',
      ).toStorageKey();
      expect(await provider.keyToPath, {key: wordPath});
    });
  });
}
