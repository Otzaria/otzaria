import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';

void main() {
  group('LinkTypes.isDependentTextLink', () {
    test('מזהה את סוגי הקישורים התלויים שמוצגים כמפרשים', () {
      for (final type in const [
        'COMMENTARY',
        'SUPER_COMMENTARY',
        'TARGUM',
        'MIDRASH',
        'PARSHANUT',
        'DIBUR_HAMATCHIL',
        'ELUCIDATION',
        'EXPLICATION',
      ]) {
        expect(LinkTypes.isDependentTextLink(type), isTrue, reason: type);
      }
    });

    test('דוחה סוגי הפניה ואת SOURCE הווירטואלי', () {
      for (final type in const [
        'REFERENCE',
        'QUOTATION',
        'MESORAT_HASHAS',
        'EIN_MISHPAT',
        'MISHNAH_IN_TALMUD',
        'RELATED',
        'OTHER',
        'SOURCE',
      ]) {
        expect(LinkTypes.isDependentTextLink(type), isFalse, reason: type);
      }
    });

    test('אינו תלוי רישיות ומחזיר false ל-null', () {
      expect(LinkTypes.isDependentTextLink('commentary'), isTrue);
      expect(LinkTypes.isDependentTextLink('Targum'), isTrue);
      expect(LinkTypes.isDependentTextLink(null), isFalse);
    });
  });

  group('LinkTypes.normalize', () {
    test('ממיר לאותיות גדולות ומקצץ רווחים', () {
      expect(LinkTypes.normalize('reference'), 'REFERENCE');
      expect(LinkTypes.normalize('  Quotation  '), 'QUOTATION');
      expect(LinkTypes.normalize(null), '');
      expect(LinkTypes.normalize('   '), '');
    });

    test('מחליף רווחים ומקפים פנימיים בקו תחתון — כפורמט ספריא', () {
      expect(LinkTypes.normalize('ein mishpat'), 'EIN_MISHPAT');
      expect(LinkTypes.normalize('mesorat hashas'), 'MESORAT_HASHAS');
      expect(LinkTypes.normalize('related passage'), 'RELATED_PASSAGE');
      expect(LinkTypes.normalize('mishnah in talmud'), 'MISHNAH_IN_TALMUD');
      expect(LinkTypes.normalize('quotation auto'), 'QUOTATION_AUTO');
      expect(LinkTypes.normalize('dibur-hamatchil'), 'DIBUR_HAMATCHIL');
      expect(LinkTypes.normalize('  ein   mishpat  '), 'EIN_MISHPAT');
    });
  });

  group('LinkTypes.canonicalType', () {
    test('ממזג את סוגי הציטוט האוטומטי לציטוט', () {
      expect(LinkTypes.canonicalType('QUOTATION_AUTO'), 'QUOTATION');
      expect(LinkTypes.canonicalType('quotation auto'), 'QUOTATION');
      expect(LinkTypes.canonicalType('QUOTATION_AUTO_TANAKH'), 'QUOTATION');
      expect(LinkTypes.canonicalType('QUOTATION'), 'QUOTATION');
    });

    test('ממזג related passage ל-RELATED', () {
      expect(LinkTypes.canonicalType('RELATED_PASSAGE'), 'RELATED');
      expect(LinkTypes.canonicalType('related passage'), 'RELATED');
      expect(LinkTypes.canonicalType('RELATED'), 'RELATED');
    });

    test('NONE, null ומחרוזת ריקה הופכים ל-OTHER', () {
      expect(LinkTypes.canonicalType('NONE'), 'OTHER');
      expect(LinkTypes.canonicalType('none'), 'OTHER');
      expect(LinkTypes.canonicalType(''), 'OTHER');
      expect(LinkTypes.canonicalType('   '), 'OTHER');
      expect(LinkTypes.canonicalType(null), 'OTHER');
    });

    test('ESSAY ממוזג ל-OTHER (לא מסווג)', () {
      expect(LinkTypes.canonicalType('ESSAY'), 'OTHER');
      expect(LinkTypes.canonicalType('essay'), 'OTHER');
    });

    test('סוגים מובחנים וסוג לא-מוכר נשמרים כמות שהם (מנורמלים)', () {
      for (final type in const [
        'ALLUSION',
        'LAW',
        'FOOTNOTES',
        'LITURGY',
        'LINKER',
        'SUMMARY',
        'SIFREI_MITZVOT',
        'EIN_MISHPAT',
        'MESORAT_HASHAS',
      ]) {
        expect(LinkTypes.canonicalType(type), type, reason: type);
      }
      expect(LinkTypes.canonicalType('MYSTERY_TYPE'), 'MYSTERY_TYPE');
      expect(LinkTypes.canonicalType('mystery type'), 'MYSTERY_TYPE');
    });
  });

  group('LinkTypes.hebrewLabel', () {
    test('מחזיר תווית עברית לכל 16 הסוגים המוכרים', () {
      const expected = {
        'COMMENTARY': 'פירוש',
        'SUPER_COMMENTARY': 'פירוש על פירוש',
        'TARGUM': 'תרגום',
        'MIDRASH': 'מדרש',
        'PARSHANUT': 'פרשנות',
        'DIBUR_HAMATCHIL': 'דיבור המתחיל',
        'ELUCIDATION': 'ביאור',
        'EXPLICATION': 'ביאור',
        'REFERENCE': 'עיון',
        'QUOTATION': 'ציטוט',
        'MESORAT_HASHAS': 'מסורת הש"ס',
        'EIN_MISHPAT': 'עין משפט',
        'MISHNAH_IN_TALMUD': 'משנה בתלמוד',
        'RELATED': 'נושא קרוב',
        'SOURCE': 'מקור',
        'OTHER': 'לא מסווג',
      };
      expected.forEach((type, label) {
        expect(LinkTypes.hebrewLabel(type), label, reason: type);
      });
    });

    test('מחזיר תווית עברית לסוגים הנוספים של ספריא', () {
      const expected = {
        'QUOTATION_AUTO': 'ציטוט אוטומטי',
        'QUOTATION_AUTO_TANAKH': 'ציטוט אוטומטי מהתנ"ך',
        'RELATED_PASSAGE': 'קטע קשור',
        // "רמז" בעולם התורני הוא חלק מפרד"ס או מספר סימן, ו"הלכה" רחב מדי.
        'ALLUSION': 'אזכור',
        'LAW': 'פסיקת הלכה',
        'FOOTNOTES': 'הערות שוליים',
        'LITURGY': 'תפילה',
        'LINKER': 'אוטומטי',
        'SUMMARY': 'סיכום',
        'SIFREI_MITZVOT': 'ספרי מצוות',
        'NONE': 'לא מסווג',
      };
      expected.forEach((type, label) {
        expect(LinkTypes.hebrewLabel(type), label, reason: type);
      });
    });

    test('ערכי ספריא עם רווחים מתורגמים ולא נופלים ל-fallback', () {
      expect(LinkTypes.hebrewLabel('ein mishpat'), 'עין משפט');
      expect(LinkTypes.hebrewLabel('mesorat hashas'), 'מסורת הש"ס');
      expect(LinkTypes.hebrewLabel('related passage'), 'קטע קשור');
      expect(LinkTypes.hebrewLabel('mishnah in talmud'), 'משנה בתלמוד');
      expect(LinkTypes.hebrewLabel('quotation auto'), 'ציטוט אוטומטי');
    });

    test('אינו תלוי רישיות — ערכי JSON מגיעים באותיות קטנות', () {
      expect(LinkTypes.hebrewLabel('reference'), 'עיון');
      expect(LinkTypes.hebrewLabel('Mesorat_Hashas'), 'מסורת הש"ס');
      expect(LinkTypes.hebrewLabel('  targum  '), 'תרגום');
    });

    test('מתרגם את alt_toc שאינו חלק מסוגי ה-DB', () {
      expect(LinkTypes.hebrewLabel('alt_toc'), 'חלוקה חלופית');
      expect(LinkTypes.hebrewLabel('ALT_TOC'), 'חלוקה חלופית');
    });

    test('ערך לא מוכר מוחזר כמות שהוא ולא נבלע', () {
      expect(LinkTypes.hebrewLabel('SOME_NEW_TYPE'), 'SOME_NEW_TYPE');
      expect(LinkTypes.hebrewLabel('some_new_type'), 'some_new_type');
      expect(LinkTypes.hebrewLabel('  spaced_type  '), 'spaced_type');
    });

    test('null או מחרוזת ריקה נופלים לתווית "לא מסווג" ולא לערך ריק', () {
      expect(LinkTypes.hebrewLabel(null), 'לא מסווג');
      expect(LinkTypes.hebrewLabel(''), 'לא מסווג');
      expect(LinkTypes.hebrewLabel('   '), 'לא מסווג');
    });
  });

  group('LinkTypes.eraGroupedTypes', () {
    test('כולל בדיוק את הסוגים חסרי-התווית המשמעותית', () {
      expect(LinkTypes.eraGroupedTypes, {
        'OTHER',
        'NONE',
        'RELATED',
        'RELATED_PASSAGE',
        'REFERENCE',
        'LINKER',
      });
    });

    test('סוגים בעלי משמעות תיאורית אינם מקובצים לפי דור', () {
      for (final type in const [
        'EIN_MISHPAT',
        'MESORAT_HASHAS',
        'QUOTATION',
        'MISHNAH_IN_TALMUD',
        'LAW',
        'ALLUSION',
        'SIFREI_MITZVOT',
        'FOOTNOTES',
        'LITURGY',
        'SUMMARY',
        'ALT_TOC',
      ]) {
        expect(LinkTypes.isEraGroupedType(type), isFalse, reason: type);
      }
    });

    test('isEraGroupedType עובד על הסוג הקנוני ולא על הגולמי', () {
      expect(LinkTypes.isEraGroupedType('none'), isTrue);
      expect(LinkTypes.isEraGroupedType('related passage'), isTrue);
      expect(LinkTypes.isEraGroupedType(null), isTrue);
      expect(LinkTypes.isEraGroupedType('reference'), isTrue);
      // ציטוט אוטומטי ממוזג ל-QUOTATION שהוא סוג ייעודי.
      expect(LinkTypes.isEraGroupedType('quotation auto'), isFalse);
      expect(LinkTypes.isEraGroupedType('MYSTERY_TYPE'), isFalse);
    });
  });

  group('LinkTypes.isEraKey', () {
    test('מבחין בין מפתח דור לסוג קישור', () {
      expect(LinkTypes.isEraKey('ERA:RISHONIM'), isTrue);
      expect(LinkTypes.isEraKey('REFERENCE'), isFalse);
      expect(LinkTypes.isEraKey('EIN_MISHPAT'), isFalse);
    });

    test('התחילית אינה יכולה להיווצר מנרמול של סוג קישור', () {
      // normalize לא מייצר נקודתיים, ולכן אין התנגשות במרחב המפתחות.
      expect(LinkTypes.normalize('era rishonim'), 'ERA_RISHONIM');
      expect(LinkTypes.isEraKey(LinkTypes.normalize('era rishonim')), isFalse);
    });

    test('normalize משמר מפתח דור כמות שהוא', () {
      expect(LinkTypes.normalize('ERA:RISHONIM'), 'ERA:RISHONIM');
    });
  });

  group('LinkTypes.onBookKey', () {
    test('שורד round-trip דרך normalize (בלי רווחים שיוחלפו)', () {
      expect(LinkTypes.onBookKey, 'ON_BOOK');
      expect(LinkTypes.normalize(LinkTypes.onBookKey), LinkTypes.onBookKey);
    });

    test('אינו מתנגש עם סוג קישור קיים', () {
      expect(LinkTypes.hebrewLabels.containsKey(LinkTypes.onBookKey), isFalse);
      expect(LinkTypes.isEraKey(LinkTypes.onBookKey), isFalse);
    });
  });

  group('LinkTypes.isVirtualSource', () {
    test('מזהה רק את SOURCE (לא תלוי רישיות)', () {
      expect(LinkTypes.isVirtualSource('SOURCE'), isTrue);
      expect(LinkTypes.isVirtualSource('source'), isTrue);
      expect(LinkTypes.isVirtualSource('COMMENTARY'), isFalse);
      expect(LinkTypes.isVirtualSource(null), isFalse);
    });
  });

  group('LinkTypes.referenceTypes (דו-כיווניות, סכמה 3)', () {
    /// תמונת מצב ידנית של ConnectionType בצד הקוטליני. היא תופסת מחיקה או
    /// חפיפה בסיווג — לא הוספה של סוג חדש בקוטלין, שלא תגיע לכאן מעצמה.
    const generatorTypes = <String>{
      'COMMENTARY',
      'SUPER_COMMENTARY',
      'TARGUM',
      'REFERENCE',
      'SOURCE',
      'MIDRASH',
      'QUOTATION',
      'MESORAT_HASHAS',
      'EIN_MISHPAT',
      'DIBUR_HAMATCHIL',
      'PARSHANUT',
      'MISHNAH_IN_TALMUD',
      'RELATED',
      'OTHER',
      'LINKER',
      'SIFREI_MITZVOT',
      'ESSAY',
      'ALLUSION',
      'LITURGY',
      'ELUCIDATION',
      'EXPLICATION',
      'LAW',
      'SUMMARY',
    };

    test('כל סוג של הגנרטור מסווג — תלוי-טקסט, הפניה, או חד-כיווני מוצהר', () {
      const oneDirectional = {'SOURCE', 'LINKER'};
      final unclassified = generatorTypes
          .where(
            (t) =>
                !LinkTypes.dependentTextTypes.contains(t) &&
                !LinkTypes.referenceTypes.contains(t) &&
                !oneDirectional.contains(t),
          )
          .toList();
      expect(unclassified, isEmpty, reason: 'סוגים ללא סיווג: $unclassified');
    });

    test('אין ב-referenceTypes ערך שהגנרטור אינו יכול לכתוב', () {
      // ערכים כמו QUOTATION_AUTO ממופים לסוג אחר לפני האחסון, ולכן היו
      // פרמטרים מתים בשאילתה.
      expect(LinkTypes.referenceTypes.difference(generatorTypes), isEmpty);
    });

    test('הקטגוריות זרות זו לזו', () {
      expect(
        LinkTypes.dependentTextTypes.intersection(LinkTypes.referenceTypes),
        isEmpty,
      );
    });

    test('SOURCE ו-LINKER אינם דו-כיווניים', () {
      // SOURCE וירטואלי ואינו נשמר; LINKER אינו עובר דרך ה-mask המיוצא ולכן
      // לא ניתן לדעת אם צדו הוסתר. הנימוק אינו נפח — ל-OTHER יש יותר קישורים.
      expect(LinkTypes.referenceTypes, isNot(contains(LinkTypes.source)));
      expect(LinkTypes.referenceTypes, isNot(contains(LinkTypes.linker)));
    });
  });

  group('LinkTypes.inverseQueryTypes', () {
    test('בלי תמיכת דיכוי — בדיוק ההתנהגות הקודמת', () {
      final types = LinkTypes.inverseQueryTypes(bidirectional: false);
      expect(types.toSet(), LinkTypes.dependentTextTypes);
    });

    test('עם תמיכת דיכוי — מתווספים קישורי ההפניה', () {
      final types = LinkTypes.inverseQueryTypes(bidirectional: true);
      expect(
        types.toSet(),
        LinkTypes.dependentTextTypes.union(LinkTypes.referenceTypes),
      );
      expect(types.length, types.toSet().length, reason: 'בלי כפילויות');
    });
  });

  group('LinkTypes.normalize', () {
    String legacyNormalize(String? connectionType) {
      final trimmed = connectionType?.trim() ?? '';
      if (trimmed.isEmpty) return '';
      return trimmed.toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
    }

    test('תוצאה זהה למימוש המקורי על כל צורות הקלט', () {
      for (final value in const [
        null,
        '',
        '   ',
        'COMMENTARY',
        'SUPER_COMMENTARY',
        'commentary',
        'Super Commentary',
        ' TARGUM ',
        'EIN_MISHPAT_/_NER_MITSVAH',
        'SUPER-COMMENTARY',
        'SUPER COMMENTARY',
        'A\tB',
        '__',
        '_A_',
        '123',
        'super-commentary',
        'a - b',
        'MISHNAH_IN_TALMUD2',
        '_',
        'פירוש',
      ]) {
        expect(
          LinkTypes.normalize(value),
          legacyNormalize(value),
          reason: '$value',
        );
      }
    });

    test('ערך קנוני מה-DB מנורמל מהר בהרבה מהמימוש המקורי', () {
      const dbValues = [
        'COMMENTARY',
        'SUPER_COMMENTARY',
        'REFERENCE',
        'TARGUM',
        'MESORAT_HASHAS',
        'EIN_MISHPAT',
      ];
      final links = [for (var i = 0; i < 50000; i++) dbValues[i % 6]];
      int bestMicros(String Function(String) normalize) {
        var best = 1 << 62;
        for (var run = 0; run < 5; run++) {
          final sw = Stopwatch()..start();
          for (final type in links) {
            normalize(type);
          }
          if (sw.elapsedMicroseconds < best) best = sw.elapsedMicroseconds;
        }
        return best;
      }

      final legacy = bestMicros(legacyNormalize);
      final current = bestMicros(LinkTypes.normalize);
      // הסף רחב כדי שלא יהבהב במכונה עמוסה.
      expect(current * 5, lessThan(legacy), reason: '$current/$legacy µs');
    });
  });
}
