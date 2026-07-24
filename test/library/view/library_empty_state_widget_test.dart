import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/view/library_empty_state_widget.dart';

Widget _buildWidget({
  String message = 'אין פריטים להצגה בתיקייה זו',
  VoidCallback? onBack,
  VoidCallback? onHome,
  VoidCallback? onOpenSearch,
  bool showSearchElsewhereHint = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LibraryEmptyStateWidget(
        message: message,
        onBack: onBack ?? () {},
        onHome: onHome ?? () {},
        onOpenSearch: onOpenSearch ?? () {},
        showSearchElsewhereHint: showSearchElsewhereHint,
      ),
    ),
  );
}

void main() {
  group('LibraryEmptyStateWidget — בדיקות יחידה', () {
    // Example 1: מציג את הודעת הטקסט שהועברה
    testWidgets('מציג את הודעת הטקסט הראשית', (tester) async {
      const msg = 'אין תוצאות עבור "תורה"';
      await tester.pumpWidget(_buildWidget(message: msg));
      expect(find.text(msg), findsOneWidget);
    });

    // Example 2: מציג את כל הרכיבים הנדרשים
    testWidgets('מציג לחצן חזור, לחצן בית, הודעת עזר ולחצן פתח חיפוש טקסט', (
      tester,
    ) async {
      await tester.pumpWidget(_buildWidget());

      expect(find.text('חזור'), findsOneWidget);
      expect(find.text('בית'), findsOneWidget);
      expect(find.text('ניתן לחפש גם טקסט ספציפי במאגר'), findsOneWidget);
      expect(find.text('פתח חיפוש טקסט'), findsOneWidget);
    });

    // Example 3: לחיצה על "חזור" קוראת ל-onBack
    testWidgets('לחיצה על חזור קוראת ל-onBack', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildWidget(onBack: () => called = true));
      await tester.tap(find.text('חזור'));
      expect(called, isTrue);
    });

    // Example 4: לחיצה על "בית" קוראת ל-onHome
    testWidgets('לחיצה על בית קוראת ל-onHome', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildWidget(onHome: () => called = true));
      await tester.tap(find.text('בית'));
      expect(called, isTrue);
    });

    // Example 5: לחיצה על "פתח חיפוש טקסט" קוראת ל-onOpenSearch
    testWidgets('לחיצה על פתח חיפוש טקסט קוראת ל-onOpenSearch', (tester) async {
      var called = false;
      await tester.pumpWidget(_buildWidget(onOpenSearch: () => called = true));
      await tester.tap(find.text('פתח חיפוש טקסט'));
      expect(called, isTrue);
    });

    // Example 6: סדר הרכיבים — הודעה ראשית → לחצנים → הודעת עזר → לחצן חיפוש
    testWidgets('הרכיבים מוצגים בסדר הנכון', (tester) async {
      const msg = 'אין פריטים להצגה בתיקייה זו';
      await tester.pumpWidget(_buildWidget(message: msg));

      final msgY = tester.getTopLeft(find.text(msg)).dy;
      final backY = tester.getTopLeft(find.text('חזור')).dy;
      final helpTextY = tester
          .getTopLeft(find.text('ניתן לחפש גם טקסט ספציפי במאגר'))
          .dy;
      final searchBtnY = tester.getTopLeft(find.text('פתח חיפוש טקסט')).dy;

      expect(msgY, lessThan(backY));
      expect(backY, lessThan(helpTextY));
      expect(helpTextY, lessThan(searchBtnY));
    });

    // רמז "לחפש בתיקייה אחרת" — מוצג רק כש-showSearchElsewhereHint=true
    testWidgets('לא מציג רמז "לחפש בתיקייה אחרת" כברירת מחדל', (tester) async {
      await tester.pumpWidget(_buildWidget());
      expect(find.text('ניתן לנסות לחפש בתיקייה אחרת'), findsNothing);
    });

    testWidgets(
      'מציג רמז "לחפש בתיקייה אחרת" כש-showSearchElsewhereHint=true',
      (tester) async {
        await tester.pumpWidget(_buildWidget(showSearchElsewhereHint: true));
        expect(find.text('ניתן לנסות לחפש בתיקייה אחרת'), findsOneWidget);
      },
    );

    // אייקונים
    testWidgets('מציג אייקונים מתאימים', (tester) async {
      await tester.pumpWidget(_buildWidget());
      expect(find.byIcon(FluentIcons.arrow_up_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.home_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.search_24_regular), findsOneWidget);
    });
  });

  // **Validates: Requirements 1.3, 2.1, 3.1, 4.1, 5.1**
  group('LibraryEmptyStateWidget — בדיקות property', () {
    // תכונה 1: הצגת פעולות עזר בשני מצבי תצוגה
    // עבור כל הודעת טקסט, ארבעת הרכיבים תמיד מוצגים
    testWidgets(
      'תכונה 1: ארבעת הרכיבים מוצגים ללא תלות בתוכן ההודעה (100 איטרציות)',
      (tester) async {
        final messages = List.generate(
          100,
          (i) => switch (i % 5) {
            0 => 'אין פריטים להצגה בתיקייה זו',
            1 => 'אין תוצאות עבור "חיפוש $i"',
            2 => 'הודעה $i ' * (i % 10 + 1), // הודעות באורכים שונים
            3 => '', // הודעה ריקה
            _ => 'א' * i, // הודעות ארוכות
          },
        );

        for (final msg in messages) {
          await tester.pumpWidget(_buildWidget(message: msg));
          await tester.pump();

          expect(
            find.text('חזור'),
            findsOneWidget,
            reason: 'לחצן חזור חסר עבור הודעה: "$msg"',
          );
          expect(
            find.text('בית'),
            findsOneWidget,
            reason: 'לחצן בית חסר עבור הודעה: "$msg"',
          );
          expect(
            find.text('ניתן לחפש גם טקסט ספציפי במאגר'),
            findsOneWidget,
            reason: 'הודעת עזר חסרה עבור הודעה: "$msg"',
          );
          expect(
            find.text('פתח חיפוש טקסט'),
            findsOneWidget,
            reason: 'לחצן פתח חיפוש טקסט חסר עבור הודעה: "$msg"',
          );
        }
      },
    );
  });
}
