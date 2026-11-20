import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/app_report/services/previous_run_system_events.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/memory_info.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/search/active_lexical_searches.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;

/// מה שהתוכנה הציגה וחיפשה, נשמר לדיסק לדוח על ההפעלה הקודמת.
class SessionContextSnapshot {
  SessionContextSnapshot({
    String? path,
    Map<String, Object?> Function()? capture,
    DateTime Function()? clock,
    Future<Map<String, Object?>> Function()? sampleResources,
    Future<List<Map<String, Object?>>> Function(SessionLock session)?
    systemEvents,
    this.interval = const Duration(seconds: 3),
    this.resourceInterval = const Duration(minutes: 5),
  }) : _pathOverride = path,
       _capture = capture ?? _defaultCapture,
       _clock = clock ?? DateTime.now,
       _sampleResources = sampleResources ?? _defaultResources,
       _systemEvents = systemEvents ?? readPreviousRunSystemEvents;

  static final SessionContextSnapshot instance = SessionContextSnapshot();

  static const String fileName = 'last_context.json';

  final String? _pathOverride;
  final Map<String, Object?> Function() _capture;
  final DateTime Function() _clock;
  final Duration interval;

  /// זיכרון ומקום פנוי משתנים כל הזמן; דגימה בכל סבב הייתה כותבת כל 3 שניות.
  final Duration resourceInterval;
  final Future<Map<String, Object?>> Function() _sampleResources;
  final Future<List<Map<String, Object?>>> Function(SessionLock session)
  _systemEvents;
  Map<String, Object?>? _resources;
  DateTime? _resourcesAt;
  Future<List<Map<String, Object?>>>? _previousSystemEvents;

  Future<Map<String, dynamic>?>? _previous;
  Timer? _timer;
  bool _started = false;
  bool _writing = false;
  String? _lastWritten;

  String get path =>
      _pathOverride ?? p.join(p.dirname(ErrorLogFile.resolvePath()), fileName);

  /// התמונה שההפעלה הקודמת השאירה. נקראת פעם אחת, לפני הכתיבה הראשונה כאן.
  Future<Map<String, dynamic>?> get previous => _previous ??= _read();

  /// התמונה רק אם נשמרה בהפעלה [session], ואירועי המערכת על סיומה. בלי
  /// נעילה (ANR) אין זיהוי אמין של ההפעלה: מספר תהליך עלול להיות בשימוש
  /// חוזר, וזמן יציאה אינו זמן התחלה.
  Future<Map<String, dynamic>?> previousFor(SessionLock? session) async {
    if (session == null) return null;
    final snapshot = await previous;
    final savedAt = DateTime.tryParse('${snapshot?['savedAt']}');
    final matches =
        snapshot != null &&
        snapshot['pid'] == session.pid &&
        savedAt != null &&
        !savedAt.isBefore(session.startedAt);
    // פעם אחת לתהליך: גם הדיאלוג וגם הדיווח האוטומטי מבקשים אותה.
    final events = await (_previousSystemEvents ??= _systemEvents(
      session,
    ).catchError((Object _) => const <Map<String, Object?>>[]));
    if (!matches && events.isEmpty) return null;
    return {
      if (matches) ...snapshot,
      if (events.isNotEmpty) 'systemEvents': events,
    };
  }

  /// מתחיל לשמור. פעם אחת לתהליך.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await previous;
    await record();
    _timer = Timer.periodic(interval, (_) => unawaited(record()));
  }

  @visibleForTesting
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// כותב רק כשהתוכן השתנה. הכתיבה לקובץ זמני ושינוי שם: תהליך שנהרג באמצע
  /// אינו משאיר קובץ חתוך.
  @visibleForTesting
  Future<void> record() async {
    if (_writing) return;
    // הדגימה אינה זורקת; הדגל מונע סבב מקביל בזמן בדיקת כונן איטית.
    _writing = true;
    await _refreshResourcesIfDue();
    _writing = false;
    final Map<String, Object?> snapshot;
    final String encoded;
    try {
      snapshot = {..._capture(), 'resources': ?_resources};
      encoded = jsonEncode(snapshot);
    } catch (error) {
      debugPrint('SessionContextSnapshot: capture failed: $error');
      return;
    }
    if (encoded == _lastWritten) return;
    _writing = true;
    try {
      final target = File(path);
      await target.parent.create(recursive: true);
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'savedAt': _clock().toUtc().toIso8601String(),
          'pid': pid,
          ...snapshot,
        }),
        flush: true,
      );
      await temp.rename(target.path);
      _lastWritten = encoded;
    } catch (error) {
      debugPrint('SessionContextSnapshot: write failed: $error');
    } finally {
      _writing = false;
    }
  }

  Future<void> _refreshResourcesIfDue() async {
    final now = _clock();
    final last = _resourcesAt;
    if (last != null && now.difference(last) < resourceInterval) return;
    _resourcesAt = now;
    try {
      _resources = {
        'sampledAt': now.toUtc().toIso8601String(),
        ...await _sampleResources(),
      };
    } catch (error) {
      debugPrint('SessionContextSnapshot: resources failed: $error');
    }
  }

  Future<Map<String, dynamic>?> _read() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, dynamic> ? json : null;
    } catch (error) {
      debugPrint('SessionContextSnapshot: read failed: $error');
      return null;
    }
  }

  /// הכונן נבדק ב-isolate: כונן רשת מנותק עלול לעכב את הקריאה שניות.
  /// בלינוקס ובמק המקום הפנוי דורש תהליך `df`, ולכן רק ב-Windows.
  static Future<Map<String, Object?>> _defaultResources() async {
    final memory = memoryInfo();
    if (!Platform.isWindows) return memory;
    final library = Settings.isInitialized
        ? Settings.getValue<String>(SettingsRepository.keyLibraryPath)
        : null;
    final dir = library == null || library.isEmpty
        ? p.dirname(ErrorLogFile.resolvePath())
        : library;
    final freeBytes = await Isolate.run(
      () async => (await getDiskSpaceInfo(dir)).freeBytes,
    ).timeout(const Duration(seconds: 10), onTimeout: () => -1);
    return {
      ...memory,
      if (freeBytes >= 0) 'libraryDriveFreeMb': freeBytes >> 20,
    };
  }

  static Map<String, Object?> _defaultCapture() => {
    'context':
        DeveloperDiagnostics.instance.contextProvider?.call() ?? const {},
    'searches': ActiveLexicalSearches.instance.collect(),
  };
}
