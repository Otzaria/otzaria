import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';

/// `pdfScopedCommentaryLinks` הוא מקור האמת היחיד לקבוצת מפרשי הקטע — ממנו
/// נגזרים גם הרשימה וגם צ׳יפי הסוגים, בחלונית שבתוך הספר ובכרטיסיית המפרשים.
/// אם שני הצדדים יגזרו אחרת, צ׳יפ יוצג לסוג שאינו ברשימה (או להיפך).
Link _link({
  required int index1,
  required String path2,
  String connectionType = 'COMMENTARY',
}) => Link(
  heRef: 'הפניה',
  index1: index1,
  path2: path2,
  index2: 1,
  connectionType: connectionType,
);

List<Link> scoped({
  required List<Link> links,
  int startLine = 10,
  int endLine = 20,
  Set<int>? extra,
  Set<String> commentators = const {'רש"י'},
  bool showAllWhenEmpty = false,
}) => pdfScopedCommentaryLinks(
  links: links,
  startLine: startLine,
  endLine: endLine,
  extraLineIndices: extra,
  activeCommentators: commentators,
  showAllWhenEmpty: showAllWhenEmpty,
);

void main() {
  group('pdfScopedCommentaryLinks — סינון לפי טווח', () {
    test('קישור בטווח נכלל', () {
      final links = [_link(index1: 12, path2: 'רש"י')];
      expect(scoped(links: links), hasLength(1));
    });

    test('גבולות הטווח כלולים', () {
      expect(scoped(links: [_link(index1: 10, path2: 'רש"י')]), hasLength(1));
      expect(scoped(links: [_link(index1: 20, path2: 'רש"י')]), hasLength(1));
    });

    test('קישור מחוץ לטווח אינו נכלל', () {
      expect(scoped(links: [_link(index1: 9, path2: 'רש"י')]), isEmpty);
      expect(scoped(links: [_link(index1: 21, path2: 'רש"י')]), isEmpty);
    });

    test('ריבוי-בחירה מכליל שורה לא-רצופה מחוץ לטווח', () {
      expect(
        scoped(
          links: [_link(index1: 50, path2: 'רש"י')],
          extra: const {50},
        ),
        hasLength(1),
      );
    });
  });

  group('pdfScopedCommentaryLinks — סינון לפי סוג הקישור', () {
    test('קישור שאינו תלוי-טקסט אינו מפרש ואינו נכלל', () {
      expect(
        scoped(
          links: [
            _link(index1: 12, path2: 'רש"י', connectionType: LinkTypes.other),
          ],
        ),
        isEmpty,
      );
    });

    test('תרגום נכלל — הוא סוג תלוי-טקסט', () {
      expect(
        scoped(
          links: [
            _link(
              index1: 12,
              path2: 'אונקלוס',
              connectionType: LinkTypes.targum,
            ),
          ],
          commentators: const {'אונקלוס'},
        ),
        hasLength(1),
      );
    });
  });

  group('pdfScopedCommentaryLinks — סינון לפי בחירת המפרשים', () {
    test('מפרש שאינו נבחר אינו נכלל', () {
      expect(scoped(links: [_link(index1: 12, path2: 'תוספות')]), isEmpty);
    });

    test('showAllWhenEmpty מציג הכול גם ללא בחירה', () {
      expect(
        scoped(
          links: [_link(index1: 12, path2: 'תוספות')],
          commentators: const {},
          showAllWhenEmpty: true,
        ),
        hasLength(1),
      );
    });

    test('ללא showAllWhenEmpty בחירה ריקה מסתירה הכול', () {
      expect(
        scoped(
          links: [_link(index1: 12, path2: 'תוספות')],
          commentators: const {},
          showAllWhenEmpty: false,
        ),
        isEmpty,
      );
    });

    test('הסינון לפי שם הספר הנגזר מהנתיב, לא לפי הנתיב המלא', () {
      expect(
        scoped(
          links: [_link(index1: 12, path2: '/books/רש"י.txt')],
          commentators: const {'רש"י'},
        ),
        hasLength(1),
      );
    });
  });

  group('pdfScopedCommentaryLinks — שמירת סדר וזהות', () {
    test('הסדר נשמר כסדר הקלט', () {
      final a = _link(index1: 12, path2: 'רש"י');
      final b = _link(index1: 13, path2: 'רש"י');
      expect(scoped(links: [b, a]), [b, a]);
    });

    test('קלט ריק מחזיר רשימה ריקה', () {
      expect(scoped(links: const []), isEmpty);
    });
  });
}
