import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_highlight_anchor_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

class PluginHighlightException implements Exception {
  final String code;
  final String message;

  const PluginHighlightException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// מאגר זמני ברמת ה-Host. התוסף אחראי להתמדה ולשחזור לאחר reload.
///
/// המפתוח הפנימי הוא per-instance — שני טאבים של אותו תוסף אינם מוחקים זה
/// את הסימונים של זה; שכבת הציור ([getAllHighlights]) מאחדת עותקים זהים.
class PluginHighlightRegistry extends ChangeNotifier {
  static final PluginHighlightRegistry instance = PluginHighlightRegistry._();
  PluginHighlightRegistry._()
    : _anchorService = const PluginHighlightAnchorService(),
      _isInstanceVisible = _dispatcherVisibility;

  @visibleForTesting
  PluginHighlightRegistry.forTesting({
    this._anchorService = const PluginHighlightAnchorService(),
    bool Function(PluginInstanceKey key)? isInstanceVisible,
  }) : _isInstanceVisible = isInstanceVisible ?? _neverVisible;

  static bool _dispatcherVisibility(PluginInstanceKey key) =>
      PluginRuntimeDispatcher.instance.isInstanceVisible(key);

  static bool _neverVisible(PluginInstanceKey key) => false;

  final PluginHighlightAnchorService _anchorService;

  /// העדפת עותק של מופע גלוי בציור — נשאל מהדיספצ'ר (מקור המצב היחיד).
  final bool Function(PluginInstanceKey key) _isInstanceVisible;
  final Map<PluginInstanceKey, Map<String, PluginHighlight>> _recordsByOwner =
      {};
  final Map<
    _PluginHighlightSectionKey,
    Map<_PluginHighlightRecordKey, PluginHighlight>
  >
  _recordsBySection = {};
  int _idCounter = 0;
  int _revision = 0;

  /// מונה מוטציות. מאפשר לצרכנים לזהות ב-O(1) שאף highlight לא השתנה,
  /// במקום להשוות רשומות בכל פריים.
  int get revision => _revision;

  @override
  void notifyListeners() {
    _revision++;
    super.notifyListeners();
  }

