import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/installed_fonts.dart';

FontRow _row(
  String name, {
  int charset = 0,
  int pitchAndFamily = 0,
  int fontType = 4,
}) => (
  name: name,
  charset: charset,
  pitchAndFamily: pitchAndFamily,
  fontType: fontType,
);

List<Map<String, dynamic>> _families(Map<String, dynamic> result) =>
    (result['families'] as List).cast<Map<String, dynamic>>();

void main() {
  setUp(() => InstalledFonts.debugOverrideResult(null));
  tearDown(() => InstalledFonts.debugOverrideResult(null));

  // הרכבת התשובה נבדקת משורות סינתטיות, ולכן רצה בכל פלטפורמה — גם ב-CI
  // שאינו Windows, שם המנייה החיה אינה זמינה.
  group('buildResult', () {
    test('משפחה בשני charsets מתכווצת לרשומה אחת עם שני scripts', () {
      final result = InstalledFonts.buildResult([
        _row('Arial', charset: 177),
        _row('Arial', charset: 0),
      ], platform: 'windows');

      final families = _families(result);
      expect(families, hasLength(1));
      expect(families.single['name'], 'Arial');
      expect(families.single['scripts'], ['hebrew', 'latin']);
    });

    test('שם שמתחיל ב-@ מדולג, והמנייה ממשיכה אחריו', () {
      final result = InstalledFonts.buildResult([
        _row('@MS Gothic', charset: 128),
        _row('David', charset: 177),
      ], platform: 'windows');

      expect(_families(result).map((f) => f['name']), ['David']);
    });

    test('שם ריק מדולג', () {
      final result = InstalledFonts.buildResult([
        _row(''),
        _row('David', charset: 177),
      ], platform: 'windows');

      expect(_families(result).map((f) => f['name']), ['David']);
    });

    test('גופן raster מדולג, ו-OpenType/CFF (DEVICE) נשמר', () {
      final result = InstalledFonts.buildResult([
        _row('Terminal', fontType: 0x0001),
        _row('Parshendata FM', fontType: 0x0002),
        _row('David', fontType: 0x0004),
        _row('Modern', fontType: 0),
      ], platform: 'windows');

      expect(_families(result).map((f) => f['name']), [
        'David',
        'Modern',
        'Parshendata FM',
      ]);
    });

    test('כל charset מהחוזה ממופה נכון, והשאר ל-latin', () {
      const expected = {
        177: 'hebrew',
        178: 'arabic',
        204: 'cyrillic',
        161: 'greek',
        128: 'cjk',
        129: 'cjk',
        134: 'cjk',
        136: 'cjk',
        130: 'cjk',
        222: 'thai',
        2: 'symbol',
        0: 'latin',
        162: 'latin',
        238: 'latin',
        255: 'latin',
      };

      for (final entry in expected.entries) {
        final result = InstalledFonts.buildResult([
          _row('F', charset: entry.key),
        ], platform: 'windows');
        expect(
          _families(result).single['scripts'],
          [entry.value],
          reason: 'charset ${entry.key}',
        );
      }
    });

    test('monospace רק כששני ביטי ה-pitch הם 1', () {
      Object? mono(int pitch) => _families(
        InstalledFonts.buildResult([
          _row('F', pitchAndFamily: pitch),
        ], platform: 'windows'),
      ).single['monospace'];

      expect(mono(1), isTrue);
      expect(mono(0x31), isTrue, reason: 'ביטי המשפחה העליונים אינם משנים');
      expect(mono(0), isFalse);
      expect(mono(2), isFalse);
    });

    test('הרשימה ממוינת לפי שם', () {
      final result = InstalledFonts.buildResult([
        _row('Zapf'),
        _row('Arial'),
        _row('Miriam'),
      ], platform: 'windows');

      expect(_families(result).map((f) => f['name']), [
        'Arial',
        'Miriam',
        'Zapf',
      ]);
    });

    test('בלי שורות — families ריק, וזו אינה שגיאה', () {
      final result = InstalledFonts.buildResult(const [], platform: 'linux');
      expect(_families(result), isEmpty);
      expect(result['platform'], 'linux');
    });
  });

  test('פלטפורמה שאין בה מימוש מחזירה families ריק', () {
    final result = InstalledFonts.list();
    expect(result['platform'], Platform.operatingSystem);
    expect(_families(result), isEmpty);
  }, testOn: '!windows');

  // מנייה אמיתית מול GDI. תלויה בגופני המערכת, ולכן נצמדת למה שקיים בכל
  // התקנת Windows ולא לרשימה מדויקת.
  group('מנייה חיה', () {
    test('מחזירה מאות משפחות עם platform: windows', () {
      final result = InstalledFonts.list();
      expect(result['platform'], 'windows');
      expect(_families(result).length, greaterThan(100));
    }, testOn: 'windows');

    test('אין כפילות שם, אין @, ואין גופני raster ישנים', () {
      final names = _families(
        InstalledFonts.list(),
      ).map((f) => f['name'] as String).toList();

      expect(names.toSet().length, names.length, reason: 'שם חוזר ברשימה');
      expect(names.where((n) => n.startsWith('@')), isEmpty);
      expect(names.where((n) => n.isEmpty), isEmpty);
      // דילוג על שורה אינו עוצר את המנייה: אלה סוננו והרשימה נמשכה אחריהם.
      expect(names, isNot(contains('Terminal')));
      expect(names, isNot(contains('MS Sans Serif')));
    }, testOn: 'windows');

    test('הרשימה ממוינת, וכל scripts הוא מזהה מוכר', () {
      const known = {
        'latin',
        'hebrew',
        'arabic',
        'cyrillic',
        'greek',
        'cjk',
        'thai',
        'symbol',
      };
      final families = _families(InstalledFonts.list());
      final names = families.map((f) => f['name'] as String).toList();
      expect(names, orderedEquals([...names]..sort()));

      for (final family in families) {
        final scripts = (family['scripts'] as List).cast<String>();
        expect(scripts, isNotEmpty, reason: '${family['name']} בלי scripts');
        expect(scripts.toSet().difference(known), isEmpty);
        expect(family['monospace'], isA<bool>());
      }
    }, testOn: 'windows');

    test('גופני העברית של Windows מקבלים hebrew', () {
      final byName = {
        for (final f in _families(InstalledFonts.list()))
          f['name'] as String: (f['scripts'] as List).cast<String>(),
      };

      final present = const [
        'David',
        'FrankRuehl',
        'Narkisim',
      ].where(byName.containsKey);
      expect(present, isNotEmpty, reason: 'אין גופני עברית מותקנים במכונה');
      for (final name in present) {
        expect(byName[name], contains('hebrew'), reason: name);
      }
    }, testOn: 'windows');

    test('Consolas monospace, Arial לא', () {
      final byName = {
        for (final f in _families(InstalledFonts.list()))
          f['name'] as String: f['monospace'] as bool,
      };

      // מכונה מצומצמת עשויה שלא לכלול אותם; מה שקיים חייב להיות נכון.
      if (byName.containsKey('Consolas')) {
        expect(byName['Consolas'], isTrue);
      }
      if (byName.containsKey('Arial')) {
        expect(byName['Arial'], isFalse);
      }
    }, testOn: 'windows');

    test('מנייה אחת בלבד — הקריאה השנייה מחזירה את אותו מופע', () {
      final first = InstalledFonts.list();
      expect(identical(InstalledFonts.list(), first), isTrue);
    }, testOn: 'windows');
  });
}
