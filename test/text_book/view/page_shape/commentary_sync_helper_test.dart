import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';

Link _link({required int index1, required int index2}) => Link(
  heRef: 'ref',
  index1: index1,
  path2: 'commentary.txt',
  index2: index2,
  connectionType: 'commentary',
);

void main() {
  group('getCommentaryTargetIndex', () {
    test('מחזיר null כשאין קישורים', () {
      expect(
        CommentarySyncHelper.getCommentaryTargetIndex(
          linksForCommentary: const [],
          logicalMainIndex: 5,
        ),
        isNull,
      );
    });

    test('נצמד לקישור מדויק כשהשורה במקור היא בדיוק על קישור', () {
      final links = [
        _link(index1: 1, index2: 1),
        _link(index1: 10, index2: 50),
      ];
      // logicalMainIndex 0 => mainLineNumber 1 => בדיוק על הקישור הראשון
      expect(
        CommentarySyncHelper.getCommentaryTargetIndex(
          linksForCommentary: links,
          logicalMainIndex: 0,
        ),
        0, // index2(1) - 1
      );
    });

    test('נצמד לקישור הקודם הקרוב גם כשיש קישור הבא', () {
      final links = [
        _link(index1: 1, index2: 1), // יעד 0-based: 0
        _link(index1: 11, index2: 101), // יעד 0-based: 100
      ];
      // mainLineNumber 6 => בין הקישורים, אך נצמד לקודם (יעד 0)
      expect(
        CommentarySyncHelper.getCommentaryTargetIndex(
          linksForCommentary: links,
          logicalMainIndex: 5,
        ),
        0,
      );
    });

    test('נצמד לקישור הקודם גם קרוב מאוד לקישור הבא', () {
      final links = [
        _link(index1: 1, index2: 1),
        _link(index1: 5, index2: 41),
      ];
      // mainLineNumber 2 => הקישור הקודם הוא (1,1), היעד 0
      expect(
        CommentarySyncHelper.getCommentaryTargetIndex(
          linksForCommentary: links,
          logicalMainIndex: 1,
        ),
        0,
      );
    });

    test('נצמד לקישור הקודם כשאין קישור הבא', () {
      final links = [
        _link(index1: 1, index2: 1),
        _link(index1: 10, index2: 50),
      ];
      // mainLineNumber 15 => אחרי הקישור האחרון
      expect(
        CommentarySyncHelper.getCommentaryTargetIndex(
          linksForCommentary: links,
          logicalMainIndex: 14,
        ),
        49, // index2(50) - 1
      );
    });

    test('נצמד לקישור הראשון כשאין קישור קודם', () {
      final links = [
        _link(index1: 10, index2: 50),
        _link(index1: 20, index2: 100),
      ];
      // mainLineNumber 5 => לפני הקישור הראשון
      expect(
        CommentarySyncHelper.getCommentaryTargetIndex(
          linksForCommentary: links,
          logicalMainIndex: 4,
        ),
        49, // index2(50) - 1
      );
    });

    test('מתמודד עם קישורים לא ממוינים', () {
      final links = [
        _link(index1: 11, index2: 101),
        _link(index1: 1, index2: 1),
      ];
      // mainLineNumber 6 => הקישור הקודם הוא (1,1), היעד 0
      expect(
        CommentarySyncHelper.getCommentaryTargetIndex(
          linksForCommentary: links,
          logicalMainIndex: 5,
        ),
        0,
      );
    });
  });
}
