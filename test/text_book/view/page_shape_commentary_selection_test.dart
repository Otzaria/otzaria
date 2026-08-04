import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';

void main() {
  group('Page shape remaining commentators', () {
    test('returns all commentators when no dedicated slots are chosen', () {
      final commentators = resolveRemainingPageShapeCommentators(
        availableCommentators: const ['רש"י', 'תוספות', 'רמב"ן'],
        excludedCommentators: const [],
      );

      expect(commentators, ['רש"י', 'תוספות', 'רמב"ן']);
    });

    test('excludes commentators already shown in other slots', () {
      final commentators = resolveRemainingPageShapeCommentators(
        availableCommentators: const ['רש"י', 'תוספות', 'רמב"ן', 'רא"ש'],
        excludedCommentators: const ['רש"י', 'רמב"ן', 'רא"ש'],
      );

      expect(commentators, ['תוספות']);
    });

    test('formats special selection with a user-facing label', () {
      expect(
        formatPageShapeCommentatorSelection(
          pageShapeRemainingCommentatorsValue,
        ),
        pageShapeRemainingCommentatorsLabel,
      );
    });

    test('encodes and decodes explicit multi selection', () {
      final encoded = encodePageShapeCommentatorsSelection(
        const ['רש"י', 'תוספות', 'רש"י'],
      );

      expect(isPageShapeMultiCommentatorsValue(encoded), isTrue);
      expect(
        decodePageShapeCommentatorsSelection(encoded),
        ['רש"י', 'תוספות'],
      );
    });

    test('תווית בחירה מרובה מציגה את כל המפרשים שנבחרו', () {
      final encoded = encodePageShapeCommentatorsSelection(
        const ['רש"י', 'תוספות'],
        forceMultipleMode: true,
      );

      expect(formatPageShapeCommentatorSelection(encoded), 'רש"י, תוספות');
    });

    test('preserves explicit multi mode without initial selection', () {
      final encoded = encodePageShapeCommentatorsSelection(
        const [],
        forceMultipleMode: true,
      );

      expect(encoded, pageShapeMultipleCommentatorsModeValue);
      expect(isPageShapeMultipleCommentatorsMode(encoded), isTrue);
      expect(
        resolvePageShapeSelectedCommentators(
          selection: encoded,
          availableCommentators: const ['רש"י', 'תוספות'],
        ),
        isEmpty,
      );
    });

    test('בחירה מרובה שמורה נשארת במצב מרובה עם כל המפרשים הזמינים', () {
      final encoded = encodePageShapeCommentatorsSelection(
        const ['רש"י', 'רמב"ן'],
      );

      final resolved = resolvePageShapeCommentatorSelection(
        selection: encoded,
        availableCommentators: const ['רש"י על ברכות', 'תוספות', 'רמב"ן'],
      );

      expect(isPageShapeMultipleCommentatorsMode(resolved), isTrue);
      expect(
        resolvePageShapeSelectedCommentators(
          selection: resolved,
          availableCommentators: const ['רש"י על ברכות', 'תוספות', 'רמב"ן'],
        ),
        ['רש"י על ברכות', 'רמב"ן'],
      );
    });

    test(
      'does not keep multiple mode when no selected commentator is available',
      () {
        final encoded = encodePageShapeCommentatorsSelection(
          const ['רש"י'],
          forceMultipleMode: true,
        );

        expect(
          resolvePageShapeCommentatorSelection(
            selection: encoded,
            availableCommentators: const ['תוספות', 'רמב"ן'],
          ),
          isNull,
        );
      },
    );

    test('שדה בחירה בודדת מציג את המפרש הראשון מבחירה מרובה', () {
      final encoded = encodePageShapeCommentatorsSelection(
        const ['רש"י'],
        forceMultipleMode: true,
      );

      expect(
        resolvePageShapeSingleCommentatorSelection(
          selection: encoded,
          availableCommentators: const ['רש"י על ברכות', 'תוספות'],
        ),
        'רש"י על ברכות',
      );
    });

    test('keeps legacy remaining selection compatible', () {
      final resolved = resolvePageShapeSelectedCommentators(
        selection: pageShapeRemainingCommentatorsValue,
        availableCommentators: const ['רש"י', 'תוספות', 'רמב"ן', 'רא"ש'],
        excludedCommentators: const ['רש"י', 'רמב"ן'],
      );

      expect(resolved, ['תוספות', 'רא"ש']);
    });

    test('מחזיר את המפרשים שמוצגים בפועל בצורת הדף', () {
      final displayed = resolvePageShapeDisplayedCommentators(
        leftSelection: 'אבן עזרא על בראשית',
        rightSelection: 'תרגום אונקלוס על בראשית',
        bottomSelection: 'אברבנאל על תורה',
        bottomRightSelection: 'בעל הטורים על בראשית',
        availableCommentators: const [
          'אבן עזרא על בראשית',
          'תרגום אונקלוס על בראשית',
          'אברבנאל על תורה',
          'בעל הטורים על בראשית',
          'רש"י על בראשית',
        ],
      );

      expect(displayed, [
        'אבן עזרא על בראשית',
        'תרגום אונקלוס על בראשית',
        'אברבנאל על תורה',
        'בעל הטורים על בראשית',
      ]);
    });

    test('הסתרת מפרש תחתון נוסף אינה מסתירה את המפרש התחתון', () {
      final displayed = resolvePageShapeDisplayedCommentators(
        leftSelection: null,
        rightSelection: null,
        bottomSelection: 'אברבנאל על תורה',
        bottomRightSelection: 'בעל הטורים על בראשית',
        availableCommentators: const [
          'אברבנאל על תורה',
          'בעל הטורים על בראשית',
        ],
        columnVisibility: const {
          'left': true,
          'right': true,
          'bottom': true,
          'bottomRight': false,
        },
      );

      // המפרש התחתון נשאר, התחתון הנוסף מוסתר
      expect(displayed, ['אברבנאל על תורה']);
    });

    test('הסתרת המפרש התחתון אינה מסתירה את המפרש התחתון הנוסף', () {
      final displayed = resolvePageShapeDisplayedCommentators(
        leftSelection: null,
        rightSelection: null,
        bottomSelection: 'אברבנאל על תורה',
        bottomRightSelection: 'בעל הטורים על בראשית',
        availableCommentators: const [
          'אברבנאל על תורה',
          'בעל הטורים על בראשית',
        ],
        columnVisibility: const {
          'left': true,
          'right': true,
          'bottom': false,
          'bottomRight': true,
        },
      );

      expect(displayed, ['בעל הטורים על בראשית']);
    });
  });
}
