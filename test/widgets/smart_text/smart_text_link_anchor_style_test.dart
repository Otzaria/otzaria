import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// ציטוט הלינקר (link-anchor-range) חייב להיראות כמו הטקסט שסביבו — צבע הנושא
// בלבד, בלי קו תחתון. וריאנט טיפוגרפי (כתב רש"י/נטוי/מודגש) שייך אך ורק
// לסמני-האות של המפרשים (link-anchor).
void main() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
  );

  Future<void> pumpText(WidgetTester tester, String html) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SmartTextWidget(
            text: html,
            settings: const RenderSettings(
              fontSize: 20,
              fontFamily: 'FrankRuhlCLM',
            ),
            onAnchorTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ציטוט לינקר: אותו גופן כמו הטקסט הסובב, בלי קו תחתון', (
    tester,
  ) async {
    await pumpText(
      tester,
      'לפני <a class="link-anchor-range" '
      'href="otzaria://anchor?ref=3_0&range=1">ציטוט</a> אחרי',
    );

    final around = _styleOf(tester, 'לפני')!;
    final citation = _styleOf(tester, 'ציטוט')!;

    expect(citation.fontFamily, around.fontFamily);
    expect(citation.fontSize, around.fontSize);
    expect(citation.fontStyle, isNot(FontStyle.italic));
    expect(citation.fontWeight ?? FontWeight.normal, FontWeight.normal);
    expect(citation.decoration ?? TextDecoration.none, TextDecoration.none);
    expect(citation.color, theme.colorScheme.primary);
  });

  testWidgets('מחלקת וריאנט על ציטוט אינה משנה גופן/משקל/נטייה', (
    tester,
  ) async {
    // link-anchor-3 = כתב רש"י ו-link-anchor-2 = מודגש+נטוי בטבלת הווריאנטים.
    // גם אם המחלקה תגיע מהזרקה עתידית, הציטוט חייב להישאר בגופן הטקסט.
    await pumpText(
      tester,
      'לפני <a class="link-anchor-range link-anchor-3" '
      'href="otzaria://anchor?ref=3_0&range=1">רשי</a> '
      '<a class="link-anchor-range link-anchor-2" '
      'href="otzaria://anchor?ref=3_1&range=1">נטוי</a> אחרי',
    );

    final around = _styleOf(tester, 'לפני')!;
    for (final needle in ['רשי', 'נטוי']) {
      final citation = _styleOf(tester, needle)!;
      expect(citation.fontFamily, around.fontFamily, reason: needle);
      expect(citation.fontStyle, isNot(FontStyle.italic), reason: needle);
      expect(
        citation.fontWeight ?? FontWeight.normal,
        FontWeight.normal,
        reason: needle,
      );
    }
  });

  testWidgets('סמן-אות של מפרש כן מקבל את הווריאנט הטיפוגרפי', (tester) async {
    await pumpText(
      tester,
      'לפני <a class="link-anchor link-anchor-3" '
      'href="otzaria://anchor?ref=3_0">(א)</a> אחרי',
    );

    final around = _styleOf(tester, 'לפני')!;
    final marker = _styleOf(tester, '(א)')!;

    expect(marker.fontFamily, 'NotoRashiHebrew');
    expect(marker.fontFamily, isNot(around.fontFamily));
    // האות מוקטנת ומורמת, ולכן וריאנט הגופן אינו פוגע בזרימת הטקסט.
    expect(marker.fontSize, lessThan(around.fontSize!));
  });
}

/// ה-[TextStyle] האפקטיבי (ממוזג מכל ההורים) של הספאן שהטקסט שלו מכיל [needle].
TextStyle? _styleOf(WidgetTester tester, String needle) {
  TextStyle? found;

  void visit(InlineSpan span, TextStyle inherited) {
    if (found != null || span is! TextSpan) return;
    final style = span.style == null ? inherited : inherited.merge(span.style);
    if (span.text != null && span.text!.contains(needle)) {
      found = style;
      return;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(richText.text, const TextStyle());
    if (found != null) break;
  }
  return found;
}
