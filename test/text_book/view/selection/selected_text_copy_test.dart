import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';

void main() {
  group('resolveHtmlTextForSelection', () {
    test('מחזיר HTML מקורי כשהבחירה מכסה את כל השורה', () {
      final resolved = resolveHtmlTextForSelection(
        plainText: 'שלום עולם',
        selectedIndex: 0,
        sourceContent: const ['<b>שלום</b> עולם'],
      );

      expect(resolved, '<b>שלום</b> עולם');
    });

    test('מחזיר טקסט פשוט כשהבחירה היא רק חלק מהשורה', () {
      final resolved = resolveHtmlTextForSelection(
        plainText: 'שלום',
        selectedIndex: 0,
        sourceContent: const ['<b>שלום</b> עולם'],
      );

      expect(resolved, 'שלום');
    });

    test('מחזיר fallback לטקסט פשוט כשאין אינדקס תקין', () {
      final resolved = resolveHtmlTextForSelection(
        plainText: 'שלום',
        selectedIndex: null,
        sourceContent: const ['<b>שלום</b> עולם'],
      );

      expect(resolved, 'שלום');
    });
  });
}
