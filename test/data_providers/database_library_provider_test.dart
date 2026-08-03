import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/library/models/library.dart' as library_models;
import 'package:otzaria/migration/models/author.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/utils/pdf_links_window.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// בונה DOCX מינימלי תקין (ZIP עם word/document.xml) המכיל פסקה אחת.
Uint8List _buildMinimalDocx(String paragraphText) {
  final documentXml = utf8.encode('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:t>$paragraphText</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''');
  final archive = Archive()
    ..addFile(
      ArchiveFile('word/document.xml', documentXml.length, documentXml),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseLibraryProvider', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('shouldIncludeBookByPath מסנן ספרי תלמוד בבלי כשהתיקייה חסרה', () {
      final filePath = path.join(
        '/library',
        DatabaseConstants.otzariaFolderName,
        DatabaseConstants.talmudBavliFolderName,
        'ברכות א.pdf',
      );

      expect(
        DatabaseLibraryProvider.shouldIncludeBookByPath(
          filePath,
          hasTalmudBavliDirectory: false,
          talmudBavliDirectoryPath: path.join(
            '/library',
            DatabaseConstants.otzariaFolderName,
            DatabaseConstants.talmudBavliFolderName,
          ),
        ),
        isFalse,
      );
    });

    test('shouldIncludeBookByPath משאיר קבצים אחרים גם כשהתיקייה חסרה', () {
      final otherFilePath = path.join(
        '/library',
        DatabaseConstants.otzariaFolderName,
        'משנה',
        'פאה.txt',
      );

      expect(
        DatabaseLibraryProvider.shouldIncludeBookByPath(
          otherFilePath,
          hasTalmudBavliDirectory: false,
          talmudBavliDirectoryPath: path.join(
            '/library',
            DatabaseConstants.otzariaFolderName,
            DatabaseConstants.talmudBavliFolderName,
          ),
        ),
        isTrue,
      );
    });

    test('isTalmudBavliFilePath מזהה נתיב מתוך התיקייה הייעודית', () {
      final filePath = path.join(
        '/library',
        'ספריה-מותאמת',
        DatabaseConstants.talmudBavliFolderName,
        'שבת ב.pdf',
      );

      expect(
        DatabaseConstants.isTalmudBavliFilePath(
          filePath,
          libraryPath: '/library',
          folderName: 'ספריה-מותאמת',
        ),
        isTrue,
      );
    });

    test(
      'getTalmudBavliDirectoryPath מחזיר נתיב ליד ה-DB גם בלי תיקיית אוצריא',
      () {
        expect(
          DatabaseConstants.getTalmudBavliDirectoryPath('/library-root', ''),
          path.join('/library-root', DatabaseConstants.talmudBavliFolderName),
        );
      },
    );

    test('isTalmudBavliFilePath מזהה גם חילוץ ידני בשורש הספרייה', () {
      final filePath = path.join(
        '/library-root',
        DatabaseConstants.talmudBavliFolderName,
        'ברכות.pdf',
      );

      expect(
        DatabaseConstants.isTalmudBavliFilePath(
          filePath,
          libraryPath: '/library-root',
          folderName: DatabaseConstants.otzariaFolderName,
        ),
        isTrue,
      );
    });

    test(
      'isTalmudBavliInstallInProgress מזהה חילוץ שנקטע לפי סימון-הביניים',
      () {
        final dir = Directory.systemTemp.createTempSync('talmud_marker_test');
        addTearDown(() => dir.deleteSync(recursive: true));
        final marker = File(
          DatabaseConstants.talmudBavliVersionFilePath(dir.path),
        );

        expect(
          DatabaseConstants.isTalmudBavliInstallInProgress(dir.path),
          isFalse,
          reason: 'תיקייה בלי סימון נחשבת שלמה',
        );

        marker.writeAsStringSync(DatabaseConstants.talmudBavliInstallingMarker);
        expect(
          DatabaseConstants.isTalmudBavliInstallInProgress(dir.path),
          isTrue,
        );

        marker.writeAsStringSync('v2.0.0');
        expect(
          DatabaseConstants.isTalmudBavliInstallInProgress(dir.path),
          isFalse,
          reason: 'סימון עם תג גרסה אמיתי הוא התקנה שלמה',
        );
      },
    );

    test(
      'resolveFileBookPathForTesting מתקן נתיב PDF ישן לפי הספרייה הפעילה',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_db_pdf_path',
        );
        final activeLibrary = path.join(tempDir.path, 'new', 'books');
        final stalePath = path.join(
          tempDir.path,
          'old',
          'books',
          DatabaseConstants.talmudBavliFolderName,
          'ברכות.pdf',
        );
        final activePath = path.join(
          activeLibrary,
          DatabaseConstants.talmudBavliFolderName,
          'ברכות.pdf',
        );
        final previousLibraryPath = Settings.getValue<String>(
          SettingsRepository.keyLibraryPath,
        );

        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            previousLibraryPath ?? '',
          );
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        await Directory(path.dirname(activePath)).create(recursive: true);
        await File(activePath).writeAsBytes([1]);
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          activeLibrary,
        );

        final resolved = DatabaseLibraryProvider.instance
            .resolveFileBookPathForTesting(stalePath);

        expect(resolved, activePath);
      },
    );

    test('loadBookLinksRowsForTesting טוען קישורים דרך sqlite ב-isolate worker', () async {
      final tempDir = await Directory.systemTemp.createTemp('otzaria_db_links');
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT)',
        );
        db.execute(
          'CREATE TABLE line (id INTEGER PRIMARY KEY, lineIndex INTEGER, heRef TEXT)',
        );
        db.execute(
          'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)',
        );
        db.execute(
          'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)',
        );

        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType) VALUES (1, 'בראשית', 7, 'txt')",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType) VALUES (2, 'רש''י על בראשית', 8, 'txt')",
        );
        db.execute(
          "INSERT INTO line (id, lineIndex, heRef) VALUES (10, 0, 'א')",
        );
        db.execute(
          "INSERT INTO line (id, lineIndex, heRef) VALUES (20, 3, 'ד')",
        );
        db.execute(
          "INSERT INTO connection_type (id, name) VALUES (5, 'reference')",
        );
        db.execute(
          'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 20, 2, 5)',
        );

        final rows = DatabaseLibraryProvider.loadBookLinksRowsForTesting(
          dbPath: dbPath,
          title: 'בראשית',
          categoryId: 7,
          fileType: 'txt',
        );

        expect(rows, hasLength(1));
        expect(rows.first['sourceLineIndex'], 0);
        expect(rows.first['targetLineIndex'], 3);
        expect(rows.first['targetBookTitle'], 'רש\'י על בראשית');
        expect(rows.first['connectionTypeName'], 'reference');
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('loadBookLinksRowsForTesting מחזיר מקור (SOURCE inverse) לספר מפרש', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_db_inverse',
      );
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT)',
        );
        db.execute(
          'CREATE TABLE line (id INTEGER PRIMARY KEY, lineIndex INTEGER, heRef TEXT)',
        );
        db.execute(
          'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)',
        );
        db.execute(
          'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)',
        );

        // בראשית (1) הוא הבסיס ורש"י (2) המפרש. הקישור נשמר בכיוון קנוני
        // base→commentary (כמו ב-v3), בלי שורה הפוכה.
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType) VALUES (1, 'בראשית', 7, 'txt')",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType) VALUES (2, 'רש''י על בראשית', 8, 'txt')",
        );
        db.execute(
          "INSERT INTO line (id, lineIndex, heRef) VALUES (10, 0, 'א')",
        );
        db.execute(
          "INSERT INTO line (id, lineIndex, heRef) VALUES (20, 5, 'ה')",
        );
        db.execute(
          "INSERT INTO connection_type (id, name) VALUES (1, 'COMMENTARY')",
        );
        db.execute(
          'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 20, 2, 1)',
        );

        // פותחים את רש"י (target) — אמור לקבל את בראשית כמקור דרך inverse.
        final rows = DatabaseLibraryProvider.loadBookLinksRowsForTesting(
          dbPath: dbPath,
          title: 'רש\'י על בראשית',
          categoryId: 8,
          fileType: 'txt',
        );

        expect(rows, hasLength(1));
        expect(rows.first['connectionTypeName'], 'SOURCE');
        expect(rows.first['targetBookTitle'], 'בראשית');
        expect(rows.first['sourceLineIndex'], 5);
        expect(rows.first['targetLineIndex'], 0);
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('SOURCE inverse נושא את baseProvenance של הקישור כשהעמודה קיימת', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_db_provenance',
      );
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT)',
        );
        db.execute(
          'CREATE TABLE line (id INTEGER PRIMARY KEY, lineIndex INTEGER, heRef TEXT)',
        );
        db.execute(
          'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)',
        );
        db.execute(
          'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER, baseProvenance INTEGER NOT NULL DEFAULT 0)',
        );

        // רש"י (3) מקושר גם מהבסיס (1, יחס מוצהר) וגם מספר תלוי ששמור בכיוון
        // ההפוך (2, ציטוט לטרלי) — שני קישורי SOURCE לאותה שורה.
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType) VALUES (1, 'בבא קמא', 7, 'txt')",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType) VALUES (2, 'אוצר לעזי רש''י', 9, 'txt')",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType) VALUES (3, 'רש''י על בבא קמא', 8, 'txt')",
        );
        db.execute(
          "INSERT INTO line (id, lineIndex, heRef) VALUES (10, 0, 'א')",
        );
        db.execute(
          "INSERT INTO line (id, lineIndex, heRef) VALUES (20, 4, 'ה')",
        );
        db.execute(
          "INSERT INTO line (id, lineIndex, heRef) VALUES (30, 7, 'ז')",
        );
        db.execute(
          "INSERT INTO connection_type (id, name) VALUES (1, 'COMMENTARY')",
        );
        db.execute(
          'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId, baseProvenance) VALUES (2, 30, 20, 3, 1, 0)',
        );
        db.execute(
          'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId, baseProvenance) VALUES (1, 10, 20, 3, 1, 2)',
        );

        final rows = DatabaseLibraryProvider.loadBookLinksRowsForTesting(
          dbPath: dbPath,
          title: 'רש\'י על בבא קמא',
          categoryId: 8,
          fileType: 'txt',
        );

        final provenanceByTitle = {
          for (final row in rows)
            row['targetBookTitle'] as String: row['baseProvenance'],
        };
        expect(provenanceByTitle['בבא קמא'], 2);
        expect(provenanceByTitle['אוצר לעזי רש\'י'], 0);
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('חלון שורות חלקי וסיכום כלל־ספרי נשארים עקביים', () async {
      final tempDir = await Directory.systemTemp.createTemp('otzaria_db_range');
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT, orderIndex INTEGER)',
        );
        db.execute(
          'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, heRef TEXT)',
        );
        db.execute(
          'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)',
        );
        db.execute(
          'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)',
        );
        db.execute(
          'CREATE TABLE link_anchor (linkId INTEGER, side INTEGER, charStart INTEGER, charEnd INTEGER, label TEXT, PRIMARY KEY (linkId, side, charStart))',
        );

        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (1, 'בראשית', 7, 'txt', 1)",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (2, 'מפרש א', 8, 'txt', 1)",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (3, 'מפרש ב', 8, 'txt', 2)",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (10, 1, 4, 'ד')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (11, 1, 400, 'ת')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (20, 2, 0, 'א')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (21, 3, 1, 'ב')",
        );
        db.execute(
          "INSERT INTO connection_type (id, name) VALUES (5, 'COMMENTARY')",
        );
        db.execute(
          'INSERT INTO link (id, sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (100, 1, 10, 20, 2, 5)',
        );
        db.execute(
          'INSERT INTO link (id, sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (101, 1, 11, 21, 3, 5)',
        );
        db.execute(
          "INSERT INTO link_anchor (linkId, side, charStart, charEnd, label) VALUES (100, 0, 2, 4, 'א'), (100, 0, 6, 8, 'ב'), (101, 0, 9, 10, 'ג')",
        );

        final rows = DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
          dbPath: dbPath,
          title: 'בראשית',
          categoryId: 7,
          fileType: 'txt',
          startLineIndex: 0,
          endLineIndex: 10,
        );

        expect(rows, hasLength(1));
        expect(rows.first['sourceLineIndex'], 4);
        expect(rows.first['targetBookTitle'], 'מפרש א');
        expect(rows.first['anchorCharStart'], 2);
        expect(rows.first['anchorSpans'], '2:4:א;6:8:ב');

        const currentStartLine = 5;
        const currentEndLine = 5;
        final narrowWindow = PdfLinksWindowPolicy.nextWindow(
          rangeStart: currentStartLine,
          rangeEnd: currentEndLine,
        )!;
        final narrowRows =
            DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
              dbPath: dbPath,
              title: 'בראשית',
              categoryId: 7,
              fileType: 'txt',
              startLineIndex: narrowWindow.startLine - 1,
              endLineIndex: narrowWindow.endLine - 1,
            );
        final legacyRows =
            DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
              dbPath: dbPath,
              title: 'בראשית',
              categoryId: 7,
              fileType: 'txt',
              startLineIndex: 0,
              endLineIndex: currentEndLine + 1500 - 1,
            );
        Set<String> currentLinkIdentities(
          List<Map<String, Object?>> candidateRows,
        ) => {
          for (final row in candidateRows)
            if ((row['sourceLineIndex'] as int) + 1 >= currentStartLine &&
                (row['sourceLineIndex'] as int) + 1 <= currentEndLine)
              '${row['sourceLineIndex']}:${row['targetBookTitle']}:'
                  '${row['connectionTypeName']}',
        };

        expect(narrowRows, hasLength(1));
        expect(legacyRows, hasLength(2));
        expect(
          currentLinkIdentities(narrowRows),
          currentLinkIdentities(legacyRows),
          reason: 'החלון הצר חייב לשמור את כל קישורי הקטע הנוכחי',
        );
        expect(currentLinkIdentities(narrowRows), hasLength(1));

        final summary =
            DatabaseLibraryProvider.loadBookLinkTargetsSummaryRowsForTesting(
              dbPath: dbPath,
              title: 'בראשית',
              categoryId: 7,
            );
        expect(
          summary.rows.map((row) => row['targetBookTitle']).toSet(),
          {'מפרש א', 'מפרש ב'},
          reason: 'רשימת הבחירה היא כלל־ספרית גם כשהחלון מכיל רק מפרש א',
        );
        expect(
          summary.rows.map((row) => row['connectionTypeName']).toSet(),
          {'COMMENTARY'},
        );
        expect(summary.maxSourceLineIndex, 400);
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('loadBookLinksRowsInRangeForTesting מסנן גם לפי ספרי יעד', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_db_target',
      );
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT, orderIndex INTEGER)',
        );
        db.execute(
          'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, heRef TEXT)',
        );
        db.execute(
          'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)',
        );
        db.execute(
          'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)',
        );

        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (1, 'בראשית', 7, 'txt', 1)",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (2, 'מפרש א', 8, 'txt', 1)",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (3, 'מפרש ב', 8, 'txt', 2)",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (10, 1, 4, 'ד')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (11, 1, 5, 'ה')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (20, 2, 0, 'א')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (21, 3, 1, 'ב')",
        );
        db.execute(
          "INSERT INTO connection_type (id, name) VALUES (5, 'COMMENTARY')",
        );
        db.execute(
          'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 20, 2, 5)',
        );
        db.execute(
          'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 11, 21, 3, 5)',
        );

        final rows = DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
          dbPath: dbPath,
          title: 'בראשית',
          categoryId: 7,
          fileType: 'txt',
          startLineIndex: 0,
          endLineIndex: 10,
          targetBookTitles: const ['מפרש ב'],
        );

        expect(rows, hasLength(1));
        expect(rows.first['sourceLineIndex'], 5);
        expect(rows.first['targetBookTitle'], 'מפרש ב');
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'loadBookLinkTargetsSummaryRowsForTesting מסכם יעדים לפי סוג כולל inverse',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_db_summary',
        );
        final dbPath = path.join(tempDir.path, 'db.sqlite');
        final db = sqlite3.sqlite3.open(dbPath);

        try {
          db.execute(
            'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT, orderIndex INTEGER)',
          );
          db.execute(
            'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, heRef TEXT)',
          );
          db.execute(
            'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)',
          );
          db.execute(
            'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)',
          );

          db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (1, 'בראשית', 7, 'txt', 1)",
          );
          db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (2, 'מפרש א', 8, 'txt', 1)",
          );
          db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (3, 'ילקוט', 8, 'txt', 2)",
          );
          db.execute(
            "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (4, 'מדרש', 8, 'txt', 3)",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (10, 1, 4, 'ד')",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (11, 1, 9, 'ט')",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (20, 2, 0, 'א')",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (21, 2, 1, 'ב')",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (30, 3, 0, 'א')",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (40, 4, 0, 'א')",
          );
          db.execute(
            "INSERT INTO connection_type (id, name) VALUES (1, 'COMMENTARY')",
          );
          db.execute(
            "INSERT INTO connection_type (id, name) VALUES (5, 'reference')",
          );
          // שני קישורי מפרש + reference אחד מבראשית; קישור COMMENTARY מ'מדרש'
          // שמצביע אל בראשית (יופיע כ-SOURCE בזרוע ההפוכה).
          db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 20, 2, 1)',
          );
          db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 11, 21, 2, 1)',
          );
          db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 30, 3, 5)',
          );
          db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (4, 40, 10, 1, 1)',
          );

          final summary =
              DatabaseLibraryProvider.loadBookLinkTargetsSummaryRowsForTesting(
                dbPath: dbPath,
                title: 'בראשית',
                categoryId: 7,
              );

          Map<String, Object?> rowFor(String title) =>
              summary.rows.firstWhere((row) => row['targetBookTitle'] == title);

          expect(summary.rows, hasLength(3));
          expect(rowFor('מפרש א')['connectionTypeName'], 'COMMENTARY');
          expect(rowFor('מפרש א')['linkCount'], 2);
          expect(rowFor('ילקוט')['connectionTypeName'], 'reference');
          expect(rowFor('ילקוט')['linkCount'], 1);
          expect(rowFor('מדרש')['connectionTypeName'], 'SOURCE');
          expect(summary.maxSourceLineIndex, 9);
        } finally {
          db.close();
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('קישורי-טווח: שורה מכוסה מקבלת את הקישור וקצה הטווח נחשף', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_db_ranged',
      );
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT, orderIndex INTEGER)',
        );
        db.execute(
          'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, heRef TEXT)',
        );
        db.execute(
          'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)',
        );
        db.execute(
          'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)',
        );
        db.execute(
          'CREATE TABLE link_range (linkId INTEGER, side INTEGER, endLineId INTEGER, endLineIndex INTEGER, PRIMARY KEY (linkId, side))',
        );
        db.execute(
          'CREATE TABLE link_coverage (lineId INTEGER, linkId INTEGER, side INTEGER, PRIMARY KEY (lineId, linkId, side))',
        );

        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (1, 'בראשית', 7, 'txt', 1)",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (2, 'ילקוט', 8, 'txt', 1)",
        );
        // בראשית: שורות 4-6; הקישור מעוגן ב-4 ומכסה גם את 5 ו-6.
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (10, 1, 4, 'בראשית א, ה')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (11, 1, 5, 'בראשית א, ו')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (12, 1, 6, 'בראשית א, ז')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (20, 2, 0, 'ילקוט א')",
        );
        db.execute(
          "INSERT INTO connection_type (id, name) VALUES (5, 'reference')",
        );
        db.execute(
          'INSERT INTO link (id, sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (100, 1, 10, 20, 2, 5)',
        );
        // טווח בצד המקור (side=0): בראשית א, ה - א, ז.
        db.execute(
          'INSERT INTO link_range (linkId, side, endLineId, endLineIndex) VALUES (100, 0, 12, 6)',
        );
        db.execute(
          'INSERT INTO link_coverage (lineId, linkId, side) VALUES (11, 100, 0)',
        );
        db.execute(
          'INSERT INTO link_coverage (lineId, linkId, side) VALUES (12, 100, 0)',
        );

        // חלון שכולל רק שורה מכוסה (5) ולא את עוגן-ההתחלה (4).
        final coveredOnly =
            DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
              dbPath: dbPath,
              title: 'בראשית',
              categoryId: 7,
              fileType: 'txt',
              startLineIndex: 5,
              endLineIndex: 5,
            );
        expect(coveredOnly, hasLength(1));
        expect(coveredOnly.first['sourceLineIndex'], 5);
        expect(coveredOnly.first['targetBookTitle'], 'ילקוט');

        // חלון שמכסה את כל הטווח: שורת העוגן + שתי המכוסות, בלי כפילויות.
        final wholeRange =
            DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
              dbPath: dbPath,
              title: 'בראשית',
              categoryId: 7,
              fileType: 'txt',
              startLineIndex: 0,
              endLineIndex: 10,
            );
        expect(wholeRange, hasLength(3));
        expect(
          wholeRange.map((r) => r['sourceLineIndex']).toList()..sort(),
          [4, 5, 6],
        );
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('קישורי-טווח: צד הפאנל חושף את קצה הטווח של היעד', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_db_ranged_end',
      );
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, fileType TEXT, orderIndex INTEGER)',
        );
        db.execute(
          'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, heRef TEXT)',
        );
        db.execute(
          'CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT)',
        );
        db.execute(
          'CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER, targetLineId INTEGER, targetBookId INTEGER, connectionTypeId INTEGER)',
        );
        db.execute(
          'CREATE TABLE link_range (linkId INTEGER, side INTEGER, endLineId INTEGER, endLineIndex INTEGER, PRIMARY KEY (linkId, side))',
        );
        db.execute(
          'CREATE TABLE link_coverage (lineId INTEGER, linkId INTEGER, side INTEGER, PRIMARY KEY (lineId, linkId, side))',
        );
        db.execute(
          'CREATE TABLE link_anchor (linkId INTEGER, side INTEGER, charStart INTEGER, charEnd INTEGER, label TEXT, PRIMARY KEY (linkId, side, charStart))',
        );

        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (1, 'בראשית', 7, 'txt', 1)",
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, fileType, orderIndex) VALUES (2, 'פירוש', 8, 'txt', 1)",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (10, 1, 0, 'בראשית א, א')",
        );
        // הפירוש: שלוש פסקאות, הקישור מעוגן בראשונה ומשתרע עד השלישית.
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (20, 2, 0, 'פירוש א, א, א')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (21, 2, 1, 'פירוש א, א, ב')",
        );
        db.execute(
          "INSERT INTO line (id, bookId, lineIndex, heRef) VALUES (22, 2, 2, 'פירוש א, א, ג')",
        );
        db.execute(
          "INSERT INTO connection_type (id, name) VALUES (5, 'COMMENTARY')",
        );
        db.execute(
          'INSERT INTO link (id, sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (200, 1, 10, 20, 2, 5)',
        );
        // טווח בצד היעד (side=1): הפירוש משתרע על שלוש פסקאות.
        db.execute(
          'INSERT INTO link_range (linkId, side, endLineId, endLineIndex) VALUES (200, 1, 22, 2)',
        );
        db.execute(
          'INSERT INTO link_coverage (lineId, linkId, side) VALUES (21, 200, 1)',
        );
        db.execute(
          'INSERT INTO link_coverage (lineId, linkId, side) VALUES (22, 200, 1)',
        );
        // עוגן-מילה בשורת ההתחלה של צד היעד — אסור שידלוף לשורות המכוסות.
        db.execute(
          "INSERT INTO link_anchor (linkId, side, charStart, charEnd, label) VALUES (200, 1, 3, NULL, 'א')",
        );

        // תצוגת ספר הבסיס: צד-הפאנל (היעד) חושף את קצה הטווח.
        final forward = DatabaseLibraryProvider.loadBookLinksRowsForTesting(
          dbPath: dbPath,
          title: 'בראשית',
          categoryId: 7,
          fileType: 'txt',
        );
        final commentaryRow = forward.firstWhere(
          (r) => r['connectionTypeName'] == 'COMMENTARY',
        );
        expect(commentaryRow['targetRangeEndHeRef'], 'פירוש א, א, ג');
        expect(commentaryRow['targetRangeEndLineIndex'], 2);

        // תצוגת ספר הפירוש: שורות 1-2 המכוסות מקבלות שורת SOURCE משלהן.
        final inverse = DatabaseLibraryProvider.loadBookLinksRowsForTesting(
          dbPath: dbPath,
          title: 'פירוש',
          categoryId: 8,
          fileType: 'txt',
        );
        final sourceRows = inverse
            .where((r) => r['connectionTypeName'] == 'SOURCE')
            .toList();
        expect(sourceRows, hasLength(3));
        expect(
          sourceRows.map((r) => r['sourceLineIndex']).toList()..sort(),
          [0, 1, 2],
        );
        // העוגן מוצמד רק לשורת ההתחלה — לא דולף לשורות המכוסות.
        for (final row in sourceRows) {
          if (row['sourceLineIndex'] == 0) {
            expect(row['anchorCharStart'], 3);
            expect(row['anchorLabel'], 'א');
          } else {
            expect(
              row['anchorCharStart'],
              isNull,
              reason: 'עוגן של שורת ההתחלה דלף לשורה מכוסה',
            );
          }
        }
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('גרסאות: רשימת המהדורות נטענת — עם תוכן תחילה, לפי priority', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_db_versions',
      );
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, totalLines INTEGER)',
        );
        db.execute(
          'CREATE TABLE book_version (id INTEGER PRIMARY KEY, bookId INTEGER, versionTitle TEXT, heVersionTitle TEXT, versionSource TEXT, priority REAL, license TEXT, versionNotes TEXT, heVersionNotes TEXT, hasContent INTEGER)',
        );
        db.execute(
          'CREATE TABLE version_line (versionId INTEGER, lineId INTEGER, content TEXT, charCount INTEGER, PRIMARY KEY (versionId, lineId))',
        );

        db.execute(
          "INSERT INTO book (id, title, categoryId, totalLines) VALUES (1, 'טור', 7, 3)",
        );
        db.execute(
          "INSERT INTO book_version VALUES (11, 1, 'Warsaw 1861', NULL, 'http://w', 1.0, 'Public Domain', NULL, NULL, 1)",
        );
        db.execute(
          "INSERT INTO book_version VALUES (12, 1, 'Vilna 1923', 'וילנא תרפ\"ג', NULL, 2.0, NULL, NULL, NULL, 1)",
        );
        db.execute(
          "INSERT INTO book_version VALUES (13, 1, 'Old Edition', NULL, NULL, 3.0, NULL, NULL, NULL, 0)",
        );

        final rows = DatabaseLibraryProvider.loadBookVersionsRowsForTesting(
          dbPath: dbPath,
          title: 'טור',
          categoryId: 7,
        );
        // עם-תוכן תחילה; בתוך כל קבוצה priority יורד.
        expect(
          rows.map((r) => r['versionTitle']).toList(),
          ['Vilna 1923', 'Warsaw 1861', 'Old Edition'],
        );
        expect(rows[0]['heVersionTitle'], 'וילנא תרפ"ג');
        expect(rows[1]['license'], 'Public Domain');
        expect(rows[2]['hasContent'], 0);

        // ספר שאינו קיים — רשימה ריקה.
        final missing = DatabaseLibraryProvider.loadBookVersionsRowsForTesting(
          dbPath: dbPath,
          title: 'איננו',
          categoryId: 7,
        );
        expect(missing, isEmpty);
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('גרסאות: DB ישן בלי book_version מחזיר רשימה ריקה', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_db_versions_old',
      );
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, totalLines INTEGER)',
        );
        db.execute(
          "INSERT INTO book (id, title, categoryId, totalLines) VALUES (1, 'טור', 7, 3)",
        );

        final rows = DatabaseLibraryProvider.loadBookVersionsRowsForTesting(
          dbPath: dbPath,
          title: 'טור',
          categoryId: 7,
        );
        expect(rows, isEmpty);

        // בקשת טקסט של מהדורה מול DB ישן — null, בלי ליפול לנוסח הממוזג.
        final range = DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
          dbPath: dbPath,
          title: 'טור',
          categoryId: 7,
          fileType: 'txt',
          startLine: 0,
          endLine: 10,
          versionTitle: 'Vilna 1923',
        );
        expect(range, isNull);
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('גרסאות: overlay — תוכן מהמהדורה, כותרת מהשלד, סגמנט חסר ריק', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_db_versions_text',
      );
      final dbPath = path.join(tempDir.path, 'db.sqlite');
      final db = sqlite3.sqlite3.open(dbPath);

      try {
        db.execute(
          'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER, totalLines INTEGER)',
        );
        db.execute(
          'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, content TEXT, heRef TEXT)',
        );
        db.execute(
          'CREATE TABLE book_version (id INTEGER PRIMARY KEY, bookId INTEGER, versionTitle TEXT, heVersionTitle TEXT, versionSource TEXT, priority REAL, license TEXT, versionNotes TEXT, heVersionNotes TEXT, hasContent INTEGER)',
        );
        db.execute(
          'CREATE TABLE version_line (versionId INTEGER, lineId INTEGER, content TEXT, charCount INTEGER, PRIMARY KEY (versionId, lineId))',
        );

        db.execute(
          "INSERT INTO book (id, title, categoryId, totalLines) VALUES (1, 'טור', 7, 4)",
        );
        // שורה 0: כותרת (heRef NULL); 1-3: תוכן, כשלמהדורה יש נוסח רק ל-1 ו-3.
        db.execute("INSERT INTO line VALUES (10, 1, 0, '<h1>טור</h1>', NULL)");
        db.execute(
          "INSERT INTO line VALUES (11, 1, 1, 'נוסח ממוזג א', 'טור א')",
        );
        db.execute(
          "INSERT INTO line VALUES (12, 1, 2, 'נוסח ממוזג ב', 'טור ב')",
        );
        db.execute(
          "INSERT INTO line VALUES (13, 1, 3, 'נוסח ממוזג ג', 'טור ג')",
        );
        db.execute(
          "INSERT INTO book_version VALUES (11, 1, 'Warsaw 1861', NULL, NULL, NULL, NULL, NULL, NULL, 1)",
        );
        db.execute(
          "INSERT INTO version_line VALUES (11, 11, 'נוסח ורשא א', 11)",
        );
        db.execute(
          "INSERT INTO version_line VALUES (11, 13, 'נוסח ורשא ג', 11)",
        );

        final versionRange =
            DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
              dbPath: dbPath,
              title: 'טור',
              categoryId: 7,
              fileType: 'txt',
              startLine: 0,
              endLine: 10,
              versionTitle: 'Warsaw 1861',
            );
        expect(versionRange, isNotNull);
        expect(versionRange!.lines, [
          '<h1>טור</h1>', // כותרת נשארת מהשלד
          'נוסח ורשא א',
          '', // סגמנט שחסר במהדורה — ריק, לא נוסח ממוזג
          'נוסח ורשא ג',
        ]);
        expect(versionRange.totalLines, 4);

        // בלי versionTitle — הנוסח הממוזג הרגיל, ללא שינוי.
        final mergedRange =
            DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
              dbPath: dbPath,
              title: 'טור',
              categoryId: 7,
              fileType: 'txt',
              startLine: 0,
              endLine: 10,
            );
        expect(mergedRange!.lines, [
          '<h1>טור</h1>',
          'נוסח ממוזג א',
          'נוסח ממוזג ב',
          'נוסח ממוזג ג',
        ]);

        // מהדורה שאינה קיימת — null, בלי ליפול לנוסח הממוזג.
        final unknownVersion =
            DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
              dbPath: dbPath,
              title: 'טור',
              categoryId: 7,
              fileType: 'txt',
              startLine: 0,
              endLine: 10,
              versionTitle: 'איננה',
            );
        expect(unknownVersion, isNull);
      } finally {
        db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'loadAlternativeStructuresRowsForTesting טוען כותרות חלופיות מה-DB',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('otzaria_db_alt');
        final dbPath = path.join(tempDir.path, 'db.sqlite');
        final db = sqlite3.sqlite3.open(dbPath);

        try {
          db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
          db.execute(
            'CREATE TABLE alt_toc_structure (id INTEGER PRIMARY KEY, bookId INTEGER, key TEXT, title TEXT, heTitle TEXT)',
          );

          db.execute("INSERT INTO book (id, title) VALUES (1, 'בראשית')");
          db.execute(
            "INSERT INTO alt_toc_structure (id, bookId, key, title, heTitle) VALUES (9, 1, 'chapters', 'Chapters', 'פרקים')",
          );

          final rows =
              DatabaseLibraryProvider.loadAlternativeStructuresRowsForTesting(
                dbPath: dbPath,
                bookTitle: 'בראשית',
              );

          expect(rows, hasLength(1));
          expect(rows.first['id'], 9);
          expect(rows.first['bookId'], 1);
          expect(rows.first['key'], 'chapters');
          expect(rows.first['heTitle'], 'פרקים');
        } finally {
          db.close();
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'buildLibraryCatalog שומר מחבר ותיאורי קטגוריה מה-DB וחיפוש הספריה מוצא לפי מחבר',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_db_minimal_books',
        );
        final dbPath = path.join(
          tempDir.path,
          DatabaseConstants.databaseFileName,
        );
        final database = MyDatabase.withPath(dbPath);
        final repository = SeforimRepository(database);
        final provider = DatabaseLibraryProvider.instance;
        final previousLibraryPath = Settings.getValue<String>(
          SettingsRepository.keyLibraryPath,
        );
        final previousFolderName = Settings.getValue<String>(
          SettingsRepository.keyLibraryFolderName,
        );
        final previousEffectiveDbPath = Settings.getValue<String>(
          SettingsRepository.keyDbEffectivePath,
        );

        try {
          await provider.sqliteProvider.dispose();
          provider.clearCache();
          await repository.ensureInitialized();
          final db = await database.database;
          db.execute('ALTER TABLE category ADD COLUMN heShortDesc TEXT');
          db.execute('ALTER TABLE category ADD COLUMN heDesc TEXT');

          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            tempDir.path,
          );
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            '',
          );

          final sourceId = await repository.insertSource('local-test', -10);
          final categoryId = await repository.insertCategory(
            const migration_models.Category(
              title: 'הלכה',
              parentId: null,
              level: 0,
            ),
          );
          db.execute(
            'UPDATE category SET heShortDesc = ?, heDesc = ? WHERE id = ?',
            ['קצר מה-DB', 'מורחב מה-DB', categoryId],
          );
          await repository.insertCategory(
            const migration_models.Category(
              title: 'קטגוריה ללא תיאור',
              parentId: null,
              level: 0,
            ),
          );

          await repository.insertBook(
            migration_models.Book(
              id: 1,
              categoryId: categoryId,
              sourceId: sourceId,
              title: 'ספר בדיקה',
              authors: const [Author(name: 'רש"י')],
              filePath: path.join(tempDir.path, 'book.txt'),
              fileType: 'txt',
            ),
          );

          db.execute('BEGIN');
          try {
            for (var index = 2; index <= 1200; index++) {
              db.execute(
                '''
              INSERT INTO book (
                id, categoryId, sourceId, title, orderIndex, totalLines, filePath, fileType
              ) VALUES (?, ?, ?, ?, ?, 0, ?, 'txt')
              ''',
                [
                  index,
                  categoryId,
                  sourceId,
                  'ספר $index',
                  index,
                  path.join(tempDir.path, 'book_$index.txt'),
                ],
              );
            }
            db.execute('COMMIT');
          } catch (_) {
            db.execute('ROLLBACK');
            rethrow;
          }

          await provider.initialize();
          final library = await provider.buildLibraryCatalog(
            {
              'הלכה': {
                'heShortDesc': 'קצר מ-metadata',
                'heDesc': 'מורחב מ-metadata',
              },
            },
            tempDir.path,
          );
          // מסננים קטגוריית "ספרים אישיים" שעלולה להצטרף אוטומטית מ-user_books.db
          // הגלובלי ב-AppData של המכונה — לטסט אכפת רק מהקטגוריה שהוא יצר.
          final halachaCategory = library.subCategories.firstWhere(
            (c) => c.title == 'הלכה',
          );
          final books = halachaCategory.books;
          final targetBook = books.firstWhere(
            (book) => book.title == 'ספר בדיקה',
          );
          final categoryWithoutDescription = library.subCategories.firstWhere(
            (category) => category.title == 'קטגוריה ללא תיאור',
          );

          expect(books, hasLength(1200));
          expect(targetBook.author, 'רש"י');
          expect(halachaCategory.shortDescription, 'קצר מה-DB');
          expect(halachaCategory.description, 'מורחב מה-DB');
          expect(categoryWithoutDescription.shortDescription, isEmpty);
          expect(categoryWithoutDescription.description, isEmpty);

          final repositoryForSearch = DataRepository()
            ..library = Future.value(library);
          final results = await repositoryForSearch.findBooks(
            'רש"י',
            halachaCategory,
            sortByRatio: false,
          );

          expect(results, hasLength(1));
          expect(results.single.title, 'ספר בדיקה');
        } finally {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            previousLibraryPath ?? '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            previousFolderName ?? '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            previousEffectiveDbPath ?? '',
          );
          await provider.sqliteProvider.dispose();
          provider.clearCache();
          database.close();
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'getLinksForBookRange מחזיר קישורים דרך Isolate.run ללא קריסת "object is unsendable"',
      () async {
        // רגרסיה: הסגירה של Isolate.run לכדה את this (עם FfiDatabase).
        // התיקון: חילוץ _sqliteProvider.dbPath למשתנה מקומי לפני הסגירה.
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_db_links_isolate',
        );
        final dbPath = path.join(
          tempDir.path,
          DatabaseConstants.databaseFileName,
        );
        final database = MyDatabase.withPath(dbPath);
        final repository = SeforimRepository(database);
        final provider = DatabaseLibraryProvider.instance;
        final previousLibraryPath = Settings.getValue<String>(
          SettingsRepository.keyLibraryPath,
        );
        final previousEffectiveDbPath = Settings.getValue<String>(
          SettingsRepository.keyDbEffectivePath,
        );

        try {
          await provider.sqliteProvider.dispose();
          provider.clearCache();
          await repository.ensureInitialized();

          // connection_type נוצר אוטומטית ע"י ensureInitialized — REFERENCE=5
          final sourceId = await repository.insertSource('local', -10);
          final catId = await repository.insertCategory(
            const migration_models.Category(
              title: 'כללי',
              parentId: null,
              level: 0,
            ),
          );

          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            tempDir.path,
          );
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            '',
          );
          await provider.initialize();

          final db = await database.database;
          db.execute(
            "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines, filePath, fileType) VALUES (1, $catId, $sourceId, 'בראשית', 1, 10, '/tmp/b.txt', 'txt')",
          );
          db.execute(
            "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines, filePath, fileType) VALUES (2, $catId, $sourceId, 'מפרש', 1, 5, '/tmp/m.txt', 'txt')",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, content, heRef) VALUES (10, 1, 2, 'ב', 'ב')",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, content, heRef) VALUES (20, 2, 0, 'א', 'א')",
          );
          db.execute(
            'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, targetBookId, connectionTypeId) VALUES (1, 10, 20, 2, 5)',
          );

          final links = await provider.getLinksForBookRange(
            'בראשית',
            1,
            'txt',
            startLineIndex: 0,
            endLineIndex: 5,
          );

          expect(links, hasLength(1));
          expect(links.first.path2, 'מפרש');
        } finally {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            previousLibraryPath ?? '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            previousEffectiveDbPath ?? '',
          );
          await provider.sqliteProvider.dispose();
          provider.clearCache();
          database.close();
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'getAlternativeStructuresForBook מחזיר נתונים דרך Isolate.run ללא קריסת "object is unsendable"',
      () async {
        // רגרסיה: הסגירה של Isolate.run לכדה את this (עם FfiDatabase).
        // התיקון: חילוץ _sqliteProvider.dbPath למשתנה מקומי לפני הסגירה.
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_db_alt_isolate',
        );
        final dbPath = path.join(
          tempDir.path,
          DatabaseConstants.databaseFileName,
        );
        final database = MyDatabase.withPath(dbPath);
        final repository = SeforimRepository(database);
        final provider = DatabaseLibraryProvider.instance;
        final previousLibraryPath = Settings.getValue<String>(
          SettingsRepository.keyLibraryPath,
        );
        final previousEffectiveDbPath = Settings.getValue<String>(
          SettingsRepository.keyDbEffectivePath,
        );

        try {
          await provider.sqliteProvider.dispose();
          provider.clearCache();
          await repository.ensureInitialized();

          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            tempDir.path,
          );
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            '',
          );

          final sourceId = await repository.insertSource('local', -10);
          final catId = await repository.insertCategory(
            const migration_models.Category(
              title: 'כללי',
              parentId: null,
              level: 0,
            ),
          );

          await provider.initialize();

          final db = await database.database;
          db.execute(
            "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines, filePath, fileType) VALUES (1, $catId, $sourceId, 'בראשית', 1, 10, '/tmp/b.txt', 'txt')",
          );
          db.execute(
            "INSERT INTO alt_toc_structure (id, bookId, key, title, heTitle) VALUES (1, 1, 'chapters', 'Chapters', 'פרקים')",
          );

          final structures = await provider.getAlternativeStructuresForBook(
            'בראשית',
          );

          expect(structures, hasLength(1));
          expect(structures.first.heTitle, 'פרקים');
        } finally {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            previousLibraryPath ?? '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            previousEffectiveDbPath ?? '',
          );
          await provider.sqliteProvider.dispose();
          provider.clearCache();
          database.close();
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'getAltTocEntriesWithLineIndex מחזיר lineIndex לערכים עם שורה ו-null לכותרות-אב, מסונן לפי structureId',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_db_alt_entries',
        );
        final dbPath = path.join(
          tempDir.path,
          DatabaseConstants.databaseFileName,
        );
        final database = MyDatabase.withPath(dbPath);
        final repository = SeforimRepository(database);
        final provider = DatabaseLibraryProvider.instance;
        final previousLibraryPath = Settings.getValue<String>(
          SettingsRepository.keyLibraryPath,
        );
        final previousEffectiveDbPath = Settings.getValue<String>(
          SettingsRepository.keyDbEffectivePath,
        );

        try {
          await provider.sqliteProvider.dispose();
          provider.clearCache();
          await repository.ensureInitialized();

          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            tempDir.path,
          );
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            '',
          );

          final sourceId = await repository.insertSource('local', -10);
          final catId = await repository.insertCategory(
            const migration_models.Category(
              title: 'כללי',
              parentId: null,
              level: 0,
            ),
          );

          await provider.initialize();

          final db = await database.database;
          db.execute(
            "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines, filePath, fileType) VALUES (1, $catId, $sourceId, 'בראשית', 1, 10, '/tmp/b.txt', 'txt')",
          );
          db.execute(
            "INSERT INTO alt_toc_structure (id, bookId, key, title, heTitle) VALUES (1, 1, 'Parasha', 'Parasha', 'פרשה')",
          );
          db.execute(
            "INSERT INTO alt_toc_structure (id, bookId, key, title, heTitle) VALUES (2, 1, 'Topic', 'Topic', 'נושא')",
          );
          db.execute(
            "INSERT INTO tocText (id, text) VALUES (1, 'ספר בראשית'), (2, 'פרשת בראשית'), (3, 'ערך זר')",
          );
          db.execute(
            "INSERT INTO line (id, bookId, lineIndex, content) VALUES (50, 1, 5, 'שורה')",
          );
          // מבנה 1: כותרת-אב בלי שורה + ילד עם שורה; מבנה 2: ערך שחייב להיות מסונן.
          db.execute(
            'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, lineId) VALUES (1, 1, NULL, 1, 1, NULL)',
          );
          db.execute(
            'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, lineId) VALUES (2, 1, 1, 2, 2, 50)',
          );
          db.execute(
            'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level, lineId) VALUES (3, 2, NULL, 3, 1, 50)',
          );

          final rows = await provider.getAltTocEntriesWithLineIndex(1);

          expect(rows, hasLength(2));
          expect(rows[0].id, 1);
          expect(rows[0].parentId, isNull);
          expect(rows[0].lineIndex, isNull);
          expect(rows[0].text, 'ספר בראשית');
          expect(rows[1].id, 2);
          expect(rows[1].parentId, 1);
          expect(rows[1].lineIndex, 5);
          expect(rows[1].level, 2);
        } finally {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            previousLibraryPath ?? '',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            previousEffectiveDbPath ?? '',
          );
          await provider.sqliteProvider.dispose();
          provider.clearCache();
          database.close();
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'buildLibraryCatalog ממזג ספרים אישיים קיימים מול user_books',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_user_books_merge',
        );
        final libraryPath = path.join(tempDir.path, 'library');
        final dataRootPath = path.join(tempDir.path, 'data_root');
        final dbPath = path.join(
          libraryPath,
          DatabaseConstants.databaseFileName,
        );
        final database = MyDatabase.withPath(dbPath);
        final repository = SeforimRepository(database);
        final provider = DatabaseLibraryProvider.instance;
        final previousLibraryPath = Settings.getValue<String>(
          SettingsRepository.keyLibraryPath,
        );
        final previousFolderName = Settings.getValue<String>(
          SettingsRepository.keyLibraryFolderName,
        );
        final previousEffectiveDbPath = Settings.getValue<String>(
          SettingsRepository.keyDbEffectivePath,
        );
        final previousDataRootPath = AppPaths.cachedDataRootPath;

        // ניקיון בעזרת addTearDown במקום try/finally: כל קריאה רצה
        // בנפרד גם אם הקודמת זורקת, ולכן הטסט לא משאיר Settings מלוכלכים
        // לטסטים הבאים גם אם רק חלק מהשלבים מצליחים.
        // addTearDown מבצע ב-LIFO — נרשום בסדר הפוך לרצוי, כדי שתחילה
        // ייסגרו ה-DBs ואחר כך תימחק התיקייה הזמנית.
        addTearDown(() => tempDir.delete(recursive: true));
        addTearDown(() => database.close());
        addTearDown(() => provider.clearCache());
        addTearDown(() => provider.sqliteProvider.dispose());
        addTearDown(
          () => AppPaths.debugOverrideDataRootPath(previousDataRootPath),
        );
        addTearDown(() => UserBooksDatabaseHolder.instance.close());
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            previousEffectiveDbPath ?? '',
          );
        });
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            previousFolderName ?? '',
          );
        });
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            previousLibraryPath ?? '',
          );
        });

        await Directory(libraryPath).create(recursive: true);
        await provider.sqliteProvider.dispose();
        provider.clearCache();
        await UserBooksDatabaseHolder.instance.close();
        AppPaths.debugOverrideDataRootPath(dataRootPath);
        await repository.ensureInitialized();

        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          libraryPath,
        );
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );
        await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath,
          '',
        );

        final sourceId = await repository.insertSource('local-test', -10);
        final personalCategoryId = await repository.insertCategory(
          const migration_models.Category(
            title: 'ספרים אישיים',
            parentId: null,
            level: 0,
            orderIndex: 1,
          ),
        );
        final existingFolderId = await repository.insertCategory(
          migration_models.Category(
            title: 'תיקייה קיימת',
            parentId: personalCategoryId,
            level: 1,
            orderIndex: 1,
          ),
        );

        await repository.insertBook(
          migration_models.Book(
            id: 1,
            categoryId: existingFolderId,
            sourceId: sourceId,
            title: 'ספר ראשי',
            filePath: path.join(tempDir.path, 'main_book.txt'),
            fileType: 'txt',
          ),
        );

        final userBooksRepository =
            await UserBooksDatabaseHolder.instance.repository;
        final userSourceId = await userBooksRepository.insertSource(
          'user-test',
          -20,
        );
        final userPersonalCategoryId = await userBooksRepository.insertCategory(
          const migration_models.Category(
            title: 'ספרים אישיים',
            parentId: null,
            level: 0,
            orderIndex: 1,
          ),
        );
        final userExistingFolderId = await userBooksRepository.insertCategory(
          migration_models.Category(
            title: 'תיקייה קיימת',
            parentId: userPersonalCategoryId,
            level: 1,
            orderIndex: 1,
          ),
        );
        final nestedFolderId = await userBooksRepository.insertCategory(
          migration_models.Category(
            title: 'תת קטגוריה',
            parentId: userExistingFolderId,
            level: 2,
            orderIndex: 1,
          ),
        );

        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: userExistingFolderId,
            sourceId: userSourceId,
            title: 'ספר משתמש',
            filePath: path.join(tempDir.path, 'user_book.txt'),
            fileType: 'txt',
          ),
        );
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: nestedFolderId,
            sourceId: userSourceId,
            title: 'ספר פנימי',
            filePath: path.join(tempDir.path, 'nested_user_book.txt'),
            fileType: 'txt',
          ),
        );

        await provider.initialize();
        final library = await provider.buildLibraryCatalog({}, libraryPath);

        final personalCategories = library.subCategories.where(
          (c) => c.title == 'ספרים אישיים',
        );
        expect(personalCategories, hasLength(1));

        final personalCategory = personalCategories.single;
        final mergedCategories = personalCategory.subCategories.where(
          (c) => c.title == 'תיקייה קיימת',
        );
        expect(mergedCategories, hasLength(1));

        final mergedCategory = mergedCategories.single;
        expect(mergedCategory.parent, same(personalCategory));
        expect(
          mergedCategory.books.map((book) => book.title),
          containsAll(['ספר ראשי', 'ספר משתמש']),
        );

        final mainBook = mergedCategory.books.firstWhere(
          (book) => book.title == 'ספר ראשי',
        );
        final userBook = mergedCategory.books.firstWhere(
          (book) => book.title == 'ספר משתמש',
        );
        expect(mainBook.category, same(mergedCategory));
        expect(userBook.category, same(mergedCategory));

        final nestedCategories = mergedCategory.subCategories.where(
          (c) => c.title == 'תת קטגוריה',
        );
        expect(nestedCategories, hasLength(1));

        final nestedCategory = nestedCategories.single;
        expect(nestedCategory.parent, same(mergedCategory));
        expect(nestedCategory.path, '/ספרים אישיים/תיקייה קיימת/תת קטגוריה');
        expect(nestedCategory.books, hasLength(1));
        expect(nestedCategory.books.single.title, 'ספר פנימי');
        expect(nestedCategory.books.single.category, same(nestedCategory));
      },
    );

    test(
      'getLinkContent קורא מהקובץ עבור ספר משתמש file-backed (ללא שורות ב-DB)',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_file_backed_link_content',
        );
        final libraryPath = path.join(tempDir.path, 'library');
        final dataRootPath = path.join(tempDir.path, 'data_root');
        final dbPath = path.join(
          libraryPath,
          DatabaseConstants.databaseFileName,
        );
        final database = MyDatabase.withPath(dbPath);
        final repository = SeforimRepository(database);
        final provider = DatabaseLibraryProvider.instance;
        final previousLibraryPath = Settings.getValue<String>(
          SettingsRepository.keyLibraryPath,
        );
        final previousFolderName = Settings.getValue<String>(
          SettingsRepository.keyLibraryFolderName,
        );
        final previousEffectiveDbPath = Settings.getValue<String>(
          SettingsRepository.keyDbEffectivePath,
        );
        final previousDataRootPath = AppPaths.cachedDataRootPath;

        addTearDown(() => tempDir.delete(recursive: true));
        addTearDown(() => provider.clearCache());
        addTearDown(() => provider.sqliteProvider.dispose());
        addTearDown(
          () => AppPaths.debugOverrideDataRootPath(previousDataRootPath),
        );
        // cache.db נפתח תחת ה-dataRoot הזמני ע"י מטמון ה-docx — חובה לסגור
        // לפני מחיקת התיקייה.
        addTearDown(() => CacheDatabaseHolder.instance.close());
        addTearDown(() => UserBooksDatabaseHolder.instance.close());
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            previousEffectiveDbPath ?? '',
          );
        });
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            previousFolderName ?? '',
          );
        });
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            previousLibraryPath ?? '',
          );
        });

        await Directory(libraryPath).create(recursive: true);
        await provider.sqliteProvider.dispose();
        provider.clearCache();
        await UserBooksDatabaseHolder.instance.close();
        AppPaths.debugOverrideDataRootPath(dataRootPath);
        // יוצר את סכימת ה-DB הרשמי ונסגר מיד — provider.initialize פותח את
        // אותו קובץ, וחיבור פתוח מקביל גורם ל-"database is locked".
        await repository.ensureInitialized();
        database.close();

        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          libraryPath,
        );
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );
        await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath,
          '',
        );

        // קובץ טקסט בסגנון תיקייה מותאמת בלי "הוסף למסד הנתונים" — CRLF,
        // והספר נרשם ב-user_books.db עם filePath בלבד (totalLines=0).
        final bookFile = File(path.join(tempDir.path, 'הערות לבדיקה.txt'));
        await bookFile.writeAsString(
          'שורה ראשונה\r\nשורה שנייה\r\nשורה שלישית',
        );

        final userBooksRepository =
            await UserBooksDatabaseHolder.instance.repository;
        final userSourceId = await userBooksRepository.insertSource(
          'user-test',
          -20,
        );
        final userCategoryId = await userBooksRepository.insertCategory(
          const migration_models.Category(
            title: 'ספרים אישיים',
            parentId: null,
            level: 0,
            orderIndex: 1,
          ),
        );
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: userCategoryId,
            sourceId: userSourceId,
            title: 'הערות לבדיקה',
            filePath: bookFile.path,
            fileType: 'txt',
          ),
        );

        // ספר שני באותה כותרת בקטגוריה אחרת — לאימות הבחנה לפי targetCategoryId.
        final otherFile = File(path.join(tempDir.path, 'הערות אחרות.txt'));
        await otherFile.writeAsString('תוכן מהקטגוריה השנייה');
        final otherCategoryId = await userBooksRepository.insertCategory(
          const migration_models.Category(
            title: 'תיקייה שנייה',
            parentId: null,
            level: 0,
            orderIndex: 2,
          ),
        );
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: otherCategoryId,
            sourceId: userSourceId,
            title: 'הערות לבדיקה',
            filePath: otherFile.path,
            fileType: 'txt',
          ),
        );

        await provider.initialize();

        final single = await provider.getLinkContent(
          Link(
            heRef: 'הערות',
            index1: 1,
            path2: 'הערות לבדיקה',
            index2: 2,
            connectionType: 'commentary',
            targetIsUserBook: true,
          ),
        );
        expect(single, 'שורה שנייה');

        final range = await provider.getLinkContent(
          Link(
            heRef: 'הערות',
            index1: 1,
            path2: 'הערות לבדיקה',
            index2: 2,
            index2End: 3,
            connectionType: 'commentary',
            targetIsUserBook: true,
          ),
        );
        expect(range, 'שורה שנייה<br>שורה שלישית');

        final outOfRange = await provider.getLinkContent(
          Link(
            heRef: 'הערות',
            index1: 1,
            path2: 'הערות לבדיקה',
            index2: 99,
            connectionType: 'commentary',
            targetIsUserBook: true,
          ),
        );
        expect(outOfRange, 'שגיאה: אינדקס מחוץ לטווח');

        // targetCategoryId מבחין בין שני ספרים בעלי אותה כותרת.
        final fromOtherCategory = await provider.getLinkContent(
          Link(
            heRef: 'הערות',
            index1: 1,
            path2: 'הערות לבדיקה',
            index2: 1,
            connectionType: 'commentary',
            targetIsUserBook: true,
            targetCategoryId: otherCategoryId,
          ),
        );
        expect(fromOtherCategory, 'תוכן מהקטגוריה השנייה');

        // ספר docx file-backed — התוכן עובר דרך ממיר ה-docx, ושורה 1 היא
        // תמיד <h1> עם כותרת הספר.
        final docxFile = File(path.join(tempDir.path, 'ספר דוקס.docx'));
        await docxFile.writeAsBytes(_buildMinimalDocx('תוכן פסקה'));
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: userCategoryId,
            sourceId: userSourceId,
            title: 'ספר דוקס',
            filePath: docxFile.path,
            fileType: 'docx',
          ),
        );
        final docxContent = await provider.getLinkContent(
          Link(
            heRef: 'דוקס',
            index1: 1,
            path2: 'ספר דוקס',
            index2: 1,
            connectionType: 'commentary',
            targetIsUserBook: true,
          ),
        );
        expect(docxContent, '<h1>ספר דוקס</h1>');

        // ספר PDF file-backed — קובץ בינארי לא מועבר למפענח הטקסט; נופל
        // למסלול ה-DB (שאין בו שורות) ומחזיר את הודעת השגיאה הרגילה.
        final pdfFile = File(path.join(tempDir.path, 'ספר סרוק.pdf'));
        await pdfFile.writeAsBytes([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF, 0xFE]);
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: userCategoryId,
            sourceId: userSourceId,
            title: 'ספר סרוק',
            filePath: pdfFile.path,
            fileType: 'pdf',
          ),
        );
        final pdfContent = await provider.getLinkContent(
          Link(
            heRef: 'סרוק',
            index1: 1,
            path2: 'ספר סרוק',
            index2: 1,
            connectionType: 'commentary',
            targetIsUserBook: true,
          ),
        );
        expect(pdfContent, 'שגיאה: אינדקס מחוץ לטווח');
      },
    );

    test(
      'buildLibraryCatalog ממזג ספרים אישיים לעץ הראשי לפי שם כשההגדרה מופעלת',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria_user_books_root_merge',
        );
        final libraryPath = path.join(tempDir.path, 'library');
        final dataRootPath = path.join(tempDir.path, 'data_root');
        final dbPath = path.join(
          libraryPath,
          DatabaseConstants.databaseFileName,
        );
        final database = MyDatabase.withPath(dbPath);
        final repository = SeforimRepository(database);
        final provider = DatabaseLibraryProvider.instance;
        final previousLibraryPath = Settings.getValue<String>(
          SettingsRepository.keyLibraryPath,
        );
        final previousFolderName = Settings.getValue<String>(
          SettingsRepository.keyLibraryFolderName,
        );
        final previousEffectiveDbPath = Settings.getValue<String>(
          SettingsRepository.keyDbEffectivePath,
        );
        final previousMergeFlag = Settings.getValue<bool>(
          SettingsRepository.keyMergeUserBooksIntoLibrary,
        );
        final previousDataRootPath = AppPaths.cachedDataRootPath;

        addTearDown(() => tempDir.delete(recursive: true));
        addTearDown(() => database.close());
        addTearDown(() => provider.clearCache());
        addTearDown(() => provider.sqliteProvider.dispose());
        addTearDown(
          () => AppPaths.debugOverrideDataRootPath(previousDataRootPath),
        );
        addTearDown(() => UserBooksDatabaseHolder.instance.close());
        addTearDown(() async {
          await Settings.setValue<bool>(
            SettingsRepository.keyMergeUserBooksIntoLibrary,
            previousMergeFlag ?? false,
          );
        });
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            previousEffectiveDbPath ?? '',
          );
        });
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            previousFolderName ?? '',
          );
        });
        addTearDown(() async {
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            previousLibraryPath ?? '',
          );
        });

        await Directory(libraryPath).create(recursive: true);
        await provider.sqliteProvider.dispose();
        provider.clearCache();
        await UserBooksDatabaseHolder.instance.close();
        AppPaths.debugOverrideDataRootPath(dataRootPath);
        await repository.ensureInitialized();

        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          libraryPath,
        );
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );
        await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath,
          '',
        );
        // הפעלת מצב המיזוג שאנו רוצים לבדוק.
        await Settings.setValue<bool>(
          SettingsRepository.keyMergeUserBooksIntoLibrary,
          true,
        );

        // seforim.db: קטגוריית-שורש "חסידות" עם תת "ברסלב" וספר ראשי בתוכה.
        final sourceId = await repository.insertSource('local-test', -10);
        final hasidutCategoryId = await repository.insertCategory(
          const migration_models.Category(
            title: 'חסידות',
            parentId: null,
            level: 0,
            orderIndex: 1,
          ),
        );
        final breslevCategoryId = await repository.insertCategory(
          migration_models.Category(
            title: 'ברסלב',
            parentId: hasidutCategoryId,
            level: 1,
            orderIndex: 1,
          ),
        );
        await repository.insertBook(
          migration_models.Book(
            id: 1,
            categoryId: breslevCategoryId,
            sourceId: sourceId,
            title: 'ליקוטי מוהר"ן',
            filePath: path.join(tempDir.path, 'main_book.txt'),
            fileType: 'txt',
          ),
        );

        // user_books.db: המשתמש בחר תיקיית-שורש "מסמכים" (זו לא צריכה
        // להופיע בעץ במצב מיזוג). בתוכה:
        //   חסידות/ברסלב/ספר ברסלב אישי  →  אמור להתמזג עם "חסידות/ברסלב"
        //   שיעורים/שיעור שבועי         →  אמור להופיע בשורש (אין התאמה)
        //   קובץ ישיר בתוך "מסמכים"      →  אמור להופיע בשורש הספרייה
        final userBooksRepository =
            await UserBooksDatabaseHolder.instance.repository;
        final userSourceId = await userBooksRepository.insertSource(
          'user-test',
          -20,
        );
        final userPersonalCategoryId = await userBooksRepository.insertCategory(
          const migration_models.Category(
            title: 'ספרים אישיים',
            parentId: null,
            level: 0,
            orderIndex: 1,
          ),
        );
        // "מסמכים" — התיקייה שהמשתמש בחר.
        final pickedFolderId = await userBooksRepository.insertCategory(
          migration_models.Category(
            title: 'מסמכים',
            parentId: userPersonalCategoryId,
            level: 1,
            orderIndex: 1,
          ),
        );
        final userHasidutId = await userBooksRepository.insertCategory(
          migration_models.Category(
            title: 'חסידות',
            parentId: pickedFolderId,
            level: 2,
            orderIndex: 1,
          ),
        );
        final userBreslevId = await userBooksRepository.insertCategory(
          migration_models.Category(
            title: 'ברסלב',
            parentId: userHasidutId,
            level: 3,
            orderIndex: 1,
          ),
        );
        final unmatchedCategoryId = await userBooksRepository.insertCategory(
          migration_models.Category(
            title: 'שיעורים',
            parentId: pickedFolderId,
            level: 2,
            orderIndex: 2,
          ),
        );
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: userBreslevId,
            sourceId: userSourceId,
            title: 'ספר ברסלב אישי',
            filePath: path.join(tempDir.path, 'user_breslev_book.txt'),
            fileType: 'txt',
          ),
        );
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: unmatchedCategoryId,
            sourceId: userSourceId,
            title: 'שיעור שבועי',
            filePath: path.join(tempDir.path, 'shiur.txt'),
            fileType: 'txt',
          ),
        );
        // קובץ שיושב ישירות בתוך "מסמכים" — צריך להגיע לשורש הספרייה.
        await userBooksRepository.insertBook(
          migration_models.Book(
            categoryId: pickedFolderId,
            sourceId: userSourceId,
            title: 'מכתב אישי',
            filePath: path.join(tempDir.path, 'letter.txt'),
            fileType: 'txt',
          ),
        );

        await provider.initialize();
        final library = await provider.buildLibraryCatalog({}, libraryPath);

        // אין קטגוריית "ספרים אישיים" וגם לא "מסמכים" — שתיהן נעקפו.
        expect(
          library.subCategories.where((c) => c.title == 'ספרים אישיים'),
          isEmpty,
          reason: 'במצב מיזוג אין צומת "ספרים אישיים" עליון',
        );
        expect(
          library.subCategories.where((c) => c.title == 'מסמכים'),
          isEmpty,
          reason: 'התיקייה שהמשתמש בחר ("מסמכים") לא אמורה להופיע בעץ',
        );

        // "חסידות" מהמשתמש מוזגה ל-"חסידות" הקיימת ב-seforim — ללא כפילות.
        final hasidutCategories = library.subCategories.where(
          (c) => c.title == 'חסידות',
        );
        expect(hasidutCategories, hasLength(1));
        final hasidutCategory = hasidutCategories.single;

        // "ברסלב" — קטגוריה ממוזגת אחת המכילה את שני הספרים.
        final breslevCategories = hasidutCategory.subCategories.where(
          (c) => c.title == 'ברסלב',
        );
        expect(breslevCategories, hasLength(1));
        final breslevCategory = breslevCategories.single;
        expect(
          breslevCategory.books.map((b) => b.title),
          containsAll(['ליקוטי מוהר"ן', 'ספר ברסלב אישי']),
        );

        // הספר האישי מסומן ב-isUserBook=true.
        final userBook = breslevCategory.books.firstWhere(
          (b) => b.title == 'ספר ברסלב אישי',
        );
        expect(userBook.isUserBook, isTrue);
        final mainBook = breslevCategory.books.firstWhere(
          (b) => b.title == 'ליקוטי מוהר"ן',
        );
        expect(mainBook.isUserBook, isFalse);

        // תיקייה ללא התאמה בעץ הראשי — מופיעה בשורש הספרייה (לא תחת "מסמכים").
        final unmatchedCategories = library.subCategories.where(
          (c) => c.title == 'שיעורים',
        );
        expect(
          unmatchedCategories,
          hasLength(1),
          reason: 'תיקייה ללא התאמה אמורה להופיע בשורש הספרייה',
        );
        final unmatchedCategory = unmatchedCategories.single;
        expect(
          unmatchedCategory.books.map((b) => b.title),
          contains('שיעור שבועי'),
        );

        // קובץ שיושב ישירות בתוך התיקייה הנבחרת — מופיע בשורש הספרייה.
        expect(
          library.books.map((b) => b.title),
          contains('מכתב אישי'),
          reason: 'קובץ ישירות תחת התיקייה הנבחרת אמור להגיע לשורש הספרייה',
        );
      },
    );

    test(
      'populateUserBooksCategoryForTesting ממלא קטגוריה קיימת בלי לשבור parent ו-category',
      () {
        final provider = DatabaseLibraryProvider.instance;
        provider.clearCache();

        final library = library_models.Library(categories: []);
        final personalCategory = library_models.Category(
          title: 'ספרים אישיים',
          description: '',
          shortDescription: '',
          order: 1,
          subCategories: [],
          books: [],
          parent: library,
        );
        library.subCategories.add(personalCategory);

        final existingCategory = library_models.Category(
          title: 'תיקייה קיימת',
          description: '',
          shortDescription: '',
          order: 1,
          subCategories: [],
          books: [],
          parent: personalCategory,
        );
        personalCategory.subCategories.add(existingCategory);

        provider.populateUserBooksCategoryForTesting(
          targetCategory: existingCategory,
          dbCategory: const migration_models.Category(
            id: 10,
            parentId: 1,
            title: 'תיקייה קיימת',
            level: 1,
            orderIndex: 1,
          ),
          booksByCategory: {
            10: [
              {
                'id': 100,
                'title': 'ספר קיים בעץ',
                'categoryId': 10,
                'orderIndex': 1,
                'fileType': 'txt',
              },
            ],
            11: [
              {
                'id': 101,
                'title': 'ספר פנימי',
                'categoryId': 11,
                'orderIndex': 1,
                'fileType': 'txt',
              },
            ],
          },
          categoriesByParent: {
            10: const [
              migration_models.Category(
                id: 11,
                parentId: 10,
                title: 'תת קטגוריה',
                level: 2,
                orderIndex: 1,
              ),
            ],
          },
          authorsByBookId: const {},
          metadata: const {},
        );

        expect(existingCategory.books, hasLength(1));
        expect(existingCategory.books.single.category, same(existingCategory));

        expect(existingCategory.subCategories, hasLength(1));
        final nestedCategory = existingCategory.subCategories.single;
        expect(nestedCategory.parent, same(existingCategory));
        expect(nestedCategory.path, '/ספרים אישיים/תיקייה קיימת/תת קטגוריה');
        expect(nestedCategory.books, hasLength(1));
        expect(nestedCategory.books.single.category, same(nestedCategory));
      },
    );

    test(
      'mergeLinksForTesting ממזג קישורים בלי כפילויות ושומר קישורים קודמים',
      () {
        final existing = [
          Link(
            heRef: 'א',
            index1: 75,
            path2: 'מפרש א',
            index2: 3,
            connectionType: 'reference',
          ),
          Link(
            heRef: 'ב',
            index1: 100,
            path2: 'מפרש ב',
            index2: 5,
            connectionType: 'reference',
          ),
        ];

        final incoming = [
          Link(
            heRef: 'ב',
            index1: 100,
            path2: 'מפרש ב',
            index2: 5,
            connectionType: 'reference',
          ),
          Link(
            heRef: 'ג',
            index1: 200,
            path2: 'מפרש ג',
            index2: 7,
            connectionType: 'reference',
          ),
        ];

        final merged = TextBookBloc.mergeLinksForTesting(existing, incoming);

        expect(merged, hasLength(3));
        expect(merged.map((link) => link.index1), [75, 100, 200]);
      },
    );
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
