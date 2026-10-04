import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_events.dart';
import 'package:otzaria/search_feedback/search_feedback_identity.dart';
import 'package:otzaria/search_feedback/search_feedback_queue.dart';
import 'package:otzaria/search_feedback/search_feedback_sender.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:path/path.dart' as p;

/// גרסת נוסח ההסכמה. הסכמה שנשמרה לגרסה ישנה נקראת כ-`unknown`.
const int kSearchFeedbackConsentVersion = 1;

/// מפתח מקומי ב-ClientContext של אירועי התצוגה המקדימה בפיתוח; מוסר לפני
/// שליחה, ומקטע שנושא אותו לעולם אינו נשלח לשרת הייצור.
const String kSearchFeedbackLocalOnlyKey = 'localOnly';

/// יוצר טיימר חד-פעמי (ניתן להחלפה בבדיקות).
typedef SearchFeedbackTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// אחסון מצב ההסכמה.
abstract interface class SearchFeedbackConsentPersistence {
  String? readState();
  int? readVersion();
  Future<void> write(String state, int version);
}

/// אחסון ההסכמה בהגדרות האפליקציה.
class SettingsSearchFeedbackConsentPersistence
    implements SearchFeedbackConsentPersistence {
  const SettingsSearchFeedbackConsentPersistence();

  @override
  String? readState() =>
      Settings.getValue<String>(SettingsRepository.keySearchFeedbackConsent);

  @override
  int? readVersion() => Settings.getValue<int>(
    SettingsRepository.keySearchFeedbackConsentVersion,
  );

  @override
  Future<void> write(String state, int version) async {
    await Settings.setValue<String>(
      SettingsRepository.keySearchFeedbackConsent,
      state,
    );
    await Settings.setValue<int>(
      SettingsRepository.keySearchFeedbackConsentVersion,
      version,
    );
  }
}

