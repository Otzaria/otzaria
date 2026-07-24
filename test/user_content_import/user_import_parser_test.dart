import 'package:flutter_test/flutter_test.dart';
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

    test('סוג ריק → commentary (כמו Link.fromJson)', () {
      const json = '[{"line_index_1": 1, "line_index_2": 2, "path_2": "ספר"}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.rows.single.connectionType, 'COMMENTARY');
      expect(result.rows.single.targetTitle, 'ספר');
    });

    test('path_2 עם רכיבי-נתיב → הכותרת היא שם הקובץ בלבד', () {
      const json =
          '[{"line_index_1": 1, "line_index_2": 2, '
          '"path_2": "מפרשים/הכי גרסינן מגילה.txt"}]';
      final result = UserImportParser.parseNativeLinksJson(json);
      expect(result.rows.single.targetTitle, 'הכי גרסינן מגילה');
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
}
