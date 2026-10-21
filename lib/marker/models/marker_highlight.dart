import 'package:equatable/equatable.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/models/marker_text.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';

/// הדגשה של התוסף הישן שיובאה, לפי המזהה שלה בתוסף והספר.
typedef MarkerLegacyRef = ({String id, String book});

/// מצב העוגן של מקטע מול טקסט הספר; הערכים כמו ב-`PluginHighlight.status`,
/// כדי שתוצאת `PluginHighlightAnchorService` תישמר כפי שהיא.

enum MarkerAnchorStatus {
  active('active'),

  /// מקום הסימון אינו ודאי: הטקסט נמצא כמה פעמים, או במקום שההקשר שלו
  /// שונה, או שהסימון יובא מהתוסף ועוד לא נבדק מול הספר.
  stale('stale'),

  /// הטקסט לא נמצא בפסקה.
  failed('failed_to_anchor');

  const MarkerAnchorStatus(this.wireName);

  final String wireName;

  bool get needsRepair => this != active;

  static MarkerAnchorStatus fromWire(Object? value) => MarkerAnchorStatus.values
      .firstWhere((status) => status.wireName == value, orElse: () => active);

  /// המצב החמור מבין השניים: סימון שאחד ממקטעיו אבד דורש תיקון.
  MarkerAnchorStatus worst(MarkerAnchorStatus other) =>
      index >= other.index ? this : other;
}

/// חלק של סימון בתוך פסקה אחת. בחירה שחוצה פסקאות נשמרת כסימון אחד עם
/// מקטע לכל פסקה.
class MarkerSegment extends Equatable {
  /// אינדקס השורה בתוכן הספר, מ-0 (כמו `TextBookTab.index`).
  final int sectionIndex;

  /// עוגן בשכבת המקור, ביחידות grapheme של `stripHtml(rawLine)`.
  final PluginTextRangeAnchor range;
  final MarkerAnchorStatus status;

  /// מזהה ההדגשה בתוסף המרקר הישן, לסימון שיובא ממנו. מונע ציור כפול
  /// כשהתוסף עדיין פעיל.
  final String? legacyId;

  const MarkerSegment({
    required this.sectionIndex,
    required this.range,
    this.status = MarkerAnchorStatus.active,
    this.legacyId,
  });

  int get start => range.start.grapheme;
  int get end => range.end.grapheme;

  bool overlaps(MarkerSegment other) =>
      sectionIndex == other.sectionIndex &&
      start < other.end &&
      other.start < end;

  bool sameRangeAs(MarkerSegment other) =>
      sectionIndex == other.sectionIndex &&
      start == other.start &&
      end == other.end;

  MarkerSegment copyWith({
    PluginTextRangeAnchor? range,
    MarkerAnchorStatus? status,
  }) => MarkerSegment(
    sectionIndex: sectionIndex,
    range: range ?? this.range,
    status: status ?? this.status,
    legacyId: legacyId,
  );

  Map<String, dynamic> toJson() => {
    'section': sectionIndex,
    'range': range.toJson(),
    if (status != MarkerAnchorStatus.active) 'status': status.wireName,
    'legacyId': ?legacyId,
  };

  static MarkerSegment fromJson(Map<String, dynamic> json) {
    final section = json['section'];
    final range = json['range'];
    if (section is! int || section < 0 || range is! Map) {
      throw const FormatException('invalid marker segment');
    }
    final legacyId = json['legacyId'];
    return MarkerSegment(
      sectionIndex: section,
      range: PluginTextRangeAnchor.fromJson(Map<String, dynamic>.from(range)),
      status: MarkerAnchorStatus.fromWire(json['status']),
      legacyId: legacyId is String ? legacyId : null,
    );
  }

  @override
  List<Object?> get props => [sectionIndex, range.toJson(), status, legacyId];
}

