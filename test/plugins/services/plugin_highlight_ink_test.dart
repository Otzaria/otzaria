// צבע האותיות של הדגשת קטע ספר על ידי תוסף (פריט 26, theme-dark-15). תוסף
// שלא קבע foregroundColor קיבל את צבע הערכה, ובכהה זה טקסט בהיר על הצהוב
// בהיר שהוא ברירת המחדל. הצבע נגזר מבהירות הרקע של ההדגשה.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';

const _raw = 'אבגדה';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return la > lb ? la / lb : lb / la;
}

PluginHighlight _highlight({
  required String color,
  String? foreground,
  double opacity = 1,
  String markerMode = 'text-background',
}) {
  const context = PluginAnchorContext(
    raw: '',
    normalized: '',
    maxGraphemes: 30,
    actualGraphemes: 0,
    truncatedAtBoundary: true,
  );
  return PluginHighlight(
    highlightId: 'h',
    ownerPluginId: 'plugin',
    bookId: 'book',
    sectionIndex: 0,
    range: const PluginTextRangeAnchor(
      layer: 'source',
      start: PluginTextOffset(grapheme: 0, codePoint: 0, utf16: 0),
      end: PluginTextOffset(grapheme: 5, codePoint: 5, utf16: 5),
      exactText: _raw,
      beforeText: context,
      afterText: context,
      occurrenceIndexInSection: 0,
      occurrenceCountInSection: 1,
    ),
    style: PluginHighlightStyle(
      backgroundColor: color,
      foregroundColor: foreground,
      opacity: opacity,
      markerMode: markerMode,
    ),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

/// ה-CSS של הקטע המודגש אחרי ההחלה.
String _style(PluginHighlight highlight, {bool revealed = false}) {
  final result = const PluginHighlightRenderer().apply(
    bookId: 'book',
    sectionIndex: 0,
    rawText: _raw,
    processedHtml: _raw,
    highlights: [highlight],
    revealedHighlightId: revealed ? 'h' : null,
  );
  return html_parser
      .parseFragment(result)
      .querySelector('[data-highlight-id="h"]')!
      .attributes['style']!;
}

/// צבע ה-`color:` האחרון ב-[style] (האחרון מנצח ב-CSS), או null.
Color? _color(String style) {
  final matches = RegExp(
    r'(?:^|; )color: rgba\((\d+), (\d+), (\d+), ([\d.]+)\)',
  ).allMatches(style);
  if (matches.isEmpty) return null;
  final m = matches.last;
  return Color.fromARGB(
    (double.parse(m[4]!) * 255).round(),
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
  );
}

void main() {
  test('רקע בהיר: אותיות כהות, קריאות מעל הצהוב וגם מעל התכלת', () {
    for (final background in ['#FFEB3B', '#FFFF00', '#80DEEA', '#FF9800']) {
      final ink = _color(_style(_highlight(color: background)));
      expect(ink, isNotNull, reason: background);
      final fill = Color(
        0xFF000000 | int.parse(background.substring(1), radix: 16),
      );
      expect(
        _contrast(ink!, fill),
        greaterThanOrEqualTo(4.5),
        reason: background,
      );
      expect(
        ink.computeLuminance(),
        lessThan(0.05),
        reason: '$background: כהה',
      );
    }
  });

  test('רקע כהה: אותיות בהירות', () {
    for (final background in ['#1A237E', '#4A148C', '#000000']) {
      final ink = _color(_style(_highlight(color: background)))!;
      expect(ink, const Color(0xFFFFFFFF), reason: background);
    }
  });

  test('foregroundColor שהתוסף קבע מנצח, והחישוב לא נוגע בו', () {
    final style = _style(_highlight(color: '#FFEB3B', foreground: '#0000FF'));
    expect(_color(style), const Color(0xFF0000FF));
    expect(RegExp('color: rgba').allMatches(style), hasLength(1));
  });

  test('רקע שקוף מאוד: הצבע נשאר לערכה, כי הקריאות תלויה ברקע הקריאה', () {
    expect(_color(_style(_highlight(color: '#FFEB3B', opacity: 0.25))), isNull);
  });

  test('מסגרת וקו תחתון לא מצוירים מתחת לאותיות: בלי צבע אותיות', () {
    for (final mode in ['box', 'underline']) {
      expect(
        _color(_style(_highlight(color: '#FFEB3B', markerMode: mode))),
        isNull,
        reason: mode,
      );
    }
  });

  test('הדגשה חשופה (רקע אטום) מקבלת אותיות קריאות גם במסגרת', () {
    final style = _style(
      _highlight(color: '#FFEB3B', markerMode: 'box'),
      revealed: true,
    );
    expect(style, contains('background-color'));
    expect(_color(style), isNotNull);
  });
}
