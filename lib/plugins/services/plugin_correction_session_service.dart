import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

class PluginCorrectionException implements Exception {
  final String code;
  final String message;

  const PluginCorrectionException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// מצב השמירה העמידה של סשן, להצגה למשתמש.
enum PluginCorrectionDraftStatus { saved, saving, failed }

/// תיקונים זמניים בתצוגה; אין לשירות גישה לכתיבה במקור הספר.
///
/// כל שינוי נשמר גם בטיוטת התאוששות בבעלות אוצריא, שנשארת עד שהתוסף מאשר
/// (`acknowledge`) את הגרסה המדויקת שקיבל. סיום סשן אינו מוחק טיוטה.
class PluginCorrectionSessionService extends ChangeNotifier {
  static final instance = PluginCorrectionSessionService();
  static const maxSessions = 32;
  static const maxChanges = 500;
  static const maxTextLength = 20000;
  static const maxChangesBytes = 1024 * 1024;

  /// הגבלת קצב, לא debounce: הקלדה רצופה אינה דוחה את האירוע או השמירה.
  static Duration eventWindow = const Duration(milliseconds: 300);
  static Duration writeInterval = const Duration(milliseconds: 250);
  static Duration flushTimeout = const Duration(seconds: 3);
  static const List<Duration> retryBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  static final Expando<String> _tabIds = Expando<String>();
  static String? knownTabIdFor(Object tab) => _tabIds[tab];

  static String tabIdFor(Object tab) => _tabIds[tab] ??= base64UrlEncode(
    List<int>.generate(24, (_) => Random.secure().nextInt(256)),
  );

  PluginCorrectionDraftRepository? _drafts;
  PluginCorrectionDraftRepository get _repository =>
      _drafts ??= PluginCorrectionDraftRepository.isolate();

  @visibleForTesting
  set draftRepository(PluginCorrectionDraftRepository repository) =>
      _drafts = repository;

  final Map<String, _Session> _sessions = {};

  /// סשנים שהסתיימו וטרם נשמרו סופית ושוחרר ה-lease שלהם.
  final Set<_Session> _finalizing = {};
  final Set<String> _pendingTabs = {};
  final Set<String> _pendingDrafts = {};
  final Set<String> _cancelledTabs = {};
  final Map<String, int> _ownerEpochs = {};
  String? _processQuitRequestId;

  bool get processQuitPending => _processQuitRequestId != null;

  bool isProcessQuitPreparedFor(String requestId) =>
      _processQuitRequestId == requestId;

  bool beginProcessQuitPreparation(String requestId) {
    if (_pendingTabs.isNotEmpty ||
        _processQuitRequestId != null && _processQuitRequestId != requestId) {
      return false;
    }
    _processQuitRequestId = requestId;
    return true;
  }

  void cancelProcessQuitPreparation(String requestId) {
    if (_processQuitRequestId == requestId) _processQuitRequestId = null;
  }

  void _rejectEditDuringProcessQuit() {
    if (_processQuitRequestId != null) {
      _fail('error.correction_busy', 'היציאה מהתוכנה בתהליך.');
    }
  }

  /// גדל בכל הסרת בעלים; מי שהתחיל לפני ההסרה לא יוצר אחריה סשן.
  int ownerEpoch(String owner) => _ownerEpochs[owner] ?? 0;

  /// האם ל-[owner] יש סשן תיקון פתוח או שעדיין נסגר.
  bool hasSessionsFor(String owner) =>
      _sessions.values.any((s) => s.owner == owner) ||
      _finalizing.any((s) => s.owner == owner);

