import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

class PluginCorrectionException implements Exception {
  final String code;
  final String message;

  const PluginCorrectionException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// תיקונים זמניים בלבד; אין לשירות גישה לכתיבה במקור הספר.
class PluginCorrectionSessionService extends ChangeNotifier {
  static final instance = PluginCorrectionSessionService();
  static const maxSessions = 32;
  static const maxChanges = 500;
  static const maxTextLength = 20000;
  static const maxChangesBytes = 1024 * 1024;
  static final Expando<String> _tabIds = Expando<String>();
  static String? knownTabIdFor(Object tab) => _tabIds[tab];

  static String tabIdFor(Object tab) => _tabIds[tab] ??= base64UrlEncode(
    List<int>.generate(24, (_) => Random.secure().nextInt(256)),
  );

  final Map<String, _Session> _sessions = {};

  Map<String, dynamic> begin({
    required String owner,
    required String tabId,
    required String bookId,
    required String bookUid,
    required String libraryVersion,
    required Future<String> Function(int) loadSource,
    Future<void> Function()? validateSource,
    void Function(String topic, Map<String, dynamic> payload)? onEvent,
  }) {
    for (final session in _sessions.values) {
      if (session.tabId != tabId) continue;
      if (session.owner != owner) {
        _fail('error.correction_busy', 'הלשונית שייכת לסשן תיקון אחר.');
      }
      return session.snapshot();
    }
    if (_sessions.length >= maxSessions) {
      _fail('error.limit_exceeded', 'מספר סשני התיקון הגיע למגבלה.');
    }
    final session = _Session(
      owner: owner,
      tabId: tabId,
      bookId: bookId,
      bookUid: bookUid,
      libraryVersion: libraryVersion,
      loadSource: loadSource,
      validateSource: validateSource,
      onEvent: onEvent,
    );
    _sessions[session.id] = session;
    notifyListeners();
    return session.snapshot();
  }

  Map<String, dynamic> get(String owner, String id) =>
      _owned(owner, id).snapshot();

  /// מחליף את הטיוטה אטומית לאחר אימות כל הפסקאות מול המקור.
  Future<Map<String, dynamic>> restore({
    required String owner,
    required String id,
    required int expectedRevision,
    required String bookUid,
    required String libraryVersion,
    required List<dynamic> changes,
  }) async {
    final session = _owned(owner, id);
    _revision(session, expectedRevision);
    if (session.bookUid != bookUid ||
        session.libraryVersion != libraryVersion) {
      _fail('error.source_changed', 'הטיוטה אינה תואמת למקור הספר.');
    }
    if (changes.length > maxChanges) {
      _fail('error.limit_exceeded', 'הטיוטה כוללת יותר מדי פסקאות.');
    }
    final prepared = <int, Map<String, dynamic>>{};
    var bytes = 0;
    for (final value in changes) {
      if (value is! Map ||
          value.length != 4 ||
          value['sectionIndex'] is! int ||
          (value['sectionIndex'] as int) < 0 ||
          value['originalSourceText'] is! String ||
          value['originalText'] is! String ||
          value['proposedText'] is! String) {
        _fail('error.invalid_params', 'נתוני פסקת התיקון אינם תקינים.');
      }
      final index = value['sectionIndex'] as int;
      if (prepared.containsKey(index)) {
        _fail('error.invalid_params', 'פסקה מופיעה יותר מפעם אחת.');
      }
      final raw = value['originalSourceText'] as String;
      final original = value['originalText'] as String;
      final proposed = value['proposedText'] as String;
      _sourceText(raw);
      _plainText(proposed);
      if (raw != original) {
        _fail('error.invalid_params', 'הטקסט העריך אינו תואם למקור.');
      }
      final change = <String, dynamic>{
        'sectionIndex': index,
        'originalSourceText': raw,
        'originalText': original,
        'proposedText': proposed,
      };
      bytes += utf8.encode(jsonEncode(change)).length;
      if (bytes > maxChangesBytes) {
        _fail('error.limit_exceeded', 'הטיוטה גדולה מדי.');
      }
      prepared[index] = change;
    }
    await session.validateSource?.call();
    for (final change in prepared.values) {
      final raw = await session.loadSource(change['sectionIndex'] as int);
      _sourceText(raw);
      if (raw != change['originalSourceText']) {
        _fail('error.source_changed', 'פסקת המקור השתנתה.');
      }
    }
    await session.validateSource?.call();
    // בדיקה חוזרת אחרי await מונעת מבקשה ישנה לדרוס תיקון חדש.
    if (!identical(_owned(owner, id), session)) {
      _fail('error.not_found', 'סשן התיקון הסתיים.');
    }
    _revision(session, expectedRevision);
    prepared.removeWhere(
      (_, value) => value['originalText'] == value['proposedText'],
    );
    String signature(Map<int, Map<String, dynamic>> values) => jsonEncode([
      for (final index in (values.keys.toList()..sort())) values[index],
    ]);
    if (signature(session.changes) != signature(prepared)) {
      session.changes = prepared;
      session.changesBytes = prepared.values.fold(
        0,
        (sum, change) => sum + _changeBytes(change),
      );
      session.revision++;
      notifyListeners();
      session.onEvent?.call('reader.correctionSessionChanged', {
        'sessionId': id,
        'revision': session.revision,
      });
    }
    return session.snapshot();
  }