/// ערוץ המשוב האנונימי של החיפוש הסמנטי: הסכמה, תור מתמשך ושליחה חתומה.
/// הבנאי אינו מבצע I/O; הכול נטען בשימוש הראשון ולא בעליית התוכנה.
class SearchFeedbackService
    implements SearchFeedbackConsentStore, SearchFeedbackRecorder {
  SearchFeedbackService({
    http.Client? client,
    Uri? baseUrl,
    DateTime Function()? clock,
    Future<Directory> Function()? storageDirectory,
    SearchFeedbackConsentPersistence? consentPersistence,
    bool Function()? sendingAllowed,
    bool? buildAllowsSending,
    String Function()? appVersion,
    String Function()? platform,
    String Function()? osVersion,
    String Function()? locale,
    Random? random,
    SearchFeedbackTimerFactory? timerFactory,
    bool Function()? isSecondaryWindow,
    Stream<String>? settingsChangesFromOtherWindows,
    this.flushDebounce = const Duration(seconds: 30),
    this.periodicInterval = const Duration(minutes: 10),
    int maxQueuedEvents = 5000,
    int maxQueuedBytes = 5 * 1024 * 1024,
  }) : _injectedClient = client,
       _clock = clock ?? DateTime.now,
       _consentPersistence =
           consentPersistence ??
           const SettingsSearchFeedbackConsentPersistence(),
       _sendingAllowed = sendingAllowed ?? _defaultSendingAllowed,
       _buildAllowsSending =
           buildAllowsSending ??
           buildAllowsSendingFor(
             debugMode: kDebugMode,
             sendInDebug: _sendInDebug,
           ),
       _appVersion = appVersion ?? (() => ErrorLogFile.appVersion),
       _platform = platform ?? (() => Platform.operatingSystem),
       _osVersion = osVersion ?? _defaultOsVersion,
       _locale = locale ?? _defaultLocale,
       _random = random ?? Random.secure(),
       _timerFactory = timerFactory ?? Timer.new,
       _isSecondaryWindow = isSecondaryWindow ?? (() => WindowRole.isSecondary),
       _baseUrl = baseUrl ?? resolveBaseUrl(_baseUrlOverride) {
    final directory = storageDirectory ?? _defaultStorageDirectory;
    _identityStore = SearchFeedbackIdentityStore(directory);
    _queue = SearchFeedbackQueue(
      directory,
      clock: _clock,
      maxEvents: maxQueuedEvents,
      maxBytes: maxQueuedBytes,
    );
    _sender = SearchFeedbackSender(
      client: _httpClient,
      baseUrl: _baseUrl,
      clock: _clock,
    );
    _events = SearchFeedbackEventBuilder(clock: _clock, newId: newId);
    // הסכמה שהשתנתה בחלון אחר מגיעה ל-box המקומי דרך SettingsSync.
    (settingsChangesFromOtherWindows ?? SettingsSync.instance.changes).listen(
      _onSettingChangedElsewhere,
    );
  }

  /// המופע המשותף; נוצר בגישה הראשונה בלבד.
  static final SearchFeedbackService instance = SearchFeedbackService();

  static final Uri defaultBaseUrl = Uri.parse('https://otzaria.org');

  static const bool _sendInDebug = bool.fromEnvironment(
    'SEARCH_FEEDBACK_SEND_IN_DEBUG',
  );
  static const String _baseUrlOverride = String.fromEnvironment(
    'SEARCH_FEEDBACK_BASE_URL',
  );

  /// בבניית debug לא שולחים כלל (רק תור מקומי), אלא אם
  /// `--dart-define=SEARCH_FEEDBACK_SEND_IN_DEBUG=true` — כדי לא לזהם את נתוני האימון.
  static bool buildAllowsSendingFor({
    required bool debugMode,
    required bool sendInDebug,
  }) => !debugMode || sendInDebug;

  /// `SEARCH_FEEDBACK_BASE_URL` (http/https) גובר על כתובת ברירת המחדל.
  static Uri resolveBaseUrl(String override) {
    final uri = Uri.tryParse(override.trim());
    final valid =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    return valid ? uri : defaultBaseUrl;
  }

  /// אחרי כמה תשובות לא-פרוטוקוליות (דף חסימה של מסנן) מוותרים על אצווה.
  static const int maxUnrecognizedStrikes = 5;

  /// 5xx רצופים לאותה אצווה: מוותרים רק אחרי מספר ניסיונות וגם פרק זמן.
  static const int maxServerErrorStrikes = 5;
  static const Duration serverErrorGiveUpAfter = Duration(hours: 24);

  /// אירועים ישנים מזה אינם נשלחים (השרת דוחה אחרי 30 יום).
  static const Duration maxEventAge = Duration(days: 29);
  static const Duration _backoffBase = Duration(seconds: 30);
  static const Duration _backoffMax = Duration(hours: 6);
  static const Duration _retryAfterMax = Duration(hours: 24);

  final Duration flushDebounce;
  final Duration periodicInterval;

  final http.Client? _injectedClient;
  final DateTime Function() _clock;
  final SearchFeedbackConsentPersistence _consentPersistence;
  final bool Function() _sendingAllowed;
  final bool _buildAllowsSending;
  final String Function() _appVersion;
  final String Function() _platform;
  final String Function() _osVersion;
  final String Function() _locale;
  final Random _random;
  final SearchFeedbackTimerFactory _timerFactory;
  final bool Function() _isSecondaryWindow;
  final Uri _baseUrl;

  /// שליחה לשרת הייצור (בלי `SEARCH_FEEDBACK_BASE_URL`).
  bool get _targetsProduction => _baseUrl == defaultBaseUrl;

  late final SearchFeedbackIdentityStore _identityStore;
  late final SearchFeedbackQueue _queue;
  late final SearchFeedbackSender _sender;
  late final SearchFeedbackEventBuilder _events;

  final StreamController<SearchFeedbackConsent> _changes =
      StreamController<SearchFeedbackConsent>.broadcast();

  http.Client? _ownedClient;
  SearchFeedbackIdentity? _identity;
  bool _identityLoaded = false;
  bool _blocked = false;
  bool _sessionFlushDone = false;
  Future<void>? _flushing;
  Future<void> _identityTail = Future.value();
  Timer? _debounceTimer;
  Timer? _nextFlushTimer;
  DateTime? _backoffUntil;
  int _backoffStep = 0;
  Future<void> _lastEnqueue = Future.value();

  /// מתחלף בכל ביטול הסכמה; פעולה שהחלה לפניו אינה כותבת לדיסק אחריו.
  int _epoch = 0;

  /// מזהה חדש לפי הפרוטוקול (למשל searchSessionId לכל שאילתה).
  String newId() => newSearchFeedbackId(_random);

  @visibleForTesting
  SearchFeedbackQueue get queue => _queue;

  @visibleForTesting
  DateTime? get backoffUntil => _backoffUntil;

  /// מסתיים כשהאירוע האחרון שנרשם נכתב לתור.
  Future<void> whenQueued() => _lastEnqueue;

  @visibleForTesting
  Future<void> settle() => whenQueued();

  void _onSettingChangedElsewhere(String key) {
    if (key != SettingsRepository.keySearchFeedbackConsent && key.isNotEmpty) {
      return;
    }
    final current = consent;
    if (current != SearchFeedbackConsent.granted) {
      _epoch++;
      _cancelTimers();
    }
    _changes.add(current);
  }

  // ── הסכמה ────────────────────────────────────────────────────────────────

  @override
  SearchFeedbackConsent get consent {
    try {
      final state = _consentPersistence.readState();
      if (state == 'declined') return SearchFeedbackConsent.declined;
      if (state == 'granted' &&
          (_consentPersistence.readVersion() ?? 0) >=
              kSearchFeedbackConsentVersion) {
        return SearchFeedbackConsent.granted;
      }
    } catch (error, stackTrace) {
      _log('consent read', error, stackTrace);
    }
    return SearchFeedbackConsent.unknown;
  }

  @override
  Stream<SearchFeedbackConsent> get changes => _changes.stream;

  @override
  Future<void> grant() async {
    await _ensureIdentityLoaded();
    if (_blocked) {
      // הסכמה מחודשת אחרי חסימה = זהות אנונימית חדשה.
      await _resetIdentity();
    }
    await _consentPersistence.write('granted', kSearchFeedbackConsentVersion);
    _changes.add(SearchFeedbackConsent.granted);
    _startSessionFlush();
  }

  @override
  Future<void> decline() async {
    await _consentPersistence.write('declined', kSearchFeedbackConsentVersion);
    _cancelTimers();
    _changes.add(SearchFeedbackConsent.declined);
  }

  @override
  Future<void> revoke() async {
    _epoch++;
    _cancelTimers();
    await _consentPersistence.write('declined', kSearchFeedbackConsentVersion);
    _changes.add(SearchFeedbackConsent.declined);
    await _queue.purge();
    await _resetIdentity();
    _backoffUntil = null;
    _backoffStep = 0;
  }

  Future<void> _resetIdentity() => _identityOp(() async {
    await _identityStore.delete();
    _identity = null;
    _identityLoaded = true;
    _blocked = false;
  });

  // ── רישום אירועים ────────────────────────────────────────────────────────

  @override
  bool get isCollecting =>
      !_blocked && consent == SearchFeedbackConsent.granted;

  @override
  void recordSearch(SemanticSearchContext context) =>
      _record(context, () => _events.search(context));

  @override
  void recordResultsShown(
    SemanticSearchContext context,
    int offset,
    List<SemanticResultSnapshot> results,
  ) => _record(context, () => _events.resultsShown(context, offset, results));

  @override
  String recordOpen(
    SemanticSearchContext context,
    SemanticResultSnapshot result,
    SearchFeedbackOpenVia via,
  ) {
    final openId = newId();
    _record(context, () => _events.open(context, result, via, openId));
    return openId;
  }

  @override
  void recordDwell(
    SemanticSearchContext context,
    String openId,
    Duration dwell,
    SearchFeedbackDwellEnd end,
  ) => _record(context, () => _events.dwell(context, openId, dwell, end));

  @override
  void recordVote(
    SemanticSearchContext context,
    SemanticResultSnapshot result,
    SearchFeedbackVote vote,
  ) => _record(context, () => _events.vote(context, result, vote));

  void _record(
    SemanticSearchContext context,
    Map<String, Object?>? Function() build,
  ) {
    try {
      if (!isCollecting) return;
      final event = build();
      if (event == null) return;
      final clientContext = _clientContext(context);
      final epoch = _epoch;
      // שרשור: האירועים נכתבים לתור בסדר שבו נרשמו.
      final pending = _lastEnqueue.then(
        (_) => _enqueue(event, clientContext, epoch),
      );
      _lastEnqueue = pending;
      unawaited(pending);
    } catch (error, stackTrace) {
      _log('record', error, stackTrace);
    }
  }

  Future<void> _enqueue(
    Map<String, Object?> event,
    Map<String, Object?> clientContext,
    int epoch,
  ) async {
    try {
      await _ensureIdentityLoaded();
      if (epoch != _epoch || !isCollecting) return;
      await _queue.append(event, clientContext);
      _debounceTimer?.cancel();
      _debounceTimer = _timerFactory(flushDebounce, _flushFromTimer);
      _startSessionFlush();
    } catch (error, stackTrace) {
      _log('enqueue', error, stackTrace);
    }
  }

  Map<String, Object?> _clientContext(SemanticSearchContext context) => {
    'app': 'otzaria',
    'appVersion': truncateForSearchFeedback(_appVersion(), 64),
    'platform': _platform(),
    'osVersion': _osVersion(),
    'locale': _locale(),
    'engine': searchFeedbackEngineJson(context.engine),
    if (context.response.fallbackReason == kSemanticDebugPreviewFallbackReason)
      kSearchFeedbackLocalOnlyKey: true,
  };

  // ── שליחה ────────────────────────────────────────────────────────────────

  /// ניסיון שליחה אחד של התור, אם יש הסכמה, רשת מותרת ואין השהיה פעילה.
  Future<void> flush() => _flushing ??= _flush().whenComplete(
    () => _flushing = null,
  );

  void _flushFromTimer() => unawaited(flush());

  void _startSessionFlush() {
    if (_sessionFlushDone) return;
    _sessionFlushDone = true;
    unawaited(flush());
  }

  Future<void> _flush() async {
    final epoch = _epoch;
    try {
      if (consent != SearchFeedbackConsent.granted) return;
      // חלון משני רק כותב לתור המשותף; החלון הראשי הוא ששולח.
      if (_isSecondaryWindow()) return;
      await _queue.load();
      await _reloadIdentity();
      if (_blocked || _queue.isEmpty) return;
      if (!_buildAllowsSending || !_sendingAllowed()) return;
      final until = _backoffUntil;
      if (until != null && _clock().isBefore(until)) return;

      final names = await _queue.sealAndList();
      if (_blocked || names.isEmpty) return;
      final identity = await _identityForSending(epoch);
      if (identity == null) return;
      for (final name in names) {
        if (epoch != _epoch ||
            consent != SearchFeedbackConsent.granted ||
            !_sendingAllowed()) {
          return;
        }
        final claimed = await _queue.claim(name);
        if (claimed == null) continue;
        if (!await _sendSegment(claimed, identity, epoch)) return;
      }
    } catch (error, stackTrace) {
      _log('flush', error, stackTrace);
      _applyBackoff(null);
    } finally {
      if (epoch == _epoch) _scheduleNextFlush();
    }
  }

  /// true = להמשיך לאצווה הבאה.
  Future<bool> _sendSegment(
    String name,
    SearchFeedbackIdentity identity,
    int epoch,
  ) async {
    final batch = await _queue.read(
      name,
      notBefore: _clock().subtract(maxEventAge),
    );
    if (batch == null) return true;
    final localOnly = batch.contextJson.contains(
      '"$kSearchFeedbackLocalOnlyKey":true',
    );
    if (batch.eventLines.isEmpty || (localOnly && _targetsProduction)) {
      await _queue.remove(name);
      return true;
    }
    var outcome = await _postBatch(
      localOnly ? batch.withoutContextKey(kSearchFeedbackLocalOnlyKey) : batch,
      identity,
    );
    if (outcome.kind == SearchFeedbackOutcomeKind.unknownKey) {
      identity.registeredKeyId = null;
      if (!await _register(identity, epoch)) return false;
      outcome = await _postBatch(batch, identity);
      if (outcome.kind == SearchFeedbackOutcomeKind.unknownKey) {
        _applyBackoff(null);
        return false;
      }
    }
    if (epoch != _epoch) return false;

    switch (outcome.kind) {
      case SearchFeedbackOutcomeKind.accepted:
        if (outcome.rejected > 0 && kDebugMode) {
          debugPrint(
            'SearchFeedback: server skipped ${outcome.rejected} events',
          );
        }
        await _queue.remove(name);
        _backoffStep = 0;
        _backoffUntil = null;
        return true;
      case SearchFeedbackOutcomeKind.drop:
        await _queue.remove(name);
        return true;
      case SearchFeedbackOutcomeKind.tooLarge:
        await _queue.split(name);
        return true;
      case SearchFeedbackOutcomeKind.keyBlocked:
        await _block(identity, epoch);
        return false;
      case SearchFeedbackOutcomeKind.unknownKey:
      case SearchFeedbackOutcomeKind.retryLater:
        if (await _strikeOut(name, outcome.strike)) {
          await _queue.remove(name);
        }
        _applyBackoff(outcome.retryAfter);
        return false;
    }
  }

  /// true = האצווה נכשלה מספיק פעמים כדי לוותר עליה.
  Future<bool> _strikeOut(String name, SearchFeedbackStrike strike) async {
    if (strike == SearchFeedbackStrike.none) return false;
    final now = _clock();
    final record = await _queue.addStrike(name, strike.name, now);
    return switch (strike) {
      SearchFeedbackStrike.filtered => record.count >= maxUnrecognizedStrikes,
      SearchFeedbackStrike.serverError =>
        record.count >= maxServerErrorStrikes &&
            now.difference(record.firstAt) >= serverErrorGiveUpAfter,
      SearchFeedbackStrike.none => false,
    };
  }

  Future<SearchFeedbackOutcome> _postBatch(
    SearchFeedbackStoredBatch batch,
    SearchFeedbackIdentity identity,
  ) {
    final body =
        '{"schema":1,"batchId":"${newId()}",'
        '"sentAt":"${searchFeedbackIsoTime(_clock())}",'
        '"context":${batch.contextJson},'
        '"events":[${batch.eventLines.join(',')}]}';
    return _sender.sendEvents(
      identity: identity,
      body: body,
      appVersion: _appVersion(),
    );
  }

  /// זהות רשומה לשליחה; יוצרת ורושמת בפעם הראשונה. null = לא עכשיו.
  Future<SearchFeedbackIdentity?> _identityForSending(int epoch) async {
    var identity = _identity;
    if (identity == null) {
      final created = SearchFeedbackIdentity.generate(_random);
      final saved = await _identityOp(() async {
        if (epoch != _epoch) return false;
        await _identityStore.save(created);
        _identity = created;
        return true;
      });
      if (!saved) return null;
      identity = created;
    }
    if (identity.isRegistered) return identity;
    return await _register(identity, epoch) ? identity : null;
  }

  Future<bool> _register(SearchFeedbackIdentity identity, int epoch) async {
    final body = searchFeedbackJsonEncode({
      'schema': 1,
      'publicKey': identity.publicKeyBase64,
      'app': 'otzaria',
      'appVersion': truncateForSearchFeedback(_appVersion(), 64),
      'platform': _platform(),
      'createdAt': searchFeedbackIsoTime(_clock()),
    });
    final outcome = await _sender.register(
      identity: identity,
      body: body,
      appVersion: _appVersion(),
    );
    if (epoch != _epoch) return false;
    switch (outcome.kind) {
      case SearchFeedbackOutcomeKind.accepted:
        if (outcome.keyId != null && outcome.keyId != identity.keyId) {
          _applyBackoff(null);
          return false;
        }
        identity.registeredKeyId = identity.keyId;
        await _identityOp(() async {
          if (epoch == _epoch) await _identityStore.save(identity);
        });
        return true;
      case SearchFeedbackOutcomeKind.keyBlocked:
        await _block(identity, epoch);
        return false;
      default:
        _applyBackoff(outcome.retryAfter);
        return false;
    }
  }

  Future<void> _block(SearchFeedbackIdentity identity, int epoch) async {
    if (epoch != _epoch) return;
    _blocked = true;
    identity.blocked = true;
    _cancelTimers();
    await _identityOp(() async {
      if (epoch == _epoch) await _identityStore.save(identity);
    });
    await _queue.purge();
  }

  void _applyBackoff(Duration? retryAfter) {
    _backoffStep++;
    final Duration delay;
    if (retryAfter != null) {
      delay = retryAfter > _retryAfterMax ? _retryAfterMax : retryAfter;
    } else {
      final factor = 1 << min(_backoffStep - 1, 20);
      final exponential = _backoffBase * factor;
      delay = exponential > _backoffMax ? _backoffMax : exponential;
    }
    _backoffUntil = _clock().add(delay);
  }

  /// טיימר מחזורי רק כשהתור אינו ריק; בזמן השהיה — עד סופה.
  void _scheduleNextFlush() {
    _nextFlushTimer?.cancel();
    _nextFlushTimer = null;
    if (_blocked ||
        _queue.isEmpty ||
        !isCollecting ||
        !_buildAllowsSending ||
        _isSecondaryWindow()) {
      return;
    }
    final until = _backoffUntil;
    final now = _clock();
    final delay = until != null && now.isBefore(until)
        ? until.difference(now)
        : periodicInterval;
    _nextFlushTimer = _timerFactory(delay, _flushFromTimer);
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _nextFlushTimer?.cancel();
    _nextFlushTimer = null;
  }

  // ── עזרים ────────────────────────────────────────────────────────────────

  /// קורא שוב את קובץ הזהות: ביטול בחלון אחר מוחק אותו, ואסור לרשום מחדש
  /// מפתח מבוטל מהזיכרון.
  Future<void> _reloadIdentity() => _identityOp(() async {
    _identity = await _identityStore.load();
    _blocked = _identity?.blocked ?? false;
    _identityLoaded = true;
  });

  Future<void> _ensureIdentityLoaded() => _identityOp(() async {
    if (_identityLoaded) return;
    _identity = await _identityStore.load();
    _blocked = _identity?.blocked ?? false;
    _identityLoaded = true;
  });

  Future<T> _identityOp<T>(Future<T> Function() action) {
    final result = _identityTail.then((_) => action());
    _identityTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  http.Client _httpClient() {
    final injected = _injectedClient;
    if (injected != null) return injected;
    var owned = _ownedClient;
    if (owned == null) {
      owned = http.Client();
      HttpClientRegistry.register(owned.close);
      _ownedClient = owned;
    }
    return owned;
  }

  static Future<Directory> _defaultStorageDirectory() async =>
      Directory(p.join(await AppPaths.getDataRootPath(), 'search_feedback'));

  static bool _defaultSendingAllowed() {
    try {
      return !(Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ??
          false);
    } catch (_) {
      // Settings לא אותחל — לא יוצאים לרשת.
      return false;
    }
  }

  static String? _cachedOsVersion;

  static String _defaultOsVersion() =>
      _cachedOsVersion ??= coarseOsVersion(Platform.operatingSystemVersion);

  static String _defaultLocale() {
    try {
      return resolveSettingsLanguage(
        Settings.getValue<String>(SettingsRepository.keySettingsLanguage),
      ).code;
    } catch (_) {
      return 'he';
    }
  }

  static void _log(String step, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('SearchFeedback $step failed: $error\n$stackTrace');
    }
  }
}
