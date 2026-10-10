import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/book_common/utils/commentary_flat_items.dart';
import 'package:otzaria/services/commentary_service.dart';

LinkGroup _group(String title, int links) => LinkGroup(
  bookTitle: title,
  links: List.generate(
    links,
    (i) => Link(
      heRef: '$title $i',
      index1: 1,
      path2: '/books/$title.txt',
      index2: i + 1,
      connectionType: 'commentary',
    ),
  ),
);

void main() {
  group('groupTitleAtFlatIndex', () {
    // העוגן שהרשימה חוזרת אליו אחרי כיווץ (issue #1174) נגזר מהאינדקס
    // השטוח האחרון — שהוא לרוב קטע בתוך קבוצה ולא הכותרת עצמה.
    final headerIndexes = <String, int>{};
    setUp(() {
      headerIndexes.clear();
      buildCommentaryFlatItems(
        groups: [_group('מגיד משנה', 3), _group('מעשה רקח', 2)],
        isGroupExpanded: (_) => true,
        linkKey: (link) => '${link.path2}:${link.index2}',
        headerIndexOut: headerIndexes,
        linkIndexOut: {},
      );
    });

    test('מחזירה את הקבוצה שהפריט שייך לה', () {
      expect(headerIndexes, {'מגיד משנה': 0, 'מעשה רקח': 4});
      expect(groupTitleAtFlatIndex(headerIndexes, 0), 'מגיד משנה');
      expect(groupTitleAtFlatIndex(headerIndexes, 3), 'מגיד משנה');
      expect(groupTitleAtFlatIndex(headerIndexes, 4), 'מעשה רקח');
      expect(groupTitleAtFlatIndex(headerIndexes, 6), 'מעשה רקח');
    });

    test('מחזירה null כשאין כותרת מעל האינדקס', () {
      expect(groupTitleAtFlatIndex(const {}, 5), isNull);
      expect(groupTitleAtFlatIndex({'א': 2}, 1), isNull);
    });
  });

  test('כיווץ מקצר את הרשימה ומזיז את אינדקסי הכותרות', () {
    final expandedHeaders = <String, int>{};
    final expanded = buildCommentaryFlatItems(
      groups: [_group('מגיד משנה', 3), _group('מעשה רקח', 2)],
      isGroupExpanded: (_) => true,
      linkKey: (link) => '${link.path2}:${link.index2}',
      headerIndexOut: expandedHeaders,
      linkIndexOut: {},
    );
    final collapsedHeaders = <String, int>{};
    final collapsed = buildCommentaryFlatItems(
      groups: [_group('מגיד משנה', 3), _group('מעשה רקח', 2)],
      isGroupExpanded: (_) => false,
      linkKey: (link) => '${link.path2}:${link.index2}',
      headerIndexOut: collapsedHeaders,
      linkIndexOut: {},
    );

    expect(expanded.length, 7);
    expect(collapsed.length, 2);
    // האינדקס שנשמר לפני הכיווץ אינו תקף אחריו — ולכן העוגן הוא שם הקבוצה.
    expect(expandedHeaders['מעשה רקח'], 4);
    expect(collapsedHeaders['מעשה רקח'], 1);
  });
}
