import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/user_content_import/services/user_links_loader.dart';

void main() {
  group('dedupeUserLinks', () {
    Link link(int i1, String p2, int i2, {String type = 'COMMENTARY'}) => Link(
      heRef: 'ref',
      index1: i1,
      path2: p2,
      index2: i2,
      connectionType: type,
    );

    test('קישור דו-כיווני (forward+inverse זהים) נשמר פעם אחת', () {
      final forward = Link(
        heRef: 'הכי גרסינן מגילה ב., א',
        index1: 3,
        path2: 'הכי גרסינן מגילה',
        index2: 5,
        connectionType: 'COMMENTARY',
        targetIsUserBook: true,
        targetCategoryId: 7,
      );
      final inverse = Link(
        heRef: 'הכי גרסינן מגילה',
        index1: 3,
        path2: 'הכי גרסינן מגילה',
        index2: 5,
        connectionType: 'COMMENTARY',
        targetIsUserBook: true,
        targetCategoryId: 7,
      );
      final result = dedupeUserLinks([forward, inverse]);
      expect(result, hasLength(1));
      // ה-forward ראשון — ה-heRef העשיר שלו נשמר
      expect(result.single.heRef, 'הכי גרסינן מגילה ב., א');
    });

    test('אותה כותרת אך ספר אישי/רשמי או קטגוריה שונה — לא ממוזגים', () {
      Link toBook(int i1, {required bool isUser, int? categoryId}) => Link(
        heRef: 'ref',
        index1: i1,
        path2: 'משותף',
        index2: 5,
        connectionType: 'COMMENTARY',
        targetIsUserBook: isUser,
        targetCategoryId: categoryId,
      );
      final result = dedupeUserLinks([
        toBook(3, isUser: true, categoryId: 7),
        toBook(3, isUser: false, categoryId: 7),
        toBook(3, isUser: true, categoryId: 8),
      ]);
      expect(result, hasLength(3));
    });

    test('קישורים שונים (שורה/ספר/סוג) אינם ממוזגים', () {
      final result = dedupeUserLinks([
        link(3, 'פירוש', 5),
        link(4, 'פירוש', 5),
        link(3, 'פירוש אחר', 5),
        link(3, 'פירוש', 6),
        link(3, 'פירוש', 5, type: 'REFERENCE'),
      ]);
      expect(result, hasLength(5));
    });
  });
}
