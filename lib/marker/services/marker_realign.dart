import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// מקטע שמצביע על מילים אחרות מאלה שסומנו, מוחזר בעוגן שבמקום הנכון.
///
/// המיפוי בין המקור לתצוגה השווה בעבר כל אות עם הניקוד שלה, ולכן סימון שנוצר
/// כשהניקוד, הטעמים או הפיסוק הוסתרו עוגן כמה אותיות או מילים הצידה. הטקסט
/// שסומן, [markText], נשמר כפי שהוצג; כשהאותיות שלו אינן האותיות שהעוגן מציג
/// בשורה [rawLine] בשום תצוגה, הוא מאותר בפסקה — בלי ניקוד, טעמים, פיסוק
/// ורווחים — במופע הקרוב למקום השמור.
///
/// null כשהעוגן תואם, או כשהטקסט אינו נמצא; אז המקטע נשאר כפי שהוא.
MarkerSegment? realignMarkerSegment({
  required MarkerSegment segment,
  required String markText,
  required String rawLine,
}) {
  final wanted = _letters(markText).map((l) => l.key).toList();
  if (wanted.isEmpty) return null;
  if (_shownAs(segment, rawLine).any((shown) => _sameKeys(shown, wanted))) {
    return null;
  }

  final sourceText = TextRendererService.stripHtml(rawLine);
  final letters = _letters(sourceText);
  int? best;
  for (var i = 0; i + wanted.length <= letters.length; i++) {
    var j = 0;
    while (j < wanted.length && letters[i + j].key == wanted[j]) {
      j++;
    }
    if (j < wanted.length) continue;
    if (best == null ||
        (letters[i].at - segment.start).abs() <
            (letters[best].at - segment.start).abs()) {
      best = i;
    }
  }
  if (best == null) return null;
  final range = const ReaderSelectionService().buildRangeAnchor(
    text: sourceText,
    startGrapheme: letters[best].at,
    endGrapheme: letters[best + wanted.length - 1].at + 1,
    layer: 'source',
    sourceTextHash: sha256.convert(utf8.encode(sourceText)).toString(),
  );
  if (range == null) return null;
  return segment.copyWith(range: range, status: MarkerAnchorStatus.active);
}

/// התצוגות שבהן אפשר היה לסמן — שם הוי"ה ושאר השמות כתובים או בכינוי בכל
/// סגנון — כי הטקסט שנשמר הוא זה שהוצג.
final List<RenderSettings> _displays = [
  const RenderSettings(),
  for (final style in text_utils.HolyNameStyle.values)
    for (final others in const [false, true])
      RenderSettings(
        replaceHolyNames: true,
        holyNameStyle: style,
        substituteDivineNames: others,
      ),
];

/// האותיות שהעוגן מציג בשורה בכל אחת מ-[_displays]. השורה עצמה ולא רק טקסט
/// העוגן: הכינויים נקבעים לפי הסימון שבשורה, והתצוגה מסירה ממנה הערות.
Iterable<Iterable<String>> _shownAs(
  MarkerSegment segment,
  String rawLine,
) sync* {
  yield _letters(segment.range.exactText).map((l) => l.key);
  const maps = TextSourceMapService();
  for (final settings in _displays) {
    final map = maps.cachedFromProcessedHtml(
      bookId: '',
      sectionIndex: segment.sectionIndex,
      rawText: rawLine,
      processedHtml: TextRendererService.processText(rawLine, settings),
    );
    final start = maps.sourceBoundaryToRendered(map, segment.start);
    final end = maps.sourceBoundaryToRendered(map, segment.end);
    if (end <= start) continue;
    final shown = map.renderedText.characters
        .skip(start)
        .take(end - start)
        .string;
    yield _letters(shown).map((l) => l.key);
  }
}

/// האותיות והספרות של [text], כל אחת בלי הסימנים שעליה, עם מיקום ה-grapheme.
List<({String key, int at})> _letters(String text) {
  final result = <({String key, int at})>[];
  var at = 0;
  for (final grapheme in text.characters) {
    final key = text_utils.removeAttachedMarks(grapheme);
    if (key.isNotEmpty && _isLetter.hasMatch(key)) {
      result.add((key: key, at: at));
    }
    at++;
  }
  return result;
}

final RegExp _isLetter = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _sameKeys(Iterable<String> a, List<String> b) {
  var i = 0;
  for (final key in a) {
    if (i >= b.length || key != b[i]) return false;
    i++;
  }
  return i == b.length;
}
