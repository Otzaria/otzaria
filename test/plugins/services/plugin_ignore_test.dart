import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_ignore.dart';
import 'package:path/path.dart' as p;

PluginIgnore _ignore(List<String> lines) => PluginIgnore.fromLines(lines);

void main() {
  group('תחביר .gitignore', () {
    test('שורות ריקות והערות אינן כללים', () {
      final ignore = _ignore(['', '   ', '# comment', '*.map']);
      expect(ignore.ruleCount, 1);
      expect(ignore.ignores('a.map'), isTrue);
    });

    test('תבנית ללא / מתאימה בכל עומק', () {
      final ignore = _ignore(['*.map']);
      expect(ignore.ignores('a.map'), isTrue);
      expect(ignore.ignores('src/deep/a.map'), isTrue);
      expect(ignore.ignores('src/a.js'), isFalse);
    });

    test('תבנית עם / מעוגנת לשורש התוסף', () {
      final ignore = _ignore(['src/dev.js']);
      expect(ignore.ignores('src/dev.js'), isTrue);
      expect(ignore.ignores('lib/src/dev.js'), isFalse);
    });

    test('/ מוביל מעגן אף הוא לשורש', () {
      final ignore = _ignore(['/dev.js']);
      expect(ignore.ignores('dev.js'), isTrue);
      expect(ignore.ignores('src/dev.js'), isFalse);
    });

    test('* אינו חוצה מקטע נתיב', () {
      final ignore = _ignore(['src/*.js']);
      expect(ignore.ignores('src/a.js'), isTrue);
      expect(ignore.ignores('src/deep/a.js'), isFalse);
    });

    test('** חוצה מקטעים', () {
      final ignore = _ignore(['src/**/*.js']);
      expect(ignore.ignores('src/a.js'), isTrue);
      expect(ignore.ignores('src/deep/nested/a.js'), isTrue);
      expect(ignore.ignores('other/a.js'), isFalse);
    });

    test('** סופי מחריג את כל תת-העץ', () {
      final ignore = _ignore(['vendor/**']);
      expect(ignore.ignores('vendor/a.js'), isTrue);
      expect(ignore.ignores('vendor/deep/a.js'), isTrue);
    });

    test('? מתאים תו בודד בתוך מקטע', () {
      final ignore = _ignore(['a?.js']);
      expect(ignore.ignores('ab.js'), isTrue);
      expect(ignore.ignores('abc.js'), isFalse);
      expect(ignore.ignores('a/b.js'), isFalse);
    });

    test('תווים מיוחדים ב-RegExp מטופלים מילולית', () {
      final ignore = _ignore(['a+b(1).js']);
      expect(ignore.ignores('a+b(1).js'), isTrue);
      expect(ignore.ignores('aXbY1Zjs'), isFalse);
    });

    test('שם תיקייה מחריג את כל תת-העץ שלה', () {
      final ignore = _ignore(['node_modules']);
      expect(ignore.ignores('node_modules'), isTrue);
      expect(ignore.ignores('node_modules/pkg/index.js'), isTrue);
      expect(ignore.ignores('src/node_modules/pkg/index.js'), isTrue);
    });

    test('/ בסוף = תיקייה בלבד, לא קובץ באותו שם', () {
      final ignore = _ignore(['build/']);
      expect(ignore.ignores('build/out.js'), isTrue);
      expect(
        ignore.ignores('build'),
        isFalse,
        reason: 'תבנית תיקייה-בלבד חייבת מקטע-צאצא',
      );
    });
  });

  group('סדר קדימויות ושלילה', () {
    test('הכלל האחרון שמתאים קובע', () {
      final ignore = _ignore(['*.js', '!keep.js']);
      expect(ignore.ignores('a.js'), isTrue);
      expect(ignore.ignores('keep.js'), isFalse);
    });

    test('החרגה מאוחרת גוברת על שלילה מוקדמת', () {
      final ignore = _ignore(['!keep.js', '*.js']);
      expect(ignore.ignores('keep.js'), isTrue);
    });

    test('hasNegation משקף קיום כללי !', () {
      expect(_ignore(['*.js']).hasNegation, isFalse);
      expect(_ignore(['*.js', '!keep.js']).hasNegation, isTrue);
    });

    test('שלילה בתוך תיקייה מוחרגת', () {
      final ignore = _ignore(['assets/', '!assets/icon.png']);
      expect(ignore.ignores('assets/big.bin'), isTrue);
      expect(ignore.ignores('assets/icon.png'), isFalse);
    });
  });

  group('reIncludes', () {
    test('true רק כשהכלל האחרון שמתאים הוא !', () {
      final ignore = _ignore(['*.md', '!help.md']);
      expect(ignore.reIncludes('help.md'), isTrue);
      expect(ignore.reIncludes('other.md'), isFalse);
    });

    test('נתיב שאין לו אף כלל מתאים אינו re-included', () {
      final ignore = _ignore(['!help.md']);
      expect(ignore.reIncludes('index.html'), isFalse);
      expect(ignore.reIncludes('help.md'), isTrue);
    });

    test('החרגה שבאה אחרי ה-! מבטלת את ההחזרה', () {
      final ignore = _ignore(['!help.md', '*.md']);
      expect(ignore.reIncludes('help.md'), isFalse);
      expect(ignore.ignores('help.md'), isTrue);
    });

    test('! על נתיב מקונן ובתיקייה', () {
      final ignore = _ignore(['!screenshots/hero.png', '!docs/']);
      expect(ignore.reIncludes('screenshots/hero.png'), isTrue);
      expect(ignore.reIncludes('screenshots/other.png'), isFalse);
      expect(ignore.reIncludes('docs/guide.md'), isTrue);
      expect(ignore.reIncludes('docs'), isFalse);
    });

    test('! מפורש הוא ההבדל בין נארז למוחרג', () {
      // האריזה מחריגה קבצי מטא-דאטה (*.md), ורק reIncludes מחזיר אותם.
      final without = _ignore(['*.map']);
      final with_ = _ignore(['*.map', '!help.md']);
      expect(without.reIncludes('help.md'), isFalse);
      expect(with_.reIncludes('help.md'), isTrue);
    });
  });

  group('load', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('otzignore_test');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('בהיעדר הקובץ — לא מחריג דבר', () {
      final ignore = PluginIgnore.load(dir.path);
      expect(ignore.ruleCount, 0);
      expect(ignore.hasNegation, isFalse);
      expect(ignore.ignores('anything.js'), isFalse);
      expect(ignore.reIncludes('anything.js'), isFalse);
    });

    test('קורא כללים מהקובץ, כולל שורות CRLF', () {
      File(
        p.join(dir.path, kOtzignoreFilename),
      ).writeAsStringSync('# c\r\n*.map\r\n!keep.map\r\n');

      final ignore = PluginIgnore.load(dir.path);

      expect(ignore.ruleCount, 2);
      expect(ignore.ignores('a.map'), isTrue);
      expect(ignore.reIncludes('keep.map'), isTrue);
    });
  });
}