/// הערה על סימון. התוכן בפורמט של עורך ההערות האישיות, כדי ששני סוגי
/// ההערות ייערכו ויוצגו באותם רכיבים.
class MarkerNote extends Equatable {
  final String content;
  final String plain;
  final PersonalNoteContentFormat format;

  const MarkerNote({
    required this.content,
    required this.plain,
    this.format = PersonalNoteContentFormat.quillDelta,
  });

  @override
  List<Object?> get props => [content, plain, format];
}

class MarkerHighlight extends Equatable {
  static const int maxTags = 12;
  static const int maxTagLength = 40;

  final String id;

  /// כותרת הספר בעת הסימון. משמשת לזיהוי כשאין [bookUid] ולתצוגה.
  final String bookTitle;

  /// מזהה יציב (`PluginBookIdentity.uidOf`) ששורד שינוי כותרת.
  final String? bookUid;

  /// ממוינים לפי פסקה; לפחות מקטע אחד.
  final List<MarkerSegment> segments;

  /// סימון בספר PDF: מקטע לכל עמוד, ו-[MarkerSegment.sectionIndex] הוא מספר
  /// העמוד (מ-1). העוגן הוא בטקסט שחולץ מהעמוד.
  final bool pdf;

  /// הטקסט כפי שהוצג בעת הסימון.
  final String text;

  /// מראה המקום בעת הסימון (`TextBookLoaded.currentTitle`).
  final String? ref;
  final String colorId;

  /// הצבע בעת הסימון; משמש כשהצבע נמחק מהפלטה.
  final String colorHex;
  final MarkerNote? note;
  final List<String> tags;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// עולה בכל שינוי של המשתמש; מזהה עריכה מתנגשת מחלון אחר.
  final int version;

  const MarkerHighlight({
    required this.id,
    required this.bookTitle,
    this.bookUid,
    required this.segments,
    this.pdf = false,
    required this.text,
    this.ref,
    required this.colorId,
    required this.colorHex,
    this.note,
    this.tags = const [],
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
  });

  int get sectionStart => segments.first.sectionIndex;
  int get sectionEnd => segments.last.sectionIndex;

  bool get hasNote => note != null && note!.plain.trim().isNotEmpty;

  MarkerAnchorStatus get status => statusOf(segments);

  /// המצב החמור ביותר מבין המקטעים.
  static MarkerAnchorStatus statusOf(List<MarkerSegment> segments) =>
      segments.map((segment) => segment.status).reduce((a, b) => a.worst(b));

  /// אותו טווח בדיוק — כל המקטעים זהים בפסקה ובגבולות.
  bool sameRangeAs(List<MarkerSegment> other) {
    if (other.length != segments.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (!segments[i].sameRangeAs(other[i])) return false;
    }
    return true;
  }

  bool overlaps(List<MarkerSegment> other) => segments.any(
    (mine) => other.any((theirs) => mine.overlaps(theirs)),
  );

  MarkerHighlight copyWith({
    String? bookTitle,
    List<MarkerSegment>? segments,
    String? text,
    String? ref,
    bool clearRef = false,
    String? colorId,
    String? colorHex,
    MarkerNote? note,
    bool clearNote = false,
    List<String>? tags,
    bool? favorite,
    DateTime? updatedAt,
    int? version,
  }) => MarkerHighlight(
    id: id,
    bookTitle: bookTitle ?? this.bookTitle,
    bookUid: bookUid,
    segments: segments ?? this.segments,
    pdf: pdf,
    text: text ?? this.text,
    ref: clearRef ? null : (ref ?? this.ref),
    colorId: colorId ?? this.colorId,
    colorHex: colorHex ?? this.colorHex,
    note: clearNote ? null : (note ?? this.note),
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookTitle': bookTitle,
    'bookUid': ?bookUid,
    'segments': [for (final segment in segments) segment.toJson()],
    if (pdf) 'pdf': true,
    'text': text,
    'ref': ?ref,
    'colorId': colorId,
    'colorHex': colorHex,
    if (note != null)
      'note': {
        'content': note!.content,
        'plain': note!.plain,
        'format': note!.format.name,
      },
    if (tags.isNotEmpty) 'tags': tags,
    if (favorite) 'favorite': true,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'version': version,
  };

