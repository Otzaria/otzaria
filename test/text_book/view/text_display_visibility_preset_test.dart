import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/text_display_visibility_preset.dart';

void main() {
  group('resolveTextDisplayVisibilityPreset', () {
    test('returns showAll when nothing is hidden', () {
      expect(
        resolveTextDisplayVisibilityPreset(
          removeNikud: false,
          removePunctuation: false,
        ),
        TextDisplayVisibilityPreset.showAll,
      );
    });

    test('returns removeNikud when only nikud is hidden', () {
      expect(
        resolveTextDisplayVisibilityPreset(
          removeNikud: true,
          removePunctuation: false,
        ),
        TextDisplayVisibilityPreset.removeNikud,
      );
    });

    test('returns removePunctuation when only punctuation is hidden', () {
      expect(
        resolveTextDisplayVisibilityPreset(
          removeNikud: false,
          removePunctuation: true,
        ),
        TextDisplayVisibilityPreset.removePunctuation,
      );
    });

    test('returns removeAll when both are hidden', () {
      expect(
        resolveTextDisplayVisibilityPreset(
          removeNikud: true,
          removePunctuation: true,
        ),
        TextDisplayVisibilityPreset.removeAll,
      );
    });
  });

  group('applyTextDisplayVisibilityPreset', () {
    test('maps showAll to visible nikud and punctuation', () {
      final values = applyTextDisplayVisibilityPreset(
        TextDisplayVisibilityPreset.showAll,
      );

      expect(values.removeNikud, isFalse);
      expect(values.removePunctuation, isFalse);
    });

    test('maps removeNikud to only nikud hidden', () {
      final values = applyTextDisplayVisibilityPreset(
        TextDisplayVisibilityPreset.removeNikud,
      );

      expect(values.removeNikud, isTrue);
      expect(values.removePunctuation, isFalse);
    });

    test('maps removePunctuation to only punctuation hidden', () {
      final values = applyTextDisplayVisibilityPreset(
        TextDisplayVisibilityPreset.removePunctuation,
      );

      expect(values.removeNikud, isFalse);
      expect(values.removePunctuation, isTrue);
    });

    test('maps removeAll to both hidden', () {
      final values = applyTextDisplayVisibilityPreset(
        TextDisplayVisibilityPreset.removeAll,
      );

      expect(values.removeNikud, isTrue);
      expect(values.removePunctuation, isTrue);
    });
  });
}
