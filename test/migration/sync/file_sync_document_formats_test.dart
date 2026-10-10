// אינטגרציה: תיקייה מותאמת עם כל פורמטי המסמכים עוברת את השרשרת המלאה —
// סריקה → הכנסה ל-DB עם fileType נכון → קריאת תוכן → זיהוי שינוי (§88, §90,
// §91).
//
// הבדיקות בקובץ ה-fixtures הבודקות ממיר אחד אינן מספיקות: הן אינן עוברות
// דרך הסורק, ה-DB ושכבת ה-provider, ושם נמצאות הטעויות של `fileType` שגוי
// או ספר שנסרק אך אינו נקרא.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:path/path.dart' as path;

import '../../utils/file/docx_golden_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory booksDir;
  late MyDatabase database;
  late SeforimRepository repository;
  late String libraryPath;
  late List<CustomFolder> folders;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-doc-formats-');
    booksDir = Directory(path.join(tempDir.path, 'ספרים'))
      ..createSync(recursive: true);
    Directory(
      path.join(tempDir.path, 'library', 'אוצריא'),
    ).createSync(recursive: true);

    FileSyncService.resetSingletonForTesting();
    database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();

    libraryPath = path.join(tempDir.path, 'library');
    folders = [
      CustomFolder(
        path: booksDir.path,
        addToDatabase: false, // קריאה מהקבצים — הנתיב הרלוונטי לפורמטים
        addedAt: DateTime(2026, 8, 9),
      ),
    ];
  });

  tearDown(() async {
    database.close();
    FileSyncService.resetSingletonForTesting();
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // נעילת קובץ ב-Windows אינה מעניינה של הבדיקה.
    }
  });

  Future<FileSyncResult> sync() async {
    final service = await FileSyncService.getInstance(
      repository,
      userBooksRepository: repository,
    );
    return service!.syncCustomFoldersWithInputs(
      libraryPath: libraryPath,
      customFolders: folders,
    );
  }

  /// כותב DOCX מינימלי עם הפסקה הנתונה.
  void writeDocx(String name, String paragraph) {
    File(path.join(booksDir.path, name)).writeAsBytesSync(
      buildDocx(document: documentXml(para(paragraph))),
    );
  }

  void writeOdt(String name, String paragraph) {
    File(path.join(booksDir.path, name)).writeAsBytesSync(
      _odtBytes(paragraph),
    );
  }

  void writeRtf(String name, String paragraph) {
    File(
      path.join(booksDir.path, name),
    ).writeAsStringSync('{\\rtf1\\ansi $paragraph\\par}');
  }

  void writeHtml(String name, String body) {
    File(
      path.join(booksDir.path, name),
    ).writeAsStringSync('<html><body>$body</body></html>');
  }

  test('כל הפורמטים נסרקים ונשמרים עם fileType נכון', () async {
    writeDocx('מסמך.docx', 'תוכן DOCX');
    writeDocx('מאקרו.docm', 'תוכן DOCM');
    writeDocx('תבנית.dotx', 'תוכן DOTX');
    writeOdt('פתוח.odt', 'תוכן ODT');
    writeRtf('עשיר.rtf', 'תוכן RTF');
    writeHtml('דף.html', '<p>תוכן HTML</p>');
    writeHtml('ישן.htm', '<p>תוכן HTM</p>');
    File(
      path.join(booksDir.path, 'טקסט.txt'),
    ).writeAsStringSync('<h1>כותרת</h1>\nתוכן');

    final result = await sync();
    expect(result.errors, isEmpty);

    final books = await repository.getAllBooksLean();
    final byTitle = {for (final b in books) b.title: b};

    expect(
      byTitle.keys,
      containsAll(['מסמך', 'מאקרו', 'תבנית', 'פתוח', 'עשיר', 'דף', 'ישן']),
    );
    expect(byTitle['מסמך']!.fileType, 'docx');
    expect(byTitle['מאקרו']!.fileType, 'docm');
    expect(byTitle['תבנית']!.fileType, 'dotx');
    expect(byTitle['פתוח']!.fileType, 'odt');
    expect(byTitle['עשיר']!.fileType, 'rtf');
    // ‏‎.htm‎ אינו ממופה ל-‎.html‎: ‏`fileType` הוא חלק מזהות הספר (§15).
    expect(byTitle['דף']!.fileType, 'html');
    expect(byTitle['ישן']!.fileType, 'htm');
  });

  test('ספר HTML נקרא מומר — ובלי הסקריפט שהיה בקובץ', () async {
    writeHtml(
      'שיעור.html',
      '<script>alert(1)</script><h1>פרק א</h1><p>גוף השיעור</p>',
    );

    expect((await sync()).errors, isEmpty);

    final book = (await repository.getAllBooksLean()).firstWhere(
      (b) => b.title == 'שיעור',
    );
    final text = await readFileBackedBookText(
      File(book.filePath!),
      book.fileType,
      book.title,
    );

    expect(text, startsWith('<h1>שיעור</h1>'));
    expect(text, contains('<h2>פרק א</h2>'));
    expect(text, contains('גוף השיעור'));
    expect(text, isNot(contains('alert')));
  });

  test('‎.xml‎ נאסף רק כשתוכנו מסמך Word', () async {
    // הסיומת גנרית: בלי שער התוכן כל קובץ הגדרות בתיקייה היה הופך ל"ספר"
    // פגום שנכשל בפתיחה.
    File(path.join(booksDir.path, 'מסמך וורד.xml')).writeAsStringSync(
      '<?xml version="1.0"?>'
      '<?mso-application progid="Word.Document"?>'
      '<pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/'
      'xmlPackage"><pkg:part pkg:name="/word/document.xml" '
      'pkg:contentType="application/xml"><pkg:xmlData>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/'
      'wordprocessingml/2006/main"><w:body><w:p><w:r>'
      '<w:t>תוכן XML</w:t></w:r></w:p></w:body></w:document>'
      '</pkg:xmlData></pkg:part></pkg:package>',
    );
    File(path.join(booksDir.path, 'הגדרות.xml')).writeAsStringSync(
      '<?xml version="1.0"?><config><item>ערך</item></config>',
    );

    final result = await sync();
    expect(result.errors, isEmpty);

    final titles = (await repository.getAllBooksLean())
        .map((b) => b.title)
        .toSet();
    expect(titles, contains('מסמך וורד'));
    expect(titles, isNot(contains('הגדרות')));
  });

  test('ספר שנסרק אכן נקרא דרך הנתיב שנשמר ב-DB', () async {
    writeDocx('מסמך.docx', 'תוכן שנשמר');
    writeOdt('פתוח.odt', 'תוכן פתוח');
    writeRtf('עשיר.rtf', 'תוכן עשיר');

    await sync();

    final books = await repository.getAllBooksLean();
    for (final book in books) {
      expect(
        book.filePath,
        isNotNull,
        reason: '${book.title} אינו file-backed',
      );
      final text = await readFileBackedBookText(
        File(book.filePath!),
        book.fileType,
        book.title,
      );
      expect(text, isNotNull, reason: book.title);
      expect(text, contains('תוכן'), reason: book.title);
      expect(text, contains('<h1>${book.title}</h1>'), reason: book.title);
    }
  });

  test('קובץ שהשתנה נסרק מחדש ושומר את מזהה הספר (§90)', () async {
    writeDocx('מסמך.docx', 'הגרסה הראשונה');
    await sync();

    final before = (await repository.getAllBooksLean()).single;
    expect(before.fileType, 'docx');

    // גודל שונה + זמן-שינוי מאוחר יותר: שני מרכיבי זיהוי-השינוי.
    final file = File(path.join(booksDir.path, 'מסמך.docx'));
    file.writeAsBytesSync(
      buildDocx(document: documentXml(para('הגרסה השנייה המורחבת מאוד'))),
    );
    file.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));

    final result = await sync();
    expect(result.errors, isEmpty);

    final after = (await repository.getAllBooksLean()).single;
    expect(after.id, before.id, reason: 'זהות הספר חייבת לשרוד עדכון קובץ');
    expect(after.fileType, 'docx');

    final text = await readFileBackedBookText(file, 'docx', after.title);
    expect(text, contains('הגרסה השנייה'));
    expect(text, isNot(contains('הגרסה הראשונה')));
  });

  test('סריקה חוזרת בלי שינוי אינה מוסיפה או מעדכנת (§91)', () async {
    writeDocx('מסמך.docx', 'תוכן');
    writeOdt('פתוח.odt', 'תוכן');
    final first = await sync();
    expect(first.addedBooks, greaterThan(0));

    final second = await sync();

    expect(second.addedBooks, 0);
    expect(second.updatedBooks, 0);
    expect(second.errors, isEmpty);
    expect((await repository.getAllBooksLean()).length, 2);
  });

  test('קובץ פגום נדחה בסנכרון ואינו נרשם כספר', () async {
    writeDocx('תקין.docx', 'תוכן תקין');
    File(
      path.join(booksDir.path, 'פגום.docx'),
    ).writeAsStringSync('זה בכלל לא ZIP');
    writeOdt('גם תקין.odt', 'תוכן נוסף');

    final result = await sync();

    expect(result.errors, hasLength(1));
    final books = await repository.getAllBooksLean();
    expect(
      books.map((b) => b.title),
      containsAll(['תקין', 'גם תקין']),
      reason: 'הקבצים התקינים נסרקו',
    );

    expect(books.map((b) => b.title), isNot(contains('פגום')));
  });
}

/// ODT מינימלי עם פסקה אחת.
List<int> _odtBytes(String paragraph) {
  const ns =
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"';
  final content = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-content $ns><office:body><office:text>'
    '<text:p>$paragraph</text:p>'
    '</office:text></office:body></office:document-content>',
  );
  final mimetype = utf8.encode('application/vnd.oasis.opendocument.text');

  final archive = Archive()
    ..addFile(ArchiveFile('mimetype', mimetype.length, mimetype))
    ..addFile(ArchiveFile('content.xml', content.length, content));
  return ZipEncoder().encode(archive);
}
