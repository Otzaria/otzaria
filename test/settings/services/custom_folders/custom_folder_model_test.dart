import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as p;

/// המודל והמנהל של תיקיות הספרים המותאמות אישית. הרשימה נשמרת כ-JSON
/// בהגדרות ומגובה יחד איתן, ולכן צריכה לשרוד סבב סדרה־ופרסור מלא.
void main() {
  CustomFolder folder(String path, {bool addToDatabase = false}) =>
      CustomFolder(
        path: path,
        addToDatabase: addToDatabase,
        addedAt: DateTime(2026, 5, 6, 7, 8),
      );

  group('CustomFolder — סדרה', () {
    test('toJson/fromJson שומרים על כל השדות', () {
      final original = folder('/books/mine', addToDatabase: true);

      final restored = CustomFolder.fromJson(original.toJson());

      expect(restored.path, original.path);
      expect(restored.addToDatabase, isTrue);
      expect(restored.addedAt, original.addedAt);
    });

    test('addToDatabase חסר ב-JSON נקרא כ-false', () {
      final restored = CustomFolder.fromJson({
        'path': '/books',
        'addedAt': DateTime(2026, 1, 1).toIso8601String(),
      });

      expect(restored.addToDatabase, isFalse);
    });

    test('JSON ללא path זורק שגיאה', () {
      expect(
        () => CustomFolder.fromJson({
          'addedAt': DateTime(2026, 1, 1).toIso8601String(),
        }),
        throwsA(anything),
      );
    });

    test('addedAt שמור בפורמט ISO ונקרא חזרה זהה', () {
      final original = folder('/books');

      final json = original.toJson();

      expect(json['addedAt'], original.addedAt.toIso8601String());
      expect(CustomFolder.fromJson(json).addedAt, original.addedAt);
    });
  });

  group('CustomFolder — התנהגות', () {
    test('name מחזיר את שם התיקייה בלי הנתיב', () {
      expect(folder('/home/david/ספרים').name, 'ספרים');
      expect(folder(r'C:\Users\david\ספרים').name, 'ספרים');
    });

    test('name של נתיב שנגמר במפריד ריק', () {
      // מלכוד: נתיב עם מפריד סופי מפיק שם ריק. מסלול ההוספה מנרמל דרך
      // p.normalize, אבל נתיב שנשמר ידנית בהגדרות עלול להגיע כך.
      expect(folder('/home/david/ספרים/').name, isEmpty);
    });

    test('copyWith משנה רק את השדה שנמסר', () {
      final original = folder('/a');

      final updated = original.copyWith(addToDatabase: true);

      expect(updated.path, '/a');
      expect(updated.addToDatabase, isTrue);
      expect(updated.addedAt, original.addedAt);
    });

    test('copyWith ללא ארגומנטים מחזיר עותק זהה', () {
      final original = folder('/a', addToDatabase: true);

      final copy = original.copyWith();

      expect(copy.path, original.path);
      expect(copy.addToDatabase, original.addToDatabase);
      expect(copy.addedAt, original.addedAt);
    });

    test('addedAt אינו חלק מהזהות', () {
      final a = CustomFolder(path: '/same', addedAt: DateTime(2026, 1, 1));
      final b = CustomFolder(path: '/same', addedAt: DateTime(2030, 12, 31));

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('שינוי הגדרה יוצר ערך שונה — אחרת ה-state לא היה נפלט', () {
      final a = CustomFolder(path: '/same', addedAt: DateTime(2026, 1, 1));

      expect(a, isNot(equals(a.copyWith(addToDatabase: true))));
      expect(a, isNot(equals(a.copyWith(mergeIntoLibrary: false))));
    });

    test('נתיבים שונים אינם שווים', () {
      expect(folder('/a'), isNot(equals(folder('/b'))));
    });
  });

  group('CustomFoldersManager — טעינה ושמירה', () {
    test('סבב שמירה-טעינה משמר את הרשימה בסדרה', () {
      final folders = [
        folder('/a', addToDatabase: true),
        folder('/b'),
      ];

      final loaded = CustomFoldersManager.loadFolders(
        CustomFoldersManager.saveFolders(folders),
      );

      expect(loaded.map((f) => f.path), ['/a', '/b']);
      expect(loaded.first.addToDatabase, isTrue);
      expect(loaded.last.addToDatabase, isFalse);
    });

    test('null וריק מחזירים רשימה ריקה', () {
      expect(CustomFoldersManager.loadFolders(null), isEmpty);
      expect(CustomFoldersManager.loadFolders(''), isEmpty);
    });

    test('JSON פגום לגמרי מחזיר רשימה ריקה ולא זורק', () {
      expect(CustomFoldersManager.loadFolders('{{{'), isEmpty);
      expect(CustomFoldersManager.loadFolders('not json'), isEmpty);
    });

    test('רשומה פגומה אחת אינה מאבדת את שאר התיקיות', () {
      // הגנה מרכזית: קובץ הגדרות שנפגם חלקית לא מוחק את כל תיקיות המשתמש.
      final raw = jsonEncode([
        {'path': '/good', 'addedAt': DateTime(2026, 1, 1).toIso8601String()},
        {'addedAt': DateTime(2026, 1, 1).toIso8601String()},
        {'path': '/also-good', 'addedAt': 'לא תאריך'},
        {'path': '/last', 'addedAt': DateTime(2026, 1, 2).toIso8601String()},
      ]);

      final loaded = CustomFoldersManager.loadFolders(raw);

      expect(loaded.map((f) => f.path), ['/good', '/last']);
    });

    test('saveFolders של רשימה ריקה מפיק מערך JSON ריק', () {
      expect(CustomFoldersManager.saveFolders([]), '[]');
      expect(CustomFoldersManager.loadFolders('[]'), isEmpty);
    });

    test('hasFolders מבחין בין רשימה עם תיקיות לריקה', () {
      expect(
        CustomFoldersManager.hasFolders(
          CustomFoldersManager.saveFolders([folder('/a')]),
        ),
        isTrue,
      );
      expect(CustomFoldersManager.hasFolders('[]'), isFalse);
      expect(CustomFoldersManager.hasFolders(null), isFalse);
      expect(CustomFoldersManager.hasFolders('פגום'), isFalse);
    });
  });

  group('CustomFoldersManager — עריכת הרשימה', () {
    test('addFolder מוסיף תיקייה בסוף הרשימה', () {
      final result = CustomFoldersManager.addFolder([folder('/a')], '/b');

      expect(result.map((f) => f.path), ['/a', '/b']);
    });

    test('addFolder אינו מכפיל תיקייה קיימת', () {
      final existing = [folder('/a')];

      final result = CustomFoldersManager.addFolder(existing, '/a');

      expect(result, hasLength(1));
      expect(result, same(existing));
    });

    test('addFolder על רשימה ריקה יוצר רשומה אחת עם addToDatabase כבוי', () {
      final result = CustomFoldersManager.addFolder([], '/first');

      expect(result.single.path, '/first');
      expect(result.single.addToDatabase, isFalse);
    });

    test('removeFolder מסיר לפי נתיב ומשאיר את השאר', () {
      final result = CustomFoldersManager.removeFolder(
        [folder('/a'), folder('/b'), folder('/c')],
        '/b',
      );

      expect(result.map((f) => f.path), ['/a', '/c']);
    });

    test('removeFolder של נתיב שאינו ברשימה אינו משנה דבר', () {
      final result = CustomFoldersManager.removeFolder(
        [folder('/a')],
        '/missing',
      );

      expect(result.map((f) => f.path), ['/a']);
    });

    test('updateFolderDbSetting מחליף את הדגל של התיקייה בלבד', () {
      final result = CustomFoldersManager.updateFolderDbSetting(
        [folder('/a'), folder('/b')],
        '/b',
        true,
      );

      expect(result.firstWhere((f) => f.path == '/a').addToDatabase, isFalse);
      expect(result.firstWhere((f) => f.path == '/b').addToDatabase, isTrue);
    });

    test('updateFolderDbSetting שומר על addedAt המקורי', () {
      final original = folder('/a');

      final result = CustomFoldersManager.updateFolderDbSetting(
        [original],
        '/a',
        true,
      );

      expect(result.single.addedAt, original.addedAt);
    });

    test('updateFolderDbSetting של נתיב שאינו קיים אינו משנה דבר', () {
      final result = CustomFoldersManager.updateFolderDbSetting(
        [folder('/a', addToDatabase: true)],
        '/missing',
        false,
      );

      expect(result.single.addToDatabase, isTrue);
    });
  });

  group('CustomFolderSource', () {
    test('nameForFolder בנוי מהקידומת ומהנתיב המנורמל', () {
      final name = CustomFolderSource.nameForFolder('/books/mine');

      expect(name, startsWith(CustomFolderSource.prefix));
      expect(
        name,
        '${CustomFolderSource.prefix}'
        '${CustomFolderSource.normalizePath('/books/mine')}',
      );
    });

    test('normalizePath מקפל רכיבי נתיב מיותרים', () {
      expect(
        CustomFolderSource.normalizePath('/books/./sub/../mine'),
        p.normalize(
          Platform.isWindows ? r'\books\mine' : '/books/mine',
        ),
      );
    });

    test('נתיבים שקולים מפיקים אותו שם source', () {
      // ה-prune והמחיקה מזהים ספרי תיקייה לפי שם ה-source; נתיב שנרשם בכתיב
      // שונה חייב להתמפות לאותו שם, אחרת הספרים לא נמצאים.
      expect(
        CustomFolderSource.nameForFolder('/books/mine'),
        CustomFolderSource.nameForFolder('/books/./mine'),
      );
    });

    test('נתיבים שונים מפיקים שמות source שונים', () {
      expect(
        CustomFolderSource.nameForFolder('/books/a'),
        isNot(CustomFolderSource.nameForFolder('/books/b')),
      );
    });

    test('ב-Windows הכתיב אינו רגיש לאותיות גדולות', () {
      if (!Platform.isWindows) return;
      expect(
        CustomFolderSource.nameForFolder(r'C:\Books\Mine'),
        CustomFolderSource.nameForFolder(r'c:\books\mine'),
      );
    });

    test('שם ה-source הישן נשמר לזיהוי נתונים legacy', () {
      expect(CustomFolderSource.legacyExternalSourceName, 'external');
      expect(
        CustomFolderSource.legacyExternalSourceName,
        isNot(startsWith(CustomFolderSource.prefix)),
      );
    });
  });

  group('CustomFolder חריגת מיזוג', () {
    test('ברירת המחדל היא null — הליכה אחרי ההגדרה הגלובלית', () {
      final folder = CustomFolder(path: '/books', addedAt: DateTime(2026));
      expect(folder.mergeIntoLibrary, isNull);
      expect(folder.resolveMergeIntoLibrary(true), isTrue);
      expect(folder.resolveMergeIntoLibrary(false), isFalse);
    });

    test('חריגה מפורשת גוברת על ההגדרה הגלובלית', () {
      final folder = CustomFolder(
        path: '/books',
        mergeIntoLibrary: false,
        addedAt: DateTime(2026),
      );
      expect(folder.resolveMergeIntoLibrary(true), isFalse);
    });

    test('רשומה ישנה ללא המפתח נטענת כ-null', () {
      final folder = CustomFolder.fromJson({
        'path': '/books',
        'addToDatabase': true,
        'addedAt': DateTime(2026).toIso8601String(),
      });
      expect(folder.mergeIntoLibrary, isNull);
    });

    test('הלוך-ושוב ב-JSON משמר את החריגה', () {
      final folder = CustomFolder(
        path: '/books',
        mergeIntoLibrary: true,
        addedAt: DateTime(2026),
      );
      expect(
        CustomFolder.fromJson(folder.toJson()).mergeIntoLibrary,
        isTrue,
      );
    });

    test('updateFolderMergeSetting עם null מנקה את החריגה', () {
      final folders = [
        CustomFolder(
          path: '/a',
          mergeIntoLibrary: true,
          addedAt: DateTime(2026),
        ),
        CustomFolder(
          path: '/b',
          mergeIntoLibrary: true,
          addedAt: DateTime(2026),
        ),
      ];
      final updated = CustomFoldersManager.updateFolderMergeSetting(
        folders,
        '/a',
        null,
      );
      expect(updated.first.mergeIntoLibrary, isNull);
      expect(updated.last.mergeIntoLibrary, isTrue);
    });

    test('updateFolderMergeSetting מעדכן תיקיות בעלות אותו שם-בסיס יחד', () {
      final folders = [
        CustomFolder(
          path: '/alpha/shared',
          mergeIntoLibrary: true,
          addedAt: DateTime(2026),
        ),
        CustomFolder(path: '/beta/shared', addedAt: DateTime(2026)),
        CustomFolder(
          path: '/gamma/other',
          mergeIntoLibrary: true,
          addedAt: DateTime(2026),
        ),
      ];

      final updated = CustomFoldersManager.updateFolderMergeSetting(
        folders,
        '/alpha/shared',
        false,
      );

      expect(updated[0].mergeIntoLibrary, isFalse);
      expect(updated[1].mergeIntoLibrary, isFalse);
      expect(updated[2].mergeIntoLibrary, isTrue);
    });
  });
}
