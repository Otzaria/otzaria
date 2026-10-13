import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/catalogue_order_revision.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CatalogueOrderRevision.shouldStamp', () {
    test('אינדקס ריק שמצבו ידוע — נחתם', () {
      expect(
        CatalogueOrderRevision.shouldStamp(
          indexStateIsKnown: true,
          hasIndexedBooks: false,
        ),
        isTrue,
      );
    });

    test('אינדקס מלא לעולם אינו נחתם — חתימה הייתה מכריזה סדר ישן כתקין', () {
      expect(
        CatalogueOrderRevision.shouldStamp(
          indexStateIsKnown: true,
          hasIndexedBooks: true,
        ),
        isFalse,
      );
    });

    test('מצב לא ידוע אינו נחתם גם כשהרשימה ריקה', () {
      // כשל קריאת הספרים או מנוע על אינדקס זמני משאירים רשימה ריקה בלי
      // שהאינדקס שבדיסק ריק — חתימה כאן הייתה מנטרלת את המנגנון לצמיתות.
      expect(
        CatalogueOrderRevision.shouldStamp(
          indexStateIsKnown: false,
          hasIndexedBooks: false,
        ),
        isFalse,
      );
    });
  });

  group('CatalogueOrderRevision.isStale', () {
    test('מצב לא ידוע אינו מכריז מיושן — לא מוחקים אינדקס על סמך ספק', () {
      expect(
        CatalogueOrderRevision.isStale(
          storedRevision: null,
          hasIndexedBooks: true,
          indexStateIsKnown: false,
        ),
        isFalse,
      );
    });

    test('אינדקס בלי ספרים לעולם אינו מיושן', () {
      expect(
        CatalogueOrderRevision.isStale(
          storedRevision: null,
          hasIndexedBooks: false,
        ),
        isFalse,
      );
      expect(
        CatalogueOrderRevision.isStale(
          storedRevision: 1,
          hasIndexedBooks: false,
        ),
        isFalse,
      );
    });

    test('אינדקס קיים בלי חותם גרסה מיושן — זה מצב המשתמש המשדרג', () {
      expect(
        CatalogueOrderRevision.isStale(
          storedRevision: null,
          hasIndexedBooks: true,
        ),
        isTrue,
      );
    });

    test('אינדקס קיים עם גרסה ישנה מיושן', () {
      expect(
        CatalogueOrderRevision.isStale(
          storedRevision: kCatalogueOrderRevision - 1,
          hasIndexedBooks: true,
        ),
        isTrue,
      );
    });

    test('אינדקס קיים עם הגרסה הנוכחית אינו מיושן', () {
      expect(
        CatalogueOrderRevision.isStale(
          storedRevision: kCatalogueOrderRevision,
          hasIndexedBooks: true,
        ),
        isFalse,
      );
    });

    test('גרסה עתידית (חזרה לגרסה ישנה של התוכנה) מחייבת בנייה מחדש', () {
      expect(
        CatalogueOrderRevision.isStale(
          storedRevision: kCatalogueOrderRevision + 1,
          hasIndexedBooks: true,
        ),
        isTrue,
      );
    });
  });

  group('CatalogueOrderRevision קריאה וכתיבה', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('otzaria_cat_rev_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('read מחזיר null כשאין קובץ', () {
      expect(CatalogueOrderRevision.read(tempDir.path), isNull);
    });

    test('write ואז read מחזירים את הגרסה הנוכחית', () {
      expect(CatalogueOrderRevision.write(tempDir.path), isTrue);

      expect(
        CatalogueOrderRevision.read(tempDir.path),
        kCatalogueOrderRevision,
      );
      expect(CatalogueOrderRevision.fileFor(tempDir.path).existsSync(), isTrue);
    });

    test('חותם ישן בלי טווח הספרים האישיים מזוהה, ו-write מוסיף אותו', () {
      CatalogueOrderRevision.fileFor(tempDir.path).writeAsStringSync(
        '{"catalogueOrderRevision": $kCatalogueOrderRevision}',
      );
      expect(
        CatalogueOrderRevision.hasPersonalOrderRange(tempDir.path),
        isFalse,
      );

      CatalogueOrderRevision.write(tempDir.path);
      expect(
        CatalogueOrderRevision.hasPersonalOrderRange(tempDir.path),
        isTrue,
      );
      expect(
        CatalogueOrderRevision.read(tempDir.path),
        kCatalogueOrderRevision,
      );
    });

    test('write אינו מותיר קובץ זמני אחריו', () {
      CatalogueOrderRevision.write(tempDir.path);

      final leftovers = tempDir
          .listSync()
          .map((entity) => p.basename(entity.path))
          .where((name) => name.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('write חוזר על עצמו דורס את החותם הקודם', () {
      CatalogueOrderRevision.write(tempDir.path, revision: 1);
      expect(CatalogueOrderRevision.write(tempDir.path), isTrue);

      expect(
        CatalogueOrderRevision.read(tempDir.path),
        kCatalogueOrderRevision,
      );
    });

    test('write יוצר את תיקיית האינדקס אם אינה קיימת', () {
      final nested = '${tempDir.path}${Platform.pathSeparator}index';

      CatalogueOrderRevision.write(nested);

      expect(CatalogueOrderRevision.read(nested), kCatalogueOrderRevision);
    });

    test('קובץ פגום נקרא כ-null ולא זורק', () {
      CatalogueOrderRevision.fileFor(
        tempDir.path,
      ).writeAsStringSync('not json at all');

      expect(CatalogueOrderRevision.read(tempDir.path), isNull);
    });

    test('JSON תקין בלי המפתח נקרא כ-null', () {
      CatalogueOrderRevision.fileFor(
        tempDir.path,
      ).writeAsStringSync(jsonEncode({'other': 5}));

      expect(CatalogueOrderRevision.read(tempDir.path), isNull);
    });

    test('כתיבה שנכשלה מחזירה false ואינה מותירה חותם', () {
      // רגרסיה: ערך ההחזרה נבלע, האינדקס המלא נבנה בלי חותם, ובהפעלה
      // הבאה זוהה כישן — המשתמש נדרש למחוק ולבנות הכול מחדש.
      final blocked = p.join(tempDir.path, 'index');
      File(blocked).writeAsStringSync('קובץ במקום תיקיית האינדקס');

      expect(CatalogueOrderRevision.write(blocked), isFalse);
      expect(CatalogueOrderRevision.read(blocked), isNull);
    });

    test('כתיבה חוזרת אחרי כשל משלימה את החותם', () {
      final blocked = p.join(tempDir.path, 'index');
      final blocker = File(blocked)..writeAsStringSync('חוסם');
      expect(CatalogueOrderRevision.write(blocked), isFalse);

      blocker.deleteSync();

      expect(CatalogueOrderRevision.write(blocked), isTrue);
      expect(CatalogueOrderRevision.read(blocked), kCatalogueOrderRevision);
    });

    test('גרסה ישנה שנכתבה נקראת כמיושנת', () {
      CatalogueOrderRevision.write(tempDir.path, revision: 1);

      expect(
        CatalogueOrderRevision.isStale(
          storedRevision: CatalogueOrderRevision.read(tempDir.path),
          hasIndexedBooks: true,
        ),
        isTrue,
      );
    });
  });
}
