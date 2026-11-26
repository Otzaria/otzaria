import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_aliases/book_aliases.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// החוזה של מודול כינויי הספרים — המקום היחיד לכללי הכינויים.
void main() {
  group('מילות קישור', () {
    test('"על" בין מילים מושמטת; בקצוות נשארת', () {
      expect(bookNameAcronymForm('רשבא על בק'), 'רשבא בק');
      expect(bookNameAcronymForm('על התורה'), 'על התורה');
      expect(bookNameAcronymForm('אוצרות יוסף על'), 'אוצרות יוסף על');
    });

    test('הצורה כוללת את כתיב וו/יי', () {
      expect(bookNameAcronymForm('מקוואות'), 'מקואות');
    });

    test('"מסכת" באמצע — גיבוי נפרד; בראש ובסוף נשארת', () {
      expect(bookNameTractateAcronymForm('תוס מסכת יומא'), 'תוס יומא');
      expect(bookNameTractateAcronymForm('מסכת סופרים'), 'מסכת סופרים');
      expect(bookNameTractateAcronymForm('רשבא בק'), 'רשבא בק');
      expect(isTractateWord('מסכת'), isTrue);
      expect(isTractateWord('מס'), isFalse);
    });
  });

  group('כינויים נגזרים מהכותרת', () {
    test('"רמב"ם על משנה X" — שמות הסט, גם עם ייחוס', () {
      final aliases = derivedBookAliases(
        normalizeForFindRefMatch('רמב"ם על משנה סוכה'),
      );
      expect(
        aliases,
        containsAll([
          'פירוש המשניות סוכה',
          'פרוש המשניות סוכה',
          'פיהמ סוכה',
          'פיהמש סוכה',
          'פירוש המשניות לרמבם סוכה',
          'פירוש המשניות להרמבם סוכה',
        ]),
      );
    });

    test('בדיקה זולה לפני נרמול — גם בכותרת מנוקדת', () {
      expect(mayHaveDerivedBookAliases('רַמְבַּ"ם עַל מִשְׁנָה סוכה'), isTrue);
      expect(mayHaveDerivedBookAliases('רמב"ם על משנה סוכה'), isTrue);
      expect(mayHaveDerivedBookAliases('רשב"א על בבא קמא'), isFalse);
    });

    test('ספר שאינו בסט — בלי כינויים נגזרים', () {
      expect(derivedBookAliases('רשבא על בבא קמא'), isEmpty);
      expect(derivedBookAliases('רמבם על משנה'), isEmpty);
    });
  });

  group('bookAliasesOf', () {
    test('בלי כינוי נגזר — הרשימה המילולית עצמה', () {
      final literal = ['רשבא בק'];
      expect(
        identical(bookAliasesOf(literal, 'רשבא על בבא קמא'), literal),
        true,
      );
      expect(bookAliasesOf(null, 'רשבא על בבא קמא'), isNull);
    });

    test('המילוליים קודם, והנגזר שכבר מילולי אינו נוסף שוב', () {
      final aliases = bookAliasesOf(const [
        'פיהמ סוכה',
        'רמבם משנה סוכה',
      ], 'רמבם על משנה סוכה')!;
      expect(aliases.take(2), ['פיהמ סוכה', 'רמבם משנה סוכה']);
      expect(aliases.where((a) => a == 'פיהמ סוכה'), hasLength(1));
      expect(aliases, contains('פירוש המשניות סוכה'));
    });

    test('ספר בלי כינויים מילוליים (מסד מצורף בלי הטבלה, ספר אישי)', () {
      expect(bookAliasesOf(null, 'רמבם על משנה סוכה'), contains('פיהמ סוכה'));
    });
  });

  group('קריאת הכינויים המילוליים', () {
    test('מנרמל, מדלג על ריקים וסופר שורות', () {
      final terms = collectBookAliasTerms(const [
        (1, 'רמב"ם'),
        (1, ''),
        (2, 'שו"ע או"ח'),
      ], normalizeForFindRefMatch);
      expect(terms.rowCount, 3);
      expect(terms.aliasesByBookId, {
        1: ['רמבם'],
        2: ['שוע אוח'],
      });
      expect(terms.quotedWordsByBookId[2], {'שוע', 'אוח'});
    });

    test('המסננת היא קבוצת-על של הספרים שכינוים מכיל את השאילתה', () {
      final data = buildAcronymCacheData(const [
        (1, 'רמב"ם'),
        (2, 'רשב"א על בק'),
      ], normalizeForFindRefMatch);
      expect(data.candidatesFor('רשב')!.contains(2), isTrue);
      expect(data.candidatesFor('רשב')!.contains(1), isFalse);
      expect(data.candidatesFor('זזז')!.length, 0);
    });
  });
}
