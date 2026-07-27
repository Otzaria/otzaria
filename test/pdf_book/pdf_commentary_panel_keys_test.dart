import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';

Link _link({
  required int index1,
  required String path2,
  required int index2,
  String connectionType = 'COMMENTARY',
}) {
  return Link(
    heRef: 'הפניה',
    index1: index1,
    path2: path2,
    index2: index2,
    connectionType: connectionType,
  );
}

void main() {
  group('pdfCommentaryItemKey — יציבות מפתח פריט המפרש', () {
    test('מפתח נגזר מזהות הקישור בלבד', () {
      expect(
        pdfCommentaryItemKey(_link(index1: 7, path2: 'רש"י על שבת', index2: 3)),
        '7_רש"י על שבת_3',
      );
    });

    test('שני קישורים זהים מקבלים אותו מפתח', () {
      final a = _link(index1: 7, path2: 'רש"י על שבת', index2: 3);
      final b = _link(index1: 7, path2: 'רש"י על שבת', index2: 3);
      expect(pdfCommentaryItemKey(a), pdfCommentaryItemKey(b));
    });

    test('שינוי index1 משנה את המפתח', () {
      expect(
        pdfCommentaryItemKey(_link(index1: 7, path2: 'רש"י', index2: 3)),
        isNot(pdfCommentaryItemKey(_link(index1: 8, path2: 'רש"י', index2: 3))),
      );
    });

    test('שינוי ספר היעד משנה את המפתח', () {
      expect(
        pdfCommentaryItemKey(_link(index1: 7, path2: 'רש"י', index2: 3)),
        isNot(
          pdfCommentaryItemKey(_link(index1: 7, path2: 'תוספות', index2: 3)),
        ),
      );
    });

    test('שינוי index2 משנה את המפתח', () {
      expect(
        pdfCommentaryItemKey(_link(index1: 7, path2: 'רש"י', index2: 3)),
        isNot(pdfCommentaryItemKey(_link(index1: 7, path2: 'רש"י', index2: 4))),
      );
    });

    test('המפתח אינו מכיל את סוג הקישור — סוג אינו חלק מהזהות התצוגתית', () {
      expect(
        pdfCommentaryItemKey(
          _link(
            index1: 7,
            path2: 'רש"י',
            index2: 3,
            connectionType: 'TARGUM',
          ),
        ),
        pdfCommentaryItemKey(
          _link(
            index1: 7,
            path2: 'רש"י',
            index2: 3,
            connectionType: 'COMMENTARY',
          ),
        ),
      );
    });
  });

  group('pdfCommentaryListStorageKey — מפתח PageStorage של הרשימה', () {
    test('תלוי בבחירת המפרשים', () {
      expect(
        pdfCommentaryListStorageKey(const ['רש"י']),
        isNot(pdfCommentaryListStorageKey(const ['רש"י', 'תוספות'])),
      );
    });

    test('אינו תלוי בסדר הבחירה — Set אינו מבטיח סדר', () {
      expect(
        pdfCommentaryListStorageKey(const ['תוספות', 'רש"י']),
        pdfCommentaryListStorageKey(const ['רש"י', 'תוספות']),
      );
    });

    test('בחירה ריקה מחזירה מפתח יציב', () {
      expect(
        pdfCommentaryListStorageKey(const []),
        pdfCommentaryListStorageKey(const <String>{}),
      );
    });
  });

  group('pdfVisibleContentCacheKey — מפתח מטמון התוכן הנראה', () {
    String key({
      int startLine = 10,
      int endLine = 60,
      Set<int>? extra,
      List<String> commentators = const ['רש"י'],
      int linksIdentity = 111,
    }) {
      return pdfVisibleContentCacheKey(
        startLine: startLine,
        endLine: endLine,
        extraLineIndices: extra,
        activeCommentators: commentators,
        linksIdentity: linksIdentity,
      );
    }

    test('אותם קלטים מחזירים אותו מפתח', () {
      expect(key(), key());
    });

    test('שינוי טווח השורות מבטל את המטמון', () {
      expect(key(startLine: 10), isNot(key(startLine: 11)));
      expect(key(endLine: 60), isNot(key(endLine: 61)));
    });

    test('החלפת רשימת הקישורים מבטלת את המטמון גם באורך זהה', () {
      // זו הרגרסיה: מפתח שהתבסס על links.length לא התעדכן ברענון חלון
      // קישורים שהחזיר בדיוק אותו מספר קישורים לטווח אחר.
      expect(key(linksIdentity: 111), isNot(key(linksIdentity: 222)));
    });

    test('שינוי בחירת המפרשים מבטל את המטמון', () {
      expect(
        key(commentators: const ['רש"י']),
        isNot(key(commentators: const ['רש"י', 'תוספות'])),
      );
    });

    test('סדר המפרשים אינו משנה את המפתח', () {
      expect(
        key(commentators: const ['תוספות', 'רש"י']),
        key(commentators: const ['רש"י', 'תוספות']),
      );
    });

    test('ריבוי-בחירה נכלל במפתח', () {
      expect(key(extra: null), isNot(key(extra: const {20})));
      expect(key(extra: const {20}), isNot(key(extra: const {20, 25})));
    });

    test('סדר שורות ריבוי-הבחירה אינו משנה את המפתח', () {
      expect(key(extra: {25, 20}), key(extra: {20, 25}));
    });

    test('ריבוי-בחירה ריק שקול ל-null', () {
      expect(key(extra: const {}), key(extra: null));
    });
  });
}