  Map<String, dynamic> reset(
    String owner,
    String id,
    int sectionIndex,
    int expectedRevision,
  ) {
    final session = _owned(owner, id);
    _revision(session, expectedRevision);
    if (sectionIndex < 0) {
      _fail('error.invalid_params', 'אינדקס הפסקה חייב להיות אפסי או חיובי.');
    }
    final removed = session.changes.remove(sectionIndex);
    if (removed != null) {
      session.changesBytes -= _changeBytes(removed);
      session.revision++;
      notifyListeners();
      session.onEvent?.call('reader.correctionSessionChanged', {
        'sessionId': id,
        'revision': session.revision,
        'sectionIndex': sectionIndex,
      });
    }
    return session.snapshot();
  }

  Map<String, dynamic> end(String owner, String id, int expectedRevision) {
    final session = _owned(owner, id);
    _revision(session, expectedRevision);
    final snapshot = session.snapshot();
    _sessions.remove(id);
    notifyListeners();
    session.onEvent?.call('reader.correctionSessionEnded', {
      'sessionId': id,
      'reason': 'explicit',
      'snapshot': snapshot,
    });
    return snapshot;
  }

  void removeOwner(String owner) {
    final before = _sessions.length;
    _removeWhere((session) => session.owner == owner, 'plugin_unavailable');
    if (before != _sessions.length) notifyListeners();
  }

  void removeTab(String tabId) {
    final before = _sessions.length;
    _removeWhere((session) => session.tabId == tabId, 'tab_closed');
    if (before != _sessions.length) notifyListeners();
  }

  void _removeWhere(bool Function(_Session) matches, String reason) {
    final removed = _sessions.values.where(matches).toList();
    for (final session in removed) {
      _sessions.remove(session.id);
      session.onEvent?.call('reader.correctionSessionEnded', {
        'sessionId': session.id,
        'reason': reason,
        'snapshot': session.snapshot(),
      });
    }
  }

  String displayText(String tabId, int index, String source) {
    for (final session in _sessions.values) {
      if (session.tabId != tabId) continue;
      final change = session.changes[index];
      if (change?['originalSourceText'] == source) {
        return change!['proposedText'] as String;
      }
    }
    return source;
  }

  bool hasChangesForTab(String tabId) => _sessions.values.any(
    (session) => session.tabId == tabId && session.changes.isNotEmpty,
  );

  bool hasSessionForTab(String tabId) => _sessionForTab(tabId) != null;

  int revisionForTab(String tabId) => _sessionForTab(tabId)?.revision ?? -1;

  bool canEditParagraph(String tabId, String source) =>
      hasSessionForTab(tabId) &&
      source.isNotEmpty &&
      source.length <= maxTextLength &&
      !_unsupportedText.hasMatch(source) &&
      _validUtf16(source);

  void validateNativeEdit(
    String tabId,
    int index,
    String source,
    String proposed,
  ) {
    final session = _sessionForTab(tabId);
    if (session == null) _fail('error.not_found', 'סשן התיקון הסתיים.');
    _sourceText(source);
    _plainText(proposed);
    final previous = session.changes[index];
    if (index < 0 ||
        previous != null && previous['originalSourceText'] != source) {
      _fail('error.source_changed', 'פסקת המקור השתנתה.');
    }
    if (proposed == source) return;
    if (previous == null && session.changes.length >= maxChanges) {
      _fail('error.limit_exceeded', 'מספר הפסקאות המתוקנות הגיע למגבלה.');
    }
    final bytes =
        session.changesBytes -
        (previous == null ? 0 : _changeBytes(previous)) +
        _changeBytes(_nativeChange(index, source, proposed));
    if (bytes > maxChangesBytes) {
      _fail('error.limit_exceeded', 'טיוטת התיקון גדולה מדי.');
    }
  }

