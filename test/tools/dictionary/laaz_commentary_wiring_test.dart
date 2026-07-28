import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// טסט מבני: מוודא שתת-בלוק הלעז מחווט בכל משטחי היעד — משטחי הפר-Link
/// (תוכן המפרש המשותף ופאנל הקישורים), וכן צורת-הדף (simple_text_viewer)
/// המרנדרת שורות-ספר שלמות דרך המסלול .forLine.
void main() {
  const subBlockRef = 'LaazCommentarySubBlock';
  const sharedContentPath = 'lib/widgets/commentary/commentary_content.dart';
  const sharedLinksPath = 'lib/widgets/commentary/links_list_view.dart';

  String? contents(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  bool referencesSubBlock(String path) =>
      contents(path)?.contains(subBlockRef) ?? false;

  group('חיווט תת-בלוק לעז', () {
    test('מחווט בתוכן המפרש המשותף וברשימת הקישורים המשותפת', () {
      expect(referencesSubBlock(sharedContentPath), isTrue);
      expect(referencesSubBlock(sharedLinksPath), isTrue);
    });

    test('מחווט בצורת-הדף (simple_text_viewer) דרך .forLine', () {
      final source = contents(
        'lib/text_book/view/page_shape/simple_text_viewer.dart',
      );
      expect(source, isNotNull);
      expect(source, contains('LaazCommentarySubBlock.forLine'));
    });

    test('הטקסט וה-PDF צורכים את אותו CommentaryContent המשותף', () {
      // בלעדי זה שני הצדדים חוזרים להתפצל, וה-PDF מאבד את הלעז (וגם את
      // הטעמים, הדגשת עוגן הציטוט וזהות ספר היעד) בשקט.
      const importRef = 'widgets/commentary/commentary_content.dart';
      expect(
        contents('lib/text_book/view/commentary_list_base.dart'),
        contains(importRef),
      );
      expect(
        contents('lib/pdf_book/view/pdf_commentary_panel.dart'),
        contains(importRef),
      );
    });

    test('לא נותר שיבוט PdfCommentaryContent', () {
      expect(
        File('lib/pdf_book/view/pdf_commentary_content.dart').existsSync(),
        isFalse,
      );
    });
  });
}
