import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

typedef ReaderSectionChangeDispatcher =
    Future<void> Function(String topic, Map<String, dynamic> payload);

class ReaderSectionContentTracker {
  static ReaderSectionContentTracker _instance =
      ReaderSectionContentTracker._();

  static ReaderSectionContentTracker get instance => _instance;

  @visibleForTesting
  static set instance(ReaderSectionContentTracker value) => _instance = value;

  ReaderSectionContentTracker._()
    : _dispatchEvent = _dispatchSectionContentChanged,
      maxSnapshots = 2000;

  ReaderSectionContentTracker.forTesting({
    required this._dispatchEvent,
    this.maxSnapshots = 2000,
  }) : assert(maxSnapshots > 0);

  final ReaderSectionChangeDispatcher _dispatchEvent;
  final int maxSnapshots;
  final Map<_SectionKey, _SectionSnapshot> _snapshots = {};

  Future<PluginSectionContentChange?> recordSnapshot({
    required String bookId,
    required int sectionIndex,
    required String sourceText,
    String? renderedText,
    Object? renderingSignature,
    String? reason,
    int? bookDbId,
    String? bookType,
    String? bookSource,
  }) async {
    if (bookId.isEmpty || sectionIndex < 0) {
      throw ArgumentError(
        'bookId and a non-negative sectionIndex are required',
      );
    }
    _validateReason(reason);

    final key = (
      bookId: bookId,
      bookDbId: bookDbId,
      bookType: bookType,
      bookSource: bookSource,
      sectionIndex: sectionIndex,
    );
    final current = (
      sourceTextHash: _hash(sourceText),
      renderedTextHash: renderedText == null ? null : _hash(renderedText),
      renderingSignature: renderingSignature,
    );
    final previous = _snapshots.remove(key);
    _snapshots[key] = current;
    _trimCache();

    if (previous == null || previous == current) return null;
    final sourceChanged = previous.sourceTextHash != current.sourceTextHash;
    final change = PluginSectionContentChange(
      bookId: bookId,
      bookDbId: bookDbId,
      bookType: bookType,
      bookSource: bookSource,
      sectionIndex: sectionIndex,
      oldSourceTextHash: previous.sourceTextHash,
      newSourceTextHash: current.sourceTextHash,
      oldRenderedTextHash: previous.renderedTextHash,
      newRenderedTextHash: current.renderedTextHash,
      changeType: sourceChanged ? 'source-content' : 'rendering-only',
      reason: reason ?? (sourceChanged ? 'book-updated' : 'settings-changed'),
    );
    await _dispatchEvent('reader.sectionContentChanged', change.toJson());
    return change;
  }

  /// מוחק את כל ה-snapshots של ספר.
  ///
  /// אם [bookDbId] או [bookType] מסופקים — מוחק רק entries שתואמות גם אותם.
  /// ללא שניהם — מוחק לפי [bookId] בלבד (תאימות לאחור).
  void forgetBook(String bookId, {int? bookDbId, String? bookType}) {
    _snapshots.removeWhere((key, _) {
      if (key.bookId != bookId) return false;
      if (bookDbId != null && key.bookDbId != bookDbId) return false;
      if (bookType != null && key.bookType != bookType) return false;
      return true;
    });
  }

  void clear() => _snapshots.clear();

  void _trimCache() {
    while (_snapshots.length > maxSnapshots) {
      _snapshots.remove(_snapshots.keys.first);
    }
  }

  static String _hash(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static void _validateReason(String? reason) {
    const reasons = {
      'book-updated',
      'settings-changed',
      'nikud-toggle',
      'teamim-toggle',
      'font-render-change',
      'name-substitution',
      'layout-change',
    };
    if (reason != null && !reasons.contains(reason)) {
      throw ArgumentError.value(reason, 'reason', 'unsupported reason');
    }
  }
}

class PluginSectionContentChange {
  final String bookId;
  final int? bookDbId;
  final String? bookType;
  final String? bookSource;
  final int sectionIndex;
  final String? oldSourceTextHash;
  final String newSourceTextHash;
  final String? oldRenderedTextHash;
  final String? newRenderedTextHash;
  final String changeType;
  final String? reason;

  const PluginSectionContentChange({
    required this.bookId,
    this.bookDbId,
    this.bookType,
    this.bookSource,
    required this.sectionIndex,
    this.oldSourceTextHash,
    required this.newSourceTextHash,
    this.oldRenderedTextHash,
    this.newRenderedTextHash,
    required this.changeType,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'bookId': bookId,
    if (bookDbId != null) 'id': bookDbId,
    if (bookType != null) 'type': bookType,
    if (bookSource != null) 'source': bookSource,
    'sectionIndex': sectionIndex,
    if (oldSourceTextHash != null) 'oldSourceTextHash': oldSourceTextHash,
    'newSourceTextHash': newSourceTextHash,
    if (oldRenderedTextHash != null) 'oldRenderedTextHash': oldRenderedTextHash,
    if (newRenderedTextHash != null) 'newRenderedTextHash': newRenderedTextHash,
    'changeType': changeType,
    if (reason != null) 'reason': reason,
  };
}

typedef _SectionKey = ({
  String bookId,
  int? bookDbId,
  String? bookType,
  String? bookSource,
  int sectionIndex,
});
typedef _SectionSnapshot = ({
  String sourceTextHash,
  String? renderedTextHash,
  Object? renderingSignature,
});

Future<void> _dispatchSectionContentChanged(
  String topic,
  Map<String, dynamic> payload,
) {
  return PluginRuntimeDispatcher.instance.dispatchEvent(topic, payload);
}
