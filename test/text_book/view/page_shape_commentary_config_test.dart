import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_config.dart';

void main() {
  group('PageShapeSlotConfiguration', () {
    test('creates single slot from legacy value', () {
      final slot = PageShapeSlotConfiguration.fromLegacyValue('רש"י');

      expect(slot.mode, PageShapeCommentaryMode.single);
      expect(slot.commentators, ['רש"י']);
      expect(slot.primaryCommentator, 'רש"י');
    });

    test(
        'promotes json config to multiple when more than one commentator exists',
        () {
      final slot = PageShapeSlotConfiguration.fromJson({
        'mode': 'single',
        'commentators': ['רש"י', 'תוספות'],
      });

      expect(slot.mode, PageShapeCommentaryMode.multiple);
      expect(slot.commentators, ['רש"י', 'תוספות']);
    });
  });

  group('PageShapeConfiguration', () {
    test('converts legacy map to configuration', () {
      final configuration = PageShapeConfiguration.fromLegacyMap({
        'left': 'רש"י',
        'right': 'תוספות',
        'bottom': null,
        'bottomRight': 'רמב"ן',
      });

      expect(configuration.left.primaryCommentator, 'רש"י');
      expect(configuration.right.primaryCommentator, 'תוספות');
      expect(configuration.bottom.isEmpty, isTrue);
      expect(configuration.bottomRight.primaryCommentator, 'רמב"ן');
    });

    test('serializes and deserializes full configuration', () {
      const configuration = PageShapeConfiguration(
        left: PageShapeSlotConfiguration(
          mode: PageShapeCommentaryMode.multiple,
          commentators: ['רש"י', 'תוספות'],
        ),
        right: PageShapeSlotConfiguration(
          mode: PageShapeCommentaryMode.single,
          commentators: ['רא"ש'],
        ),
        bottom: PageShapeSlotConfiguration.empty(),
        bottomRight: PageShapeSlotConfiguration(
          mode: PageShapeCommentaryMode.single,
          commentators: ['רמב"ן'],
        ),
      );

      final restored = PageShapeConfiguration.fromJson(configuration.toJson());

      expect(restored.left.mode, PageShapeCommentaryMode.multiple);
      expect(restored.left.commentators, ['רש"י', 'תוספות']);
      expect(restored.right.primaryCommentator, 'רא"ש');
      expect(restored.bottom.isEmpty, isTrue);
      expect(restored.bottomRight.primaryCommentator, 'רמב"ן');
    });
  });
}
