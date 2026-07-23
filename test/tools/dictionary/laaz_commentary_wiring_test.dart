import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// טסט מבני: מוודא שתת-בלוק הלעז מחווט בארבעת משטחי היעד — שלושת משטחי הפר-Link,
/// וכן צורת-הדף (simple_text_viewer) המרנדרת שורות-ספר שלמות דרך המסלול .forLine.
void main() {
  const subBlockRef = 'LaazCommentarySubBlock';

  String? contents(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  bool referencesSubBlock(String path) =>
      contents(path)?.contains(subBlockRef) ?? false;

  group('חיווט תת-בלוק לעז', () {
    test('מחווט בשלושת משטחי המפרש הפר-Link', () {
      expect(
        referencesSubBlock(
          'lib/text_book/view/combined_view/commentary_content.dart',
        ),
        isTrue,
      );
      expect(
        referencesSubBlock('lib/pdf_book/view/pdf_commentary_content.dart'),
        isTrue,
      );
      expect(
        referencesSubBlock('lib/text_book/view/selected_line_links_view.dart'),
        isTrue,
      );
    });

    test('מחווט בצורת-הדף (simple_text_viewer) דרך .forLine', () {
      final source = contents(
        'lib/text_book/view/page_shape/simple_text_viewer.dart',
      );
      expect(source, isNotNull);
      expect(source, contains('LaazCommentarySubBlock.forLine'));
    });
  });
}