  Future<Map<String, dynamic>> begin({
    required String owner,
    String? ownerName,
    required String tabId,
    required String bookId,
    required String bookUid,
    String bookSource = '',
    required String libraryVersion,
    required Future<String> Function(int) loadSource,
    Future<void> Function()? validateSource,
    void Function(String topic, Map<String, dynamic> payload)? onEvent,
    int? ownerEpoch,
  }) async {
    _rejectEditDuringProcessQuit();
    final epoch = ownerEpoch ?? this.ownerEpoch(owner);
    void checkEpoch() {
      if (epoch != this.ownerEpoch(owner)) {
        _fail('error.permission_denied', 'התוסף הושבת או שהרשאתו בוטלה.');
      }
    }

    checkEpoch();
    final draftId = correctionDraftId(owner, bookUid);
    for (final session in _sessions.values) {
      if (session.tabId == tabId) {
        if (session.owner != owner) {
          _fail('error.correction_busy', 'הלשונית שייכת לסשן תיקון אחר.');
        }
        return {...session.snapshot(), 'recovery': null};
      }
      if (session.owner == owner && session.draftId == draftId) {
        _fail('error.correction_busy', 'הספר כבר בעריכה בלשונית אחרת.');
      }
    }
    if (_pendingTabs.contains(tabId) || _pendingDrafts.contains(draftId)) {
      _fail('error.correction_busy', 'פתיחת סשן תיקון כבר מתבצעת.');
    }
    if (_sessions.length + _pendingTabs.length >= maxSessions) {
      _fail('error.limit_exceeded', 'מספר סשני התיקון הגיע למגבלה.');
    }
    _pendingTabs.add(tabId);
    _pendingDrafts.add(draftId);
    try {
      final lease = await _acquire(
        owner: owner,
        draftId: draftId,
        bookUid: bookUid,
        bookId: bookId,
        bookSource: bookSource,
        libraryVersion: libraryVersion,
      );
      try {
        checkEpoch();
        _rejectEditDuringProcessQuit();
        final session = _Session(
          owner: owner,
          ownerName: ownerName ?? owner,
          tabId: tabId,
          bookId: bookId,
          bookUid: bookUid,
          libraryVersion: libraryVersion,
          draftId: draftId,
          bookSource: bookSource,
          token: lease.token,
          leaseEpoch: lease.epoch,
          loadSource: loadSource,
          validateSource: validateSource,
          onEvent: onEvent,
        );
        Map<String, dynamic>? recovery;
        if (lease.version != null) {
          recovery = await _recover(session, lease);
          checkEpoch();
          _rejectEditDuringProcessQuit();
        }
        if (_cancelledTabs.contains(tabId)) {
          _fail('error.not_found', 'לשונית הספר נסגרה.');
        }
        _sessions[session.id] = session;
        notifyListeners();
        if (recovery != null) {
          final applied = (recovery['restoredSectionIndices'] as List).length;
          final conflicts = (recovery['conflicts'] as List).length;
          if (applied > 0 || conflicts > 0) {
            UiSnack.show(
              PluginMessages.correctionRecovered(
                applied: applied,
                conflicts: conflicts,
              ),
            );
          }
        }
        return {...session.snapshot(), 'recovery': recovery};
      } catch (_) {
        unawaited(_release(owner, draftId, lease.token));
        rethrow;
      }
    } finally {
      _pendingTabs.remove(tabId);
      _cancelledTabs.remove(tabId);
      _pendingDrafts.remove(draftId);
    }
  }

  Future<
    ({
      String token,
      int epoch,
      int? version,
      String changes,
      String conflicts,
    })
  >
  _acquire({
    required String owner,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
  }) async {
    try {
      return await _repository.acquire(
        pluginId: owner,
        draftId: draftId,
        bookUid: bookUid,
        bookId: bookId,
        bookSource: bookSource,
        libraryVersion: libraryVersion,
      );
    } on PluginCorrectionDraftBusy {
      _fail(
        'error.correction_busy',
        'הספר נמצא בעריכה בחלון אחר, או שסשן קודם עדיין משתחרר. נסו שוב בעוד רגע.',
      );
    } catch (error) {
      _fail('error.storage_failed', 'לא ניתן לפתוח את טיוטת התיקון: $error');
    }
  }

  Future<void> _release(String owner, String draftId, String token) async {
    try {
      await _repository.release(
        pluginId: owner,
        draftId: draftId,
        token: token,
      );
    } catch (error) {
      // ה-lease יפוג לבד; הטיוטה עצמה כבר שמורה.
      debugPrint('[PluginCorrectionSession] release failed: $error');
    }
  }

