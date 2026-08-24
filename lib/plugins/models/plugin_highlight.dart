import 'package:otzaria/plugins/models/plugin_reader_selection.dart';

class PluginHighlightStyle {
  final String backgroundColor;
  final String? foregroundColor;
  final double opacity;
  final bool underline;
  final String? underlineColor;
  final double borderRadius;
  final String markerMode;
  final int priority;

  const PluginHighlightStyle({
    required this.backgroundColor,
    this.foregroundColor,
    this.opacity = 1,
    this.underline = false,
    this.underlineColor,
    this.borderRadius = 0,
    this.markerMode = 'text-background',
    this.priority = 0,
  });

  Map<String, dynamic> toJson() => {
    'backgroundColor': backgroundColor,
    if (foregroundColor != null) 'foregroundColor': foregroundColor,
    'opacity': opacity,
    'underline': underline,
    if (underlineColor != null) 'underlineColor': underlineColor,
    'borderRadius': borderRadius,
    'markerMode': markerMode,
    'priority': priority,
  };
}

class PluginHighlightMetadata {
  final String? note;
  final List<String> tags;
  final String? source;

  const PluginHighlightMetadata({this.note, this.tags = const [], this.source});

  Map<String, dynamic> toJson() => {
    if (note != null) 'note': note,
    if (tags.isNotEmpty) 'tags': tags,
    if (source != null) 'source': source,
  };
}

class PluginHighlight {
  final String highlightId;
  final String ownerPluginId;
  final String bookId;

  /// מזהה ספר יציב (אופציונלי). קיים בהדגשות שנשמרו לאחר תמיכת ה-SDK בו;
  /// הדגשות ישנות נושאות רק [bookId] (כותרת) ונמצאות דרך מפתח הכותרת.
  final String? bookUid;
  final int sectionIndex;
  final String? currentRef;
  final PluginTextRangeAnchor range;
  final PluginHighlightStyle style;
  final PluginHighlightMetadata metadata;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PluginHighlight({
    required this.highlightId,
    required this.ownerPluginId,
    required this.bookId,
    this.bookUid,
    required this.sectionIndex,
    this.currentRef,
    required this.range,
    required this.style,
    this.metadata = const PluginHighlightMetadata(),
    this.status = 'active',
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  String get etag => '"$highlightId-v$version"';

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'highlightId': highlightId,
    'ownerPluginId': ownerPluginId,
    'pluginId': ownerPluginId,
    'bookId': bookId,
    if (bookUid != null) 'bookUid': bookUid,
    'sectionIndex': sectionIndex,
    'index': sectionIndex,
    'color': style.backgroundColor,
    if (metadata.note != null) 'label': metadata.note,
    'currentRef': currentRef,
    'range': range.toJson(),
    'style': style.toJson(),
    'metadata': metadata.toJson(),
    'status': status,
    'version': version,
    'etag': etag,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}
