import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';

/// בודק את ה-predicate של ה-listenWhen ב-page_shape_screen.dart שאחראי
/// על פתיחת חלונית ההערות כשנוצרת טיוטה.
///
/// הלוגיקה מועתקת מ-page_shape_screen.dart:596-599 — אם משנים אותה שם,
/// חייבים לעדכן גם כאן (וההפך).
bool _shouldOpenSidebar(
  PersonalNotesState previous,
  PersonalNotesState current,
) {
  return previous.isCreatingNewNote != current.isCreatingNewNote ||
      previous.newNoteBookId != current.newNoteBookId ||
      previous.newNoteLineNumber != current.newNoteLineNumber;
}

void main() {
  group('page_shape listener predicate', () {
    test('פותח כשמתחילים יצירת טיוטה (false -> true)', () {
      const previous = PersonalNotesState.initial();
      const current = PersonalNotesState(
        isLoading: false,
        bookId: null,
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: true,
        newNoteBookId: 'ספר א',
        newNoteLineNumber: 5,
      );

      expect(_shouldOpenSidebar(previous, current), isTrue);
    });

    test('פותח כשעוברים מטיוטה של ספר אחד לטיוטה של ספר אחר', () {
      const previous = PersonalNotesState(
        isLoading: false,
        bookId: null,
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: true,
        newNoteBookId: 'ספר א',
        newNoteLineNumber: 5,
      );
      const current = PersonalNotesState(
        isLoading: false,
        bookId: null,
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: true,
        newNoteBookId: 'ספר ב',
        newNoteLineNumber: 5,
      );

      expect(_shouldOpenSidebar(previous, current), isTrue);
    });

    test('רגרסיה: פותח כשעוברים משורה לשורה באותו ספר '
        '(מקש ימני "הוסף הערה" כשיש כבר טיוטה פתוחה)', () {
      // לפני התיקון: ה-listenWhen בדק רק isCreatingNewNote ו-newNoteBookId,
      // אז אם המשתמש כבר היה במצב יצירת הערה (sidebar פתוח לשורה 5)
      // והקליק "הוסף הערה" בתפריט הימני על שורה 10 — הסיידבר לא היה
      // נפתח (אם נסגר) כי שני השדות לא השתנו.
      const previous = PersonalNotesState(
        isLoading: false,
        bookId: null,
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: true,
        newNoteBookId: 'ספר א',
        newNoteLineNumber: 5,
      );
      const current = PersonalNotesState(
        isLoading: false,
        bookId: null,
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: true,
        newNoteBookId: 'ספר א',
        newNoteLineNumber: 10,
      );

      expect(
        _shouldOpenSidebar(previous, current),
        isTrue,
        reason: 'שינוי שורה באותו ספר חייב להפעיל את ה-listener',
      );
    });

    test('לא פותח כששום דבר רלוונטי לא השתנה', () {
      const previous = PersonalNotesState(
        isLoading: false,
        bookId: null,
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: false,
        newNoteBookId: null,
        newNoteLineNumber: null,
      );
      // שינוי בשדה לא רלוונטי
      const current = PersonalNotesState(
        isLoading: true,
        bookId: 'ספר א',
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: false,
        newNoteBookId: null,
        newNoteLineNumber: null,
      );

      expect(_shouldOpenSidebar(previous, current), isFalse);
    });

    test('פותח כשמבטלים יצירת טיוטה (true -> false) — listener בודק אח"כ '
        'שלא לפתוח אם isCreatingNewNote=false', () {
      // ה-predicate מחזיר true גם על ביטול, אבל ה-listener עצמו (שמופעל
      // אחרי שה-predicate חזר true) מתחיל ב-`if (!state.isCreatingNewNote)
      // return;` — אז זה לא בעיה.
      const previous = PersonalNotesState(
        isLoading: false,
        bookId: null,
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: true,
        newNoteBookId: 'ספר א',
        newNoteLineNumber: 5,
      );
      const current = PersonalNotesState(
        isLoading: false,
        bookId: null,
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        isCreatingNewNote: false,
      );

      expect(_shouldOpenSidebar(previous, current), isTrue);
    });
  });
}