  /// מחיל רק תיקונים שמקורם הגולמי זהה בדיוק; השאר נשמרים כהתנגשויות.
  Future<Map<String, dynamic>> _recover(
    _Session session,
    ({
      String token,
      int epoch,
      int? version,
      String changes,
      String conflicts,
    })
    lease,
  ) async {
    final conflicts = [
      for (final value in jsonDecode(lease.conflicts) as List)
        Map<String, dynamic>.from(value as Map),
    ];
    final known = {for (final conflict in conflicts) _conflictKey(conflict)};
    final restored = <int, Map<String, dynamic>>{};
    for (final value in jsonDecode(lease.changes) as List) {
      final change = Map<String, dynamic>.from(value as Map);
      final index = change['sectionIndex'];
      String? reason;
      try {
        if (index is! int || index < 0 || restored.containsKey(index)) {
          reason = 'invalid';
        } else {
          final raw = await session.loadSource(index);
          final proposed = change['proposedText'];
          if (raw != change['originalSourceText'] ||
              _sourceText(raw) != change['originalText']) {
            reason = 'source_changed';
          } else if (proposed is! String) {
            reason = 'invalid';
          } else {
            _plainText(proposed);
          }
        }
      } on PluginCorrectionException catch (error) {
        reason ??= error.code == 'error.not_found' ? 'not_found' : 'invalid';
      } catch (error) {
        // תקלה זמנית אינה הופכת תיקון להתנגשות קבועה; הפתיחה נכשלת ותנוסה שוב.
        _fail('error.storage_failed', 'קריאת מקור הספר נכשלה: $error');
      }
      if (reason == null) {
        restored[index as int] = _nativeChange(
          index,
          change['originalSourceText'] as String,
          change['proposedText'] as String,
        );
        continue;
      }
      final conflict = {...change, 'reason': reason};
      if (known.add(_conflictKey(conflict))) conflicts.add(conflict);
    }
    // not_found מלשונית שנסגרה באמצע אינו התנגשות: הפתיחה נכשלת לפני הכתיבה.
    await session.validateSource?.call();
    session.changes = restored;
    session.changesBytes = restored.values.fold(
      0,
      (sum, change) => sum + _changeBytes(change),
    );
    session.conflicts = conflicts;
    session.revision = 1;
    final result = await _repository.write(
      pluginId: session.owner,
      draftId: session.draftId,
      token: session.token,
      revision: 1,
      libraryVersion: session.libraryVersion,
      changesJson: session.changesJson(),
      conflictsJson: jsonEncode(conflicts),
      expectedVersion: lease.version,
    );
    if (result.status != 'ok') {
      if (result.status == 'conflict') {
        _fail(
          'error.revision_conflict',
          'הטיוטה אושרה או השתנתה בזמן השחזור; יש לפתוח את הסשן מחדש.',
        );
      }
      _fail('error.storage_failed', 'שמירת הטיוטה המשוחזרת נכשלה.');
    }
    session.version = result.version;
    session.persistedRevision = 1;
    session.committed = _copyChanges(restored);
    return {
      'draftId': session.draftId,
      'fromVersion': lease.version,
      'restoredSectionIndices': restored.keys.toList()..sort(),
      'conflicts': [for (final conflict in conflicts) Map.of(conflict)],
    };
  }

  static String _conflictKey(Map<String, dynamic> conflict) => jsonEncode([
    conflict['sectionIndex'],
    conflict['originalSourceText'],
    conflict['proposedText'],
  ]);

  /// מרוקן אירוע ממתין ומחכה (עד [flushTimeout]) לשמירת המצב הנוכחי, כדי
  /// ש-`draft.version` ב-snapshot יתאים לתוכן שבו.
  Future<Map<String, dynamic>> get(String owner, String id) async {
    final session = _owned(owner, id);
    _flushEvents(session);
    await _flush(session, flushTimeout);
    await _refresh(session);
    return _owned(owner, id).snapshot();
  }

  /// הצלה מחלון אחר מוסיפה התנגשויות ומעלה את הגרסה העמידה בלי לכתוב דרכנו;
  /// מאמצים אותה רק כשה-changes העמידים הם בדיוק אלה שבסשן.
  Future<void> _refresh(_Session session) async {
    if (!session.persisted || session.lost || session.purged) return;
    final revision = session.revision;
    final Map<String, Object?>? draft;
    try {
      draft = await _repository.get(session.owner, session.draftId);
    } on Object catch (error) {
      // רק כשל אחסון (worker או SQLite); שגיאת תכנות אינה נבלעת.
      if (error is! Exception && error is! StateError) rethrow;
      // גרסה ישנה נדחית באישור, ולכן כשל קריאה אינו מסכן תוכן.
      debugPrint('[PluginCorrectionSession] refresh failed: $error');
      return;
    }
    final version = draft?['version'] as int?;
    if (draft == null ||
        version == null ||
        version <= (session.version ?? -1) ||
        session.revision != revision ||
        !session.persisted ||
        jsonEncode(draft['changes']) != session.changesJson()) {
      return;
    }
    session.version = version;
    session.conflicts = [
      for (final value in draft['conflicts'] as List)
        Map<String, dynamic>.from(value as Map),
    ];
  }

  /// מחליף את הטיוטה אטומית לאחר אימות כל הפסקאות מול המקור.
  Future<Map<String, dynamic>> restore({
    required String owner,
    required String id,
    required int expectedRevision,
    required String bookUid,
    required String libraryVersion,
    required List<dynamic> changes,
  }) async {
    _rejectEditDuringProcessQuit();
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
    _rejectEditDuringProcessQuit();
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
    _rejectEditDuringProcessQuit();
    // בדיקה חוזרת אחרי await מונעת מבקשה ישנה לדרוס תיקון חדש.
    if (!identical(_owned(owner, id), session)) {
      _fail('error.not_found', 'סשן התיקון הסתיים.');
    }
    _revision(session, expectedRevision);
    prepared.removeWhere(
      (_, value) => value['originalText'] == value['proposedText'],
    );
    final touched = <int>{
      for (final index in {...session.changes.keys, ...prepared.keys})
        if (jsonEncode(session.changes[index]) != jsonEncode(prepared[index]))
          index,
    };
    if (touched.isNotEmpty) {
      session.changes = prepared;
      session.changesBytes = prepared.values.fold(
        0,
        (sum, change) => sum + _changeBytes(change),
      );
      _changed(session, touched);
    }
    return session.snapshot();
  }

