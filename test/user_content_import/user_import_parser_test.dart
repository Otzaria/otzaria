import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/services/user_import_parser.dart';

void main() {
  group('UserImportParser.parseGenerations', () {
    test('מפענח שורות תקינות עם מחבר', () {
      const csv =
          'ספר,דור,מחבר\n'
          'ביאורי יוסף,מחברי זמננו,יוסף כהן\n'
          'שו"ת הרב פלוני,אחרונים,\n';
      final result = UserImportParser.parseGenerations(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.length, 2);
      expect(result.rows[0].bookTitle, 'ביאורי יוסף');
      expect(result.rows[0].eraName, 'מחברי זמננו');
      expect(result.rows[0].author, 'יוסף כהן');
      // גרשיים בכותרת (שו"ת) נקראים נכון, מחבר ריק → null
      expect(result.rows[1].bookTitle, 'שו"ת הרב פלוני');
      expect(result.rows[1].author, isNull);
    });

    test('דור עם גרשיים שונים מתאים (חז"ל / חזל)', () {
      const csv = 'ספר,דור\nספר א,חזל\nספר ב,חז"ל\n';
      final result = UserImportParser.parseGenerations(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.every((r) => r.eraName == 'חז"ל'), isTrue);
    });

    test('דור לא חוקי → שגיאה, שורות תקינות נקלטות', () {
      const csv = 'ספר,דור\nטוב,ראשונים\nרע,דור-מומצא\n';
      final result = UserImportParser.parseGenerations(csv);
      expect(result.rows.length, 1);
      expect(result.rows.single.bookTitle, 'טוב');
      expect(result.errors.single.lineNumber, 3);
    });

    test('כותרת חסרה → שגיאה אחת בלבד', () {
      const csv = 'ספר,מחבר\nא,ב\n';
      final result = UserImportParser.parseGenerations(csv);
      expect(result.rows, isEmpty);
      expect(result.errors.single.lineNumber, 1);
    });

    test('סדר עמודות הפוך + שורות הערה/ריקות מדולגות', () {
      const csv =
          '# הדורות שלי\n'
          'דור,ספר\n'
          '\n'
          'ראשונים,רש"י\n';
      final result = UserImportParser.parseGenerations(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.single.bookTitle, 'רש"י');
      expect(result.rows.single.eraName, 'ראשונים');
    });
  });

  group('UserImportParser.parseLinks', () {
    test('מפענח קישור עם סוג עברי וממפה ל-connection_type', () {
      const csv =
          'מקור,ספר_יעד,מיקום_יעד,סוג,יעד_אישי\n'
          '12,ברכות,ב ע"א,פירוש,לא\n'
          '83,קונטרס הזמנים,יב,מקור,כן\n';
      final result = UserImportParser.parseLinks(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.length, 2);
      expect(result.rows[0].sourceLineNumber, 12);
      expect(result.rows[0].targetTitle, 'ברכות');
      expect(result.rows[0].connectionType, 'COMMENTARY');
      expect(result.rows[0].targetIsUserBook, isFalse);
      expect(result.rows[1].connectionType, 'SOURCE');
      expect(result.rows[1].targetIsUserBook, isTrue);
    });

    test('שדה יעד מצוטט עם פסיק נקרא כשדה אחד', () {
      const csv =
          'מקור,ספר_יעד,מיקום_יעד,סוג\n'
          '47,"שולחן ערוך אורח חיים","רטו, א",הפניה\n';
      final result = UserImportParser.parseLinks(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.single.targetTitle, 'שולחן ערוך אורח חיים');
      expect(result.rows.single.targetRef, 'רטו, א');
      expect(result.rows.single.connectionType, 'REFERENCE');
    });

    test('סוג אנגלי ישיר מתקבל', () {
      const csv = 'מקור,ספר_יעד,סוג\n5,ברכות,TARGUM\n';
      final result = UserImportParser.parseLinks(csv);
      expect(result.rows.single.connectionType, 'TARGUM');
    });

    // הדרישה: מה שה-DB יודע לאחסן — הייבוא יודע לקלוט. הטסט רץ על הרשימה
    // עצמה ולכן סוג חדש ב-LinkTypes מפיל אותו עד שייתמך גם כאן.
    test('כל סוג קישור שה-DB מכיר נקלט בשמו האנגלי', () {
      for (final type in kImportableConnectionTypes) {
        final result = UserImportParser.parseLinks(
          'מקור,ספר_יעד,סוג\n5,ברכות,$type\n',
        );
        expect(result.errors, isEmpty, reason: type);
        // LINKER נשמר כמפרש — הוא פלט אוטומטי ולא סיווג שהמשתמש בחר.
        expect(
          result.rows.single.connectionType,
          type == LinkTypes.linker ? LinkTypes.commentary : type,
          reason: type,
        );
      }
    });

    test('"אוטומטי" נשמר כמפרש, כמו LINKER באנגלית', () {
      final result = UserImportParser.parseLinks(
        'מקור,ספר_יעד,סוג\n5,ברכות,${LinkTypes.hebrewLabels[LinkTypes.linker]}\n',
      );
      expect(result.errors, isEmpty);
      expect(result.rows.single.connectionType, LinkTypes.commentary);
    });

    test('כל סוג קישור נקלט גם בתווית העברית שהאפליקציה מציגה', () {
      for (final type in kImportableConnectionTypes.difference({
        LinkTypes.linker,
      })) {
        final label = LinkTypes.hebrewLabels[type]!;
        final result = UserImportParser.parseLinks(
          'מקור,ספר_יעד,סוג\n5,ברכות,$label\n',
        );
        expect(result.errors, isEmpty, reason: '$type ($label)');
        // תווית משותפת נפתרת לסוג הקנוני, ולכן משווים לפי התווית ולא לפי הסוג.
        expect(
          LinkTypes.hebrewLabels[result.rows.single.connectionType],
          label,
          reason: '$type ($label)',
        );
      }
    });

    test('רישיות ומפרידים בשם האנגלי אינם משנים', () {
      for (final raw in const [
        'super commentary',
        'Super-Commentary',
        'super_commentary',
      ]) {
        final result = UserImportParser.parseLinks(
          'מקור,ספר_יעד,סוג\n5,ברכות,$raw\n',
        );
        expect(result.rows.single.connectionType, LinkTypes.superCommentary);
      }
    });

    test('כינויים עבריים היסטוריים ממשיכים להיקלט', () {
      kLegacyHebrewConnectionTypes.forEach((label, type) {
        final result = UserImportParser.parseLinks(
          'מקור,ספר_יעד,סוג\n5,ברכות,$label\n',
        );
        expect(result.rows.single.connectionType, type, reason: label);
      });
    });

    test('מספר שורה לא חוקי / סוג לא מוכר → שגיאות', () {
      const csv =
          'מקור,ספר_יעד,סוג\n'
          'אבג,ברכות,פירוש\n'
          '10,ברכות,משהו\n';
      final result = UserImportParser.parseLinks(csv);
      expect(result.rows, isEmpty);
      expect(result.errors.length, 2);
      expect(result.errors[0].lineNumber, 2);
      expect(result.errors[1].lineNumber, 3);
    });

    test('עמודת ספר_מקור (קובץ רוחבי) נקלטת', () {
      const csv =
          'ספר_מקור,מקור,ספר_יעד,סוג\n'
          'ביאורי יוסף,12,ברכות,פירוש\n';
      final result = UserImportParser.parseLinks(csv);
      expect(result.rows.single.sourceBookTitle, 'ביאורי יוסף');
    });

    test('ללא עמודת מקור_אישי — ברירת מחדל: מקור אישי', () {
      const csv = 'מקור,ספר_יעד,סוג\n12,ברכות,פירוש\n';
      final result = UserImportParser.parseLinks(csv);
      expect(result.rows.single.sourceIsUserBook, isTrue);
    });

    test('מקור_אישי=לא + קטגוריית_מקור → מקור רשמי עם קטגוריה', () {
      const csv =
          'מקור_אישי,קטגוריית_מקור,מקור,ספר_יעד,סוג\n'
          'לא,7,12,ברכות,הפניה\n';
      final result = UserImportParser.parseLinks(csv);
      expect(result.rows.single.sourceIsUserBook, isFalse);
      expect(result.rows.single.sourceCategoryId, 7);
    });
  });

  group('UserImportParser.parseNativeLinksJson', () {
    test('מפענח את פורמט ה-native (line_index, path_2, heRef_2)', () {
      const json =
          '['
          '{"line_index_1": 3, "line_index_2": 5, '
          '"heRef_2": "הכי גרסינן מגילה ב., א", '
          '"path_2": "הכי גרסינן מגילה.txt", "Conection Type": "commentary"},'
          '{"line_index_1": 4.0, "line_index_2": 21, '
          '"heRef_2": "ב., ב", "path_2": "הכי גרסינן מגילה.txt", '
          '"Conection Type": "reference"}'
          ']';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.errors, isEmpty);
      expect(result.rows.length, 2);
      expect(result.rows[0].sourceLineNumber, 3);
      expect(result.rows[0].targetLineNumber, 5);
      // סיומת .txt מוסרת מהכותרת
      expect(result.rows[0].targetTitle, 'הכי גרסינן מגילה');
      expect(result.rows[0].targetRef, 'הכי גרסינן מגילה ב., א');
      expect(result.rows[0].connectionType, 'COMMENTARY');
      // line_index כ-double (4.0) נקרא כמספר שלם
      expect(result.rows[1].sourceLineNumber, 4);
      expect(result.rows[1].connectionType, 'REFERENCE');
    });

    test('סוג חסר → REFERENCE (כמו Link.fromJson)', () {
      const json = '[{"line_index_1": 1, "line_index_2": 2, "path_2": "ספר"}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.errors, isEmpty);
      expect(result.rows.single.connectionType, LinkTypes.reference);
      expect(result.rows.single.targetTitle, 'ספר');
    });

    test('תמיכה באיות התקני Connection Type (עם שני n)', () {
      const json =
          '['
          '{"line_index_1": 1, "line_index_2": 2, '
          '"path_2": "בסיס.txt", "Connection Type": "commentary"}'
          ']';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.errors, isEmpty);
      expect(result.rows.single.connectionType, 'COMMENTARY');
    });

    for (final (label, value) in [
      ('ריק', '""'),
      ('רווחים בלבד', '"   "'),
      ('null', 'null'),
    ]) {
      test('סוג $label → REFERENCE, כמו Link.fromJson', () {
        final json =
            '[{"line_index_1": 1, "line_index_2": 2, "path_2": "ספר", '
            '"Conection Type": $value}]';
        final result = UserImportParser.parseNativeLinksJson(json);
        expect(result.errors, isEmpty);
        final type = result.rows.single.connectionType;
        expect(type, LinkTypes.reference);
        // אותו פאנל כמו בקריאת אותו קובץ ב-Link.fromJson.
        expect(
          LinkTypes.normalize(
            Link.fromJson(
              jsonDecode(json)[0] as Map<String, dynamic>,
            ).connectionType,
          ),
          type,
        );
        expect(LinkTypes.isDependentTextLink(type), isFalse);
      });
    }

    test('כל ערכי ה-Conection Type של כלי Link-Notes נקלטים', () {
      // ערכי ה-<select> שב-Link-Notes/index.html → הסוג שנשמר.
      const expected = {
        'commentary': LinkTypes.commentary,
        'super_commentary': LinkTypes.superCommentary,
        'targum': LinkTypes.targum,
        'midrash': LinkTypes.midrash,
        'parshanut': LinkTypes.parshanut,
        'dibur_hamatchil': LinkTypes.diburHamatchil,
        'reference': LinkTypes.reference,
        'quotation': LinkTypes.quotation,
        'quotation_auto': LinkTypes.quotation,
        'quotation_auto_tanakh': LinkTypes.quotation,
        'explication': LinkTypes.explication,
        'related passage': LinkTypes.related,
        'related': LinkTypes.related,
        'allusion': LinkTypes.allusion,
        'mesorat hashas': LinkTypes.mesoratHashas,
        'ein mishpat': LinkTypes.einMishpat,
        'ein mishpat / ner mitsvah': LinkTypes.einMishpat,
        'mishnah in talmud': LinkTypes.mishnahInTalmud,
        'law': LinkTypes.law,
        'footnotes': LinkTypes.footnotes,
        'liturgy': LinkTypes.liturgy,
        'linker': LinkTypes.linker,
        'summary': LinkTypes.summary,
        'sifrei mitzvot': LinkTypes.sifreiMitzvot,
        'sifrei mitsvot': LinkTypes.sifreiMitzvot,
        'none': LinkTypes.other,
        '': LinkTypes.reference,
      };
      final json = jsonEncode([
        for (final raw in expected.keys)
          {
            'line_index_1': 1,
            'line_index_2': 2,
            'path_2': 'ספר.txt',
            'Conection Type': raw,
          },
      ]);
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.errors, isEmpty);
      expect(
        [for (final r in result.rows) r.connectionType],
        expected.values.toList(),
      );
    });

    test('סוגים מלאים של ה-DB נקלטים בכל רישיות ובכל מפריד', () {
      const raws = [
        'SUPER_COMMENTARY',
        'Super Commentary',
        'super-commentary',
        'ELUCIDATION',
        'ellucidation',
        'sifrei mitzvot',
        'ESSAY',
        'other',
        'source',
      ];
      final json = jsonEncode([
        for (final raw in raws)
          {
            'line_index_1': 1,
            'line_index_2': 2,
            'path_2': 'ספר',
            'Conection Type': raw,
          },
      ]);
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.errors, isEmpty);
      expect(
        [for (final r in result.rows) r.connectionType],
        [
          LinkTypes.superCommentary,
          LinkTypes.superCommentary,
          LinkTypes.superCommentary,
          LinkTypes.elucidation,
          LinkTypes.elucidation,
          LinkTypes.sifreiMitzvot,
          LinkTypes.essay,
          LinkTypes.other,
          LinkTypes.source,
        ],
      );
    });

    test('סוגי תלוי-טקסט יוצאים תלויי-טקסט, השאר — הפניה', () {
      final json = jsonEncode([
        for (final raw in ['midrash', 'footnotes', 'explication', 'law'])
          {
            'line_index_1': 1,
            'line_index_2': 2,
            'path_2': 'ספר',
            'Conection Type': raw,
          },
      ]);
      final rows = UserImportParser.parseNativeLinksJson(json).rows;
      expect(
        [for (final r in rows) LinkTypes.isDependentTextLink(r.connectionType)],
        [
          true,
          true,
          true,
          false,
        ],
      );
    });

    test('תוויות עבריות עדיין נקלטות בפורמט ה-native', () {
      const json =
          '[{"line_index_1": 1, "line_index_2": 2, "path_2": "ספר", '
          '"Conection Type": "תרגום"}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.rows.single.connectionType, LinkTypes.targum);
    });

    test('סוג לא מוכר → שגיאת שורה, שורות תקינות נקלטות', () {
      const json =
          '['
          '{"line_index_1": 1, "line_index_2": 2, "path_2": "ספר", '
          '"Conection Type": "no such type"},'
          '{"line_index_1": 1, "line_index_2": 2, "path_2": "ספר", '
          '"Conection Type": "midrash"}'
          ']';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.rows.single.connectionType, LinkTypes.midrash);
      expect(result.errors.single.lineNumber, 1);
      expect(result.errors.single.message, contains('no such type'));
    });

    test('אינדקסי שורה כמספר עשרוני או כמחרוזת, כמו הקורא של הספרייה', () {
      // כלי ייצוא דרך pandas כותב כל עמודה מספרית כ-float, ולפעמים כמחרוזת.
      const row = {
        'heRef_2': 'ספר א',
        'line_index_1': '3.0',
        'line_index_2': 5.0,
        'path_2': 'ספר.txt',
        'Conection Type': 'commentary',
        'start': '7.0',
      };
      final canonical = Link.fromJson(row);
      expect(canonical.index1, 3);
      expect(canonical.index2, 5);

      final result = UserImportParser.parseNativeLinksJson(jsonEncode([row]));
      expect(result.errors, isEmpty);
      expect(result.rows.single.sourceLineNumber, canonical.index1);
      expect(result.rows.single.targetLineNumber, canonical.index2);
      expect(result.rows.single.anchorStart, 7);
    });

    test('path_2 עם רכיבי-נתיב → הכותרת היא שם הקובץ בלבד', () {
      const json =
          '[{"line_index_1": 1, "line_index_2": 2, '
          '"path_2": "מפרשים/הכי גרסינן מגילה.txt"}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.rows.single.targetTitle, 'הכי גרסינן מגילה');
    });

    test('native linker שומר את הסוג, העוגן והטווח', () {
      const json =
          '[{"line_index_1": 5, "line_index_1_end": 5, '
          '"line_index_2": 6, "line_index_2_end": 8, '
          '"heRef_2": "המאיר לארץ, סימן א, סעיף א אות א", '
          '"heRef_2_end": "המאיר לארץ, סימן א, סעיף א אות ג", '
          '"path_2": "המאיר לארץ.txt", "Conection Type": "linker", '
          '"start": 11, "end": 18}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.errors, isEmpty);
      final row = result.rows.single;
      expect(row.connectionType, LinkTypes.linker);
      expect(row.anchorStart, 11);
      expect(row.anchorEnd, 18);
      expect(row.anchorLabel, 'א');
      expect(row.sourceLineNumberEnd, 5);
      expect(row.targetLineNumberEnd, 8);
      expect(row.targetRefEnd, contains('אות ג'));
    });

    test('end<=start מתפרש כעוגן-נקודה ולא כשגיאה', () {
      const json =
          '[{"line_index_1": 1, "line_index_2": 2, "path_2": "מפרש.txt", '
          '"start": 7, "end": 7}, '
          '{"line_index_1": 3, "line_index_2": 4, "path_2": "מפרש.txt", '
          '"start": 9, "end": 2}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.errors, isEmpty);
      expect(result.rows.map((r) => r.anchorStart), [7, 9]);
      expect(result.rows.every((r) => r.anchorEnd == null), isTrue);
    });

    test('end בלי start → נזרק, והשורה נקלטת', () {
      // הקורא של הספרייה סלחני לזה, והייבוא אטומי — פסילה כאן הייתה מפילה
      // את כל הקבצים שנבחרו בגלל שדה שאינו שמיש ממילא.
      const json =
          '[{"line_index_1": 1, "line_index_2": 2, "path_2": "מפרש.txt", '
          '"end": 7}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.errors, isEmpty);
      expect(result.rows.single.anchorStart, isNull);
      expect(result.rows.single.anchorEnd, isNull);
    });

    test('סוג קישור שאינו מוכר נפסל בייבוא native', () {
      const json =
          '[{"line_index_1": 1, "line_index_2": 2, "path_2": "מפרש.txt", '
          '"Conection Type": "some new type"}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.rows, isEmpty);
      expect(result.errors.single.message, contains('some new type'));
    });

    test('בקובץ CSV סוג לא מוכר עדיין נפסל (שם זו שגיאת הקלדה)', () {
      final result = UserImportParser.parseLinks(
        'מקור,ספר_יעד,סוג\n5,ברכות,סוג מומצא\n',
      );
      expect(result.rows, isEmpty);
      expect(result.errors, isNotEmpty);
    });

    test('קובץ בפורמט native בשם גנרי מקבל הודעה שמסבירה מה לעשות', () {
      const json =
          '[{"line_index_1": 3, "line_index_2": 5, "path_2": "מפרש.txt"}]';
      final result = UserImportParser.parseLinksJson(json);
      expect(result.rows, isEmpty);
      expect(result.errors.single.message, contains('_links.json'));
    });

    test('אות עוגן בגימטריה דו-אותית נשמרת שלמה', () {
      String labelOf(String heRef) {
        final json =
            '[{"line_index_1": 1, "line_index_2": 2, '
            '"path_2": "מפרש.txt", "start": 0, '
            '"heRef_2": ${jsonEncode(heRef)}}]';
        return UserImportParser.parseNativeLinksJson(
          json,
        ).rows.single.anchorLabel!;
      }

      expect(labelOf('מפרש, סימן א, אות א'), 'א');
      expect(labelOf('מפרש, סימן א, אות י"א'), 'י"א');
      expect(labelOf('מפרש, סימן א, אות י״א'), 'י״א');
      // גרש-סיום אינו חלק מהאות ולכן נגזם.
      expect(labelOf('מפרש, סימן א, אות ט׳'), 'ט');
    });

    test('line_index חסר/לא חוקי → שגיאה, שורות תקינות נקלטות', () {
      const json =
          '['
          '{"line_index_1": 0, "line_index_2": 2, "path_2": "ספר"},'
          '{"line_index_1": 1, "path_2": "ספר"},'
          '{"line_index_1": 1, "line_index_2": 2, "path_2": "ספר"}'
          ']';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.rows.length, 1);
      expect(result.errors.length, 2);
    });
  });

  group('UserImportParser.parseLinksJson', () {
    test('מפענח מערך JSON עם מפתחות עברית ו-aliases', () {
      const json =
          '['
          '{"מקור": 12, "ספר_יעד": "ברכות", "מיקום_יעד": 5, "סוג": "פירוש", "יעד_אישי": false},'
          '{"source": 47, "targetTitle": "שולחן ערוך אורח חיים", "ref": "רטו א", "type": "REFERENCE", "isUserBook": true}'
          ']';
      final result = UserImportParser.parseLinksJson(json);
      expect(result.errors, isEmpty);
      expect(result.rows.length, 2);
      expect(result.rows[0].sourceLineNumber, 12);
      expect(result.rows[0].targetTitle, 'ברכות');
      expect(result.rows[0].connectionType, 'COMMENTARY');
      expect(result.rows[0].targetIsUserBook, isFalse);
      expect(result.rows[1].connectionType, 'REFERENCE');
      expect(result.rows[1].targetRef, 'רטו א');
      expect(result.rows[1].targetIsUserBook, isTrue);
    });

    test('JSON: מקור_אישי=false נקרא; חסר → ברירת מחדל אישי', () {
      const json =
          '['
          '{"מקור": 3, "ספר_יעד": "ברכות", "סוג": "הפניה", "מקור_אישי": false},'
          '{"מקור": 5, "ספר_יעד": "ברכות", "סוג": "פירוש"}'
          ']';
      final result = UserImportParser.parseLinksJson(json);
      expect(result.rows[0].sourceIsUserBook, isFalse);
      expect(result.rows[1].sourceIsUserBook, isTrue);
    });

    test('JSON לא תקין → שגיאה אחת, בלי קריסה', () {
      final result = UserImportParser.parseLinksJson('{ לא תקין');
      expect(result.rows, isEmpty);
      expect(result.errors, isNotEmpty);
    });

    test('שורה פגומה מדולגת, תקינות נקלטות', () {
      const json =
          '['
          '{"מקור": "אבג", "ספר_יעד": "ברכות", "סוג": "פירוש"},'
          '{"מקור": 5, "ספר_יעד": "ברכות", "סוג": "פירוש"}'
          ']';
      final result = UserImportParser.parseLinksJson(json);
      expect(result.rows.length, 1);
      expect(result.errors.length, 1);
    });
  });

  group('UserImportParser.parseVersions', () {
    test('קובץ ישן בלי עמודות מקור — ראשי אישי', () {
      final result = UserImportParser.parseVersions(
        'ראשי,גרסה,שם,הערות,עדיפות\nרשבא.txt,רשבא קוק.txt,מוסד הרב קוק,,5\n',
      );

      expect(result.errors, isEmpty);
      final row = result.rows.single;
      expect(row.primary, 'רשבא.txt');
      expect(row.version, 'רשבא קוק.txt');
      expect(row.label, 'מוסד הרב קוק');
      expect(row.priority, 5);
      expect(row.primarySource, BookSource.user);
      expect(row.primaryCategoryPath, isNull);
    });

    test('ראשי רשמי עם קטגוריה, ראשי ממסד מצורף ומקור "אישי" מפורש', () {
      final result = UserImportParser.parseVersions(
        'ראשי,גרסה,שם,מקור_ראשי,קטגוריית_ראשי\n'
        'בראשית,בראשית כתב יד.txt,כתב יד,רשמי,תנך/תורה\n'
        'בראשית,בראשית מצורף.txt,,מסד:ספרייה,\n'
        'ראשי.txt,משני.txt,,אישי,תנך\n',
      );

      expect(result.errors, isEmpty);
      final [official, attached, user] = result.rows;
      expect(official.primarySource, BookSource.official);
      expect(official.primaryCategoryPath, 'תנך/תורה');
      expect(attached.primarySource, BookSource.attached('ספרייה'));
      expect(attached.primaryCategoryPath, isNull);
      expect(user.primarySource, BookSource.user);
      // קטגוריה רלוונטית רק לראשי שאינו אישי.
      expect(user.primaryCategoryPath, isNull);
    });

    test('מקור ראשי לא מוכר נדחה עם מספר השורה, ושאר השורות נקלטות', () {
      final result = UserImportParser.parseVersions(
        'ראשי,גרסה,מקור_ראשי\n'
        'בראשית,א.txt,ספריא\n'
        'בראשית,ב.txt,official\n'
        'בראשית,ג.txt,מסד:\n',
      );

      expect(result.rows.single.version, 'ב.txt');
      expect(result.errors.map((e) => e.lineNumber), [2, 4]);
      expect(result.errors.first.message, contains('מקור ראשי לא חוקי'));
    });
  });
}
