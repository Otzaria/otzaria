import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/view/library_empty_state_widget.dart';

Widget _buildWidget({
  String message = 'אין פריטים להצגה בתיקייה זו',
  VoidCallback? onBack,
  VoidCallback? onHome,
  VoidCallback? onOpenSearch,
  VoidCallback? onSearchWholeLibrary,
  bool showSearchElsewhereHint = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LibraryEmptyStateWidget(
        message: message,
        onBack: onBack ?? () {},
        onHome: onHome ?? () {},
        onOpenSearch: onOpenSearch ?? () {},
        onSearchWholeLibrary: onSearchWholeLibrary,
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

    // לחצן "חפש בתיקייה הראשית" (issue #1118) — מוצג רק עם הרמז ועם callback
    testWidgets('לא מציג לחצן "חפש בתיקייה הראשית" כברירת מחדל', (
      tester,
    ) async {
      await tester.pumpWidget(_buildWidget(onSearchWholeLibrary: () {}));
      expect(find.text('חפש בתיקייה הראשית'), findsNothing);
    });

    testWidgets('לא מציג את הלחצן כשהרמז מוצג אך אין callback', (tester) async {
      await tester.pumpWidget(_buildWidget(showSearchElsewhereHint: true));
      expect(find.text('חפש בתיקייה הראשית'), findsNothing);
    });

    testWidgets('מציג את הלחצן כשהרמז מוצג ויש callback', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          showSearchElsewhereHint: true,
          onSearchWholeLibrary: () {},
        ),
      );
      expect(find.text('חפש בתיקייה הראשית'), findsOneWidget);
      expect(find.byIcon(FluentIcons.library_24_regular), findsOneWidget);
    });

    testWidgets('לחיצה על "חפש בתיקייה הראשית" קוראת ל-onSearchWholeLibrary', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        _buildWidget(
          showSearchElsewhereHint: true,
          onSearchWholeLibrary: () => called = true,
        ),
      );
      await tester.tap(find.text('חפש בתיקייה הראשית'));
      expect(called, isTrue);
    });

    testWidgets('הלחצן ממוקם מעל לחצן "פתח חיפוש טקסט"', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          showSearchElsewhereHint: true,
          onSearchWholeLibrary: () {},
        ),
      );

      final homeY = tester.getTopLeft(find.text('בית')).dy;
      final wholeLibraryY = tester
          .getTopLeft(find.text('חפש בתיקייה הראשית'))
          .dy;
      final searchBtnY = tester.getTopLeft(find.text('פתח חיפוש טקסט')).dy;

      expect(homeY, lessThan(wholeLibraryY));
      expect(wholeLibraryY, lessThan(searchBtnY));
    });
  });
}