  /// רשומה מגיבוי. זורק [FormatException] על רשומה שאינה תקינה.
  static MarkerHighlight fromJson(Map<String, dynamic> json) {
    String text(String key, {int max = 20000, bool required = true}) {
      final value = json[key];
      if (value is String && value.isNotEmpty) {
        return truncateGraphemes(value, max);
      }
      if (required) throw FormatException('missing $key');
      return '';
    }

    final id = text('id', max: 128);
    final rawSegments = json['segments'];
    if (rawSegments is! List || rawSegments.isEmpty) {
      throw const FormatException('missing segments');
    }
    final segments = [
      for (final raw in rawSegments)
        if (raw is Map)
          MarkerSegment.fromJson(Map<String, dynamic>.from(raw))
        else
          throw const FormatException('invalid segment'),
    ]..sort((a, b) => a.sectionIndex.compareTo(b.sectionIndex));
    final rawNote = json['note'];
    MarkerNote? note;
    if (rawNote is Map && rawNote['content'] is String) {
      note = MarkerNote(
        content: rawNote['content'] as String,
        plain: rawNote['plain'] is String ? rawNote['plain'] as String : '',
        format: rawNote['format'] == PersonalNoteContentFormat.plain.name
            ? PersonalNoteContentFormat.plain
            : PersonalNoteContentFormat.quillDelta,
      );
    }
    final created = DateTime.tryParse(text('createdAt'))?.toUtc();
    if (created == null) throw const FormatException('invalid createdAt');
    final updated =
        DateTime.tryParse(text('updatedAt', required: false))?.toUtc() ??
        created;
    final version = json['version'];
    final bookUid = text('bookUid', max: 2000, required: false);
    final ref = text('ref', max: 1000, required: false);
    return MarkerHighlight(
      id: id,
      bookTitle: text('bookTitle', max: 500),
      bookUid: bookUid.isEmpty ? null : bookUid,
      segments: segments,
      pdf: json['pdf'] == true,
      text: text('text', required: false),
      ref: ref.isEmpty ? null : ref,
      colorId:
          MarkerColor.normalizeId(json['colorId']) ??
          (throw const FormatException('invalid colorId')),
      colorHex:
          MarkerColor.normalizeHex(json['colorHex']) ??
          (throw const FormatException('invalid colorHex')),
      note: note,
      tags: json['tags'] is List
          ? normalizeTags((json['tags'] as List).whereType<String>())
          : const [],
      favorite: json['favorite'] == true,
      createdAt: created,
      updatedAt: updated,
      version: version is int && version > 0 ? version : 1,
    );
  }

  /// תגיות ללא כפילויות (לפי צורה מנורמלת), מקוצרות ומוגבלות בכמות.
  static List<String> normalizeTags(Iterable<String> raw) {
    final result = <String>[];
    final keys = <String>{};
    for (final value in raw) {
      for (final part in value.split(RegExp('[,،;]'))) {
        var tag = part.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (tag.isEmpty) continue;
        tag = truncateGraphemes(tag, maxTagLength);
        if (!keys.add(tagKey(tag))) continue;
        result.add(tag);
        if (result.length == maxTags) return result;
      }
    }
    return result;
  }

  /// מפתח השוואה לתגית: בלי ניקוד, טעמים ורישיות.
  static String tagKey(String tag) =>
      tag.replaceAll(RegExp('[\u0591-\u05C7]'), '').trim().toLowerCase();

  @override
  List<Object?> get props => [
    pdf,
    id,
    bookTitle,
    bookUid,
    segments,
    text,
    ref,
    colorId,
    colorHex,
    note,
    tags,
    favorite,
    createdAt,
    updatedAt,
    version,
  ];
}