  Map<String, dynamic> reset(
    String owner,
    String id,
    int sectionIndex,
    int expectedRevision,
  ) {
    _rejectEditDuringProcessQuit();
    final session = _owned(owner, id);
    _revision(session, expectedRevision);
    if (sectionIndex < 0) {
      _fail('error.invalid_params', 'אינדקס הפסקה חייב להיות אפסי או חיובי.');
    }
    final removed = session.changes.remove(sectionIndex);
    if (removed != null) {
      session.changesBytes -= _changeBytes(removed);
      _changed(session, {sectionIndex});
    }
    return session.snapshot();
  }

  /// מסיים את התצוגה בלבד; הטיוטה נשמרת עד ack. מחכה (עד [flushTimeout])
  /// לשמירה כדי שה-snapshot יכלול גרסה שאפשר לאשר.
  Future<Map<String, dynamic>> end(
    String owner,
    String id,
    int expectedRevision,
  ) async {
    _rejectEditDuringProcessQuit();
    final session = _owned(owner, id);
    _revision(session, expectedRevision);
    final finished = _end(session, 'explicit');
    await finished.timeout(flushTimeout, onTimeout: () {});
    return session.snapshot();
  }

  /// סיום בידי המשתמש — פועל גם כשהתוסף אינו מגיב.
  void endByUser(String tabId) {
    if (_processQuitRequestId != null) return;
    final session = _sessionForTab(tabId);
    if (session != null) unawaited(_end(session, 'user'));
  }

  /// מסיים את כל הסשנים בתהליך (יציאה, העברת מסדים).
  void endAll(String reason) {
    _cancelledTabs.addAll(_pendingTabs);
    for (final session in _sessions.values.toList()) {
      unawaited(_end(session, reason));
    }
  }

  /// ביציאה מהתהליך: מסיים, שומר ומשחרר את ה-leases, כדי שהפעלה מחדש לא
  /// תמתין לפקיעתם.
  Future<void> shutdown({required Duration timeout}) async {
    endAll('app_exit');
    await Future.wait([
      for (final session in _finalizing.toList()) session.finished.future,
    ]).timeout(timeout, onTimeout: () => const []);
  }

  void removeOwner(String owner) {
    _ownerEpochs[owner] = ownerEpoch(owner) + 1;
    for (final session in _sessions.values.toList()) {
      if (session.owner == owner) {
        unawaited(_end(session, 'plugin_unavailable'));
      }
    }
  }

  void removeTab(String tabId, {String reason = 'tab_closed'}) {
    final session = _sessionForTab(tabId);
    if (session != null) {
      unawaited(_end(session, reason));
    } else if (_pendingTabs.contains(tabId)) {
      // begin שעדיין ממתין לא יירשם ללשונית שנסגרה.
      _cancelledTabs.add(tabId);
    }
  }

  /// מחיקה מכוונת שהמשתמש אישר (הסרת תוסף או איפוס נתוניו).
  Future<void> purgeOwner(String owner) async {
    _rejectEditDuringProcessQuit();
    removeOwner(owner);
    for (final session in _finalizing.where((s) => s.owner == owner).toList()) {
      session.purged = true;
      _stopTimers(session);
      _settle(session);
    }
    await _repository.purge(owner);
  }

  Future<void> _end(_Session session, String reason) {
    if (session.ended) return session.finished.future;
    // אירוע ממתין נשלח לפני הסימון, כדי ש-changed לא יאבד ולא יגיע אחרי ended.
    _flushEvents(session);
    session.ended = true;
    _sessions.remove(session.id);
    _finalizing.add(session);
    notifyListeners();
    unawaited(_finalize(session, reason));
    return session.finished.future;
  }

  /// הכתיבה האחרונה, שחרור ה-lease ואירוע הסיום — בלי תלות ב-dispose
  /// או בכך שהתוסף יצרוך את האירוע.
  Future<void> _finalize(_Session session, String reason) async {
    _scheduleWrite(session, immediate: true);
    // כשל מתמשך אינו מעכב את האירוע: התוסף מקבל את המצב עם persisted=false,
    // והניסיונות וה-lease נמשכים עד שהמצב נשמר.
    await session.settled.future.timeout(flushTimeout, onTimeout: () {});
    var released = false;
    if (session.settled.isCompleted) {
      released = true;
      await _refresh(session);
      await _releaseFinal(session);
    }
    if (!session.purged) {
      session.onEvent?.call('reader.correctionSessionEnded', {
        'sessionId': session.id,
        'reason': session.lost ? 'ownership_lost' : reason,
        'snapshot': session.snapshot(),
      });
    }
    if (!session.finished.isCompleted) session.finished.complete();
    if (!released) {
      await session.settled.future;
      await _releaseFinal(session);
    }
  }

  Future<void> _releaseFinal(_Session session) async {
    if (!session.lost && !session.purged) {
      await _release(session.owner, session.draftId, session.token);
    }
    _finalizing.remove(session);
  }

