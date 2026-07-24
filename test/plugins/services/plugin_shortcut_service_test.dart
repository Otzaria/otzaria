import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PluginShortcutService.buildWindowsUrl', () {
    test('פורמט InternetShortcut עם השורות הנכונות ו-CRLF', () {
      final content = PluginShortcutService.buildWindowsUrl(
        'otzaria://open/plugin/com.x',
      );
      expect(
        content,
        '[InternetShortcut]\r\nURL=otzaria://open/plugin/com.x\r\n',
      );
    });
  });

  group('PluginShortcutService.buildWebloc', () {
    test('plist תקין עם ה-URL', () {
      final content = PluginShortcutService.buildWebloc(
        'otzaria://open/plugin/com.x',
      );
      expect(content, contains('<plist version="1.0">'));
      expect(content, contains('<key>URL</key>'));
      expect(content, contains('<string>otzaria://open/plugin/com.x</string>'));
    });

    test('escaping של תווי XML ב-URL', () {
      final content = PluginShortcutService.buildWebloc(
        'otzaria://open/search?q=a&b',
      );
      expect(content, contains('q=a&amp;b'));
      expect(content, isNot(contains('q=a&b<')));
    });
  });

  group('PluginShortcutService.buildLinuxDesktop', () {
    test('Desktop Entry עם xdg-open והשם', () {
      final content = PluginShortcutService.buildLinuxDesktop(
        'otzaria://open/plugin/com.x',
        'התוסף שלי',
      );
      expect(content, contains('[Desktop Entry]'));
      expect(content, contains('Type=Application'));
      expect(content, contains('Name=התוסף שלי'));
      expect(content, contains('Exec=xdg-open "otzaria://open/plugin/com.x"'));
    });
  });

  group('PluginShortcutService.sanitizeFileName', () {
    test('מסיר תווים אסורים בשמות קבצים', () {
      expect(
        PluginShortcutService.sanitizeFileName('a/b\\c:d*e?f"g<h>i|j'),
        'a b c d e f g h i j',
      );
    });

    test('מסיר תווי בקרה ושורות חדשות (מניעת הזרקה)', () {
      expect(
        PluginShortcutService.sanitizeFileName('name\nwith\rnewlines'),
        'name with newlines',
      );
    });

    test('מקצץ רווחים בקצוות', () {
      expect(PluginShortcutService.sanitizeFileName('  שם  '), 'שם');
    });

    test('מחרוזת שמכילה רק תווים אסורים הופכת לריקה', () {
      expect(PluginShortcutService.sanitizeFileName('///').trim(), '');
    });
  });

  group('PluginShortcutService.createShortcut', () {
    test('שם ריק לאחר ניקוי נכשל', () async {
      const service = PluginShortcutService();
      expect(
        () => service.createShortcut(
          deepLink: 'otzaria://open/plugin/com.x',
          label: '///',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('startMenu אינו נתמך מחוץ ל-Windows', () async {
      if (Platform.isWindows) return;
      const service = PluginShortcutService();
      expect(
        () => service.createShortcut(
          deepLink: 'otzaria://open/plugin/com.x',
          label: 'בדיקה',
          location: ShortcutLocation.startMenu,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PluginShortcutService.writeUniqueShortcut', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('otz_shortcut_test');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    const service = PluginShortcutService();

    test('כותב את הקובץ עם התוכן והשם המבוקש', () async {
      final path = await service.writeUniqueShortcut(
        dirPath: tmp.path,
        baseName: 'foo',
        extension: '.url',
        content: 'CONTENT',
      );
      expect(p.basename(path), 'foo.url');
      expect(File(path).readAsStringSync(), 'CONTENT');
    });

    test('לא דורס קובץ קיים — יוצר שם ייחודי', () async {
      final p1 = await service.writeUniqueShortcut(
        dirPath: tmp.path,
        baseName: 'foo',
        extension: '.url',
        content: 'A',
      );
      final p2 = await service.writeUniqueShortcut(
        dirPath: tmp.path,
        baseName: 'foo',
        extension: '.url',
        content: 'B',
      );

      expect(p1, isNot(p2));
      expect(p.basename(p2), 'foo (2).url');
      expect(File(p1).readAsStringSync(), 'A'); // המקורי לא נדרס
      expect(File(p2).readAsStringSync(), 'B');
    });

    test('לא כותב דרך symlink קיים בשם היעד', () async {
      // קובץ מטרה + symlink בשם שאליו ננסה לכתוב.
      final outside = File(p.join(tmp.path, 'real-target.txt'))
        ..writeAsStringSync('ORIGINAL');
      Link(p.join(tmp.path, 'foo.url')).createSync(outside.path);

      final written = await service.writeUniqueShortcut(
        dirPath: tmp.path,
        baseName: 'foo',
        extension: '.url',
        content: 'NEW',
      );

      expect(p.basename(written), 'foo (2).url'); // לא נכתב דרך ה-symlink
      expect(outside.readAsStringSync(), 'ORIGINAL'); // היעד לא השתנה
    });
  });
}
