import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/info/personal_folders_info.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:path/path.dart' as p;

/// מקטע `folders` הוא ממשק מכונה (`otzaria://info/folders` ו-`otzaria info
/// folders`), והוא חייב לזהות בדיוק את מה שסורק הספרייה מזהה — אחרת הדוח
/// מבטיח ספרים שלא ייקלטו, או מסתיר ספרים שכן.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('otzaria_folders_info');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File write(String relativePath, String content) {
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  group('scanFolder — אילו קבצים נספרים', () {
    test('אוסף סיומות נתמכות, רקורסיבית, ומדלג על שאר הקבצים', () async {
      write('בראשית.txt', 'א');
      write('מדף/ויקרא.txt', 'ב');
      write('מדף/שולחן ערוך.pdf', '%PDF-1.4');
      write('הערות.ini', 'not a book');
      write('archive.zip', 'PK');

      final scan = await PersonalFoldersInfo.scanFolder(root.path);

      expect(scan.exists, isTrue);
      expect(scan.fileCount, 3);
      expect(scan.countByType, {'pdf': 1, 'txt': 2});
      expect(
        scan.files.map((f) => f['name']),
        containsAll(['בראשית.txt', 'ויקרא.txt', 'שולחן ערוך.pdf']),
      );
    });

    test('מדלג על קבצים ותיקיות מוסתרים, כמו הסורק', () async {
      write('.hidden/ספר.txt', 'א');
      write(r'~$temp.docx', 'א');
      write('ספר.txt', 'א');

      final scan = await PersonalFoldersInfo.scanFolder(root.path);

      expect(scan.fileCount, 1);
      expect(scan.files.single['name'], 'ספר.txt');
    });

    test('‎.xml‎ נספר רק כשתוכנו מסמך Word', () async {
      write('settings.xml', '<?xml version="1.0"?><config><a/></config>');
      write(
        'doc.xml',
        '<?xml version="1.0"?><w:wordDocument xmlns:w="x"> </w:wordDocument>',
      );

      final scan = await PersonalFoldersInfo.scanFolder(root.path);

      expect(scan.fileCount, 1);
      expect(scan.files.single['name'], 'doc.xml');
      expect(scan.countByType, {'xml': 1});
    });

    test('תיקייה שאינה קיימת מדווחת exists:false בלי לזרוק', () async {
      final scan = await PersonalFoldersInfo.scanFolder(
        p.join(root.path, 'לא-קיים'),
      );

      expect(scan.exists, isFalse);
      expect(scan.fileCount, 0);
      expect(scan.files, isEmpty);
    });
  });

  group('scanFolder — תקרת הקבצים', () {
    test('fileLimit מקצץ את הרשימה אך לא את הספירה', () async {
      for (var i = 0; i < 5; i++) {
        write('ספר$i.txt', 'א');
      }

      final scan = await PersonalFoldersInfo.scanFolder(
        root.path,
        fileLimit: 2,
      );

      expect(scan.fileCount, 5);
      expect(scan.files, hasLength(2));
      expect(scan.countByType, {'txt': 5});
    });

    test('fileLimit=0 מחזיר ספירות בלבד', () async {
      write('ספר.txt', 'א');

      final scan = await PersonalFoldersInfo.scanFolder(
        root.path,
        fileLimit: 0,
      );

      expect(scan.fileCount, 1);
      expect(scan.files, isEmpty);
    });

    test('הרשימה ממוינת לפי נתיב — אותו דוח בכל הרצה', () async {
      write('ג.txt', 'א');
      write('א.txt', 'א');
      write('ב.txt', 'א');

      final scan = await PersonalFoldersInfo.scanFolder(root.path);
      final paths = scan.files.map((f) => f['path'] as String).toList();

      expect(paths, List<String>.from(paths)..sort());
    });
  });

  group('collect — חוזה ה-JSON', () {
    test('supportedExtensions נגזר מה-registry היחיד ולא מרשימה מקומית', () async {
      final section = await PersonalFoldersInfo.collect(
        foldersOverride: const [],
      );

      expect(section['supportedExtensions'], kSupportedBookExtensions);
      expect(section['configuredCount'], 0);
      expect(section['existingCount'], 0);
      expect(section['totalFiles'], 0);
      expect(section['folders'], isEmpty);
    });

    test('רשומת תיקייה נושאת את ההגדרות ואת תוצאות הסריקה', () async {
      write('ספר.txt', 'אבג');
      write('אחר.pdf', '%PDF-1.4');
      final addedAt = DateTime.utc(2026, 3, 1, 12);

      final section = await PersonalFoldersInfo.collect(
        foldersOverride: [
          CustomFolder(
            path: root.path,
            addToDatabase: true,
            hidden: true,
            addedAt: addedAt,
          ),
          CustomFolder(path: p.join(root.path, 'אין'), addedAt: addedAt),
        ],
      );

      expect(section['configuredCount'], 2);
      expect(section['existingCount'], 1);
      expect(section['totalFiles'], 2);
      expect(section['fileLimit'], PersonalFoldersInfo.defaultFileLimit);

      final folders = section['folders'] as List;
      final first = folders.first as Map<String, dynamic>;
      expect(first['path'], root.path);
      expect(first['exists'], isTrue);
      expect(first['addToDatabase'], isTrue);
      expect(first['hidden'], isTrue);
      // חריגה לא הוגדרה, ולכן הערך האפקטיבי הוא הגלובלי והמקור מסומן ככזה.
      expect(first['mergeIntoLibrarySource'], 'default');
      expect(first['addedAt'], addedAt.toIso8601String());
      expect(first['fileCount'], 2);
      expect(first['filesTruncated'], isFalse);
      expect(first['files'], hasLength(2));

      final missing = folders[1] as Map<String, dynamic>;
      expect(missing['exists'], isFalse);
      expect(missing['fileCount'], 0);
    });

    test('files מושמט לגמרי כש-fileLimit=0', () async {
      write('ספר.txt', 'א');

      final section = await PersonalFoldersInfo.collect(
        fileLimit: 0,
        foldersOverride: [
          CustomFolder(path: root.path, addedAt: DateTime.utc(2026)),
        ],
      );

      final folder = (section['folders'] as List).single as Map;
      expect(folder.containsKey('files'), isFalse);
      expect(folder.containsKey('filesTruncated'), isFalse);
      expect(folder['fileCount'], 1);
    });

    test('חריגת מיזוג של תיקייה גוברת על ברירת המחדל ומסומנת', () async {
      final section = await PersonalFoldersInfo.collect(
        foldersOverride: [
          CustomFolder(
            path: root.path,
            mergeIntoLibrary: true,
            addedAt: DateTime.utc(2026),
          ),
        ],
      );

      final folder = (section['folders'] as List).single as Map;
      expect(folder['mergeIntoLibrary'], isTrue);
      expect(folder['mergeIntoLibrarySource'], 'folder');
    });
  });
}
