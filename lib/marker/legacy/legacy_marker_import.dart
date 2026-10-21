import 'dart:convert';
import 'dart:isolate';

import 'package:characters/characters.dart';
import 'package:otzaria/marker/legacy/legacy_marker_plugin.dart';
import 'package:otzaria/marker/legacy/legacy_note_html.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/models/marker_text.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

/// מה שנקרא מנתוני התוסף הישן, לפני שנשמר.
class LegacyMarkerData {
  final List<MarkerHighlight> highlights;

  /// הפלטה של התוסף, אם נשמרה.
  final MarkerPalette? palette;

  /// רשומות שנדחו (בלי מזהה, בלי ספר או בלי עוגן שמיש).
  final int invalid;

  /// הדגשות של התוסף שיובאו בעבר, גם אם הסימון נמחק מאז.
  final List<MarkerLegacyRef> importedLegacy;

  /// הנתונים באו מהתוסף הישן (מהאחסון שלו או מקובץ הגיבוי שלו).
  final bool fromPlugin;

  const LegacyMarkerData({
    required this.highlights,
    this.palette,
    this.invalid = 0,
    this.importedLegacy = const [],
    this.fromPlugin = true,
  });
}

class LegacyMarkerFormatException implements Exception {
  const LegacyMarkerFormatException();
}

/// קובץ גיבוי של התוסף (`otzaria-marker-backup`, גרסאות 1 ו-2).
LegacyMarkerData parseLegacyMarkerBackup(Object? json) {
  if (json is! Map ||
      json['format'] != 'otzaria-marker-backup' ||
      (json['schemaVersion'] != 1 && json['schemaVersion'] != 2) ||
      json['highlights'] is! List) {
    throw const LegacyMarkerFormatException();
  }
  return parseLegacyMarkerRecords(
    json['highlights'] as List,
    settings: json['settings'],
  );
}

/// הנתונים שהתוסף שמר באחסון שלו, לקריאה בלבד: אין כאן כתיבה או מחיקה,
/// כדי שהתוסף ימשיך לעבוד כמקודם אם הוא עדיין מותקן.
Future<LegacyMarkerData?> readLegacyMarkerStore(
  PluginRegistryRepository registry,
) async {
  const namespace = 'default';
  final keys = await registry.listKVKeys(kLegacyMarkerPluginId, namespace);
  final recordKeys = keys.where((key) => key.startsWith('highlight:'));
  if (recordKeys.isEmpty) return null;
  final values = await registry.getKVMany(kLegacyMarkerPluginId, namespace, [
    ...recordKeys,
    'marker_settings',
  ]);
  // עשרות אלפי רשומות JSON מפוענחות ב-isolate, כדי לא לעצור את החלונות.
  return Isolate.run(() => _parseStore(values));
}

LegacyMarkerData _parseStore(Map<String, String> values) {
  final settingsJson = values.remove('marker_settings');
  return parseLegacyMarkerRecords(
    [for (final value in values.values) _decode(value)],
    settings: settingsJson == null ? null : _decode(settingsJson),
  );
}

