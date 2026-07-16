import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';

// טסטים לרדוסרים הטהורים שמפעילים את מצב הניווט ב-[CommentatorsTabScreen].
// כל מסלולי עדכון ה-state ב-_CommentatorsTabScreenState עוברים דרך
// _applyNavSelection עם תוצאת אחד הרדוסרים:
//   - reduceChevronTap     → onPressed של ה-IconButton של החץ
//   - reduceChapterBodyTap → no-op check ב-onTap של גוף שורת הפרק
//   - reduceSubItemTap     → _selectVerseInChapter / _selectParaInChapter
//                            ו-_onChapterSelected (עם verseIdx=_kAllChapter)
// כך שהטסטים על הרדוסרים תופסים רגרסיות בהתנהגות שמופעלת מה-UI.
void main() {
  TocEntry chapterA() => TocEntry(text: 'פרק א', index: 0);
  TocEntry chapterB() => TocEntry(text: 'פרק ב', index: 5);

  group('chapterEndLineIndex — גבול הפרק', () {
    // דף ראשון (אינדקס 0), דף אחרון (אינדקס 10) בספר בן 25 שורות.
    final firstDaf = TocEntry(text: 'דף ב', index: 0);
    final lastDaf = TocEntry(text: 'דף יג', index: 10);
    final chapters = [firstDaf, lastDaf];

    test('פרק שאינו אחרון נתחם ע"י תחילת הפרק העוקב פחות 1', () {
      expect(chapterEndLineIndex(chapters, firstDaf, 25), equals(9));
    });

    test('הפרק האחרון נתחם עד שורת התוכן האחרונה (לא שורה בודדת)', () {
      // הרגרסיה: בעבר "כל הדף" בדף האחרון הוחזר כשורה בודדת (index 10) בלבד,
      // ולכן לא זוהו מפרשים. כעת הגבול הוא שורת התוכן האחרונה (24).
      expect(chapterEndLineIndex(chapters, lastDaf, 25), equals(24));
      expect(chapterEndLineIndex(chapters, lastDaf, 25), greaterThan(10));
    });

    test('פרק יחיד נתחם עד סוף התוכן', () {
      final only = TocEntry(text: 'דף ב', index: 0);
      expect(chapterEndLineIndex([only], only, 40), equals(39));
    });
  });

  group('reduceChevronTap — שמירה על בחירת המפרשים', () {
    test('לחיצה על חץ הפרק הנבחר (הרגרסיה המקורית) לא מבטלת את הבחירה', () {
      final chA = chapterA();
      final state = CommentatorsNavSelection(
        selectedChapter: chA,
        navExpandedChapter: chA,
      );

      final next = reduceChevronTap(state, chA);

      // הבחירה והאינדקס נשמרו — זה התיקון של הבאג שבו 'לא נמצאו מפרשים'
      // הופיע אחרי כיווץ הניווט.
      expect(next.selectedChapter, equals(chA));
      expect(next.selectedVerseIdx, equals(state.selectedVerseIdx));
      // אך הניווט כווץ.
      expect(next.navExpandedChapter, isNull);
    });

    test('לחיצה על חץ פרק לא-נבחר מרחיבה אותו בלי לשנות את הבחירה', () {
      final chA = chapterA();
      final chB = chapterB();
      final state = CommentatorsNavSelection(
        selectedChapter: chA,
        selectedVerseIdx: 3,
        navExpandedChapter: chA,
      );

      final next = reduceChevronTap(state, chB);

      // הבחירה ואינדקס הפסוק נשמרו — לחיצה על חץ של פרק אחר היא ניווט בלבד.
      expect(next.selectedChapter, equals(chA));
      expect(next.selectedVerseIdx, equals(3));
      expect(next.navExpandedChapter, equals(chB));
    });

    test('לחיצה חוזרת על חץ פרק מורחב מכווצת אותו ל-null', () {
      final chB = chapterB();
      final state = CommentatorsNavSelection(navExpandedChapter: chB);

      final next = reduceChevronTap(state, chB);

      expect(next.navExpandedChapter, isNull);
    });

    test('לחיצה על חץ בעוד אין הרחבה בכלל מרחיבה את הפרק הנלחץ', () {
      final chA = chapterA();
      const state = CommentatorsNavSelection();

      final next = reduceChevronTap(state, chA);

      expect(next.navExpandedChapter, equals(chA));
      expect(next.selectedChapter, isNull);
    });
  });

  group('reduceChapterBodyTap — לחיצה על גוף שורת פרק', () {
    test('לחיצה על פרק לא-נבחר בוחרת אותו ומרחיבה אותו בניווט', () {
      final chA = chapterA();
      final chB = chapterB();
      final state = CommentatorsNavSelection(
        selectedChapter: chA,
        selectedVerseIdx: 5,
        navExpandedChapter: chA,
      );

      final next = reduceChapterBodyTap(state, chB);

      expect(next.selectedChapter, equals(chB));
      expect(next.selectedVerseIdx, equals(-1));
      expect(next.navExpandedChapter, equals(chB));
    });

    test('לחיצה על פרק שכבר נבחר היא no-op (מחזירה אותו state)', () {
      final chA = chapterA();
      final state = CommentatorsNavSelection(
        selectedChapter: chA,
        selectedVerseIdx: 5,
        navExpandedChapter: chA,
      );

      final next = reduceChapterBodyTap(state, chA);

      // identical: ה-instance הוא בדיוק אותו — חשוב עבור short-circuit
      // שמונע טעינה מיותרת של links ב-_onChapterSelected.
      expect(identical(next, state), isTrue);
    });

    test('לחיצה על פרק לא-נבחר עם חירה ניקויה מעדכנת את הבחירה', () {
      final chA = chapterA();
      const state = CommentatorsNavSelection();

      final next = reduceChapterBodyTap(state, chA);

      expect(next.selectedChapter, equals(chA));
      expect(next.navExpandedChapter, equals(chA));
    });
  });

  group('reduceSubItemTap — לחיצה על תת-פריט', () {
    test('לחיצה על תת-פריט בפרק לא-נבחר מחליפה את בחירת הפרק לאותו פרק', () {
      // תרחיש: המשתמש פתח פרק ב בניווט (חץ פתיחה), ופרק א הוא הנבחר.
      // כעת הוא לוחץ על פסוק בפרק ב. הבחירה צריכה לעבור לפרק ב + אותו פסוק.
      final chA = chapterA();
      final chB = chapterB();
      final state = CommentatorsNavSelection(
        selectedChapter: chA,
        selectedVerseIdx: -1,
        navExpandedChapter: chB,
      );

      final next = reduceSubItemTap(state, chB, 2);

      expect(next.selectedChapter, equals(chB));
      expect(next.selectedVerseIdx, equals(2));
      expect(next.navExpandedChapter, equals(chB));
    });

    test('לחיצה על תת-פריט בפרק הנבחר מעדכנת רק את אינדקס הפסוק', () {
      final chA = chapterA();
      final state = CommentatorsNavSelection(
        selectedChapter: chA,
        selectedVerseIdx: -1,
        navExpandedChapter: chA,
      );

      final next = reduceSubItemTap(state, chA, 7);

      expect(next.selectedChapter, equals(chA));
      expect(next.selectedVerseIdx, equals(7));
      expect(next.navExpandedChapter, equals(chA));
    });
  });

  group('computeVerseStep — ניווט קטע קודם/הבא (חוצה פרקים)', () {
    // שני פרקים: פרק 0 עם קטעים [0,1,2], פרק 1 עם קטעים [0,1].
    final twoChapters = [
      [0, 1, 2],
      [0, 1],
    ];

    test('קטע הבא בתוך אותו פרק', () {
      expect(computeVerseStep(twoChapters, 0, 0, forward: true),
          equals(const CommentatorsVerseStep(0, 1)));
    });

    test('קטע קודם בתוך אותו פרק', () {
      expect(computeVerseStep(twoChapters, 0, 2, forward: false),
          equals(const CommentatorsVerseStep(0, 1)));
    });

    test('מהקטע האחרון בפרק — קטע הבא חוצה לפרק הבא (קטע ראשון)', () {
      expect(computeVerseStep(twoChapters, 0, 2, forward: true),
          equals(const CommentatorsVerseStep(1, 0)));
    });

    test('מהקטע הראשון בפרק — קטע קודם חוצה לפרק הקודם (קטע אחרון)', () {
      // ליבת הבאג: פעם הניווט "נתקע" בתחילת הפרק. כעת חוצה אחורה.
      expect(computeVerseStep(twoChapters, 1, 0, forward: false),
          equals(const CommentatorsVerseStep(0, 2)));
    });

    test('"כל הפרק" — קטע קודם יורד לקטע האחרון של אותו פרק', () {
      expect(computeVerseStep(twoChapters, 0, -1, forward: false),
          equals(const CommentatorsVerseStep(0, 2)));
    });

    test('"כל הפרק" — קטע הבא עולה לקטע הראשון של אותו פרק', () {
      expect(computeVerseStep(twoChapters, 0, -1, forward: true),
          equals(const CommentatorsVerseStep(0, 0)));
    });

    test('קצה הספר — קטע קודם מהקטע הראשון בפרק הראשון מחזיר null', () {
      expect(computeVerseStep(twoChapters, 0, 0, forward: false), isNull);
    });

    test('קצה הספר — קטע הבא מהקטע האחרון בפרק האחרון מחזיר null', () {
      expect(computeVerseStep(twoChapters, 1, 1, forward: true), isNull);
    });

    test('חצייה קדימה לפרק שכן ריק מקטעים — מחזיר "כל הפרק"', () {
      final withEmpty = [
        [0, 1],
        <int>[],
      ];
      expect(computeVerseStep(withEmpty, 0, 1, forward: true),
          equals(const CommentatorsVerseStep(1, -1)));
    });

    test('חצייה אחורה לפרק שכן ריק מקטעים — מחזיר "כל הפרק"', () {
      final withEmpty = [
        <int>[],
        [0, 1],
      ];
      expect(computeVerseStep(withEmpty, 1, 0, forward: false),
          equals(const CommentatorsVerseStep(0, -1)));
    });

    test('"כל הפרק" בפרק ריק — קטע קודם חוצה אחורה לקטע האחרון של הקודם', () {
      final withEmpty = [
        [0, 1],
        <int>[],
      ];
      expect(computeVerseStep(withEmpty, 1, -1, forward: false),
          equals(const CommentatorsVerseStep(0, 1)));
    });

    test('"כל הפרק" בפרק ריק — קטע הבא חוצה קדימה לקטע הראשון של הבא', () {
      final withEmpty = [
        <int>[],
        [0, 1],
      ];
      expect(computeVerseStep(withEmpty, 0, -1, forward: true),
          equals(const CommentatorsVerseStep(1, 0)));
    });

    test('קצה הספר — "כל הפרק" בפרק יחיד ריק מחזיר null בשני הכיוונים', () {
      final single = [<int>[]];
      expect(computeVerseStep(single, 0, -1, forward: false), isNull);
      expect(computeVerseStep(single, 0, -1, forward: true), isNull);
    });

    test('אינדקס פרק לא חוקי מחזיר null', () {
      expect(computeVerseStep(twoChapters, 5, 0, forward: true), isNull);
    });

    test('verseIdx שאינו ברשימת הקטעים מחזיר null', () {
      expect(computeVerseStep(twoChapters, 0, 99, forward: true), isNull);
    });
  });

  group('computeVerseStep — תרחיש הבאג המקורי (פתיחה + חזרה אחורה)', () {
    // הבאג: בפתיחה בקטע ספציפי, 'קטע קודם' נתקע בקטע שנפתח ולא ירד מתחתיו.
    // הרצף מדמה: פתיחה בפרק 1, ואז לחיצות 'קודם' רצופות — עד חצייה לפרק 0,
    // בלי היתקעות.
    final book = [
      [0, 1, 2],
      [0, 1],
    ];

    test('פתיחה בקטע הראשון בפרק 1 — קטע קודם חוצה לפרק 0 ולא נתקע', () {
      final back1 = computeVerseStep(book, 1, 0, forward: false);
      expect(back1, equals(const CommentatorsVerseStep(0, 2)),
          reason: 'מהקטע הראשון בפרק 1 יש לחצות לקטע האחרון בפרק 0');

      final back2 = computeVerseStep(book, back1!.chapterIndex, back1.verseIdx,
          forward: false);
      expect(back2, equals(const CommentatorsVerseStep(0, 1)));

      final back3 = computeVerseStep(book, back2!.chapterIndex, back2.verseIdx,
          forward: false);
      expect(back3, equals(const CommentatorsVerseStep(0, 0)));

      // בקטע הראשון של הפרק הראשון — אין לאן לחזור.
      expect(
          computeVerseStep(book, back3!.chapterIndex, back3.verseIdx,
              forward: false),
          isNull);
    });

    test('הלוך-ושוב סימטרי: הבא ואז קודם חוזר לאותו מיקום', () {
      final fwd = computeVerseStep(book, 0, 2, forward: true);
      expect(fwd, equals(const CommentatorsVerseStep(1, 0)));
      final back = computeVerseStep(book, fwd!.chapterIndex, fwd.verseIdx,
          forward: false);
      expect(back, equals(const CommentatorsVerseStep(0, 2)));
    });
  });

  group('computeVerseStep — חוזה חישוב עצל (רק הנוכחי והשכן מלאים)', () {
    // _navigateVerse ממלא רק את הפרק הנוכחי ואת השכן בכיוון; שאר הפרקים
    // ריקים לחיסכון. כאן מוודאים שהחישוב תקין תחת אילוץ זה.
    test('קדימה: רק הפרק הנוכחי והבא מלאים — חצייה לפרק הבא', () {
      final lazy = [
        <int>[], // פרק לפני — לא רלוונטי לכיוון קדימה
        [0, 1], // נוכחי
        [0, 1, 2], // שכן בכיוון
        <int>[], // אחרי — לא רלוונטי
      ];
      expect(computeVerseStep(lazy, 1, 1, forward: true),
          equals(const CommentatorsVerseStep(2, 0)));
    });

    test('אחורה: רק הפרק הנוכחי והקודם מלאים — חצייה לפרק הקודם', () {
      final lazy = [
        <int>[], // לפני — לא רלוונטי
        [0, 1, 2], // שכן בכיוון (קודם)
        [0, 1], // נוכחי
        <int>[], // אחרי — לא רלוונטי
      ];
      expect(computeVerseStep(lazy, 2, 0, forward: false),
          equals(const CommentatorsVerseStep(1, 2)));
    });
  });

  group('resolveOpenedVerseIdx — בחירת הקטע בפתיחת הטאב', () {
    test('פרק עם תת-פרקים — נבחר הפסוק שזוהה (posVerseIdx נשמר)', () {
      expect(
        resolveOpenedVerseIdx(
          posVerseIdx: 2,
          lineIndex: 12,
          chapterIndex: 10,
          hasChildren: true,
          selectableParagraphOffsets: const [],
        ),
        equals(2),
      );
    });

    test('פרק עם תת-פרקים ו-posVerseIdx=-1 — נשאר "כל הפרק"', () {
      // כשלא זוהה פסוק ספציפי בפרק שיש בו תת-פרקים, לא גוזרים היסט פסקה.
      expect(
        resolveOpenedVerseIdx(
          posVerseIdx: -1,
          lineIndex: 12,
          chapterIndex: 10,
          hasChildren: true,
          selectableParagraphOffsets: const [],
        ),
        equals(-1),
      );
    });

    test('פרק ללא תת-פרקים — נגזר היסט הפסקה שנפתחה כשהוא ניתן לבחירה', () {
      // הפער שנסגר: פתיחה על שורה ספציפית בפרק-פסקאות בוחרת את הפסקה,
      // ולא "כל הפרק" — כך ש'קטע קודם' מיד אחרי הפתיחה עובד.
      expect(
        resolveOpenedVerseIdx(
          posVerseIdx: -1,
          lineIndex: 13,
          chapterIndex: 10,
          hasChildren: false,
          selectableParagraphOffsets: const [0, 1, 2, 3],
        ),
        equals(3),
      );
    });

    test('פרק ללא תת-פרקים — היסט מסונן נשאר "כל הפרק" (לא נתקע)', () {
      // הרגרסיה שנמנעה: לו היינו בוחרים היסט שמסונן מרשימת ה-selectable,
      // ניווט 'קטע קודם' היה מקבל indexOf==-1 ונתקע.
      expect(
        resolveOpenedVerseIdx(
          posVerseIdx: -1,
          lineIndex: 10,
          chapterIndex: 10,
          hasChildren: false,
          selectableParagraphOffsets: const [1, 2, 3], // 0 מסונן (כותרת)
        ),
        equals(-1),
      );
    });

    test('פרק ללא תת-פרקים — הקטע הראשון (היסט 0) נבחר כשהוא ניתן לבחירה', () {
      expect(
        resolveOpenedVerseIdx(
          posVerseIdx: -1,
          lineIndex: 10,
          chapterIndex: 10,
          hasChildren: false,
          selectableParagraphOffsets: const [0, 1, 2],
        ),
        equals(0),
      );
    });
  });

  group('resolveSelectedSnippetGlobalIndex — סימון השורה בניווט היקרויות', () {
    // מפרש א' עם 3 היקרויות (0-2), מפרש ב' עם 2 (3-4) — שורה אחת לכל מפרש.
    const snippets = [
      CommentarySearchSnippet(path: 'a', snippet: 's1', globalIndex: 0),
      CommentarySearchSnippet(path: 'b', snippet: 's2', globalIndex: 3),
    ];

    test('היקרות ראשונה של מפרש בוחרת את שורתו', () {
      expect(resolveSelectedSnippetGlobalIndex(snippets, 0), 0);
      expect(resolveSelectedSnippetGlobalIndex(snippets, 3), 3);
    });

    test('היקרויות המשך באותו מפרש נשארות על שורתו', () {
      expect(resolveSelectedSnippetGlobalIndex(snippets, 1), 0);
      expect(resolveSelectedSnippetGlobalIndex(snippets, 2), 0);
      expect(resolveSelectedSnippetGlobalIndex(snippets, 4), 3);
    });

    test('רשימה ריקה — אין שורה נבחרת', () {
      expect(resolveSelectedSnippetGlobalIndex(const [], 0), -1);
    });
  });
}