  void _changed(_Session session, Set<int> indices) {
    session.revision++;
    notifyListeners();
    _scheduleWrite(session);
    session.pendingEventIndices.addAll(indices);
    session.eventTimer ??= Timer(eventWindow, () {
      session.eventTimer = null;
      _emitChanged(session);
    });
  }

  void _emitChanged(_Session session) {
    if (session.pendingEventIndices.isEmpty || session.ended) return;
    final indices = session.pendingEventIndices.toList()..sort();
    session.pendingEventIndices.clear();
    session.onEvent?.call('reader.correctionSessionChanged', {
      'sessionId': session.id,
      'revision': session.revision,
      'sectionIndices': indices,
    });
  }

  void _flushEvents(_Session session) {
    session.eventTimer?.cancel();
    session.eventTimer = null;
    _emitChanged(session);
  }

  static Map<int, Map<String, dynamic>> _copyChanges(
    Map<int, Map<String, dynamic>> changes,
  ) => {
    for (final entry in changes.entries)
      entry.key: Map<String, dynamic>.of(entry.value),
  };

  /// ההפרש שטרם נשמר בין ה-commit האחרון למצב הנוכחי, כולל פסקאות שהוחזרו למקור.
  /// פסקה [uncertain] נכללת תמיד: ייתכן שכתיבה שתשובתה אבדה שינתה אותה במסד.
  static List<Map<String, dynamic>> _displacedEntries(
    Map<int, Map<String, dynamic>> committed,
    Map<int, Map<String, dynamic>> current,
    Map<int, Map<String, dynamic>> uncertain,
  ) => [
    for (final index in ({
      ...committed.keys,
      ...current.keys,
      ...uncertain.keys,
    }.toList()..sort()))
      if (uncertain.containsKey(index) ||
          jsonEncode(committed[index]) != jsonEncode(current[index]))
        if (current[index] case final change?)
          {...change, 'reason': 'displaced'}
        else if (committed[index] ?? uncertain[index] case final base?)
          {
            'sectionIndex': index,
            'originalSourceText': base['originalSourceText'],
            'originalText': base['originalText'],
            'proposedText': base['originalText'],
            'reason': 'displaced',
          },
  ];

  /// כתיבה אחת בכל פעם, תמיד של המצב האחרון; כתיבה ישנה אינה דורסת חדשה.
  void _scheduleWrite(_Session session, {bool immediate = false}) {
    if (session.purged || session.rescued) {
      _settle(session);
      return;
    }
    if (session.writing) return;
    if (session.persistedRevision == session.revision) {
      _settle(session);
      return;
    }
    if (session.retryTimer != null && !immediate) return;
    final elapsed = session.lastWriteStart == null
        ? writeInterval
        : DateTime.now().difference(session.lastWriteStart!);
    if (!immediate && elapsed < writeInterval) {
      session.writeTimer ??= Timer(writeInterval - elapsed, () {
        session.writeTimer = null;
        _scheduleWrite(session);
      });
      return;
    }
    session.writeTimer?.cancel();
    session.writeTimer = null;
    session.retryTimer?.cancel();
    session.retryTimer = null;
    unawaited(_write(session));
  }

  Future<void> _write(_Session session) async {
    session.writing = true;
    session.lastWriteStart = DateTime.now();
    final revision = session.revision;
    final changes = _copyChanges(session.changes);
    final rescuing = session.lost;
    try {
      if (rescuing) {
        await _rescue(session, revision, changes);
        return;
      }
      final result = await _repository.write(
        pluginId: session.owner,
        draftId: session.draftId,
        token: session.token,
        revision: revision,
        libraryVersion: session.libraryVersion,
        changesJson: session.changesJson(),
      );
      if (result.status == 'lost') {
        // תשובה ודאית: הכשל הקודם אינו ממתין עוד, ההצלה היא הצעד הבא.
        session.error = null;
        _ownershipLost(session);
        return;
      }
      if (result.version != null) {
        session.version = result.version;
        session.conflicts = [
          for (final value in jsonDecode(result.conflicts!) as List)
            Map<String, dynamic>.from(value as Map),
        ];
      }
      if (revision > session.persistedRevision) {
        session.persistedRevision = revision;
        session.committed = changes;
      }
      session.uncertain.clear();
      _writeSucceeded(session);
    } catch (error) {
      if (!rescuing) {
        // ייתכן שהכתיבה הגיעה למסד והתשובה אבדה.
        for (final index in {...changes.keys, ...session.committed.keys}) {
          if (jsonEncode(changes[index]) !=
              jsonEncode(session.committed[index])) {
            session.uncertain[index] =
                changes[index] ?? session.committed[index]!;
          }
        }
      }
      session.error = error;
      session.failures++;
      if (session.failures == 1 && !session.purged) {
        UiSnack.showWithAction(
          message: PluginMessages.correctionDraftSaveFailed,
          actionLabel: PluginMessages.correctionDraftRetry,
          onAction: retryDraftWrites,
        );
      }
      final delay =
          retryBackoff[min(session.failures, retryBackoff.length) - 1];
      session.retryTimer = Timer(delay, () {
        session.retryTimer = null;
        _scheduleWrite(session, immediate: true);
      });
    } finally {
      session.writing = false;
      notifyListeners();
      if (session.error != null) _wakeFlushWaiters(session);
      // אחרי כשל ה-backoff קובע, גם בסשן שהסתיים — אחרת זו לולאה צפופה.
      _scheduleWrite(
        session,
        immediate: session.ended && session.error == null,
      );
    }
  }

