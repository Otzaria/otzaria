import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_bibliography_reader.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_bibliography.dart';
import 'package:path/path.dart' as p;

/// עמודי הביבליוגרפיה של פרויקט השו"ת.
///
/// כל דוגמה כאן היא עמוד **אמיתי** מ-`HELP/Respheb.chm` של CD25, כולל
/// הקידוד המקורי — CP1255. כל השאר הוא נגזרת: אם הפענוח או הניתוח
/// ישתנו, הבדיקות האלה נופלות לפני שספר מקבל מהדורה שגויה.
Uint8List cp1255(String text) {
  const reverse = {
    0x05D0: 0xE0,
    0x05D1: 0xE1,
    0x05D2: 0xE2,
    0x05D3: 0xE3,
    0x05D4: 0xE4,
    0x05D5: 0xE5,
    0x05D6: 0xE6,
    0x05D7: 0xE7,
    0x05D8: 0xE8,
    0x05D9: 0xE9,
    0x05DA: 0xEA,
    0x05DB: 0xEB,
    0x05DC: 0xEC,
    0x05DD: 0xED,
    0x05DE: 0xEE,
    0x05DF: 0xEF,
    0x05E0: 0xF0,
    0x05E1: 0xF1,
    0x05E2: 0xF2,
    0x05E3: 0xF3,
    0x05E4: 0xF4,
    0x05E5: 0xF5,
    0x05E6: 0xF6,
    0x05E7: 0xF7,
    0x05E8: 0xF8,
    0x05E9: 0xF9,
    0x05EA: 0xFA,
    0x05F3: 0xD7,
    0x05F4: 0xD8,
    0x2013: 0x96,
  };
  return Uint8List.fromList([
    for (final unit in text.codeUnits)
      if (unit < 0x80) unit else reverse[unit] ?? 0x3F,
  ]);
}

/// עמוד ביבליוגרפיה, במבנה שבו המאגר כותב אותם.
String page(String title, List<String> body) =>
    '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">\n'
    '<HTML DIR=rtl>\n<HEAD>\n'
    '<META HTTP-EQUIV="Content-Type" Content="text/html; charset=Windows-1255">\n'
    '<TITLE>$title</TITLE>\n</HEAD>\n<BODY>\n'
    '<h4><b><font face="Arial">$title</FONT></b></h4>\n'
    '${body.map((line) => '<P><font face="Arial" size="2">$line</FONT></P>\n').join()}'
    '</BODY>\n</HTML>\n';

