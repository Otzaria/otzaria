import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';

void main() {
  test('defaults have an enabled default colour', () {
    final palette = MarkerPalette.defaults();
    expect(palette.defaultColor.id, 'yellow');
    expect(palette.menuColors.map((c) => c.id), [
      'yellow',
      'green',
      'blue',
      'red',
      'orange',
    ]);
  });

  test('round-trips through its stored form', () {
    final palette = MarkerPalette(
      colors: [
        ...MarkerPalette.defaults().colors,
        const MarkerColor(
          id: 'custom-1',
          label: 'לעיון',
          hex: '#D8B4E2',
          mode: MarkerStyleMode.box,
          opacity: 0.45,
        ),
      ],
      defaultColorId: 'custom-1',
    );
    expect(MarkerPalette.decode(palette.encode()), palette);
  });

  test('reads the old plugin palette and repairs bad values', () {
    final palette = MarkerPalette.fromJson(
      jsonDecode('''
      {"colors": [
        {"id": "yellow", "hex": "#f1e784ff", "label": "צהוב", "enabled": true,
         "opacity": 3, "markerMode": "underline", "borderRadius": 99},
        {"id": "yellow", "hex": "nope", "label": "", "enabled": false},
        {"id": "x y", "hex": "#123456", "label": "תווית ארוכה מאוד שחורגת מהמותר בהחלט"}
      ],
      "defaultColorId": "missing"}
      '''),
    );
    expect(palette.colors.first.hex, '#F1E784');
    expect(palette.colors.first.opacity, 1);
    expect(palette.colors.first.mode, MarkerStyleMode.underline);
    expect(palette.colors.first.borderRadius, MarkerColor.maxBorderRadius);
    expect(palette.colors[1].id, 'yellow-2');
    expect(palette.colors[1].label, 'צבע');
    expect(palette.colors[2].id, 'x-y');
    expect(palette.colors[2].label.length, MarkerColor.maxLabelLength);
    expect(palette.defaultColorId, 'yellow');
  });

  test('a corrupt stored palette falls back to the defaults', () {
    expect(MarkerPalette.decode('{not json'), MarkerPalette.defaults());
    expect(MarkerPalette.decode('{"colors": []}'), MarkerPalette.defaults());
  });

  test('tags are split, de-duplicated by spelling and capped', () {
    expect(
      MarkerHighlight.normalizeTags(['הלכה, לְעִיּוּן;לעיון', '  א  ב ', '']),
      ['הלכה', 'לְעִיּוּן', 'א ב'],
    );
    expect(
      MarkerHighlight.normalizeTags([for (var i = 0; i < 20; i++) 't$i']),
      hasLength(MarkerHighlight.maxTags),
    );
  });
}