  /// ניסיון שמירה מיידי לכל סשן שהשמירה שלו נכשלה.
  void retryDraftWrites() {
    for (final session in [..._sessions.values, ..._finalizing]) {
      if (session.error != null) _scheduleWrite(session, immediate: true);
    }
  }

  void _ownershipLost(_Session session) {
    session.lost = true;
    _stopTimers(session);
    if (!session.purged) {
      UiSnack.showWarning(PluginMessages.correctionOwnershipLost);
    }
    if (!session.ended) {
      unawaited(_end(session, 'ownership_lost'));
    }
    // אין settle: המצב שלא נשמר יוצל כהתנגשויות לפני שהסשן משתחרר.
  }

  /// אינו נוגע ב-changes או ב-lease של הבעלים החדש; מחיקה מכוונת אחרי
  /// פתיחת הסשן גוברת, והמצב אינו נשמר מחדש.
  Future<void> _rescue(
    _Session session,
    int revision,
    Map<int, Map<String, dynamic>> changes,
  ) async {
    final result = await _repository.rescue(
      pluginId: session.owner,
      draftId: session.draftId,
      bookUid: session.bookUid,
      bookId: session.bookId,
      bookSource: session.bookSource,
      libraryVersion: session.libraryVersion,
      entriesJson: jsonEncode(
        _displacedEntries(session.committed, changes, session.uncertain),
      ),
      sinceEpoch: session.leaseEpoch,
    );
    // הגרסה המשותפת כוללת תוכן של הבעלים החדש שאינו ב-snapshot שלנו, ולכן
    // אינה נשמרת כאן: האישור שלה שייך לבעלים החדש.
    if (result.status == 'purged') session.purged = true;
    session.rescued = true;
    session.persistedRevision = revision;
    session.committed = changes;
    session.uncertain.clear();
    _writeSucceeded(session);
  }

  void _writeSucceeded(_Session session) {
    if (session.failures == 0) return;
    session.failures = 0;
    session.error = null;
    if (!session.purged) {
      UiSnack.showSuccess(PluginMessages.correctionDraftSaved);
    }
  }

  void _stopTimers(_Session session) {
    session.writeTimer?.cancel();
    session.writeTimer = null;
    session.retryTimer?.cancel();
    session.retryTimer = null;
    session.eventTimer?.cancel();
    session.eventTimer = null;
  }

  /// המצב הנוכחי נשמר (או שאין עוד מה לשמור).
  void _settle(_Session session) {
    _wakeFlushWaiters(session);
    if (session.ended && !session.settled.isCompleted) {
      session.settled.complete();
    }
  }