  /// ההקלדה נשמרת מיד, לפני אירוע השינוי וללא תלות במיקוד השדה.
  void editParagraph(String tabId, int index, String source, String proposed) {
    validateNativeEdit(tabId, index, source, proposed);
    final session = _sessionForTab(tabId)!;
    final previous = session.changes[index];
    if ((previous?['proposedText'] ?? source) == proposed) return;
    session.changesBytes -= previous == null ? 0 : _changeBytes(previous);
    if (proposed == source) {
      session.changes.remove(index);
    } else {
      final change = _nativeChange(index, source, proposed);
      session.changes[index] = change;
      session.changesBytes += _changeBytes(change);
    }
    session.revision++;
    notifyListeners();
    session.onEvent?.call('reader.correctionSessionChanged', {
      'sessionId': session.id,
      'revision': session.revision,
      'sectionIndex': index,
    });
  }

  Map<String, dynamic> _nativeChange(
    int index,
    String source,
    String proposed,
  ) => {
    'sectionIndex': index,
    'originalSourceText': source,
    'originalText': source,
    'proposedText': proposed,
  };

  int _changeBytes(Map<String, dynamic> change) =>
      utf8.encode(jsonEncode(change)).length;

  _Session? _sessionForTab(String tabId) {
    for (final session in _sessions.values) {
      if (session.tabId == tabId) return session;
    }
    return null;
  }

  bool hasSessionForBook(String bookId, String? bookUid) =>
      _sessions.values.any(
        (session) => (bookUid == null
            ? session.bookId == bookId
            : session.bookUid == bookUid),
      );

  _Session _owned(String owner, String id) {
    final session = _sessions[id];
    if (session == null || session.owner != owner) {
      _fail('error.not_found', 'סשן התיקון אינו זמין לתוסף.');
    }
    return session;
  }

  void _revision(_Session session, int revision) {
    if (revision < 0) _fail('error.invalid_params', 'מספר הגרסה אינו תקין.');
    if (session.revision != revision) {
      _fail('error.revision_conflict', 'סשן התיקון השתנה; יש לקרוא אותו מחדש.');
    }
  }

  void _sourceText(String text) {
    if (text.isEmpty) {
      _fail(
        'error.unsupported_context',
        'פסקת מקור ריקה אינה נתמכת בעריכה מקומית.',
      );
    }
    _plainText(text);
  }

  void _plainText(String text) {
    if (text.length > maxTextLength) {
      _fail('error.limit_exceeded', 'טקסט הפסקה גדול מדי.');
    }
    if (_unsupportedText.hasMatch(text)) {
      _fail('error.unsupported_context', 'נתמך רק טקסט פשוט בתוך פסקה אחת.');
    }
    if (!_validUtf16(text)) {
      _fail('error.invalid_params', 'הטקסט מכיל תו פגום.');
    }
  }

  static final _unsupportedText = RegExp(
    r'[<>\r\n\u2028\u2029]|&(?:#[xX]?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);',
  );

  static bool _validUtf16(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (++i >= text.length ||
            text.codeUnitAt(i) < 0xDC00 ||
            text.codeUnitAt(i) > 0xDFFF) {
          return false;
        }
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        return false;
      }
    }
    return true;
  }

  Never _fail(String code, String message) =>
      throw PluginCorrectionException(code, message);
}

class _Session {
  final String id = base64UrlEncode(
    List<int>.generate(24, (_) => Random.secure().nextInt(256)),
  );
  final String owner;
  final String tabId;
  final String bookId;
  final String bookUid;
  final String libraryVersion;
  final Future<String> Function(int) loadSource;
  final Future<void> Function()? validateSource;
  final void Function(String topic, Map<String, dynamic> payload)? onEvent;
  int revision = 0;
  int changesBytes = 0;
  Map<int, Map<String, dynamic>> changes = {};

  _Session({
    required this.owner,
    required this.tabId,
    required this.bookId,
    required this.bookUid,
    required this.libraryVersion,
    required this.loadSource,
    this.validateSource,
    this.onEvent,
  });

  Map<String, dynamic> snapshot() => {
    'sessionId': id,
    'tabId': tabId,
    'bookId': bookId,
    'bookUid': bookUid,
    'libraryVersion': libraryVersion,
    'revision': revision,
    'capabilities': {
      'plainTextOnly': true,
      'paragraphBoundaries': false,
      'offsetUnit': 'utf16',
      'sourceSelection': false,
      'sourceAnchorsOnCorrectedParagraphs': false,
      'continuousReading': true,
      'pageShape': false,
      'splitView': false,
      'maxChanges': PluginCorrectionSessionService.maxChanges,
      'maxTextLength': PluginCorrectionSessionService.maxTextLength,
      'maxChangesBytes': PluginCorrectionSessionService.maxChangesBytes,
    },
    'changes': [
      for (final index in (changes.keys.toList()..sort()))
        Map<String, dynamic>.of(changes[index]!),
    ],
  };
}
