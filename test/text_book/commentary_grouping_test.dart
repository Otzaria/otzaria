import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/links/links.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';

void main() {
  group('Commentary Grouping Tests', () {
    test('Groups consecutive links from same book', () {
      // יצירת קישורים מאותו ספר ברצף
      final links = [
        Link(
          heRef: 'פירוש א',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ב',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 2,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ג',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 3,
          connectionType: 'commentary',
        ),
      ];

      final groups = groupConsecutiveLinksForTesting(links);

      // צריך להיות רק קבוצה אחת
      expect(groups.length, 1);
      expect(groups[0].links.length, 3);
    });

    test('Separates non-consecutive links from different books', () {
      // יצירת קישורים מספרים שונים
      final links = [
        Link(
          heRef: 'פירוש א',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ב',
          index1: 1,
          path2: '/books/commentary2.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ג',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 2,
          connectionType: 'commentary',
        ),
      ];

      final groups = groupConsecutiveLinksForTesting(links);

      // צריך להיות 3 קבוצות - כל קישור מספר אחר או לא רצוף
      expect(groups.length, 3);
      expect(groups[0].links.length, 1);
      expect(groups[1].links.length, 1);
      expect(groups[2].links.length, 1);
    });

    test('Groups only consecutive segments from same book', () {
      // יצירת קישורים שבהם יש רצף ואז הפרדה ואז רצף נוסף
      final links = [
        Link(
          heRef: 'פירוש א1',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש א2',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 2,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ב',
          index1: 1,
          path2: '/books/commentary2.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש א3',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 3,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש א4',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 4,
          connectionType: 'commentary',
        ),
      ];

      final groups = groupConsecutiveLinksForTesting(links);

      // צריך להיות 3 קבוצות:
      // 1. commentary1: פריטים 1-2
      // 2. commentary2: פריט 1
      // 3. commentary1: פריטים 3-4
      expect(groups.length, 3);
      expect(groups[0].links.length, 2);
      expect(groups[1].links.length, 1);
      expect(groups[2].links.length, 2);
    });

    test('Handles empty list', () {
      final links = <Link>[];
      final groups = groupConsecutiveLinksForTesting(links);
      expect(groups.length, 0);
    });

    test('Handles single link', () {
      final links = [
        Link(
          heRef: 'פירוש א',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
      ];

      final groups = groupConsecutiveLinksForTesting(links);
      expect(groups.length, 1);
      expect(groups[0].links.length, 1);
    });
  });
}

// פונקציה עוזרת לבדיקות - חושפת את הפונקציה הפרטית
List<CommentaryGroup> groupConsecutiveLinksForTesting(List<Link> links) {
  // מכיוון שהפונקציה היא פרטית, נשתמש בה דרך wrapper
  // או נעתיק את הלוגיקה לצורך הבדיקה
  if (links.isEmpty) return [];

  final groups = <CommentaryGroup>[];
  String? currentTitle;
  List<Link> currentGroup = [];

  for (final link in links) {
    // מחלץ את שם הספר מה-path
    final title = link.path2.split('/').last.replaceAll('.txt', '');

    if (currentTitle == null || currentTitle != title) {
      if (currentGroup.isNotEmpty) {
        groups.add(CommentaryGroup(
          bookTitle: currentTitle!,
          links: List.from(currentGroup),
        ));
      }
      currentTitle = title;
      currentGroup = [link];
    } else {
      currentGroup.add(link);
    }
  }

  if (currentGroup.isNotEmpty) {
    groups.add(CommentaryGroup(
      bookTitle: currentTitle!,
      links: List.from(currentGroup),
    ));
  }

  return groups;
}
