import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// טבלת האמת של הניקוד והפיסוק: מה חל על הספר עצמו ומה על מפרשיו. מגן על
/// הרגרסיה שבה "הצג ניקוד בתנ״ך" הותירה ניקוד גם במפרשים, שאינם תנ״ך.
void main() {
  group('ניקוד — הצג תמיד', () {
    test('התנ״ך והמפרשים מנוקדים', () {
      final state = _load(nikud: NikudMode.always, isTanach: true);

      expect(state.removeNikud, isFalse);
      expect(state.commentaryRemoveNikud, isFalse);
    });

    test('הסתרה יזומה בסרגל חלה גם על המפרשים', () {
      final state = _load(nikud: NikudMode.always, isTanach: true);

      expect(state.copyWith(removeNikud: true).commentaryRemoveNikud, isTrue);
    });

    test('גם בספר שאינו תנ"ך אין פטור, והכל מנוקד', () {
      final state = _load(nikud: NikudMode.always, isTanach: false);

      expect(state.removeNikud, isFalse);
      expect(state.nikudExemptByTanach, isFalse);
      expect(state.commentaryRemoveNikud, isFalse);
    });
  });

  group('ניקוד — הצג בתנ״ך בלבד', () {
    test('התנ״ך מנוקד אבל מפרשיו אינם', () {
      final state = _load(nikud: NikudMode.tanachOnly, isTanach: true);

      expect(state.removeNikud, isFalse);
      expect(state.commentaryRemoveNikud, isTrue);
    });

    test('בספר שאינו תנ״ך גם הספר וגם המפרשים ללא ניקוד', () {
      final state = _load(nikud: NikudMode.tanachOnly, isTanach: false);

      expect(state.removeNikud, isTrue);
      expect(state.commentaryRemoveNikud, isTrue);
    });

    test('הצגה יזומה בסרגל התנ״ך אינה מחזירה ניקוד למפרשים', () {
      // בחירת המשתמש: הכפתור בסרגל ספר התנ״ך שולט בתנ״ך בלבד.
      final state = _load(nikud: NikudMode.tanachOnly, isTanach: true);

      expect(state.copyWith(removeNikud: true).commentaryRemoveNikud, isTrue);
      expect(state.copyWith(removeNikud: false).commentaryRemoveNikud, isTrue);
    });

    test('בספר שאינו תנ״ך הצגה יזומה כן מחזירה ניקוד למפרשים', () {
      final state = _load(nikud: NikudMode.tanachOnly, isTanach: false);

      expect(state.copyWith(removeNikud: false).commentaryRemoveNikud, isFalse);
    });

    test('עקיפת המפרשים מחזירה ניקוד בלי לשנות את ספר התנ״ך', () {
      final state = _load(nikud: NikudMode.tanachOnly, isTanach: true);

      final showingCommentaries = state.copyWith(
        commentaryRemoveNikudOverride: false,
      );

      expect(showingCommentaries.removeNikud, isFalse);
      expect(showingCommentaries.commentaryRemoveNikud, isFalse);
    });
  });

  group('ניקוד — אל תציג', () {
    test('התנ״ך והמפרשים ללא ניקוד', () {
      final state = _load(nikud: NikudMode.never, isTanach: true);

      expect(state.removeNikud, isTrue);
      expect(state.commentaryRemoveNikud, isTrue);
    });

    test('הצגה יזומה בסרגל מחזירה ניקוד לתנ״ך ולמפרשים', () {
      // אין כאן פטור-תנ״ך, ולכן ההחלפה היזומה חלה על שניהם.
      final state = _load(nikud: NikudMode.never, isTanach: true);

      expect(state.copyWith(removeNikud: false).commentaryRemoveNikud, isFalse);
    });
  });

  group('פיסוק', () {
    test('בתנ״ך הפיסוק נשמר בספר אך מוסר מהמפרשים', () {
      final state = _load(removePunctuation: true, isTanach: true);

      expect(state.removePunctuation, isFalse);
      expect(state.commentaryRemovePunctuation, isTrue);
    });

    test('בספר שאינו תנ״ך הפיסוק מוסר משניהם', () {
      final state = _load(removePunctuation: true, isTanach: false);

      expect(state.removePunctuation, isTrue);
      expect(state.commentaryRemovePunctuation, isTrue);
    });

    test('כשההגדרה כבויה הפיסוק נשמר בשניהם', () {
      final state = _load(removePunctuation: false, isTanach: true);

      expect(state.removePunctuation, isFalse);
      expect(state.commentaryRemovePunctuation, isFalse);
    });

    test('כשההגדרה כבויה ובספר שאינו תנ"ך אין פטור', () {
      final state = _load(removePunctuation: false, isTanach: false);

      expect(state.punctuationExemptByTanach, isFalse);
      expect(state.commentaryRemovePunctuation, isFalse);
    });

    test('עקיפת המפרשים מחזירה פיסוק בלי לשנות את ספר התנ״ך', () {
      final state = _load(removePunctuation: true, isTanach: true);

      final showingCommentaries = state.copyWith(
        commentaryRemovePunctuationOverride: false,
      );

      expect(showingCommentaries.removePunctuation, isFalse);
      expect(showingCommentaries.commentaryRemovePunctuation, isFalse);
    });
  });

  group('הדגלים נכללים בהשוואת ה-state', () {
    test('שינוי פטור הניקוד מייצר state שונה', () {
      expect(
        _load(nikud: NikudMode.tanachOnly, isTanach: true),
        isNot(equals(_load(nikud: NikudMode.tanachOnly, isTanach: false))),
      );
    });

    test('שינוי פטור הפיסוק מייצר state שונה', () {
      final exempt = _load(removePunctuation: true, isTanach: true);

      expect(
        exempt,
        isNot(equals(exempt.copyWith(punctuationExemptByTanach: false))),
      );
    });
  });
}

/// שלושת מצבי הגדרת הניקוד כפי שהם מוצגים במסך ההגדרות.
enum NikudMode { always, tanachOnly, never }

/// בונה state כפי שה-bloc מחשב אותו בטעינת ספר, מאותן פונקציות טהורות
/// שה-bloc עצמו משתמש בהן.
TextBookLoaded _load({
  NikudMode nikud = NikudMode.always,
  bool removePunctuation = false,
  required bool isTanach,
}) {
  final defaultRemoveNikud = nikud != NikudMode.always;
  final removeNikudFromTanach = nikud == NikudMode.never;

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    isTanach: isTanach,
    removeNikud: shouldRemoveNikudForBook(
      defaultRemoveNikud: defaultRemoveNikud,
      removeNikudFromTanach: removeNikudFromTanach,
      isTanach: isTanach,
    ),
    nikudExemptByTanach:
        defaultRemoveNikud && !removeNikudFromTanach && isTanach,
    removePunctuation: shouldRemovePunctuationForBook(
      defaultRemovePunctuation: removePunctuation,
      isTanach: isTanach,
    ),
    punctuationExemptByTanach: removePunctuation && isTanach,
    visibleIndices: const [0],
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}
