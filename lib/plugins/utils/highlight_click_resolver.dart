import 'package:characters/characters.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// מאתר את הדגשות התוספים שנקודת הלחיצה [globalPosition] נופלת עליהן
/// בפסקה [sectionIndex]. מאפשר להציג "הסר סימון" גם ללא בחירה פעילה.
List<PluginHighlight> resolveClickedHighlights({
  required RenderObject root,
  required Offset globalPosition,
  required String bookId,
  required int sectionIndex,
  required String rawText,
  required RenderSettings settings,
  String? bookUid,
}) {
  final highlights = PluginHighlightRegistry.instance.getAllHighlights(
    bookId: bookId,
    sectionIndex: sectionIndex,
    bookUid: bookUid,
  );
  if (highlights.isEmpty) return const [];

  const mapService = TextSourceMapService();
  final map = mapService.build(
    bookId: bookId,
    sectionIndex: sectionIndex,
    rawText: rawText,
    settings: settings,
  );
  final renderedChars = map.renderedText.characters.toList(growable: false);

  final result = <PluginHighlight>[];
  for (final highlight in highlights) {
    final start = mapService
        .sourceBoundaryToRendered(map, highlight.range.start.grapheme)
        .clamp(0, renderedChars.length);
    final end = mapService
        .sourceBoundaryToRendered(map, highlight.range.end.grapheme)
        .clamp(0, renderedChars.length);
    if (end <= start) continue;
    // ההשוואה מול הטקסט המוצג נעשית לפי תוכן ולא לפי אופסטים — כך סטיות
    // רווחים בין מרחבי הרינדור אינן מזיזות את הבדיקה.
    final displayText = renderedChars
        .sublist(start, end)
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (displayText.isEmpty) continue;
    final occurrence = displayTextOccurrence(
      renderedChars: renderedChars,
      startGrapheme: start,
      displayText: displayText,
    );
    final hit = clickIsOnTextOccurrence(
      root: root,
      globalPosition: globalPosition,
      text: displayText,
      occurrenceIndex: occurrence?.index,
      occurrenceCount: occurrence?.count,
    );
    if (hit == true) result.add(highlight);
  }
  return result;
}

/// אינדקס המופע של [displayText] במרחב המכווץ של הטקסט המרונדר, עבור
/// הדגשה שמתחילה ב-grapheme [startGrapheme]. בלעדיו לחיצה על מופע זהה
/// לא-מודגש הייתה מזוהה כלחיצה על ההדגשה. `null` — אין מופעים.
({int index, int count})? displayTextOccurrence({
  required List<String> renderedChars,
  required int startGrapheme,
  required String displayText,
}) {
  final whitespace = RegExp(r'\s+');
  final collapsedFull = renderedChars.join().replaceAll(whitespace, ' ');
  final starts = <int>[];
  for (var from = 0; ;) {
    final found = collapsedFull.indexOf(displayText, from);
    if (found < 0) break;
    starts.add(found);
    from = found + 1;
  }
  if (starts.isEmpty) return null;
  if (starts.length == 1) return (index: 0, count: 1);

  // מיקום תחילת ההדגשה במרחב המכווץ; כיווץ בגבול ה-slice עלול להזיז
  // בתו-שניים, לכן נבחר המופע הקרוב ביותר ולא נדרשת התאמה מדויקת.
  final collapsedPrefixLength = renderedChars
      .sublist(0, startGrapheme)
      .join()
      .replaceAll(whitespace, ' ')
      .trimRight()
      .length;
  var best = 0;
  for (var i = 1; i < starts.length; i++) {
    if ((starts[i] - collapsedPrefixLength).abs() <
        (starts[best] - collapsedPrefixLength).abs()) {
      best = i;
    }
  }
  return (index: best, count: starts.length);
}

/// בונה payload ללחיצה על הדגשה (הקשר `reader-highlight`): שדות ה-legacy
/// של בחירה + זיהוי ההדגשות שנלחצו, לצריכת התוסף שרשם את הפריט.
Map<String, dynamic> buildClickedHighlightsPayload({
  required List<PluginHighlight> highlights,
  required String bookId,
  required String bookTitle,
  required int sectionIndex,
  String? currentRef,
  int? bookDbId,
  String? bookType,
  String? bookSource,
  String? bookUid,
}) => {
  'id': ?bookDbId,
  'type': ?bookType,
  'source': ?bookSource,
  'text': '',
  'currentRef': currentRef,
  'currentBook': bookTitle,
  'currentBookId': bookId,
  'bookUid': ?bookUid,
  'currentIndex': sectionIndex,
  'clickedHighlights': [
    for (final highlight in highlights)
      {
        'highlightId': highlight.highlightId,
        'pluginId': highlight.ownerPluginId,
      },
  ],
};