  PluginHighlight setHighlight({
    required String ownerPluginId,
    required Map<String, dynamic> payload,
    String ownerInstanceId = PluginInstanceIds.defaultForeground,
    DateTime? now,
  }) {
    if (payload.containsKey('pluginId') ||
        payload.containsKey('ownerPluginId')) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'plugin ownership is assigned by the Host',
      );
    }
    _rejectUnknownFields(
      payload,
      const {
        'highlightId',
        'bookId',
        'bookUid',
        'sectionIndex',
        'currentRef',
        'range',
        'style',
        'metadata',
      },
      'setHighlight',
    );
    final bookId = _requiredString(payload, 'bookId', maxLength: 500);
    final bookUid = _optionalText(payload['bookUid'], maxLength: 500);
    final sectionIndex = payload['sectionIndex'];
    if (sectionIndex is! int || sectionIndex < 0) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'sectionIndex must be a non-negative integer',
      );
    }
    final rangeJson = _requiredObject(payload, 'range');
    final PluginTextRangeAnchor range;
    try {
      range = PluginTextRangeAnchor.fromJson(rangeJson);
    } on FormatException catch (error) {
      throw PluginHighlightException('error.invalid_params', error.message);
    }
    if (range.layer != 'source' || range.start.grapheme >= range.end.grapheme) {
      throw const PluginHighlightException(
        'error.unsupported_layer',
        'highlight range must be a non-empty source range',
      );
    }

    final style = _parseStyle(_requiredObject(payload, 'style'));
    final metadata = _parseMetadata(
      payload['metadata'] == null
          ? const <String, dynamic>{}
          : _requiredObject(payload, 'metadata'),
    );
    final timestamp = now ?? DateTime.now().toUtc();
    final requestedId = payload['highlightId'];
    final highlightId = requestedId == null
        ? _generateId(ownerPluginId, timestamp)
        : _validateId(requestedId);
    final ownerKey = (pluginId: ownerPluginId, instanceId: ownerInstanceId);
    final existing = _recordsByOwner[ownerKey]?[highlightId];

    final record = PluginHighlight(
      highlightId: highlightId,
      ownerPluginId: ownerPluginId,
      bookId: bookId,
      bookUid: bookUid == null || bookUid.isEmpty ? null : bookUid,
      sectionIndex: sectionIndex,
      currentRef: _optionalText(payload['currentRef'], maxLength: 500),
      range: range,
      style: style,
      metadata: metadata,
      version: (existing?.version ?? 0) + 1,
      createdAt: existing?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    _store(ownerKey, record);
    notifyListeners();
    return record;
  }

  PluginHighlight setLegacyHighlight({
    required String ownerPluginId,
    required String bookId,
    required int sectionIndex,
    String? bookUid,
    String ownerInstanceId = PluginInstanceIds.defaultForeground,
    String? color,
    String? label,
    DateTime? now,
  }) {
    if (bookId.isEmpty || bookId.length > 500 || sectionIndex < 0) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'bookId and a non-negative sectionIndex are required',
      );
    }
    const emptyContext = PluginAnchorContext(
      raw: '',
      normalized: '',
      maxGraphemes: 30,
      actualGraphemes: 0,
      truncatedAtBoundary: true,
    );
    const legacyRange = PluginTextRangeAnchor(
      layer: 'source',
      start: PluginTextOffset(grapheme: 0, codePoint: 0, utf16: 0),
      end: PluginTextOffset(grapheme: 1, codePoint: 1, utf16: 1),
      exactText: '',
      beforeText: emptyContext,
      afterText: emptyContext,
      occurrenceIndexInSection: 0,
      occurrenceCountInSection: 0,
    );
    final style = _parseStyle({
      'backgroundColor': color ?? '#FFFF00',
      'markerMode': 'line-marker',
    });
    final metadata = _parseMetadata({'note': ?label});
    final ownerKey = (pluginId: ownerPluginId, instanceId: ownerInstanceId);
    final records = _recordsByOwner.putIfAbsent(ownerKey, () => {});
    PluginHighlight? existing;
    for (final record in records.values) {
      if (record.bookId == bookId &&
          record.sectionIndex == sectionIndex &&
          record.range.exactText.isEmpty) {
        existing = record;
        break;
      }
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final record = PluginHighlight(
      highlightId:
          existing?.highlightId ?? _generateId(ownerPluginId, timestamp),
      ownerPluginId: ownerPluginId,
      bookId: bookId,
      bookUid: (bookUid != null && bookUid.isNotEmpty)
          ? bookUid
          : existing?.bookUid,
      sectionIndex: sectionIndex,
      range: legacyRange,
      style: style,
      metadata: metadata,
      version: (existing?.version ?? 0) + 1,
      createdAt: existing?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    _store(ownerKey, record);
    notifyListeners();
    return record;
  }

  PluginHighlight updateHighlight({
    required String ownerPluginId,
    required Map<String, dynamic> payload,
    String ownerInstanceId = PluginInstanceIds.defaultForeground,
    DateTime? now,
  }) {
    if (payload.containsKey('pluginId') ||
        payload.containsKey('ownerPluginId')) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'plugin ownership is assigned by the Host',
      );
    }
    const allowedFields = {
      'highlightId',
      'expectedVersion',
      'expectedEtag',
      'style',
      'metadata',
    };
    _rejectUnknownFields(payload, allowedFields, 'updateHighlight');
    final highlightId = _validateId(payload['highlightId']);
    final ownerKey = (pluginId: ownerPluginId, instanceId: ownerInstanceId);
    final existing = _recordsByOwner[ownerKey]?[highlightId];
    if (existing == null) {
      throw const PluginHighlightException(
        'error.highlight_not_found',
        'highlight was not found',
      );
    }

    _validateExpected(
      existing,
      expectedVersion: payload['expectedVersion'],
      expectedEtag: payload['expectedEtag'],
    );
    if (!payload.containsKey('style') && !payload.containsKey('metadata')) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'style or metadata patch is required',
      );
    }

    var style = existing.style;
    if (payload.containsKey('style')) {
      final patch = _requiredObject(payload, 'style');
      _rejectUnknownFields(patch, const {
        'backgroundColor',
        'foregroundColor',
        'opacity',
        'underline',
        'underlineColor',
        'borderRadius',
        'markerMode',
        'priority',
      }, 'style');
      style = _parseStyle({...existing.style.toJson(), ...patch});
    }

    var metadata = existing.metadata;
    if (payload.containsKey('metadata')) {
      final patch = _requiredObject(payload, 'metadata');
      _rejectUnknownFields(patch, const {'note', 'tags', 'source'}, 'metadata');
      metadata = _parseMetadata({...existing.metadata.toJson(), ...patch});
    }

    final updated = PluginHighlight(
      highlightId: existing.highlightId,
      ownerPluginId: existing.ownerPluginId,
      bookId: existing.bookId,
      bookUid: existing.bookUid,
      sectionIndex: existing.sectionIndex,
      currentRef: existing.currentRef,
      range: existing.range,
      style: style,
      metadata: metadata,
      status: existing.status,
      version: existing.version + 1,
      createdAt: existing.createdAt,
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
    _store(ownerKey, updated);
    notifyListeners();
    return updated;
  }

  List<PluginHighlight> getHighlights({
    required String ownerPluginId,
    String ownerInstanceId = PluginInstanceIds.defaultForeground,
    String? bookId,
    int? sectionIndex,
    bool includeStale = false,
  }) {
    final records =
        _recordsByOwner[(
              pluginId: ownerPluginId,
              instanceId: ownerInstanceId,
            )]
            ?.values ??
        const [];
    final result = records.where((record) {
      if (bookId != null && record.bookId != bookId) return false;
      if (sectionIndex != null && record.sectionIndex != sectionIndex) {
        return false;
      }
      return includeStale || record.status == 'active';
    }).toList();
    result.sort((a, b) {
      final section = a.sectionIndex.compareTo(b.sectionIndex);
      if (section != 0) return section;
      final priority = b.style.priority.compareTo(a.style.priority);
      return priority != 0 ? priority : a.createdAt.compareTo(b.createdAt);
    });
    return List.unmodifiable(result);
  }

  /// לשימוש פנימי של מנוע הציור בלבד; אינו חשוף ל-Plugin Bridge.
  ///
  /// שני מופעים של אותו תוסף טוענים את אותן הדגשות מהאחסון המשותף —
  /// עותקים זהים ב-(pluginId, highlightId) מצוירים פעם אחת, בעדיפות
  /// לעותק של מופע גלוי.
  List<PluginHighlight> getAllHighlights({
    required String bookId,
    required int sectionIndex,
    String? bookUid,
  }) {
    // נשאלים שני המפתחות: הכותרת (הדגשות ישנות) והמזהה היציב (הדגשות חדשות).
    // עותק זהה שנרשם תחת שניהם מסונן ב-dedup לפי (ownerPluginId, highlightId).
    final uid = (bookUid != null && bookUid.isNotEmpty) ? bookUid : null;
    final bookKeys = <String>{bookId, ?uid};
    final records = <_PluginHighlightRecordKey, PluginHighlight>{
      for (final key in bookKeys)
        ...?_recordsBySection[(bookId: key, sectionIndex: sectionIndex)],
    };
    if (records.isEmpty) return const [];
    final deduped = <(String, String), PluginHighlight>{};
    final fromVisibleOwner = <(String, String)>{};
    for (final entry in records.entries) {
      final record = entry.value;
      if (record.status != 'active') continue;
      // כשנמסר bookUid — הדגשה של ספר אחר (uid שונה) שהגיעה דרך מפתח הכותרת
      // המשותף מסוננת החוצה; הדגשה ישנה ללא uid נשמרת (best-effort, לא ניתן
      // לפתור את הכותרת הדו-משמעית שלה).
      if (uid != null && record.bookUid != null && record.bookUid != uid) {
        continue;
      }
      final dedupeKey = (record.ownerPluginId, record.highlightId);
      final visible = _isInstanceVisible((
        pluginId: entry.key.ownerPluginId,
        instanceId: entry.key.ownerInstanceId,
      ));
      if (deduped.containsKey(dedupeKey) &&
          (fromVisibleOwner.contains(dedupeKey) || !visible)) {
        continue;
      }
      deduped[dedupeKey] = record;
      if (visible) fromVisibleOwner.add(dedupeKey);
    }
    final result = deduped.values.toList()
      ..sort((a, b) {
        final priority = b.style.priority.compareTo(a.style.priority);
        return priority != 0 ? priority : a.createdAt.compareTo(b.createdAt);
      });
    return List.unmodifiable(result);
  }

  List<PluginHighlight> reanchorSection({
    required String bookId,
    required int sectionIndex,
    required String sourceText,
    String? bookUid,
    DateTime? now,
  }) {
    final changed = <PluginHighlight>[];
    final timestamp = (now ?? DateTime.now()).toUtc();
    final uid = (bookUid != null && bookUid.isNotEmpty) ? bookUid : null;
    for (final ownerEntry in _recordsByOwner.entries.toList(growable: false)) {
      final records = ownerEntry.value;
      for (final entry in records.entries.toList(growable: false)) {
        final existing = entry.value;
        // הדגשה של ספר אחר בעל אותה כותרת נפסלת לפי ה-uid, אחרת היא הייתה
        // מעוגנת מחדש מול טקסט זר ומסומנת ככושלת.
        final bookMatches =
            (existing.bookId == bookId ||
                (uid != null && existing.bookUid == uid)) &&
            !(uid != null &&
                existing.bookUid != null &&
                existing.bookUid != uid);
        if (!bookMatches ||
            existing.sectionIndex != sectionIndex ||
            existing.range.exactText.isEmpty) {
          continue;
        }
        PluginHighlightAnchorResult result;
        try {
          result = _anchorService.resolve(
            anchor: existing.range,
            sourceText: sourceText,
          );
        } on FormatException {
          result = const PluginHighlightAnchorResult(
            status: 'failed_to_anchor',
            range: null,
            strategy: 'invalid-normalization-profile',
            confidence: 0,
          );
        }
        final nextRange = result.range ?? existing.range;
        if (existing.status == result.status &&
            jsonEncode(existing.range.toJson()) ==
                jsonEncode(nextRange.toJson())) {
          continue;
        }
        final updated = PluginHighlight(
          highlightId: existing.highlightId,
          ownerPluginId: existing.ownerPluginId,
          bookId: existing.bookId,
          bookUid: existing.bookUid,
          sectionIndex: existing.sectionIndex,
          currentRef: existing.currentRef,
          range: nextRange,
          style: existing.style,
          metadata: existing.metadata,
          status: result.status,
          version: existing.version + 1,
          createdAt: existing.createdAt,
          updatedAt: timestamp,
        );
        _store(ownerEntry.key, updated);
        changed.add(updated);
      }
    }
    if (changed.isNotEmpty) notifyListeners();
    return List.unmodifiable(changed);
  }

  bool clearHighlight({
    required String ownerPluginId,
    required String highlightId,
    String ownerInstanceId = PluginInstanceIds.defaultForeground,
    Object? expectedVersion,
    Object? expectedEtag,
  }) {
    final ownerKey = (pluginId: ownerPluginId, instanceId: ownerInstanceId);
    final existing = _recordsByOwner[ownerKey]?[highlightId];
    if (existing == null) return false;
    _validateExpected(
      existing,
      expectedVersion: expectedVersion,
      expectedEtag: expectedEtag,
    );
    final removed = _remove(ownerKey, highlightId) != null;
    if (removed) notifyListeners();
    return removed;
  }

  int clearAll({
    required String ownerPluginId,
    String ownerInstanceId = PluginInstanceIds.defaultForeground,
    String? bookId,
    int? sectionIndex,
  }) {
    final ownerKey = (pluginId: ownerPluginId, instanceId: ownerInstanceId);
    final records = _recordsByOwner[ownerKey];
    if (records == null) return 0;
    final ids = records.values
        .where(
          (record) =>
              (bookId == null || record.bookId == bookId) &&
              (sectionIndex == null || record.sectionIndex == sectionIndex),
        )
        .map((record) => record.highlightId)
        .toList();
    for (final id in ids) {
      _remove(ownerKey, id);
    }
    if (ids.isNotEmpty) notifyListeners();
    return ids.length;
  }

  /// ניקוי מלא ברמת התוסף (הסרה/טעינה מחדש) — כל המופעים.
  void removePlugin(String pluginId) {
    final ownerKeys = _recordsByOwner.keys
        .where((key) => key.pluginId == pluginId)
        .toList(growable: false);
    if (ownerKeys.isEmpty) return;
    for (final ownerKey in ownerKeys) {
      _removeOwner(ownerKey);
    }
    notifyListeners();
  }

  /// מסיר רק את רישומי המופע [key] (סגירת טאב אחד) — עותק של מופע אחר
  /// לאותה הדגשה נחשף אוטומטית בציור דרך ה-dedup.
  void removeInstance(PluginInstanceKey key) {
    if (!_recordsByOwner.containsKey(key)) return;
    _removeOwner(key);
    notifyListeners();
  }

  void _removeOwner(PluginInstanceKey ownerKey) {
    final records = _recordsByOwner.remove(ownerKey);
    if (records == null) return;
    for (final record in records.values) {
      _removeFromSection(ownerKey, record);
    }
  }

  /// מפתחות הספר שתחתם הרשומה נרשמת במפת הסקציות: תמיד הכותרת ([bookId]),
  /// ובנוסף ה-[bookUid] כשקיים. כך הדגשה חדשה נמצאת גם דרך המזהה היציב
  /// וגם דרך הכותרת (migrate-on-read), והדגשה ישנה נמצאת דרך הכותרת כמקודם.
  List<String> _sectionBookKeys(PluginHighlight record) {
    final uid = record.bookUid;
    if (uid != null && uid.isNotEmpty && uid != record.bookId) {
      return [record.bookId, uid];
    }
    return [record.bookId];
  }

  void _store(PluginInstanceKey ownerKey, PluginHighlight record) {
    final records = _recordsByOwner.putIfAbsent(ownerKey, () => {});
    final previous = records[record.highlightId];
    if (previous != null) _removeFromSection(ownerKey, previous);
    records[record.highlightId] = record;
    final recordKey = (
      ownerPluginId: ownerKey.pluginId,
      ownerInstanceId: ownerKey.instanceId,
      highlightId: record.highlightId,
    );
    for (final bookKey in _sectionBookKeys(record)) {
      _recordsBySection.putIfAbsent(
        (bookId: bookKey, sectionIndex: record.sectionIndex),
        () => {},
      )[recordKey] = record;
    }
  }

  PluginHighlight? _remove(PluginInstanceKey ownerKey, String highlightId) {
    final records = _recordsByOwner[ownerKey];
    final removed = records?.remove(highlightId);
    if (removed == null) return null;
    if (records!.isEmpty) _recordsByOwner.remove(ownerKey);
    _removeFromSection(ownerKey, removed);
    return removed;
  }

  void _removeFromSection(PluginInstanceKey ownerKey, PluginHighlight record) {
    final recordKey = (
      ownerPluginId: ownerKey.pluginId,
      ownerInstanceId: ownerKey.instanceId,
      highlightId: record.highlightId,
    );
    for (final bookKey in _sectionBookKeys(record)) {
      final sectionKey = (bookId: bookKey, sectionIndex: record.sectionIndex);
      final records = _recordsBySection[sectionKey];
      records?.remove(recordKey);
      if (records?.isEmpty ?? false) _recordsBySection.remove(sectionKey);
    }
  }

  String _generateId(String pluginId, DateTime timestamp) {
    _idCounter++;
    return sha256
        .convert(
          utf8.encode(
            '$pluginId:${timestamp.microsecondsSinceEpoch}:$_idCounter',
          ),
        )
        .toString()
        .substring(0, 24);
  }

  String _validateId(Object value) {
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(value)) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'highlightId contains unsupported characters',
      );
    }
    return value;
  }

  PluginHighlightStyle _parseStyle(Map<String, dynamic> json) {
    _rejectUnknownFields(
      json,
      const {
        'backgroundColor',
        'foregroundColor',
        'opacity',
        'underline',
        'underlineColor',
        'borderRadius',
        'markerMode',
        'priority',
      },
      'style',
    );
    final background = _validColor(json['backgroundColor'], required: true)!;
    final foreground = _validColor(json['foregroundColor']);
    final underlineColor = _validColor(json['underlineColor']);
    final opacityValue = json['opacity'];
    final borderRadiusValue = json['borderRadius'];
    if ((opacityValue != null && opacityValue is! num) ||
        (borderRadiusValue != null && borderRadiusValue is! num) ||
        (json['underline'] != null && json['underline'] is! bool)) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'highlight style contains an invalid value type',
      );
    }
    final opacity = (opacityValue as num?)?.toDouble() ?? 1;
    final borderRadius = (borderRadiusValue as num?)?.toDouble() ?? 0;
    final priority = json['priority'] ?? 0;
    final markerMode = json['markerMode'] ?? 'text-background';
    if (opacity < 0 || opacity > 1 || borderRadius < 0 || borderRadius > 32) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'opacity or borderRadius is out of range',
      );
    }
    if (priority is! int || priority < -1000 || priority > 1000) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'priority must be an integer between -1000 and 1000',
      );
    }
    const modes = {'text-background', 'line-marker', 'box', 'underline'};
    if (markerMode is! String || !modes.contains(markerMode)) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'unsupported markerMode',
      );
    }
    return PluginHighlightStyle(
      backgroundColor: background,
      foregroundColor: foreground,
      opacity: opacity,
      underline: json['underline'] == true,
      underlineColor: underlineColor,
      borderRadius: borderRadius,
      markerMode: markerMode,
      priority: priority,
    );
  }

  PluginHighlightMetadata _parseMetadata(Map<String, dynamic> json) {
    _rejectUnknownFields(json, const {'note', 'tags', 'source'}, 'metadata');
    final note = _optionalText(json['note'], maxLength: 4000);
    final source = json['source'];
    const sources = {'manual', 'ai', 'import', 'sync'};
    if (source != null && (source is! String || !sources.contains(source))) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'unsupported highlight source',
      );
    }
    final tagsValue = json['tags'];
    if (tagsValue != null && tagsValue is! List) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'tags must be an array',
      );
    }
    final tags = <String>[];
    for (final tag in (tagsValue as List?) ?? const []) {
      final value = _optionalText(tag, maxLength: 64);
      if (value == null || value.isEmpty || tags.length >= 20) {
        throw const PluginHighlightException(
          'error.invalid_params',
          'tags must contain 1-20 non-empty text values',
        );
      }
      tags.add(value);
    }
    return PluginHighlightMetadata(
      note: note,
      tags: tags,
      source: source as String?,
    );
  }

  String? _validColor(Object? value, {bool required = false}) {
    if (value == null && !required) return null;
    if (value is! String ||
        !RegExp(r'^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$').hasMatch(value)) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'colors must use #RRGGBB or #RRGGBBAA',
      );
    }
    return value;
  }

  String _requiredString(
    Map<String, dynamic> json,
    String key, {
    required int maxLength,
  }) {
    final value = _optionalText(json[key], maxLength: maxLength);
    if (value == null || value.isEmpty) {
      throw PluginHighlightException(
        'error.invalid_params',
        '$key is required',
      );
    }
    return value;
  }

  Map<String, dynamic> _requiredObject(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! Map) {
      throw PluginHighlightException(
        'error.invalid_params',
        '$key is required',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  String? _optionalText(Object? value, {required int maxLength}) {
    if (value == null) return null;
    if (value is! String || value.length > maxLength) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'text field has an invalid type or length',
      );
    }
    if (RegExp(
      r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
    ).hasMatch(value)) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'text field contains unsupported control characters',
      );
    }
    return value;
  }

  void _rejectUnknownFields(
    Map<String, dynamic> json,
    Set<String> allowed,
    String objectName,
  ) {
    final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw PluginHighlightException(
        'error.invalid_params',
        '$objectName contains unsupported fields: ${unknown.join(', ')}',
      );
    }
  }

  void _validateExpected(
    PluginHighlight existing, {
    Object? expectedVersion,
    Object? expectedEtag,
  }) {
    if (expectedVersion != null &&
        (expectedVersion is! int || expectedVersion < 1)) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'expectedVersion must be a positive integer',
      );
    }
    if (expectedEtag != null && expectedEtag is! String) {
      throw const PluginHighlightException(
        'error.invalid_params',
        'expectedEtag must be a string',
      );
    }
    if ((expectedVersion is int && expectedVersion != existing.version) ||
        (expectedEtag is String && expectedEtag != existing.etag)) {
      throw const PluginHighlightException(
        'error.conflict',
        'highlight version has changed',
      );
    }
  }
}

typedef _PluginHighlightSectionKey = ({String bookId, int sectionIndex});
typedef _PluginHighlightRecordKey = ({
  String ownerPluginId,
  String ownerInstanceId,
  String highlightId,
});