void main() {
  group('פענוח CP1255', () {
    test('אותיות עבריות, גרשיים וסימני כיווניות', () {
      expect(
        ResponsaBibliography.decodeCp1255(cp1255('שו״ת אבני נזר')),
        'שו״ת אבני נזר',
      );
      expect(
        ResponsaBibliography.decodeCp1255(Uint8List.fromList([0xFE, 0xE0])),
        '‏א',
      );
    });

    test('בית שאינו מוגדר בקידוד הופך לרווח ולא לתו החלפה', () {
      expect(
        ResponsaBibliography.decodeCp1255(Uint8List.fromList([0x81])),
        ' ',
      );
    });

    test('קריאה כ-Latin-1 הייתה מחזירה ג׳יבריש — זו הסיבה לטבלה', () {
      final bytes = cp1255('ירושלים');
      expect(latin1.decode(bytes), isNot('ירושלים'));
      expect(ResponsaBibliography.decodeCp1255(bytes), 'ירושלים');
    });
  });

  group('ניתוח עמוד', () {
    ({List<String> names, ResponsaBibliographyEntry entry})? parse(
      String title,
      List<String> body,
    ) => ResponsaBibliography.parsePage(page(title, body));

    test('שו"ת: שורת מחבר ואחריה שורת מהדורה', () {
      final parsed = parse('שו"ת אבני נזר', [
        'רבי אברהם בורנשטיין (פולין המאה ה- 19)',
        'ירושלים תשס"ו',
      ]);
      expect(parsed, isNotNull);
      expect(parsed!.entry.author, 'רבי אברהם בורנשטיין (פולין המאה ה- 19)');
      expect(parsed.entry.pubPlace, 'ירושלים');
      expect(parsed.entry.pubDate, 'תשס"ו');
    });

    test('בלי שורת מחבר — מהדורה בלבד, והמחבר נשאר ריק', () {
      final parsed = parse('חתם סופר', ['ד"צ וינה תרמ"ט, פיעטרקוב תרס"ג']);
      expect(parsed!.entry.author, isNull);
      expect(parsed.entry.pubPlace, 'וינה');
      expect(parsed.entry.pubDate, 'תרמ"ט');
    });

    test('שם מהדורה לפני המקום אינו נחשב מקום', () {
      final parsed = parse('ערוך לנר', ['מהדורת אור החיים, בני ברק תשס"ד']);
      expect(parsed!.entry.pubPlace, 'בני ברק');
      expect(parsed.entry.pubDate, 'תשס"ד');
    });

    test('טווח שנים נשמר כפי שהוא', () {
      final parsed = parse('ערוך השולחן', ['ורשא תרמ"ד-תרנ"ג']);
      expect(parsed!.entry.pubPlace, 'ורשא');
      expect(parsed.entry.pubDate, 'תרמ"ד-תרנ"ג');
    });

    test('"ד"צ" מפריד בין מקום למקום ואינו נדבק לשם העיר', () {
      final parsed = parse('רש"י', [
        'רבי שלמה בן יצחק (צרפת, המאה ה - 11)',
        'ד"צ ניו יורק תש"ג',
      ]);
      expect(parsed!.entry.pubPlace, 'ניו יורק');
      expect(parsed.entry.pubDate, 'תש"ג');
    });

    test('שם עיר עם מקף צמוד נקרא כמילה אחת', () {
      final parsed = parse('אפרקסתא דעניא', ['ניו-יורק תשס"ב']);
      expect(parsed!.entry.pubPlace, 'ניו-יורק');
      expect(parsed.entry.pubDate, 'תשס"ב');
    });

    test('מקף בודד מפריד תווית מהמקום ואינו חלק ממנו', () {
      // נמדד: גישור מעל המקף הזה יצר 113 ספרים ש"מקום הדפסתם"
      // `ורשא ירושלים` ו-31 ש-`מועד ירושלים`.
      for (final edition in [
        'זרעים - ירושלים תשל"ט',
        'מהדורא קמא - ירושלים תשל"ג',
        "חלק א'-ד' - ירושלים תש\"ל",
        'מהדורת ורשא - ירושלים תשי"ח',
      ]) {
        expect(
          parse('ספר', [edition])!.entry.pubPlace,
          'ירושלים',
          reason: edition,
        );
      }
    });

    test('ראשי תיבות של מדור אינם נדבקים לשם העיר', () {
      expect(parse('ספר', ['או"ח פרעמישלא תרנ"ז'])!.entry.pubPlace, 'פרעמישלא');
      expect(
        parse('ספר', ['יו"ד וחו"מ בני ברק תשס"ה'])!.entry.pubPlace,
        'בני ברק',
      );
    });

    test('מקף בסוף מילה מדביק אותה לבאה אחריה', () {
      // במאגר `ניו- יורק` ו-`ניו-יורק` הן אותה עיר.
      expect(parse('ספר', ['ניו- יורק תש"ג'])!.entry.pubPlace, 'ניו-יורק');
    });

    test('עיר בת שתי מילים ועיר שנגמרת בגרש', () {
      expect(parse('ספר', ['תל אביב תשל"ו'])!.entry.pubPlace, 'תל אביב');
      expect(parse('ספר', ["לודז' תרפ\"ח"])!.entry.pubPlace, "לודז'");
    });

    test('ראשי תיבות שאינם שנה — `ש"ס` — אינם נקראים כשנה', () {
      final parsed = parse('רי"ף', ['על פי מהדורת ש"ס וילנא']);
      expect(parsed!.entry.pubPlace, isNull);
      expect(parsed.entry.pubDate, isNull);
      expect(parsed.entry.edition, 'על פי מהדורת ש"ס וילנא');
    });

    test('שורת מהדורה בלי שנה כלל אינה מייצרת מקום', () {
      final parsed = parse('מגילת תענית', ['מהדורת ליכטנשטיין.']);
      expect(parsed!.entry.pubPlace, isNull);
      expect(parsed.entry.pubDate, isNull);
    });

    test('מאמר ארוך שנפתח במילה "רבי" אינו שורת מחבר', () {
      final parsed = parse('אנציקלופדיה תלמודית', [
        'רבי יהודה הנשיא - או איסי בן יהודה - מונה שבעה שמות '
            'שנקראו להם חכמים, והם שבעה דורות',
        'ירושלים תש"ז',
      ]);
      expect(parsed!.entry.author, isNull);
    });

    test('עמוד ריכוז שמונה חיבורים אינו רשומה', () {
      expect(
        parse('מפרשי הירושלמי', [
          'רשימת ספרים ומהדורות: מפרשי הירושלמי',
          'קרבן העדה',
          'פני משה',
        ]),
        isNull,
      );
    });

    test('עמוד עם יותר מארבע שורות גוף אינו מתאר חיבור אחד', () {
      expect(
        parse('ספרי ר\' צדוק', [
          'אור זרוע לצדיק',
          'דברי חלומות',
          'דובר צדק',
          'ישראל קדושים',
          'לבושי צדקה',
          'רסיסי לילה',
        ]),
        isNull,
      );
    });

    test('עמוד בלי מחבר, בלי מהדורה ובלי מקום אינו רשומה', () {
      expect(parse('שער הציון', const []), isNull);
    });
  });

  group('חיפוש', () {
    ResponsaBibliography build(Map<String, String> pages) =>
        ResponsaBibliography.parse({
          for (final entry in pages.entries) entry.key: cp1255(entry.value),
        });

    test('הצומת בעץ הוא `כתב סופר` והעמוד הוא `שו"ת כתב סופר`', () {
      final bibliography = build({
        'Shoot_Achronim/ktav_sofer.htm': page('שו"ת כתב סופר', [
          'רבי אברהם שמואל בנימין סופר (הונגריה, המאה ה - 19)',
          'ירושלים תשכ"א',
        ]),
      });
      final found = bibliography.lookup(['כתב סופר']);
      expect(found, isNotNull);
      expect(found!.pubPlace, 'ירושלים');
    });

    test('כתיב מלא וחסר אינם מפרידים בין הצומת לעמוד', () {
      final bibliography = build({
        'a.htm': page('תוספות רי"ד', ['ירושלים תשנ"ב']),
      });
      expect(bibliography.lookup(['תוספות ריד']), isNotNull);
    });

    test('הסתייגות בסוגריים אינה מונעת התאמה', () {
      final bibliography = build({
        'a.htm': page('מרכבת המשנה (חעלמא)', ['ירושלים תשל"ח']),
      });
      expect(bibliography.lookup(['מרכבת המשנה']), isNotNull);
    });

    test('שני חיבורים באותו שם — מוחזר רק מה שמוסכם על שניהם', () {
      final bibliography = build({
        'a.htm': page('חתם סופר', ['ד"צ וינה תרמ"ט']),
        'b.htm': page('חתם סופר', ['ירושלים תשס"ה']),
      });
      // מקום ושנה חלוקים, ולכן אינם מיוחסים לאיש.
      expect(bibliography.lookup(['חתם סופר'])?.pubPlace, isNull);
    });

    test('שני עמודים באותו שם שמסכימים על המחבר — המחבר נשמר', () {
      final bibliography = build({
        'a.htm': page('שו"ת רש"י', ['רבי שלמה בן יצחק', 'ניו יורק תש"ג']),
        'b.htm': page('רש"י', ['רבי שלמה בן יצחק', 'ירושלים תשמ"ה']),
      });
      final found = bibliography.lookup(['רש"י']);
      expect(found?.author, 'רבי שלמה בן יצחק');
      expect(found?.pubPlace, isNull);
    });

    test('שם שאינו בביבליוגרפיה מחזיר null ולא ניחוש', () {
      final bibliography = build({
        'a.htm': page('ערוך לנר', ['בני ברק תשס"ד']),
      });
      expect(bibliography.lookup(['אין ספר כזה']), isNull);
    });

    test('מועמדים נבדקים לפי סדר — המדויק ראשון', () {
      final bibliography = build({
        'a.htm': page('שם משמואל', ['פיוטרקוב תרפ"ז']),
        'b.htm': page('מועדים', ['ירושלים תש"ן']),
      });
      expect(
        bibliography.lookup(['שם משמואל', 'מועדים'])?.pubPlace,
        'פיוטרקוב',
      );
    });

    test('קובץ שאינו HTML אינו נקרא', () {
      final bibliography = ResponsaBibliography.parse({
        'a.gif': cp1255(page('ערוך לנר', ['בני ברק תשס"ד'])),
      });
      expect(bibliography.isEmpty, isTrue);
    });
  });

  group('איתור תיקיית הביבליוגרפיה', () {
    Uint8List help(String title) => cp1255(
      '<HTML><HEAD><TITLE>$title</TITLE></HEAD><BODY>'
      '<P>לחיצה על $title תפתח חלון ובו רשימה כללית של מאגרים בכל ספרי '
      'התנ"ך, ובחירה בכל אחד מהם תפרוש רשימה של ספרים.</P>'
      '</BODY></HTML>',
    );

    /// בקובץ העזרה של CD25 יש 98 עמודי הדרכה שעוברים את `parsePage`:
    /// `גימטריה` מקבל מקום הדפסה `בכל ספרי` ושנה `התנ"ך`. אורך הטקסט
    /// אינו מבדיל — רק המיקום.
    test('עמודי הדרכה מחוץ לתיקייה נשארים בחוץ', () {
      final pages = <String, Uint8List>{
        for (var i = 0; i < 20; i++)
          'html/Bblgrphy/shoot/$i.htm': cp1255(
            page('שו"ת ספר $i', ['רבי פלוני אלמוני', 'ירושלים תשס"ו']),
          ),
        'html/Menu/Gimatria.htm': help('גימטריה'),
        'html/Menu/Biographia.htm': help('ביוגרפיה'),
      };
      final selected = ResponsaBibliography.onlyBibliographyFolder(pages);
      expect(selected.keys, hasLength(20));
      expect(
        selected.keys.every((k) => k.startsWith('html/Bblgrphy/')),
        isTrue,
      );

      final bibliography = ResponsaBibliography.parse(selected);
      expect(bibliography.lookup(['שו"ת ספר 1'])?.pubPlace, 'ירושלים');
      expect(bibliography.lookup(['גימטריה']), isNull);
    });

    /// שם התיקייה אינו קבוע בין מהדורות. הבחירה היא לפי המבנה, ולכן
    /// תיקייה בשם אחר לגמרי עובדת בלי שינוי קוד.
    test('תיקייה בשם אחר נבחרת בדיוק כמו המוכרת', () {
      final pages = <String, Uint8List>{
        for (var i = 0; i < 20; i++)
          'DOCS/SefarimList/$i.htm': cp1255(
            page('שו"ת ספר $i', ['ירושלים תשס"ו']),
          ),
        'DOCS/Help/Gimatria.htm': help('גימטריה'),
      };
      final selected = ResponsaBibliography.onlyBibliographyFolder(pages);
      expect(selected.keys, hasLength(20));
      expect(
        ResponsaBibliography.parse(selected).lookup(['שו"ת ספר 5'])?.pubDate,
        'תשס"ו',
      );
    });

    /// מטא-דאטה שגויה גרועה מהיעדר מטא-דאטה: בקובץ שבו הכול שטוח אין
    /// דרך להבדיל בין רשומה לעמוד הדרכה, ולכן לא נבחר דבר.
    test('קובץ שאין בו תיקייה נפרדת אינו מנחש', () {
      final pages = <String, Uint8List>{
        'a.htm': cp1255(page('שו"ת ספר', ['ירושלים תשס"ו'])),
        'b.htm': help('גימטריה'),
      };
      expect(ResponsaBibliography.onlyBibliographyFolder(pages), isEmpty);
    });

    test('קובץ בלי עמודים שנקראים כרשומה מחזיר ריק', () {
      expect(
        ResponsaBibliography.onlyBibliographyFolder({
          'html/Menu/a.htm': help('גימטריה'),
        }),
        isEmpty,
      );
      expect(ResponsaBibliography.onlyBibliographyFolder(const {}), isEmpty);
    });
  });

  group('איתור קובץ העזרה', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('responsa_help'));
    tearDown(() => root.deleteSync(recursive: true));

    void touch(String relative) {
      final file = File(p.join(root.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('');
    }

    test('הקובץ העברי נבדק לפני האנגלי', () {
      touch(p.join('HELP', 'RESPENG.CHM'));
      touch(p.join('HELP', 'Respheb.chm'));
      expect(
        ResponsaBibliographyReader.helpFiles(
          root.path,
        ).map(p.basename).toList(),
        ['Respheb.chm', 'RESPENG.CHM'],
      );
    });

    test('שם התיקייה אינו קבוע — נסרקות כל תיקיות הבת', () {
      touch(p.join('Documentation', 'guide.chm'));
      expect(ResponsaBibliographyReader.helpFiles(root.path), hasLength(1));
    });

    test('קובץ עזרה בתיקיית ההתקנה עצמה נמצא', () {
      touch('Respheb.chm');
      expect(ResponsaBibliographyReader.helpFiles(root.path), hasLength(1));
    });

    /// `DB` הוא כ-10GB. סריקה עמוקה הייתה עוברת עליו בכל בנייה.
    test('הסריקה אינה יורדת מתחת לתיקיות הבת', () {
      touch(p.join('DB', 'deep', 'nested.chm'));
      expect(ResponsaBibliographyReader.helpFiles(root.path), isEmpty);
    });

    /// התקנה שנייה על אותו מחשב נבנית לעיתים כתיקייה שבה `HELP` ו-`DB`
    /// הם קישורים לתיקיות של ההתקנה הראשית. בלי מעקב אחרי קישורים
    /// הקטלוג נבנה שם בלי מחבר ובלי פרטי הדפסה, בלי שום סימן למשתמש.
    test('תיקייה שהיא קישור נסרקת כמו תיקייה רגילה', () {
      final target = Directory(
        p.join(root.path, '..', 'responsa_help_target'),
      ).absolute;
      target.createSync(recursive: true);
      addTearDown(() => target.deleteSync(recursive: true));
      File(p.join(target.path, 'Respheb.chm')).writeAsStringSync('');
      try {
        Link(p.join(root.path, 'HELP')).createSync(target.path);
      } on FileSystemException {
        // יצירת קישור ב-Windows דורשת הרשאה שאינה קיימת בכל סביבה.
        markTestSkipped('אין הרשאה ליצירת קישור בסביבה הזו');
        return;
      }
      expect(
        ResponsaBibliographyReader.helpFiles(root.path).map(p.basename),
        ['Respheb.chm'],
      );
    });

    test('התקנה בלי קובץ עזרה אינה שגיאה', () {
      expect(ResponsaBibliographyReader.forRoots([root.path]).isEmpty, isTrue);
      expect(ResponsaBibliographyReader.forRoots([null, '']).isEmpty, isTrue);
    });
  });
}
