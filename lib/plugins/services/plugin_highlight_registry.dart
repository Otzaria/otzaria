import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_highlight_anchor_service.dart';

class PluginHighlightException implements Exception {
  final String code;
  final String message;

  const PluginHighlightException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// מאגר זמני ברמת ה-Host. התוסף אחראי להתמדה ולשחזור לאחר reload.
class PluginHighlightRegistry extends ChangeNotifier {
  static final PluginHighlightRegistry instance = PluginHighlightRegistry._();
  PluginHighlightRegistry._()
    : _anchorService = const PluginHighlightAnchorService();

  @visibleForTesting
  PluginHighlightRegistry.forTesting({
    this._anchorService = const PluginHighlightAnchorService(),
  });

  final PluginHighlightAnchorService _anchorService;
  final Map<String, Map<String, PluginHighlight>> _recordsByPlugin = {};
  int _idCounter = 0;

  PluginHighlight setHighlight({
    required String ownerPluginId,
    required Map<String, dynamic> payload,
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
        'sectionIndex',
        'currentRef',
        'range',
        'style',
        'metadata',
      },
      'setHighlight',
    );
    final bookId = _requiredString(payload, 'bookId', maxLength: 500);
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
    final ownRecords = _recordsByPlugin.putIfAbsent(ownerPluginId, () => {});
    if (ownRecords.containsKey(highlightId)) {
      throw const PluginHighlightException(
        'error.conflict',
        'highlightId already exists for this plugin',
      );
    }

    final record = PluginHighlight(
      highlightId: highlightId,
      ownerPluginId: ownerPluginId,
      bookId: bookId,
      sectionIndex: sectionIndex,
      currentRef: _optionalText(payload['currentRef'], maxLength: 500),
      range: range,
      style: style,
      metadata: metadata,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    ownRecords[highlightId] = record;
    notifyListeners();
    return record;
  }

  PluginHighlight setLegacyHighlight({
    required String ownerPluginId,
    required String bookId,
    required int sectionIndex,
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
    final records = _recordsByPlugin.putIfAbsent(ownerPluginId, () => {});
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
      sectionIndex: sectionIndex,
      range: legacyRange,
      style: style,
      metadata: metadata,
      version: (existing?.version ?? 0) + 1,
      createdAt: existing?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    records[record.highlightId] = record;
    notifyListeners();
    return record;
  }

  PluginHighlight updateHighlight({
    required String ownerPluginId,
    required Map<String, dynamic> payload,
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
    final existing = _recordsByPlugin[ownerPluginId]?[highlightId];
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
    _recordsByPlugin[ownerPluginId]![highlightId] = updated;
    notifyListeners();
    return updated;
  }

  List<PluginHighlight> getHighlights({
    required String ownerPluginId,
    String? bookId,
    int? sectionIndex,
    bool includeStale = false,
  }) {
    final records = _recordsByPlugin[ownerPluginId]?.values ?? const [];
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
  List<PluginHighlight> getAllHighlights({
    required String bookId,
    required int sectionIndex,
  }) {
    final result =
        _recordsByPlugin.values
            .expand((records) => records.values)
            .where(
              (record) =>
                  record.bookId == bookId &&
                  record.sectionIndex == sectionIndex &&
                  record.status == 'active',
            )
            .toList()
          ..sort((a, b) {
            final priority = b.style.priority.compareTo(a.style.priority);
            return priority != 0
                ? priority
                : a.createdAt.compareTo(b.createdAt);
          });
    return List.unmodifiable(result);
  }

  List<PluginHighlight> reanchorSection({
    required String bookId,
    required int sectionIndex,
    required String sourceText,
    DateTime? now,
  }) {
    final changed = <PluginHighlight>[];
    final timestamp = (now ?? DateTime.now()).toUtc();
    for (final records in _recordsByPlugin.values) {
      for (final entry in records.entries.toList(growable: false)) {
        final existing = entry.value;
        if (existing.bookId != bookId ||
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
        records[entry.key] = updated;
        changed.add(updated);
      }
    }
    if (changed.isNotEmpty) notifyListeners();
    return List.unmodifiable(changed);
  }

  bool clearHighlight({
    required String ownerPluginId,
    required String highlightId,
    Object? expectedVersion,
    Object? expectedEtag,
  }) {
    final records = _recordsByPlugin[ownerPluginId];
    final existing = records?[highlightId];
    if (existing == null) return false;
    _validateExpected(
      existing,
      expectedVersion: expectedVersion,
      expectedEtag: expectedEtag,
    );
    final removed = records!.remove(highlightId) != null;
    if (removed) notifyListeners();
    return removed;
  }

  int clearAll({
    required String ownerPluginId,
    String? bookId,
    int? sectionIndex,
  }) {
    final records = _recordsByPlugin[ownerPluginId];
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
      records.remove(id);
    }
    if (records.isEmpty) _recordsByPlugin.remove(ownerPluginId);
    if (ids.isNotEmpty) notifyListeners();
    return ids.length;
  }

  void removePlugin(String pluginId) {
    if (_recordsByPlugin.remove(pluginId) != null) notifyListeners();
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