  void _wakeFlushWaiters(_Session session) {
    final waiters = session.flushWaiters.toList();
    session.flushWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  /// מנסה לשמור מיד; חוזר כשהמצב נשמר, כשהשמירה נכשלה או כשתם הזמן.
  Future<void> _flush(_Session session, Duration timeout) {
    if (session.persisted || session.purged) return Future.value();
    final waiter = Completer<void>();
    session.flushWaiters.add(waiter);
    _scheduleWrite(session, immediate: true);
    return waiter.future.timeout(timeout, onTimeout: () {});
  }

  /// לפני סגירה: שומר ומחזיר את המצבים שעדיין לא נשמרו — גם של סשנים
  /// שהסתיימו או שהלשונית שלהם נסגרה. [tabIds] null = כל התהליך.
  Future<List<({String tabId, String ownerName, String bookId})>>
  unsavedStates({Iterable<String>? tabIds, Duration? timeout}) async {
    final wanted = tabIds?.toSet();
    final sessions = [
      for (final session in [..._sessions.values, ..._finalizing])
        if (!session.purged &&
            (wanted == null || wanted.contains(session.tabId)))
          session,
    ];
    await Future.wait([
      for (final session in sessions) _flush(session, timeout ?? flushTimeout),
    ]);
    return [
      for (final session in sessions)
        if (!session.persisted && !session.purged)
          (
            tabId: session.tabId,
            ownerName: session.ownerName,
            bookId: session.bookId,
          ),
    ];
  }

  Future<Set<String>> unpersistedTabIds(
    Iterable<String> tabIds, {
    Duration? timeout,
  }) async => {
    for (final state in await unsavedStates(tabIds: tabIds, timeout: timeout))
      state.tabId,
  };

  /// לפני יציאה מהתהליך: כל הסשנים, כולל אלה שהסתיימו וטרם נשמרו.
  Future<bool> flushAll({Duration? timeout}) async {
    final sessions = [..._sessions.values, ..._finalizing];
    await Future.wait([
      for (final session in sessions) _flush(session, timeout ?? flushTimeout),
    ]);
    return sessions.every((s) => s.persisted || s.purged);
  }

  /// סוגר את חיבור הטיוטות לפני החלפת נתיב המסדים או בניית runtime מחדש.
  Future<void> prepareForRuntimeReset({String? requestId}) async {
    final preparationId =
        requestId ?? 'runtime-reset-${DateTime.now().microsecondsSinceEpoch}';
    final alreadyPrepared = isProcessQuitPreparedFor(preparationId);
    if (!alreadyPrepared && !beginProcessQuitPreparation(preparationId)) {
      throw StateError('Correction sessions are already being prepared.');
    }
    try {
      final repository = _drafts;
      if (repository == null) return;
      if (!await flushAll()) {
        throw StateError('Correction drafts could not be saved before reset.');
      }
      await shutdown(timeout: flushTimeout);
      await repository.dispose();
      if (identical(_drafts, repository)) _drafts = null;
    } finally {
      if (!alreadyPrepared) cancelProcessQuitPreparation(preparationId);
    }
  }

  Future<bool> prepareForStorageMove(String requestId) async {
    if (!isProcessQuitPreparedFor(requestId)) return false;
    if (_drafts == null) return true;
    if (!await flushAll(timeout: const Duration(seconds: 8))) return false;
    return true;
  }

  Future<bool> finishStorageMovePreparation(String requestId) async {
    if (!isProcessQuitPreparedFor(requestId)) return false;
    final repository = _drafts;
    if (repository == null) return true;
    if (!await flushAll(timeout: const Duration(seconds: 8))) return false;
    endAll('storage_move');
    final ending = [for (final session in _finalizing) session.finished.future];
    try {
      await Future.wait(ending).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return false;
    }
    await repository.dispose();
    if (identical(_drafts, repository)) _drafts = null;
    return true;
  }

  /// התוסף מאשר ששמר את הגרסה המדויקת [version]; רק אז התוכן נמחק.
  Future<Map<String, dynamic>> acknowledge(
    String owner,
    String draftId,
    int version,
  ) async {
    _rejectEditDuringProcessQuit();
    if (draftId.isEmpty || version < 0) {
      _fail('error.invalid_params', 'נדרשים draftId וגרסת טיוטה.');
    }
    final Map<String, Object?> result;
    try {
      result = await _repository.acknowledge(
        pluginId: owner,
        draftId: draftId,
        version: version,
      );
    } catch (error) {
      _fail('error.storage_failed', 'אישור הטיוטה נכשל: $error');
    }
    switch (result['status']) {
      case 'acknowledged':
        for (final session in [..._sessions.values, ..._finalizing]) {
          if (session.owner == owner &&
              session.draftId == draftId &&
              session.version == version) {
            session.conflicts = [];
          }
        }
        notifyListeners();
        return {
          'draftId': draftId,
          'version': version,
          'acknowledged': true,
          'duplicate': false,
        };
      case 'duplicate':
        return {
          'draftId': draftId,
          'version': version,
          'acknowledged': true,
          'duplicate': true,
        };
      case 'conflict':
        _fail(
          'error.revision_conflict',
          'הטיוטה השתנתה מאז גרסה $version '
              '(גרסה נוכחית: ${result['currentVersion'] ?? 'אין תוכן'}); '
              'יש לקרוא אותה מחדש.',
        );
      default:
        _fail('error.not_found', 'טיוטת התיקון אינה קיימת.');
    }
  }

  Future<List<Map<String, dynamic>>> listDrafts(String owner) async {
    _rejectEditDuringProcessQuit();
    try {
      return [
        for (final draft in await _repository.list(owner))
          Map<String, dynamic>.from(draft),
      ];
    } catch (error) {
      _fail('error.storage_failed', 'קריאת הטיוטות נכשלה: $error');
    }
  }

  Future<Map<String, dynamic>> getDraft(String owner, String draftId) async {
    _rejectEditDuringProcessQuit();
    final Map<String, Object?>? draft;
    try {
      draft = await _repository.get(owner, draftId);
    } catch (error) {
      _fail('error.storage_failed', 'קריאת הטיוטה נכשלה: $error');
    }
    if (draft == null) _fail('error.not_found', 'טיוטת התיקון אינה קיימת.');
    return Map<String, dynamic>.from(draft);
  }

  String displayText(String tabId, int index, String source) {
    final change = _sessionForTab(tabId)?.changes[index];
    if (change?['originalSourceText'] == source) {
      return change!['proposedText'] as String;
    }
    return source;
  }

  String editableText(String tabId, int index, String source) =>
      TextRendererService.stripHtml(displayText(tabId, index, source));

  bool hasSessionForTab(String tabId) => _sessionForTab(tabId) != null;

  bool isCorrected(String tabId, int index, String source) =>
      _sessionForTab(tabId)?.changes[index]?['originalSourceText'] == source;

  String? ownerNameForTab(String tabId) => _sessionForTab(tabId)?.ownerName;

  PluginCorrectionDraftStatus? draftStatusForTab(String tabId) {
    final session = _sessionForTab(tabId);
    if (session == null) return null;
    if (session.error != null) return PluginCorrectionDraftStatus.failed;
    return session.persisted
        ? PluginCorrectionDraftStatus.saved
        : PluginCorrectionDraftStatus.saving;
  }

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
    _rejectEditDuringProcessQuit();
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

  /// ההקלדה מוצגת מיד; השמירה העמידה והאירוע מוגבלים בקצב בנפרד.
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
    _changed(session, {index});
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

  static int _changeBytes(Map<String, dynamic> change) =>
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
    // ירידת שורה מותרת בהצעה: זה פיצול הפסקה. מקור הפסקה נבדק ב-
    // [_unsupportedText] ואינו כולל ירידות שורה.
    if (_unsupportedProposed.hasMatch(text)) {
      _fail('error.unsupported_context', 'נתמך רק טקסט פשוט, ללא תגיות.');
    }
    if (!_validUtf16(text)) {
      _fail('error.invalid_params', 'הטקסט מכיל תו פגום.');
    }
  }

