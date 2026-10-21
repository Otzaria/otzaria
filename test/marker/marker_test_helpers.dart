import 'package:characters/characters.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/storage/marker_changes.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';

/// עוגן מקור לביטוי [phrase] בתוך [source] (המופע ה-[occurrence]).
PluginTextRangeAnchor anchorFor(
  String source,
  String phrase, {
  int occurrence = 0,
}) {
  final graphemes = source.characters.toList();
  final needle = phrase.characters.toList();
  final starts = <int>[];
  for (var i = 0; i + needle.length <= graphemes.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (graphemes[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) starts.add(i);
  }
  final start = starts[occurrence];
  final end = start + needle.length;
  PluginTextOffset offset(int boundary) {
    final prefix = graphemes.take(boundary).join();
    return PluginTextOffset(
      grapheme: boundary,
      codePoint: prefix.runes.length,
      utf16: prefix.length,
    );
  }

  PluginAnchorContext context(int from, int to) {
    final raw = graphemes.sublist(from, to).join();
    return PluginAnchorContext(
      raw: raw,
      normalized: raw,
      maxGraphemes: 30,
      actualGraphemes: to - from,
      truncatedAtBoundary: from == 0 || to == graphemes.length,
    );
  }

  return PluginTextRangeAnchor(
    layer: 'source',
    start: offset(start),
    end: offset(end),
    exactText: phrase,
    beforeText: context((start - 30).clamp(0, start), start),
    afterText: context(end, (end + 30).clamp(end, graphemes.length)),
    occurrenceIndexInSection: occurrence,
    occurrenceCountInSection: starts.length,
  );
}

MarkerSegment segmentFor(
  int section,
  String source,
  String phrase, {
  int occurrence = 0,
  String? legacyId,
}) => MarkerSegment(
  sectionIndex: section,
  range: anchorFor(source, phrase, occurrence: occurrence),
  legacyId: legacyId,
);

MarkerDraft draftFor(
  List<MarkerSegment> segments, {
  String book = 'בראשית',
  String? uid = 'id:1',
  String text = 'טקסט',
}) => MarkerDraft(
  bookTitle: book,
  bookUid: uid,
  segments: segments,
  text: text,
  ref: '$book א',
);

MarkerHighlight highlightFor(
  String id,
  List<MarkerSegment> segments, {
  String book = 'בראשית',
  String? uid = 'id:1',
  String colorId = 'yellow',
  DateTime? createdAt,
  List<String> tags = const [],
  bool favorite = false,
  MarkerNote? note,
  String text = 'טקסט',
}) {
  final time = createdAt ?? DateTime.utc(2026, 1, 1);
  return MarkerHighlight(
    id: id,
    bookTitle: book,
    bookUid: uid,
    segments: segments,
    text: text,
    colorId: colorId,
    colorHex: '#F1E784',
    tags: tags,
    favorite: favorite,
    note: note,
    createdAt: time,
    updatedAt: time,
  );
}

MarkerColor colorOf(String id) => MarkerPalette.defaults().colorById(id)!;

/// מסד בזיכרון ומאגר שמדווח לזרם שינויים משלו.
({MarkerDatabase db, MarkerRepository repository, MarkerChanges changes})
openTestMarkerStore({DateTime Function()? clock}) {
  final db = MarkerDatabase.withDatabase(sqlite3.openInMemory());
  final changes = MarkerChanges();
  return (
    db: db,
    repository: MarkerRepository(database: db, changes: changes, clock: clock),
    changes: changes,
  );
}
