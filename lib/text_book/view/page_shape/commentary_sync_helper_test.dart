import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';

void main() {
  group('CommentarySyncHelper - calculateTargetIndex', () {
    final List<Link> mockLinks = [
      Link(index1: 10, index2: 20, connectionType: 'commentary', path2: 'dummy'),
      Link(index1: 20, index2: 50, connectionType: 'commentary', path2: 'dummy'),
      Link(index1: 30, index2: 80, connectionType: 'commentary', path2: 'dummy'),
    ];

    test('exact match returns correct target index', () {
      // logicalMainIndex ממפה בתוכנה ל- index1 - 1
      final result = CommentarySyncHelper.calculateTargetIndex(
        linksForCommentary: mockLinks,
        logicalMainIndex: 19, // ממפה ל- index1 = 20
      );
      // היעד המצופה הוא index2 - 1 = 49
      expect(result, 49);
    });

    test('between two links returns previous link target deterministically', () {
      final result = CommentarySyncHelper.calculateTargetIndex(
        linksForCommentary: mockLinks,
        logicalMainIndex: 14, // ממפה ל- index1 = 15, בין 10 ל-20
      );
      // מצופה להישאר צמוד ליעד של העוגן הקודם: index2 = 20 -> 19
      expect(result, 19);
    });

    test('before first link returns first link target', () {
      final result = CommentarySyncHelper.calculateTargetIndex(
        linksForCommentary: mockLinks,
        logicalMainIndex: 4, // ממפה ל- index1 = 5, לפני 10
      );
      expect(result, 19);
    });

    test('after last link returns last link target', () {
      final result = CommentarySyncHelper.calculateTargetIndex(
        linksForCommentary: mockLinks,
        logicalMainIndex: 35, // ממפה ל- index1 = 36, אחרי 30
      );
      expect(result, 79);
    });

    test('unsorted links are sorted internally and process correctly', () {
      final unsortedLinks = [
        Link(index1: 30, index2: 80, connectionType: 'commentary', path2: 'dummy'),
        Link(index1: 10, index2: 20, connectionType: 'commentary', path2: 'dummy'),
        Link(index1: 20, index2: 50, connectionType: 'commentary', path2: 'dummy'),
      ];

      final result = CommentarySyncHelper.calculateTargetIndex(
        linksForCommentary: unsortedLinks,
        logicalMainIndex: 14,
      );
      expect(result, 19);
    });
  });
}