Object? _decode(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

/// ממיר רשומות של התוסף לסימונים. חלקי בחירה חוצת-פסקאות (`groupId` משותף)
/// מתאחדים לסימון אחד. המזהה נשמר, ולכן ייבוא חוזר מזהה את מה שכבר יובא.
LegacyMarkerData parseLegacyMarkerRecords(
  Iterable<Object?> records, {
  Object? settings,
}) {
  var invalid = 0;
  final parts = <_Part>[];
  final seen = <String>{};
  for (final record in records) {
    final part = record is Map ? _Part.tryParse(record) : null;
    if (part == null || !seen.add(part.id)) {
      invalid++;
      continue;
    }
    parts.add(part);
  }
  final grouped = <String, List<_Part>>{};
  for (final part in parts) {
    grouped.putIfAbsent(part.groupId ?? part.id, () => []).add(part);
  }
  return LegacyMarkerData(
    highlights: [
      for (final entry in grouped.entries)
        ..._mergeGroup(entry.key, entry.value),
    ],
    palette: settings is Map && settings['colors'] is List
        ? MarkerPalette.fromJson(settings)
        : null,
    invalid: invalid,
  );
}

/// בתוסף כל חלק נערך לחוד. חלקים שההערה, הצבע, התגיות או המועדף שלהם
/// שונים נשארים סימונים נפרדים, כדי ששום הערה לא תאבד באיחוד.
List<MarkerHighlight> _mergeGroup(String id, List<_Part> parts) {
  parts.sort(
    (a, b) => a.segment.sectionIndex.compareTo(b.segment.sectionIndex),
  );
  final clusters = <String, List<_Part>>{};
  for (final part in parts) {
    clusters.putIfAbsent(part.signature, () => []).add(part);
  }
  final result = <MarkerHighlight>[];
  final ids = <String>{};
  for (final cluster in clusters.values) {
    var own = result.isEmpty ? id : cluster.first.id;
    if (!ids.add(own)) {
      own = '$id-${result.length}';
      ids.add(own);
    }
    result.add(_merge(own, cluster));
  }
  return result;
}

MarkerHighlight _merge(String id, List<_Part> parts) {
  final first = parts.first;
  final created = parts
      .map((part) => part.createdAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  return MarkerHighlight(
    id: id,
    bookTitle: first.bookTitle,
    bookUid: first.bookUid,
    segments: [for (final part in parts) part.segment],
    text: parts.map((part) => part.text).where((t) => t.isNotEmpty).join(' '),
    ref: first.ref,
    colorId: first.colorId,
    colorHex: first.colorHex,
    note: parts.map((part) => part.note).whereType<MarkerNote>().firstOrNull,
    tags: MarkerHighlight.normalizeTags([for (final p in parts) ...p.tags]),
    favorite: parts.any((part) => part.favorite),
    createdAt: created,
    updatedAt: created,
  );
}

final RegExp _safeId = RegExp(r'^[A-Za-z0-9._-]{1,128}$');

class _Part {
  final String id;
  final String? groupId;
  final String bookTitle;
  final String? bookUid;
  final MarkerSegment segment;
  final String text;
  final String? ref;
  final String colorId;
  final String colorHex;
  final MarkerNote? note;
  final List<String> tags;
  final bool favorite;
  final DateTime createdAt;

  _Part({
    required this.id,
    required this.groupId,
    required this.bookTitle,
    required this.bookUid,
    required this.segment,
    required this.text,
    required this.ref,
    required this.colorId,
    required this.colorHex,
    required this.note,
    required this.tags,
    required this.favorite,
    required this.createdAt,
  });

  /// מה שחייב להיות זהה בין חלקים כדי לאחד אותם.
  String get signature => [
    bookTitle,
    bookUid,
    colorId,
    colorHex,
    note?.content,
    tags.join('\u001F'),
    favorite,
  ].join('\u0000');

  static _Part? tryParse(Map<dynamic, dynamic> raw) {
    final id = raw['highlightId'];
    final section = raw['sectionIndex'];
    final book = _text(raw['bookId'], 500) ?? _text(raw['book'], 500);
    if (id is! String || !_safeId.hasMatch(id)) return null;
    if (section is! int || section < 0 || book == null) return null;
    final anchor = _anchor(raw['sourceRange']);
    if (anchor == null) return null;
    final groupId = raw['groupId'];
    final timestamp = raw['timestamp'];
    final status = MarkerAnchorStatus.fromWire(raw['status']);
    return _Part(
      id: id,
      groupId: groupId is String && _safeId.hasMatch(groupId) ? groupId : null,
      bookTitle: book,
      bookUid: _text(raw['bookUid'], 2000),
      segment: MarkerSegment(
        sectionIndex: section,
        range: anchor.range,
        // עוגן ששוחזר מנתונים חלקיים יאומת מול הטקסט לפני שיצויר.
        status: anchor.repaired ? MarkerAnchorStatus.stale : status,
        legacyId: id,
      ),
      text: _text(raw['text'], 20000) ?? anchor.range.exactText,
      ref: _text(raw['ref'], 1000),
      colorId: MarkerColor.normalizeId(raw['colorId']) ?? 'yellow',
      colorHex: MarkerColor.normalizeHex(raw['color']) ?? '#FFF176',
      note: _note(raw['noteHtml'], raw['note']),
      tags: raw['tags'] is List
          ? MarkerHighlight.normalizeTags(
              (raw['tags'] as List).whereType<String>(),
            )
          : const [],
      favorite: raw['favorite'] == true,
      // מחוץ לטווח התאריכים DateTime זורק, ורשומה אחת הייתה עוצרת את הייבוא.
      createdAt: timestamp is num && timestamp > 0 && timestamp < _maxTimestamp
          ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt(), isUtc: true)
          : DateTime.utc(2000),
    );
  }

  static const num _maxTimestamp = 8.64e15;

  static String? _text(Object? value, int max) {
    if (value is! String) return null;
    final clean = value
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
        .trim();
    if (clean.isEmpty) return null;
    return truncateGraphemes(clean, max);
  }

  static MarkerNote? _note(Object? html, Object? plain) {
    final plainText = _text(plain, 4000);
    if (html is String && html.trim().isNotEmpty) {
      final delta = legacyNoteHtmlToDelta(html);
      if (delta != null) {
        // בלי עותק פשוט ההערה לא הייתה נספרת, נמצאת או מוצגת.
        final plain =
            plainText ?? truncateGraphemes(legacyDeltaPlainText(delta), 4000);
        if (plain.isNotEmpty) return MarkerNote(content: delta, plain: plain);
      }
    }
    if (plainText == null) return null;
    return MarkerNote(
      content: plainText,
      plain: plainText,
      format: PersonalNoteContentFormat.plain,
    );
  }

  /// העוגן כפי שנשמר; כשהוא חלקי (גרסאות ישנות, עריכה ידנית) — עוגן חדש
  /// מהטקסט המדויק, שיאותר מחדש בפתיחת הספר.
  static ({PluginTextRangeAnchor range, bool repaired})? _anchor(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    try {
      final range = PluginTextRangeAnchor.fromJson(json);
      if (range.layer == 'source' &&
          range.start.grapheme < range.end.grapheme) {
        return (range: range, repaired: false);
      }
    } on FormatException {
      // ממשיכים לשחזור מהטקסט המדויק.
    } on TypeError {
      // ממשיכים לשחזור מהטקסט המדויק.
    }
    final exact = json['exactText'];
    if (exact is! String || exact.trim().isEmpty) return null;
    if (exact.characters.length > PluginTextRangeAnchor.maxExactTextGraphemes) {
      return null;
    }
    final start = json['start'] is Map ? json['start'] as Map : const {};
    final hint = start['grapheme'] ?? start['utf16'];
    final from = hint is int && hint >= 0 ? hint : 0;
    PluginAnchorContext context(Object? value) {
      final text = value is Map && value['raw'] is String
          ? (value['raw'] as String).characters
                .take(PluginAnchorContext.maxSupportedGraphemes)
                .toString()
          : '';
      final length = text.characters.length;
      return PluginAnchorContext(
        raw: text,
        normalized: text,
        maxGraphemes: length < 30 ? 30 : length,
        actualGraphemes: length,
        truncatedAtBoundary: length == 0,
      );
    }

    return (
      range: PluginTextRangeAnchor(
        layer: 'source',
        start: PluginTextOffset(grapheme: from, codePoint: from, utf16: from),
        end: PluginTextOffset(
          grapheme: from + exact.characters.length,
          codePoint: from + exact.runes.length,
          utf16: from + exact.length,
        ),
        exactText: exact,
        beforeText: context(json['beforeText']),
        afterText: context(json['afterText']),
        occurrenceIndexInSection: 0,
        occurrenceCountInSection: 1,
      ),
      repaired: true,
    );
  }
}
