import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_search_index_restorer.dart';

void main() {
  test('האינדקס השמור משוחזר בסיום הסריקה — ופעם אחת בלבד', () {
    final restorer = PdfSearchIndexRestorer(4);
    expect(
      restorer.onSearcherUpdate(session: 7, isSearching: true, matchCount: 2),
      isNull,
    );
    // הסריקה גולשת: התאמות מתחילת הספר עוד ייכנסו לפני האינדקס השמור.
    expect(
      restorer.onSearcherUpdate(session: 7, isSearching: true, matchCount: 6),
      isNull,
    );
    expect(
      restorer.onSearcherUpdate(session: 7, isSearching: false, matchCount: 9),
      4,
    );
    expect(
      restorer.onSearcherUpdate(session: 7, isSearching: false, matchCount: 9),
      isNull,
    );
  });

  test('חיפוש חדש לפני השחזור מבטל אותו — לא קופצים להתאמה של שאילתה ישנה', () {
    final restorer = PdfSearchIndexRestorer(4);
    restorer.onSearcherUpdate(session: 7, isSearching: true, matchCount: 1);
    expect(
      restorer.onSearcherUpdate(session: 8, isSearching: true, matchCount: 9),
      isNull,
    );
    expect(
      restorer.onSearcherUpdate(session: 8, isSearching: false, matchCount: 9),
      isNull,
    );
  });

  test('חיפוש שהסתיים עם פחות התאמות — מוותרים', () {
    final restorer = PdfSearchIndexRestorer(4);
    expect(
      restorer.onSearcherUpdate(session: 7, isSearching: false, matchCount: 3),
      isNull,
    );
    expect(
      restorer.onSearcherUpdate(session: 7, isSearching: false, matchCount: 9),
      isNull,
    );
  });

  test('searcher שנבנה מחדש (טעינה חוזרת) — ה-session החדש הוא הראשון', () {
    final restorer = PdfSearchIndexRestorer(1);
    restorer.onSearcherUpdate(session: 7, isSearching: true, matchCount: 0);
    restorer.resetSession();
    expect(
      restorer.onSearcherUpdate(session: 1, isSearching: false, matchCount: 3),
      1,
    );
  });

  test('המשתמש ניווט להתאמה לפני סוף הסריקה — לא חוזרים לשמורה', () {
    final restorer = PdfSearchIndexRestorer(4);
    expect(
      restorer.onSearcherUpdate(session: 7, isSearching: true, matchCount: 6),
      isNull,
    );
    expect(
      restorer.onSearcherUpdate(
        session: 7,
        isSearching: false,
        matchCount: 9,
        hasCurrentMatch: true,
      ),
      isNull,
    );
    expect(restorer.isPending, isFalse);
  });

  test('האינדקס השמור ממתין עד השחזור או הוויתור עליו', () {
    final restorer = PdfSearchIndexRestorer(4);
    expect(restorer.isPending, isTrue);
    restorer.onSearcherUpdate(session: 7, isSearching: true, matchCount: 6);
    expect(restorer.isPending, isTrue);
    restorer.onSearcherUpdate(session: 7, isSearching: false, matchCount: 9);
    expect(restorer.isPending, isFalse);
    expect(PdfSearchIndexRestorer(null).isPending, isFalse);
  });

  test('בלי אינדקס שמור — לא עושה דבר', () {
    expect(
      PdfSearchIndexRestorer(
        null,
      ).onSearcherUpdate(session: 1, isSearching: false, matchCount: 5),
      isNull,
    );
  });
}
