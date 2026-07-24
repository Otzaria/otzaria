import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  group('TextBookBloc.filterBarelyVisiblePositionsForTesting', () {
    test('שומר על position יחיד גם אם גלוי מעט (אין fallback אחר)', () {
      // אחרי גלילה לתחילת/סוף הספר ייתכן שיש רק position אחד גלוי, גם אם
      // גלוי חלקית. לא נסיר אותו - אין מה להחזיר במקום.
      final positions = [
        const ItemPosition(
          index: 5,
          itemLeadingEdge: -2,
          itemTrailingEdge: 0.05,
        ),
      ];

      final filtered = TextBookBloc.filterBarelyVisiblePositionsForTesting(
        positions,
      );

      expect(filtered.length, 1);
      expect(filtered.first.index, 5);
    });

    test('מסיר position שמסיים ב-5% העליונים של ה-viewport', () {
      // הסיטואציה המדויקת אחרי scrollToSourceLine עם alignment=0.05:
      // הקטע הקודם משתרע מ-itemLeadingEdge=-2 עד itemTrailingEdge=0.05
      // (5% מהמסך עליון), בעוד הקטע אליו ניווטו תופס את שאר המסך.
      final positions = [
        const ItemPosition(
          index: 99,
          itemLeadingEdge: -2,
          itemTrailingEdge: 0.05,
        ),
        const ItemPosition(
          index: 100,
          itemLeadingEdge: 0.05,
          itemTrailingEdge: 0.95,
        ),
        const ItemPosition(
          index: 101,
          itemLeadingEdge: 0.95,
          itemTrailingEdge: 1.5,
        ),
      ];

      final filtered = TextBookBloc.filterBarelyVisiblePositionsForTesting(
        positions,
      );

      expect(filtered.map((p) => p.index), [100]);
    });

    test('שומר על segment גדול חצי-גלוי (visibility ratio > 15%)', () {
      // segment שמשתרע מ-leadingEdge=-0.5 עד trailingEdge=0.5: 50% מה-extent
      // גלוי - נשמר.
      final positions = [
        const ItemPosition(
          index: 10,
          itemLeadingEdge: -0.5,
          itemTrailingEdge: 0.5,
        ),
        const ItemPosition(
          index: 11,
          itemLeadingEdge: 0.5,
          itemTrailingEdge: 1.5,
        ),
      ];

      final filtered = TextBookBloc.filterBarelyVisiblePositionsForTesting(
        positions,
      );

      expect(filtered.length, 2);
      expect(filtered.map((p) => p.index), [10, 11]);
    });

    test('מסיר שורה קצרה שנגמרת בקו העוגן (0.05) - שייר של הסעיף הקודם', () {
      // שורה קצרה הגלויה במלואה ב-5% העליונים (trailingEdge=0.05) היא שייר
      // של הסעיף הקודם שאליו הניווט מיישר - נסיר אותה כדי שההדגשה בסרגל
      // הניווט תזוהה לפי הסעיף שאליו ניווטו (index 51), ולא לפי השייר.
      final positions = [
        const ItemPosition(
          index: 50,
          itemLeadingEdge: 0.02,
          itemTrailingEdge: 0.05,
        ),
        const ItemPosition(
          index: 51,
          itemLeadingEdge: 0.05,
          itemTrailingEdge: 0.95,
        ),
      ];

      final filtered = TextBookBloc.filterBarelyVisiblePositionsForTesting(
        positions,
      );

      expect(filtered.map((p) => p.index), [51]);
    });

    test('שומר על סגמנט קצר שמתחיל בקו העוגן - יעד ניווט אמיתי', () {
      // סגמנט קצר שגללו אליו בפועל מתחיל ב-0.05 (קו העוגן) ונגמר ב-0.058.
      // למרות שנוכחותו זעירה הוא היעד עצמו, לא שייר של הסעיף הקודם (שמגיע
      // מלמעלה) - ולכן נשמר וההדגשה תזוהה לפיו (index 50).
      final positions = [
        const ItemPosition(
          index: 50,
          itemLeadingEdge: 0.05,
          itemTrailingEdge: 0.058,
        ),
        const ItemPosition(
          index: 51,
          itemLeadingEdge: 0.058,
          itemTrailingEdge: 0.95,
        ),
      ];

      final filtered = TextBookBloc.filterBarelyVisiblePositionsForTesting(
        positions,
      );

      expect(filtered.map((p) => p.index), [50, 51]);
    });

    test('מסיר שורה קצרה שנגמרת מעט מתחת לקו העוגן (רעש מדידה)', () {
      // אחרי גלילה ורעש מדידה (כמו "overflowed by 2px") הקצה התחתון של השייר
      // עלול לנחות מעט מתחת ל-0.05 (0.058). נוכחותו מתחת לקו העוגן זניחה,
      // ולכן נסיר אותו כדי שההדגשה תזוהה לפי הסעיף שאליו ניווטו (index 51).
      final positions = [
        const ItemPosition(
          index: 50,
          itemLeadingEdge: 0.02,
          itemTrailingEdge: 0.058,
        ),
        const ItemPosition(
          index: 51,
          itemLeadingEdge: 0.058,
          itemTrailingEdge: 0.95,
        ),
      ];

      final filtered = TextBookBloc.filterBarelyVisiblePositionsForTesting(
        positions,
      );

      expect(filtered.map((p) => p.index), [51]);
    });

    test('מסיר גם position שמתחיל ב-95% התחתונים של ה-viewport', () {
      // הסימטריה ההפוכה: segment שמתחיל ב-leadingEdge=0.97 ונמשך החוצה - גלוי
      // רק 3% מה-extent שלו - יוסר.
      final positions = [
        const ItemPosition(
          index: 100,
          itemLeadingEdge: 0.05,
          itemTrailingEdge: 0.97,
        ),
        const ItemPosition(
          index: 101,
          itemLeadingEdge: 0.97,
          itemTrailingEdge: 2,
        ),
      ];

      final filtered = TextBookBloc.filterBarelyVisiblePositionsForTesting(
        positions,
      );

      expect(filtered.map((p) => p.index), [100]);
    });

    test('fallback: אם כל ה-positions מתחת לסף, חוזרים למקור', () {
      // edge case שלא אמור לקרות בפועל - שני positions גלויים פחות מ-15%.
      // כדי לא להחזיר רשימה ריקה (שתשבש visibleIndices לגמרי), חוזרים למקור.
      final positions = [
        const ItemPosition(
          index: 1,
          itemLeadingEdge: -10,
          itemTrailingEdge: 0.05,
        ),
        const ItemPosition(
          index: 2,
          itemLeadingEdge: 0.95,
          itemTrailingEdge: 10,
        ),
      ];

      final filtered = TextBookBloc.filterBarelyVisiblePositionsForTesting(
        positions,
      );

      expect(filtered.length, 2);
    });
  });
}
