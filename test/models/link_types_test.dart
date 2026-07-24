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

  group('LinkTypes.isReferenceLikeLink', () {
    test('מזהה קשרי עיון/הפניה אך לא מפרשים או SOURCE', () {
      expect(LinkTypes.isReferenceLikeLink('REFERENCE'), isTrue);
      expect(LinkTypes.isReferenceLikeLink('QUOTATION'), isTrue);
      expect(LinkTypes.isReferenceLikeLink('EIN_MISHPAT'), isTrue);
      expect(LinkTypes.isReferenceLikeLink('OTHER'), isTrue);
      expect(LinkTypes.isReferenceLikeLink('COMMENTARY'), isFalse);
      expect(LinkTypes.isReferenceLikeLink('EXPLICATION'), isFalse);
      expect(LinkTypes.isReferenceLikeLink('SOURCE'), isFalse);
      expect(LinkTypes.isReferenceLikeLink(null), isFalse);
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

    test('סוגים מובחנים וסוג לא-מוכר נשמרים כמות שהם (מנורמלים)', () {
      for (final type in const [
        'ALLUSION',
        'LAW',
        'FOOTNOTES',
        'LITURGY',
        'LINKER',
        'SUMMARY',
        'SIFREI_MITSVOT',
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
        'SIFREI_MITSVOT': 'ספרי מצוות',
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
        'SIFREI_MITSVOT',
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
}
