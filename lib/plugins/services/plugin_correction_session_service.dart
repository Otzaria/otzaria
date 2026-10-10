import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

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
  final Map<String, int> _ownerEpochs = {};

  /// גדל בכל הסרת בעלים; מי שהתחיל לפני ההסרה לא יוצר אחריה סשן.
  int ownerEpoch(String owner) => _ownerEpochs[owner] ?? 0;

  Map<String, dynamic> begin({
    required String owner,
    required String tabId,
    required String bookId,
    required String bookUid,
    required String libraryVersion,
    required Future<String> Function(int) loadSource,
    Future<void> Function()? validateSource,
    void Function(String topic, Map<String, dynamic> payload)? onEvent,
    int? ownerEpoch,
  }) {
    if (ownerEpoch != null && ownerEpoch != this.ownerEpoch(owner)) {
      _fail('error.permission_denied', 'התוסף הושבת או שהרשאתו בוטלה.');
    }
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
      _rawSource(raw);
      _plainText(proposed);
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
      if (raw != change['originalSourceText']) {
        _fail('error.source_changed', 'פסקת המקור השתנתה.');
      }
      if (_sourceText(raw) != change['originalText']) {
        _fail('error.invalid_params', 'הטקסט העריך אינו תואם למקור.');
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
    _ownerEpochs[owner] = ownerEpoch(owner) + 1;
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

  String editableText(String tabId, int index, String source) =>
      TextRendererService.stripHtml(displayText(tabId, index, source));

  bool hasSessionForTab(String tabId) => _sessionForTab(tabId) != null;

  String? sessionIdForTab(String owner, String tabId) {
    final session = _sessionForTab(tabId);
    return session?.owner == owner ? session?.id : null;
  }

  bool canEditParagraph(String tabId, String source) {
    if (!hasSessionForTab(tabId) ||
        source.isEmpty ||
        source.length > maxTextLength ||
        !_validUtf16(source)) {
      return false;
    }
    final plain = TextRendererService.stripHtml(source);
    return plain.isNotEmpty &&
        plain.length <= maxTextLength &&
        !_unsupportedText.hasMatch(plain) &&
        _validUtf16(plain);
  }

  void validateNativeEdit(
    String tabId,
    int index,
    String source,
    String proposed,
  ) {
    final session = _sessionForTab(tabId);
    if (session == null) _fail('error.not_found', 'סשן התיקון הסתיים.');
    final original = _sourceText(source);
    _plainText(proposed);
    final previous = session.changes[index];
    if (index < 0 ||
        previous != null && previous['originalSourceText'] != source) {
      _fail('error.source_changed', 'פסקת המקור השתנתה.');
    }
    if (proposed == original) return;
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
    final original = TextRendererService.stripHtml(source);
    if ((previous?['proposedText'] ?? original) == proposed) return;
    session.changesBytes -= previous == null ? 0 : _changeBytes(previous);
    if (proposed == original) {
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
    'originalText': TextRendererService.stripHtml(source),
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

  /// הטעינה מקצצת רווחים מ-bookUid, ולכן גם ההשוואה כאן, אחרת הם עוקפים את החסם.
  bool hasSessionForBook(String bookId, String? bookUid) {
    final uid = bookUid?.trim();
    return _sessions.values.any(
      (session) => uid == null || uid.isEmpty
          ? session.bookId == bookId
          : session.bookUid == uid,
    );
  }

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

  /// בדיקות זולות בלבד: ניתוח HTML של קלט לא מהימן ריבועי ומקפיא את הממשק.
  void _rawSource(String text) {
    if (text.isEmpty) {
      _fail(
        'error.unsupported_context',
        'פסקת מקור ריקה אינה נתמכת בעריכה מקומית.',
      );
    }
    if (text.length > maxTextLength) {
      _fail('error.limit_exceeded', 'טקסט פסקת המקור גדול מדי.');
    }
    if (!_validUtf16(text)) {
      _fail('error.invalid_params', 'מקור הספר מכיל תו פגום.');
    }
  }

  String _sourceText(String text) {
    _rawSource(text);
    final plain = TextRendererService.stripHtml(text);
    if (plain.isEmpty) {
      _fail(
        'error.unsupported_context',
        'פסקת מקור ריקה אינה נתמכת בעריכה מקומית.',
      );
    }
    _plainText(plain);
    return plain;
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
      'htmlSource': true,
      'paragraphBoundaries': false,
      'offsetUnit': 'utf16',
      'sourceSelection': false,
      'sourceAnchorsOnCorrectedParagraphs': false,
      'continuousReading': true,
      'pageShape': false,
      'splitView': true,
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
