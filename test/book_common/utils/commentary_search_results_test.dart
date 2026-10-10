import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/commentary_search_results.dart';

void main() {
  const counts = {'a': 2, 'b': 0, 'c': 3};

  group('totalCommentarySearchResults', () {
    test('סוכם את כל הספירות', () {
      expect(totalCommentarySearchResults(counts), 5);
      expect(totalCommentarySearchResults(const {}), 0);
    });
  });

  group('commentarySearchOffsets', () {
    test('ההיסט של כל פריט הוא סכום הפריטים שלפניו', () {
      expect(commentarySearchOffsets(['a', 'b', 'c'], counts), {
        'a': 0,
        'b': 2,
        'c': 2,
      });
    });

    test('מפתח כפול שומר את ההיסט הראשון', () {
      expect(commentarySearchOffsets(['a', 'c', 'a'], counts), {
        'a': 0,
        'c': 2,
      });
    });

    test('פריט בלי ספירה נחשב כאפס', () {
      expect(commentarySearchOffsets(['x', 'a'], counts), {'x': 0, 'a': 0});
    });
  });

  group('commentarySearchRelativeIndex', () {
    final offsets = commentarySearchOffsets(['a', 'b', 'c'], counts);

    int relative(String key, int current) => commentarySearchRelativeIndex(
      key: key,
      currentIndex: current,
      offsets: offsets,
      countsByKey: counts,
    );

    test('התוצאה הנוכחית ממוקמת בתוך הפריט שלה', () {
      expect(relative('a', 0), 0);
      expect(relative('a', 1), 1);
      expect(relative('c', 2), 0);
      expect(relative('c', 4), 2);
    });

    test('תוצאה של פריט אחר מחזירה -1', () {
      expect(relative('a', 2), -1);
      expect(relative('c', 1), -1);
      expect(relative('c', 5), -1);
    });

    test('פריט בלי תוצאות או מחוץ לסדר מחזיר -1', () {
      expect(relative('b', 2), -1);
      expect(relative('x', 0), -1);
      expect(
        commentarySearchRelativeIndex(
          key: 'd',
          currentIndex: 0,
          offsets: offsets,
          countsByKey: const {'d': 1},
        ),
        -1,
      );
    });
  });

  group('orderCommentarySearchSnippets', () {
    test('הקטעים בסדר התצוגה עם האינדקס הגלובלי של הפריט', () {
      final snippets = orderCommentarySearchSnippets<String>(
        items: ['c', 'b', 'a'],
        keyOf: (item) => item,
        pathOf: (item) => 'path/$item',
        countsByKey: counts,
        snippetsOf: (key, count) => count > 0 ? ['s$key'] : const [],
      );
      expect(
        [
          for (final s in snippets) (s.path, s.snippet, s.globalIndex),
        ],
        [('path/c', 'sc', 0), ('path/a', 'sa', 3)],
      );
    });

    test('כמה קטעים לפריט חולקים את אותו אינדקס', () {
      final snippets = orderCommentarySearchSnippets<String>(
        items: ['a', 'c'],
        keyOf: (item) => item,
        pathOf: (item) => item,
        countsByKey: counts,
        snippetsOf: (key, _) => ['1$key', '2$key'],
      );
      expect([for (final s in snippets) s.globalIndex], [0, 0, 2, 2]);
    });
  });

  group('commentarySearchCountsByPath', () {
    test('מסכם לפי נתיב ומדלג על ריקים', () {
      expect(
        commentarySearchCountsByPath(
          {'a': 2, 'b': 0, 'c': 3, 'd': 4},
          {'a': 'x', 'b': 'y', 'c': 'x', 'd': ''},
        ),
        {'x': 5},
      );
    });
  });
}
