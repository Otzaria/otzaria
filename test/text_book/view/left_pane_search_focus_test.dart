import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';

/// טסט רגרסיה ל-resolveLeftPaneSearchFocus — ההגנה מפני באג "הגלילה
/// האינסופית" (commit 41a5816fc).
///
/// הבאג ההיסטורי: לוגיקת הפוקוס ביקשה requestFocus לשדה החיפוש בכל build.
/// בזמן גלילה ה-bloc פולט states חדשים שוב ושוב → הפוקוס נחטף מתוכן הספר
/// בכל פריים → נוצרה גלילה אינסופית עד סוף המסמך.
///
/// העיקרון המגן: מבקשים פוקוס אך ורק במעבר הפאנל מסגור לפתוח, ולעולם לא
/// כשהפאנל כבר פתוח (כלומר לא ב-rebuild רגיל בזמן גלילה).
void main() {
  group('resolveLeftPaneSearchFocus', () {
    test('פתיחת הפאנל (סגור→פתוח) מבקשת פוקוס פעם אחת', () {
      final result = resolveLeftPaneSearchFocus(
        showLeftPane: true,
        wasShown: false,
      );
      expect(result.shouldFocus, isTrue);
      expect(result.wasShownNext, isTrue);
    });

    test('פאנל סגור — לא מבקש פוקוס ומאפס את מצב "הוצג"', () {
      final result = resolveLeftPaneSearchFocus(
        showLeftPane: false,
        wasShown: true,
      );
      expect(result.shouldFocus, isFalse);
      expect(result.wasShownNext, isFalse);
    });

    test(
      'רגרסיה: rebuild-ים חוזרים בזמן גלילה (פאנל פתוח) לא מבקשים פוקוס שוב',
      () {
        // הסימולציה: הפאנל נפתח, ואז עשרות emits נוספים (כמו בזמן גלילה)
        // שכולם עם showLeftPane=true. רק הראשון רשאי לבקש פוקוס.
        var wasShown = false;
        var focusRequests = 0;

        // build ראשון — פתיחת הפאנל
        var result = resolveLeftPaneSearchFocus(
          showLeftPane: true,
          wasShown: wasShown,
        );
        if (result.shouldFocus) focusRequests++;
        wasShown = result.wasShownNext;

        // 50 rebuilds נוספים תוך כדי גלילה (הפאנל נשאר פתוח)
        for (var i = 0; i < 50; i++) {
          result = resolveLeftPaneSearchFocus(
            showLeftPane: true,
            wasShown: wasShown,
          );
          if (result.shouldFocus) focusRequests++;
          wasShown = result.wasShownNext;
        }

        // אסור שיהיה יותר מבקשת פוקוס אחת — אחרת חוזר באג הגלילה האינסופית.
        expect(
          focusRequests,
          1,
          reason: 'requestFocus חוזר בזמן גלילה הוא הבאג של commit 41a5816fc',
        );
      },
    );

    test('סגירה ופתיחה מחדש מבקשות פוקוס שוב (פוקוס בכל פתיחה)', () {
      // פתיחה ראשונה
      var result = resolveLeftPaneSearchFocus(
        showLeftPane: true,
        wasShown: false,
      );
      expect(result.shouldFocus, isTrue);
      var wasShown = result.wasShownNext;

      // גלילה (פתוח) — בלי פוקוס
      result = resolveLeftPaneSearchFocus(
        showLeftPane: true,
        wasShown: wasShown,
      );
      expect(result.shouldFocus, isFalse);
      wasShown = result.wasShownNext;

      // סגירה
      result = resolveLeftPaneSearchFocus(
        showLeftPane: false,
        wasShown: wasShown,
      );
      expect(result.shouldFocus, isFalse);
      wasShown = result.wasShownNext;
      expect(wasShown, isFalse);

      // פתיחה מחדש — שוב מבקש פוקוס
      result = resolveLeftPaneSearchFocus(
        showLeftPane: true,
        wasShown: wasShown,
      );
      expect(result.shouldFocus, isTrue);
    });
  });
}
