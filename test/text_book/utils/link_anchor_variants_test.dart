import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/link_anchor_variants.dart';

// מקור האמת של הווריאנטים משרת שני מסלולי רינדור: CSS (HtmlWidget) ו-TextStyle
// (קריאה רציפה). הטסטים כאן נועלים את שקילות שני התרגומים.
void main() {
  const base = TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM');

  group('linkAnchorVariantFromClasses', () {
    test('כל אינדקס ממופה לווריאנט המתאים לו', () {
      for (var index = 0; index < kLinkAnchorVariants.length; index++) {
        expect(
          linkAnchorVariantFromClasses(['link-anchor', 'link-anchor-$index']),
          same(kLinkAnchorVariants[index]),
          reason: 'link-anchor-$index',
        );
      }
    });

    test('בלי מחלקת וריאנט — null', () {
      expect(linkAnchorVariantFromClasses(const ['link-anchor']), isNull);
      expect(linkAnchorVariantFromClasses(const ['link-anchor-range']), isNull);
      expect(linkAnchorVariantFromClasses(const []), isNull);
    });

    test('אינדקס מחוץ לטווח אינו מזוהה', () {
      expect(
        linkAnchorVariantFromClasses([
          'link-anchor-${kLinkAnchorVariants.length}',
        ]),
        isNull,
      );
    });
  });

  group('שקילות CSS ↔ TextStyle', () {
    test('כתב רש"י מוחל בשני המסלולים על אותם אינדקסים', () {
      for (var index = 0; index < kLinkAnchorVariants.length; index++) {
        final variant = kLinkAnchorVariants[index];
        final css = linkAnchorVariantCss(variant);
        final style = applyLinkAnchorVariant(variant, base);

        expect(
          css['font-family'] == kLinkAnchorRashiFont,
          style.fontFamily == kLinkAnchorRashiFont,
          reason: 'אינדקס $index — גופן',
        );
        expect(
          css['font-weight'] == 'bold',
          style.fontWeight == FontWeight.bold,
          reason: 'אינדקס $index — משקל',
        );
        expect(
          css['font-style'] == 'italic',
          style.fontStyle == FontStyle.italic,
          reason: 'אינדקס $index — נטייה',
        );
        expect(
          css['text-decoration'] == 'underline',
          style.decoration == TextDecoration.underline,
          reason: 'אינדקס $index — קו תחתון',
        );
      }
    });

    test('כל הווריאנטים נבדלים זה מזה ויזואלית', () {
      final signatures = kLinkAnchorVariants
          .map(
            (variant) => (
              variant.bold,
              variant.italic,
              variant.rashiScript,
              variant.underline,
            ),
          )
          .toSet();
      expect(signatures.length, kLinkAnchorVariants.length);
    });

    test('אף וריאנט אינו "ריק" — לכל אחד יש סימן מבחין', () {
      for (final variant in kLinkAnchorVariants) {
        expect(
          variant.bold ||
              variant.italic ||
              variant.rashiScript ||
              variant.underline,
          isTrue,
        );
      }
    });
  });

  group('applyLinkAnchorVariant', () {
    test('null מחזיר את הסגנון כמות שהוא', () {
      expect(applyLinkAnchorVariant(null, base), same(base));
    });

    test('וריאנט שאינו כתב רש"י שומר על גופן הטקסט הסובב', () {
      final style = applyLinkAnchorVariant(
        const LinkAnchorVariant(bold: true),
        base,
      );
      expect(style.fontFamily, 'FrankRuhlCLM');
      expect(style.fontWeight, FontWeight.bold);
    });

    test('כתב רש"י מחליף גופן ושומר על הגודל', () {
      final style = applyLinkAnchorVariant(
        const LinkAnchorVariant(rashiScript: true),
        base,
      );
      expect(style.fontFamily, kLinkAnchorRashiFont);
      expect(style.fontSize, 20);
    });

    test('בולד בכתב רש"י מקבל FontVariation (גופן משתנה, לא בולד מלאכותי)', () {
      final style = applyLinkAnchorVariant(
        const LinkAnchorVariant(rashiScript: true, bold: true),
        base,
      );
      expect(style.fontVariations, isNotNull);
      expect(
        style.fontVariations!.any((variation) => variation.axis == 'wght'),
        isTrue,
      );
    });

    test('תכונה שהווריאנט אינו קובע נשארת בירושה', () {
      const inherited = TextStyle(
        fontSize: 20,
        fontFamily: 'FrankRuhlCLM',
        fontStyle: FontStyle.italic,
      );
      final style = applyLinkAnchorVariant(
        const LinkAnchorVariant(bold: true),
        inherited,
      );
      expect(style.fontStyle, FontStyle.italic);
    });
  });
}