  static final _unsupportedProposed = RegExp(
    r'[<>\r\u2028\u2029]|&(?:#[xX]?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);',
  );

  static final _unsupportedText = RegExp(
    r'[<>\r\n  ]|&(?:#[xX]?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);',
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

  static Never _fail(String code, String message) =>
      throw PluginCorrectionException(code, message);
}

class _Session {
  final String id = base64UrlEncode(
    List<int>.generate(24, (_) => Random.secure().nextInt(256)),
  );
  final String owner;
  final String ownerName;
  final String tabId;
  final String bookId;
  final String bookUid;
  final String libraryVersion;
  final String bookSource;
  final int leaseEpoch;
  final String draftId;
  final String token;
  final Future<String> Function(int) loadSource;
  final Future<void> Function()? validateSource;
  final void Function(String topic, Map<String, dynamic> payload)? onEvent;
  int revision = 0;
  int changesBytes = 0;
  Map<int, Map<String, dynamic>> changes = {};
  List<Map<String, dynamic>> conflicts = [];

  /// הגרסה העמידה של ה-commit האחרון, ו-revision שהוא שמר.
  int? version;
  int persistedRevision = 0;
  bool writing = false;
  DateTime? lastWriteStart;
  Timer? writeTimer;
  Timer? retryTimer;
  Object? error;
  int failures = 0;
  bool lost = false;

  /// המצב שלא נשמר של סשן שאיבד את ה-lease נשמר כהתנגשויות אצל הבעלים החדש.
  bool rescued = false;

  /// התיקונים כפי שנשמרו ב-commit האחרון, לחישוב מה טרם נשמר.
  Map<int, Map<String, dynamic>> committed = {};

  /// פסקאות שכתיבה שנכשלה ניסתה לשנות; מצבן במסד אינו ידוע.
  final Map<int, Map<String, dynamic>> uncertain = {};
  bool purged = false;
  bool ended = false;
  final Set<int> pendingEventIndices = {};
  Timer? eventTimer;
  final List<Completer<void>> flushWaiters = [];
  final Completer<void> settled = Completer<void>();
  final Completer<void> finished = Completer<void>();

  _Session({
    required this.owner,
    required this.ownerName,
    required this.tabId,
    required this.bookId,
    required this.bookUid,
    required this.libraryVersion,
    required this.bookSource,
    required this.leaseEpoch,
    required this.draftId,
    required this.token,
    required this.loadSource,
    this.validateSource,
    this.onEvent,
  });

  /// נכון רק כשה-commit האחרון שמר בדיוק את ה-revision הנוכחי.
  bool get persisted =>
      (!lost || rescued) && error == null && persistedRevision == revision;

  String changesJson() => jsonEncode([
    for (final index in (changes.keys.toList()..sort())) changes[index],
  ]);

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
    'draft': {
      'draftId': draftId,
      // גרסה לאישור רק כשהתוכן כאן הוא בדיוק התוכן העמיד שלה.
      'version': persisted && !lost ? version : null,
      'persisted': persisted,
      'pending': !persisted && error == null,
      'displaced': lost,
      'error': error == null ? null : '$error',
      'conflicts': [for (final conflict in conflicts) Map.of(conflict)],
    },
  };
}
