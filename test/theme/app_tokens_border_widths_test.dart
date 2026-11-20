import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_tokens.dart';

void main() {
  test('עוביי המסגרת הרשמיים כוללים את 3 ואת 0.5', () {
    expect(AppTokens.borderThick, 3);
    expect(AppTokens.borderHairline, 0.5);
    // הסולם עולה: דקיק < דק < בחירה מרובה < טבעת פוקוס < עבה.
    expect(
      [
        AppTokens.borderHairline,
        AppTokens.borderThin,
        AppTokens.multiSelectedBorderWidth,
        AppTokens.focusRingWidth,
        AppTokens.borderThick,
      ],
      orderedEquals([0.5, 1, 1.5, 2, 3]),
    );
  });

  test('אין ליטרל 3 או 0.5 בעובי מסגרת בקבצים שהועברו לטוקנים', () {
    const files = [
      'lib/personal_notes/view/personal_notes_screen.dart',
      'lib/plugins/view/plugin_correction_paragraph.dart',
      'lib/text_book/view/page_shape/simple_text_viewer.dart',
      'lib/tools/calendar/helpers/calendar_print_helpers.dart',
    ];
    final literal = RegExp(r'\bwidth:\s*(3|0\.5)\b');
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(literal.hasMatch(source), isFalse, reason: path);
    }
  });
}
