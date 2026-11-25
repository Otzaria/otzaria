import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// טסטים ללוגיקה הטהורה של החלטות מצב-רצף ב-bloc. זרימת ה-state המלאה
/// נבדקת ב-`text_book_bloc_test.dart`, והפריסה ב-`reading_layout_test.dart`.
void main() {
  group('computeEffectiveContinuousReading', () {
    test('ביקוש לאפשר על ספר שתומך → מחזיר true', () {
      expect(
        TextBookBloc.computeEffectiveContinuousReading(
          requestedEnabled: true,
          stateSupportsContinuous: true,
        ),
        isTrue,
      );
    });

    test('ביקוש לאפשר על ספר שלא תומך → מחזיר false', () {
      // קריטי: מגן מקיצורי מקלדת/plugins שעלולים לדרוש true גם בספר
      // שאין לו תמיכה (מפרשים וכו'). ה-UI ממילא לא חושף את הכפתור שם,
      // אבל הbloc חייב להגן מקריאות תוכנתיות.
      expect(
        TextBookBloc.computeEffectiveContinuousReading(
          requestedEnabled: true,
          stateSupportsContinuous: false,
        ),
        isFalse,
      );
    });

    test('ביקוש לכבות → false ללא תלות בתמיכה', () {
      expect(
        TextBookBloc.computeEffectiveContinuousReading(
          requestedEnabled: false,
          stateSupportsContinuous: true,
        ),
        isFalse,
      );
      expect(
        TextBookBloc.computeEffectiveContinuousReading(
          requestedEnabled: false,
          stateSupportsContinuous: false,
        ),
        isFalse,
      );
    });
  });

  group('resolvePreservedContinuousReadingMode', () {
    final loadedTrue = _loaded(continuous: true, supports: true);
    final loadedFalse = _loaded(continuous: false, supports: true);

    test(
      'ספר לא תומך → false (גם אם preserve+state+globalDefault מבקשים true)',
      () {
        expect(
          TextBookBloc.resolvePreservedContinuousReadingMode(
            supportsContinuous: false,
            preserveFlag: true,
            currentState: loadedTrue,
            globalDefault: true,
          ),
          isFalse,
        );
      },
    );

    test('preserveFlag=false → globalDefault (מסלול פתיחת ספר / איפוס)', () {
      // בפתיחת ספר חדש ובאיפוס פר-ספר, הערך נגזר מברירת המחדל הגלובלית.
      expect(
        TextBookBloc.resolvePreservedContinuousReadingMode(
          supportsContinuous: true,
          preserveFlag: false,
          currentState: loadedTrue,
          globalDefault: false,
        ),
        isFalse,
      );
      expect(
        TextBookBloc.resolvePreservedContinuousReadingMode(
          supportsContinuous: true,
          preserveFlag: false,
          currentState: loadedFalse,
          globalDefault: true,
        ),
        isTrue,
      );
    });

    test('הגדרת הספר גוברת על ברירת המחדל, ושימור גובר על שתיהן', () {
      expect(
        TextBookBloc.resolvePreservedContinuousReadingMode(
          supportsContinuous: true,
          preserveFlag: false,
          currentState: null,
          globalDefault: false,
          perBookValue: true,
        ),
        isTrue,
      );
      expect(
        TextBookBloc.resolvePreservedContinuousReadingMode(
          supportsContinuous: true,
          preserveFlag: true,
          currentState: loadedFalse,
          perBookValue: true,
        ),
        isFalse,
      );
    });

    test('preserveFlag=true + state.continuous=true → מחזיר true', () {
      // מסלול ה-listener על שינוי גופן/ניקוד: אסור לכבות את המצב.
      expect(
        TextBookBloc.resolvePreservedContinuousReadingMode(
          supportsContinuous: true,
          preserveFlag: true,
          currentState: loadedTrue,
        ),
        isTrue,
      );
    });

    test('preserveFlag=true + state.continuous=false → false', () {
      expect(
        TextBookBloc.resolvePreservedContinuousReadingMode(
          supportsContinuous: true,
          preserveFlag: true,
          currentState: loadedFalse,
        ),
        isFalse,
      );
    });

    test('currentState אינו Loaded (Initial/Loading) → globalDefault', () {
      // טעינה ראשונית של ספר: אין מה לשמר, אז נגזר מברירת המחדל הגלובלית.
      final initial = TextBookInitial(TextBook(title: 'בראשית'), 0, false, []);
      expect(
        TextBookBloc.resolvePreservedContinuousReadingMode(
          supportsContinuous: true,
          preserveFlag: true,
          currentState: initial,
          globalDefault: true,
        ),
        isTrue,
      );

      expect(
        TextBookBloc.resolvePreservedContinuousReadingMode(
          supportsContinuous: true,
          preserveFlag: true,
          currentState: null,
          globalDefault: false,
        ),
        isFalse,
      );
    });
  });
}

TextBookLoaded _loaded({
  required bool continuous,
  required bool supports,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'בראשית'),
    showLeftPane: false,
    content: const ['בראשית', 'ברא', 'אלהים'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    supportsContinuousReadingMode: supports,
    continuousReadingMode: continuous,
    visibleIndices: const [0],
    searchText: '',
    searchMode: SearchMode.exact,
  );
}
