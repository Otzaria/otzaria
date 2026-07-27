import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tools_screen.dart';

/// בדיקות רגרסיה לבאג "לא ניתן להקליד בתוך תוסף" (אחרי 0.9.95).
///
/// הרקע: מאז שאוצריא מושכת את `flutter_inappwebview_windows` מה-fork, ה-WebView
/// מגשר את הפוקוס של פלאטר לפוקוס הנייטיבי — `onFocusChange(false)` מריץ
/// `document.activeElement.blur()` בתוך הדף. בגרסה שב-pub.dev הגשר היה ריק
/// ולכן אובדן פוקוס בצד פלאטר לא הזיק.
///
/// מכאן שכל קריאת `requestFocus` על צומת **אב** של ה-WebView מוחקת את סמן
/// הכתיבה מהשדה שהמשתמש מקליד בו.
void main() {
  group('shouldRestoreToolsContentFocus', () {
    test('הפוקוס כבר בתוך התוכן — אין שחזור (הבאג המקורי)', () {
      // hasFocus כולל צאצאים, ולכן true גם כשהפוקוס בשדה קלט שב-WebView.
      // שחזור כאן היה גוזל את הפוקוס לצומת האב → blur() → הסמן נעלם.
      expect(
        shouldRestoreToolsContentFocus(
          contentIsAttached: true,
          contentHasFocus: true,
        ),
        isFalse,
      );
    });

    test('התוכן מחובר ואינו ממוקד — משחזרים', () {
      expect(
        shouldRestoreToolsContentFocus(
          contentIsAttached: true,
          contentHasFocus: false,
        ),
        isTrue,
      );
    });

    test('התוכן אינו מחובר לעץ (תפריט מובייל) — אין שחזור', () {
      expect(
        shouldRestoreToolsContentFocus(
          contentIsAttached: false,
          contentHasFocus: false,
        ),
        isFalse,
      );
    });
  });

  group('גשר הפוקוס של ה-WebView — התנהגות עץ הפוקוס', () {
    testWidgets(
      'requestFocus על צומת האב גוזל פוקוס מה-WebView ומפעיל blur',
      (tester) async {
        // מדמה את מבנה tools_screen: Focus(_contentFocusNode) עוטף את
        // IndexedStack שבתוכו ה-WebView של התוסף.
        final content = FocusNode(debugLabel: 'content', skipTraversal: true);
        final webView = FocusNode(debugLabel: 'webview');
        addTearDown(content.dispose);
        addTearDown(webView.dispose);

        // רושם את הקריאות הנייטיביות שהגשר בחבילה היה מבצע.
        final nativeCalls = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Focus(
              focusNode: content,
              child: Focus(
                focusNode: webView,
                autofocus: true,
                onFocusChange: (focused) =>
                    nativeCalls.add(focused ? 'MoveFocus' : 'blur'),
                child: const SizedBox(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(webView.hasFocus, isTrue, reason: 'autofocus מיקד את ה-WebView');
        expect(nativeCalls, ['MoveFocus']);

        // המצב שבו נמצא המשתמש בזמן הקלדה: הפוקוס בתוך ה-WebView, ולכן
        // hasFocus של האב הוא true.
        expect(content.hasFocus, isTrue);

        // כך היה נראה ה-restorer לפני התיקון — בלי בדיקת hasFocus.
        content.requestFocus();
        await tester.pump();

        expect(
          nativeCalls,
          ['MoveFocus', 'blur'],
          reason: 'שחזור לא-מותנה מוחק את סמן הכתיבה מהשדה שבתוך הדף',
        );
        expect(webView.hasFocus, isFalse);
      },
    );

    testWidgets('עם התיקון — שחזור בזמן הקלדה אינו נוגע ב-WebView', (
      tester,
    ) async {
      final content = FocusNode(debugLabel: 'content', skipTraversal: true);
      final webView = FocusNode(debugLabel: 'webview');
      addTearDown(content.dispose);
      addTearDown(webView.dispose);

      final nativeCalls = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            focusNode: content,
            child: Focus(
              focusNode: webView,
              autofocus: true,
              onFocusChange: (focused) =>
                  nativeCalls.add(focused ? 'MoveFocus' : 'blur'),
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();
      nativeCalls.clear();

      // אותו שחזור, הפעם דרך ה-predicate האמיתי של מסך הכלים.
      if (shouldRestoreToolsContentFocus(
        contentIsAttached: content.enclosingScope != null,
        contentHasFocus: content.hasFocus,
      )) {
        content.requestFocus();
      }
      await tester.pump();

      expect(nativeCalls, isEmpty, reason: 'אין blur — הסמן נשמר');
      expect(webView.hasFocus, isTrue);
    });

    testWidgets('התוכן אינו ממוקד — השחזור עדיין מחזיר פוקוס למסך', (
      tester,
    ) async {
      final content = FocusNode(debugLabel: 'content', skipTraversal: true);
      final elsewhere = FocusNode(debugLabel: 'elsewhere');
      addTearDown(content.dispose);
      addTearDown(elsewhere.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Focus(focusNode: elsewhere, child: const SizedBox(height: 10)),
              Focus(focusNode: content, child: const SizedBox(height: 10)),
            ],
          ),
        ),
      );

      elsewhere.requestFocus();
      await tester.pump();
      expect(content.hasFocus, isFalse);

      if (shouldRestoreToolsContentFocus(
        contentIsAttached: content.enclosingScope != null,
        contentHasFocus: content.hasFocus,
      )) {
        content.requestFocus();
      }
      await tester.pump();

      expect(
        content.hasFocus,
        isTrue,
        reason: 'התיקון לא שובר את השחזור עצמו — רק מדלג כשהוא מיותר',
      );
    });
  });

  group('WebView נסתר של תוסף רקע', () {
    testWidgets('בלי ExcludeFocus — autofocus חוטף פוקוס כשאין ממוקד', (
      tester,
    ) async {
      // תוספי רקע נטענים אסינכרונית אחרי עליית האפליקציה. אם באותו רגע אין
      // פוקוס בעץ, ה-Focus(autofocus: true) שבתוך ה-WebView תופס אותו — והפוקוס
      // הנייטיבי עובר לחלון בלתי-נראה.
      final hidden = FocusNode(debugLabel: 'hidden-background-webview');
      addTearDown(hidden.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Offstage(
            offstage: true,
            child: Focus(
              focusNode: hidden,
              autofocus: true,
              child: const SizedBox(width: 1, height: 1),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        hidden.hasFocus,
        isTrue,
        reason: 'Offstage לבדו אינו מונע פוקוס',
      );
    });

    testWidgets('עם ExcludeFocus — ה-WebView הנסתר אינו יכול לקבל פוקוס', (
      tester,
    ) async {
      final hidden = FocusNode(debugLabel: 'hidden-background-webview');
      addTearDown(hidden.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ExcludeFocus(
            child: Offstage(
              offstage: true,
              child: Focus(
                focusNode: hidden,
                autofocus: true,
                child: const SizedBox(width: 1, height: 1),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(hidden.hasFocus, isFalse);
    });
  });
}
