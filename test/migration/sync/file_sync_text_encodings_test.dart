// אינטגרציה: ספרים בכל קידוד עוברים את השרשרת המלאה — סריקת תיקייה מותאמת →
// שורות ו-TOC ב-SQLite → קריאה חזרה (§51, §70, §71).
//
// הרגרסיה שהבדיקה מונעת: ג'יבריש שנכנס לבסיס הנתונים נראה כספר תקין לכל
// השכבות שמעליו — הקורא, החיפוש, ההערות והסימניות — ואי אפשר לתקן אותו בלי
// סריקה מחדש. בדיקות היחידה של המפענח אינן עוברות דרך הסורק, הגנרטור וה-DB.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:path/path.dart' as path;

import '../../../tool/generate_text_encoding_fixtures.dart';

/// גוף הספר: אותיות עבריות ו-ASCII בלבד, כדי שכל הקידודים — כולל CP862
/// ו-ISO-8859-8 — יוכלו לייצג אותו, וכך אפשר להשוות ביניהם.
List<String> bookLines(String title) => [
  '<h1>$title</h1>',
  'מאימתי קורין את שמע בערבית, משעה שהכהנים נכנסים לאכול בתרומתן.',
  'עד סוף האשמורה הראשונה, דברי רבי אליעזר, וחכמים אומרים עד חצות.',
  'שורה עם ASCII ומספרים: Chapter 1, page 12.',
];

/// כל הקידודים שהצנרת אמורה לעכל, וכיצד לכתוב בהם קובץ.
final Map<String, Uint8List Function(String)> encoders = {
  'utf8': (text) => Uint8List.fromList(utf8.encode(text)),
  'utf8_bom': (text) =>
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]),
  'utf16le_bom': (text) => encodeUtf16(text, littleEndian: true, bom: true),
  'utf16be_bom': (text) => encodeUtf16(text, littleEndian: false, bom: true),
  'utf16le': (text) => encodeUtf16(text, littleEndian: true),
  'utf16be': (text) => encodeUtf16(text, littleEndian: false),
  'utf32le_bom': (text) => encodeUtf32(text, littleEndian: true, bom: true),
  'windows1255': (text) => encodeLegacy(text, TextEncoding.windows1255),
  'iso88598': (text) => encodeLegacy(text, TextEncoding.iso88598),
  'cp862': (text) => encodeLegacy(text, TextEncoding.cp862),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory booksDir;
  late MyDatabase database;
  late SeforimRepository repository;
  late String libraryPath;
  late List<CustomFolder> folders;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-encodings-sync-');
    booksDir = Directory(path.join(tempDir.path, 'ספרים אישיים'))
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
        // עותק עצמאי: התוכן נכנס ל-SQLite — זה המסלול שהבדיקה בודקת.
        addToDatabase: true,
        addedAt: DateTime(2026, 8, 18),
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

  /// כותב ספר בשם [title] בקידוד [encoding] ומחזיר את השורות שנכתבו.
  List<String> writeBook(String title, String encoding) {
    final lines = bookLines(title);
    File(
      path.join(booksDir.path, '$title.txt'),
    ).writeAsBytesSync(encoders[encoding]!(lines.join('\n')));
    return lines;
  }

  test('ספר בכל קידוד נכנס ל-SQLite כטקסט קריא', () async {
    final expected = <String, List<String>>{};
    for (final encoding in encoders.keys) {
      final title = 'ספר $encoding';
      expected[title] = writeBook(title, encoding);
    }

    final result = await sync();
    expect(result.errors, isEmpty);

    final books = await repository.getAllBooksLean();
    expect(books.map((book) => book.title).toSet(), expected.keys.toSet());

    for (final book in books) {
      final lines = await repository.getLineContents(book.id);
      expect(
        lines,
        expected[book.title],
        reason: '${book.title}: השורות ב-DB אינן הטקסט המקורי',
      );
      expect(book.totalLines, expected[book.title]!.length);

      final toc = await repository.getBookToc(book.id);
      expect(toc, isNotEmpty, reason: '${book.title}: אין TOC');
      expect(
        toc.first.text,
        contains(book.title),
        reason: '${book.title}: כותרת ה-TOC אינה קריאה',
      );
    }
  });

  test('ייבוא מרובה בקידודים מעורבים — ללא שגיאות ובלי ג׳יבריש', () async {
    // §71: ריצת ייבוא על קורפוס משמעותי, ודיווח התפלגות הזיהוי וזמן הריצה.
    const copiesPerEncoding = 6;
    final expected = <String, List<String>>{};
    for (final encoding in encoders.keys) {
      for (var copy = 1; copy <= copiesPerEncoding; copy++) {
        final title = 'ספר $encoding $copy';
        expected[title] = writeBook(title, encoding);
      }
    }

    final watch = Stopwatch()..start();
    final result = await sync();
    final elapsed = watch.elapsedMilliseconds;

    expect(result.errors, isEmpty);
    final books = await repository.getAllBooksLean();
    expect(books.length, expected.length);

    var mismatches = 0;
    for (final book in books) {
      final lines = await repository.getLineContents(book.id);
      if (lines.join('\n') != expected[book.title]!.join('\n')) mismatches++;
    }
    expect(mismatches, 0);

    // התפלגות הזיהוי נמדדת מול אותם בייטים שנסרקו, לצורכי טלמטריה (§72).
    final distribution = <TextEncoding, int>{};
    var lowConfidence = 0;
    for (final file in booksDir.listSync().whereType<File>()) {
      final detection = detectTextEncoding(file.readAsBytesSync());
      distribution.update(
        detection.encoding,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (detection.lowConfidence) lowConfidence++;
    }

    stdout.writeln(
      'ייבוא ${books.length} ספרים ב-$elapsed מילישניות '
      '(${result.addedBooks} נוספו)',
    );
    for (final entry in distribution.entries) {
      stdout.writeln('  ${entry.key.label}: ${entry.value}');
    }
    stdout.writeln('  ודאות נמוכה: $lowConfidence');

    expect(lowConfidence, 0);
    // וריאנטי ה-BOM מתלכדים עם הקידוד שלהם, ו-ISO-8859-8 בטקסט ללא בתים
    // מבדילים מדווח כ-Windows-1255 (§29).
    expect(distribution, {
      TextEncoding.utf8: 2 * copiesPerEncoding,
      TextEncoding.utf16LE: 2 * copiesPerEncoding,
      TextEncoding.utf16BE: 2 * copiesPerEncoding,
      TextEncoding.utf32LE: copiesPerEncoding,
      TextEncoding.windows1255: 2 * copiesPerEncoding,
      TextEncoding.cp862: copiesPerEncoding,
    });
  });

  test('סריקה חוזרת אינה משנה את התוכן שנשמר', () async {
    final expected = <String, List<String>>{};
    for (final encoding in ['windows1255', 'cp862', 'utf16le']) {
      final title = 'ספר $encoding';
      expected[title] = writeBook(title, encoding);
    }
    await sync();
    final second = await sync();

    expect(second.addedBooks, 0);
    expect(second.updatedBooks, 0);
    for (final book in await repository.getAllBooksLean()) {
      expect(
        await repository.getLineContents(book.id),
        expected[book.title],
        reason: '${book.title}: התוכן השתנה בסריקה חוזרת',
      );
    }
  });
}
