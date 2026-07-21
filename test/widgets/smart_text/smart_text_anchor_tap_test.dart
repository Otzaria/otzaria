import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// אימות שהעוגן (<a href="otzaria://anchor...">) מרונדר ב-HtmlWidget עם
// recognizer, ולחיצתו מנתבת ל-onAnchorTap עם ה-URL המלא (בלי WidgetSpan).
void main() {
  testWidgets('לחיצה על עוגן-מילה מפעילה onAnchorTap עם ה-URL', (tester) async {
    String? tappedUrl;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartTextWidget(
            text:
                'לפני <a class="link-anchor link-anchor-0" '
                'href="otzaria://anchor?ref=3_0">(א)</a> אחרי',
            settings: const RenderSettings(fontSize: 20),
            onAnchorTap: (url) => tappedUrl = url,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final recognizer = _findAnchorRecognizer(tester);
    expect(
      recognizer,
      isNotNull,
      reason: 'העוגן צריך להיות TextSpan עם TapGestureRecognizer',
    );
    recognizer!.onTap!();
    await tester.pump();

    expect(tappedUrl, 'otzaria://anchor?ref=3_0');
  });

  testWidgets(
    'עם onAnchorHover — גם אות-הסמן וגם טווח-הציטוט מקבלים onEnter/onExit '
    'ו-recognizer ללחיצה',
    (tester) async {
      final hovered = <String>[];
      final exited = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartTextWidget(
              text:
                  'לפני <a class="link-anchor link-anchor-0" '
                  'href="otzaria://anchor?ref=3_0">(א)</a> '
                  '<a class="link-anchor-range link-anchor-0" '
                  'href="otzaria://anchor?ref=3_1&range=1">שמות כט מג</a> אחרי',
              settings: const RenderSettings(fontSize: 20),
              onAnchorTap: (_) {},
              onAnchorHover: (url, position) => hovered.add(url),
              onAnchorHoverExit: exited.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markerSpan = _findHoverableSpan(tester, '(א)');
      final rangeSpan = _findHoverableSpan(tester, 'שמות');
      expect(
        markerSpan,
        isNotNull,
        reason: 'אות-הסמן צריכה TextSpan עם onEnter',
      );
      expect(
        rangeSpan,
        isNotNull,
        reason: 'טווח-הציטוט צריך TextSpan עם onEnter',
      );
      expect(markerSpan!.recognizer, isA<TapGestureRecognizer>());
      expect(rangeSpan!.recognizer, isA<TapGestureRecognizer>());

      markerSpan.onEnter!(const PointerEnterEvent(position: Offset(3, 4)));
      rangeSpan.onEnter!(const PointerEnterEvent(position: Offset(5, 6)));
      markerSpan.onExit!(const PointerExitEvent());
      expect(hovered, [
        'otzaria://anchor?ref=3_0',
        'otzaria://anchor?ref=3_1&range=1',
      ]);
      expect(exited, ['otzaria://anchor?ref=3_0']);
    },
  );

  testWidgets('הערות וקישור־טווח מקבלים אירועי ריחוף', (tester) async {
    final hovered = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartTextWidget(
            text:
                '<a class="book-note-marker" '
                'href="otzaria://book-note?line=1&note=0">א</a> '
                '<a href="otzaria://note?line=1">מילה</a> '
                '<a href="otzaria://inline-link?path=%D7%A4%D7%99%D7%A8%D7%95%D7%A9&index=2&ref=%D7%90">קישור</a>',
            settings: const RenderSettings(fontSize: 20),
            onNoteTap: (_) {},
            onAnchorHover: (url, _) => hovered.add(url),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    _findHoverableSpan(tester, 'א')!.onEnter!(const PointerEnterEvent());
    _findHoverableSpan(tester, 'מילה')!.onEnter!(const PointerEnterEvent());
    _findHoverableSpan(tester, 'קישור')!.onEnter!(const PointerEnterEvent());

    expect(hovered, [
      'otzaria://book-note?line=1&note=0',
      'otzaria://note?line=1',
      'otzaria://inline-link?path=%D7%A4%D7%99%D7%A8%D7%95%D7%A9&index=2&ref=%D7%90',
    ]);
  });
}

/// TextSpan עם onEnter שהטקסט השטוח שלו מכיל את [needle].
TextSpan? _findHoverableSpan(WidgetTester tester, String needle) {
  TextSpan? result;
  void visit(InlineSpan span) {
    if (result != null || span is! TextSpan) return;
    if (span.onEnter != null && span.toPlainText().contains(needle)) {
      result = span;
      return;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child);
    }
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(richText.text);
    if (result != null) break;
  }
  return result;
}

TapGestureRecognizer? _findAnchorRecognizer(WidgetTester tester) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final found = _searchSpan(richText.text);
    if (found != null) return found;
  }
  return null;
}

TapGestureRecognizer? _searchSpan(InlineSpan span) {
  if (span is TextSpan) {
    final recognizer = span.recognizer;
    if (recognizer is TapGestureRecognizer &&
        (span.toPlainText(includeSemanticsLabels: false)).contains('א')) {
      return recognizer;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = _searchSpan(child);
      if (found != null) return found;
    }
  }
  return null;
}
