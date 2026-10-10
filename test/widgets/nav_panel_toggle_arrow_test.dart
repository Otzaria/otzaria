// issue #1417: כפתור "הצג ניווט"/"הסתר ניווט" הציג את אותו חץ בשני המצבים —
// גליף ה-text_continuous מצויר עם חץ קבוע, ולכן כשהחלונית פתוחה החץ המשיך
// להצביע לכיוון הפתיחה. החץ צריך להצביע לכיוון שאליו החלונית תזוז בלחיצה:
// ב-RTL (החלונית מימין) סגורה → שמאלה (text_continuous_rtl), פתוחה → ימינה
// (text_continuous_ltr); ב-LTR להפך.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// האם כפתור המעבר מציג את גליף ה-ltr (חץ ימינה) ולא את ה-rtl (חץ שמאלה).
bool _iconMirrored(WidgetTester tester) {
  final icon = tester.widget<Icon>(
    find.descendant(
      of: find.byType(NavPanelToggleButton),
      matching: find.byType(Icon),
    ),
  );
  final data = icon.icon;
  if (data == OtzariaIcons.text_continuous_ltr_24_regular ||
      data == OtzariaIcons.text_continuous_ltr_24_filled) {
    return true;
  }
  expect(
    data == OtzariaIcons.text_continuous_rtl_24_regular ||
        data == OtzariaIcons.text_continuous_rtl_24_filled,
    isTrue,
    reason: 'הכפתור חייב להציג אחד מגלִיפֵי text_continuous',
  );
  return false;
}

Widget _host(bool isOpen, TextDirection direction) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Center(
        child: NavPanelToggleButton(isOpen: isOpen, onToggle: () {}),
      ),
    ),
  ),
);

void main() {
  group('חץ כפתור הניווט מצביע לכיוון תנועת החלונית (issue #1417)', () {
    testWidgets('RTL: החץ מתהפך בין חלונית סגורה לפתוחה', (tester) async {
      await tester.pumpWidget(_host(false, TextDirection.rtl));
      expect(find.byTooltip('הצג ניווט'), findsOneWidget);
      final closedMirrored = _iconMirrored(tester);

      await tester.pumpWidget(_host(true, TextDirection.rtl));
      await tester.pumpAndSettle();
      expect(find.byTooltip('הסתר ניווט'), findsOneWidget);
      final openMirrored = _iconMirrored(tester);

      expect(
        openMirrored,
        isNot(closedMirrored),
        reason: 'במצב פתוח החץ חייב להצביע לכיוון ההפוך מהמצב הסגור',
      );
      // הגליף מצויר עם חץ שמאלה; חלונית מימין נפתחת שמאלה — לא משוקף כשסגור.
      expect(closedMirrored, isFalse);
      expect(openMirrored, isTrue);
    });

    testWidgets('LTR: החלונית בצד שמאל, ולכן שני המצבים מתהפכים', (
      tester,
    ) async {
      await tester.pumpWidget(_host(false, TextDirection.ltr));
      expect(_iconMirrored(tester), isTrue, reason: 'סגורה: נפתחת ימינה');

      await tester.pumpWidget(_host(true, TextDirection.ltr));
      await tester.pumpAndSettle();
      expect(_iconMirrored(tester), isFalse, reason: 'פתוחה: נסגרת שמאלה');
    });

    test('useLtrGlyph — טבלת האמת של ארבעת המצבים', () {
      expect(
        NavPanelToggleButton.useLtrGlyph(
          isOpen: false,
          textDirection: TextDirection.rtl,
        ),
        isFalse,
      );
      expect(
        NavPanelToggleButton.useLtrGlyph(
          isOpen: true,
          textDirection: TextDirection.rtl,
        ),
        isTrue,
      );
      expect(
        NavPanelToggleButton.useLtrGlyph(
          isOpen: false,
          textDirection: TextDirection.ltr,
        ),
        isTrue,
      );
      expect(
        NavPanelToggleButton.useLtrGlyph(
          isOpen: true,
          textDirection: TextDirection.ltr,
        ),
        isFalse,
      );
    });
  });
}
