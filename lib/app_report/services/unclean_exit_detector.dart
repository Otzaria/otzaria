import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/app_report/services/breakpad_envelope.dart';
import 'package:otzaria/app_report/services/minidump_signature.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// תוכן `logs/session.lock` — סימן שהתהליך רץ ועוד לא נסגר כראוי.
@immutable
class SessionLock {
  const SessionLock({
    required this.pid,
    required this.version,
    required this.startedAt,
  });

  final int pid;
  final String version;
  final DateTime startedAt;

  Map<String, dynamic> toJson() => {
    'pid': pid,
    'version': version,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };

  static SessionLock? tryParse(String content) {
    try {
      final json = jsonDecode(content);
      if (json is! Map) return null;
      final pid = json['pid'];
      final startedAt = DateTime.tryParse('${json['startedAt']}');
      if (pid is! int || startedAt == null) return null;
      return SessionLock(
        pid: pid,
        version: '${json['version'] ?? ''}',
        startedAt: startedAt,
      );
    } catch (_) {
      return null;
    }
  }
}

/// סוג האירוע שמדווחים עליו: סגירה לא צפויה, או תוכנה שהפסיקה להגיב.
enum CrashIncidentKind { crash, hang }

/// קריסה של ההפעלה הקודמת: הנעילה שנשארה, הראיות והחתימה.
class CrashCandidate {
  const CrashCandidate({
    required SessionLock this.previousSession,
    required this.entries,
    required this.signature,
    required this.hasStartupStall,
    required this.hasMinidump,
    this.minidump,
    this.minidumpSignature,
    this.kind = CrashIncidentKind.crash,
  }) : hangDuration = null,
       details = null,
       occurredInPreviousRun = true;

  /// תקיעה שזוהתה בזמן ריצה (או ANR של אנדרואיד). [details] נכנס לאבחון
  /// הפרטי, למשל מחסנית שאינה ב-errors.txt.
  const CrashCandidate.hang({
    required this.signature,
    this.hangDuration,
    this.details,
    this.entries = const [],
    this.previousSession,
    this.occurredInPreviousRun = false,
  }) : kind = CrashIncidentKind.hang,
       hasStartupStall = false,
       hasMinidump = false,
       minidump = null,
       minidumpSignature = null;

  final CrashIncidentKind kind;

  /// קובע את נוסח ההצעה: ANR מגיע מההפעלה הקודמת גם בלי [previousSession].
  final bool occurredInPreviousRun;

  bool get isHang => kind == CrashIncidentKind.hang;

  /// משך התקיעה, כשהיא הסתיימה ונמדדה.
  final Duration? hangDuration;

  final String? details;

  /// null בתקיעה שזוהתה בהפעלה הנוכחית.
  final SessionLock? previousSession;

  /// רשומות errors.txt מאז תחילת ההפעלה הקודמת, מהישנה לחדשה.
  final List<ErrorLogBlock> entries;

  /// מהרשומה החדשה ביותר, ובלעדיה מה-minidump החדש ביותר; null כשאין
  /// מאיפה (`last_crash` בלבד, או dump שאינו ניתן לפענוח).
  final CrashSignature? signature;
  final bool hasStartupStall;
  final bool hasMinidump;

  /// ה-dump החדש ביותר מאז תחילת ההפעלה הקודמת, לצירוף בהסכמת המשתמש.
  final File? minidump;

  /// חתימת [minidump] גם כש-[signature] נלקחה מרשומה ב-errors.txt.
  final CrashSignature? minidumpSignature;
}

/// מזהה יציאה לא נקייה של ההפעלה הקודמת. לוגיקה בלבד — הקריאה מהעלייה
/// והסימון בסגירה שייכים לתהליך.
class UncleanExitDetector {
  UncleanExitDetector({
    String? logsDirectory,
    List<String>? sentryDatabaseDirs,
    bool Function(int pid)? isProcessAlive,
    DateTime? Function(int pid)? processCreatedAt,
    int? currentPid,
    DateTime? processStartedAt,
    DateTime Function()? clock,
  }) : logsDirectory = logsDirectory ?? p.dirname(ErrorLogFile.resolvePath()),
       _sentryDirs = sentryDatabaseDirs,
       _isProcessAlive = isProcessAlive ?? defaultIsProcessAlive,
       _processCreatedAt =
           processCreatedAt ??
           (isProcessAlive == null ? defaultProcessCreatedAt : (_) => null),
       _currentPid = currentPid ?? pid,
       _processStartedAt = processStartedAt ?? (clock ?? DateTime.now)();

  static const String lockFileName = 'session.lock';

  /// ה-runner של Windows כותב `startup-<pid>.lock` בתחילת התהליך, בפורמט של
  /// [SessionLock]. נשאר רק כשהתהליך מת לפני [startSession].
  static const String startupLockPrefix = 'startup-';
  static const String startupLockSuffix = '.lock';

  /// נעילת עלייה של תהליך חי (pid ממוחזר) נמחקת אחרי הזמן הזה.
  static const Duration staleStartupLockAge = Duration(days: 7);

  final String logsDirectory;
  final List<String>? _sentryDirs;
  final bool Function(int pid) _isProcessAlive;
  final DateTime? Function(int pid) _processCreatedAt;
  final int _currentPid;
  final DateTime _processStartedAt;

  String get lockPath => p.join(logsDirectory, lockFileName);
  String get errorLogPath => p.join(logsDirectory, ErrorLogFile.fileName);
  String startupLockPath(int processId) =>
      p.join(logsDirectory, '$startupLockPrefix$processId$startupLockSuffix');

  /// כותב את נעילת ההפעלה הנוכחית. יש לקרוא אחרי [detectPreviousCrash].
  Future<void> startSession({required String version}) async {
    final lock = SessionLock(
      pid: _currentPid,
      version: version,
      startedAt: _processStartedAt,
    );
    final file = File(lockPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(lock.toJson()), flush: true);
    await _deleteOwnStartupLock();
  }

  Future<void> _deleteOwnStartupLock() async {
    try {
      await File(startupLockPath(_currentPid)).delete();
    } on FileSystemException {
      // אין נעילת עלייה (לא Windows, או שה-runner לא כתב).
    }
  }

  /// מוחק את הנעילה ביציאה מסודרת (סינכרוני — מסלול הסגירה אינו ממתין).
  void markCleanExitSync() {
    try {
      final file = File(lockPath);
      if (_ownsLock(file)) file.deleteSync();
    } on FileSystemException {
      // אין נעילה — אין מה לסמן.
    }
    try {
      File(startupLockPath(_currentPid)).deleteSync();
    } on FileSystemException {
      // כבר נמחקה ב-startSession.
    }
  }

  /// נעילה של תהליך אחר שייכת להפעלה שטרם נבדקה — מחיקתה תאבד את הקריסה.
  bool _ownsLock(File file) {
    try {
      if (!file.existsSync()) return false;
      final lock = SessionLock.tryParse(file.readAsStringSync());
      return lock == null || lock.pid == _currentPid;
    } catch (_) {
      return false;
    }
  }

  /// מחזיר מועמד לקריסה רק כשנשארה נעילה של תהליך שאינו חי, ויש ראיה לקריסה:
  /// רשומת שגיאה מאז תחילתו, `Startup stall`, או minidump של Sentry.
  /// נעילת עלייה מכסה תהליך שמת לפני שכתב את `session.lock`.
  Future<CrashCandidate?> detectPreviousCrash() async {
    for (final dir in _sentryDirs ?? defaultSentryDatabaseDirs()) {
      await pruneRecoveredMinidumps(dir);
    }
    final abandoned = await _takeAbandonedStartupLocks();
    SessionLock? lock;
    try {
      final file = File(lockPath);
      if (await file.exists()) {
        lock = SessionLock.tryParse(await file.readAsString());
      }
    } catch (_) {}
    if (lock != null && (lock.pid == _currentPid || _isStillRunning(lock))) {
      lock = null;
    }
    // הוותיקה מכולן: רשומות של כל ההפעלות שלא נסגרו נכנסות לבדיקה.
    final previous = [?lock, ...abandoned].fold<SessionLock?>(
      null,
      (oldest, next) =>
          oldest == null || next.startedAt.isBefore(oldest.startedAt)
          ? next
          : oldest,
    );
    if (previous == null) return null;

    final blocks = await _errorBlocksSince(
      previous.startedAt,
      until: _processStartedAt,
    );
    final hasStall = blocks.any((b) => b.isStartupStall);
    final dump = await _minidumpSince(previous.startedAt);
    // תקיעה שהשתחררה כבר דווחה בזמן ריצה; שלא השתחררה — התהליך נהרג תקוע.
    bool unrecoveredHang(ErrorLogBlock hang) =>
        hang.isAppHang &&
        !blocks.any(
          (b) =>
              b.isAppHangRecovered && !b.timestamp!.isBefore(hang.timestamp!),
        );
    final evidence = blocks
        .where((b) => b.isCrashEvidence || unrecoveredHang(b))
        .toList();
    if (evidence.isEmpty && !dump.found) return null;

    final newestDump = dump.newest;
    final dumpSignature = newestDump == null
        ? null
        : await readMinidumpSignature(newestDump);
    return CrashCandidate(
      previousSession: previous,
      entries: blocks,
      signature: evidence.isNotEmpty ? evidence.last.signature : dumpSignature,
      hasStartupStall: hasStall,
      hasMinidump: dump.found,
      minidump: newestDump,
      minidumpSignature: dumpSignature,
      kind: evidence.isNotEmpty && evidence.last.isAppHang
          ? CrashIncidentKind.hang
          : CrashIncidentKind.crash,
    );
  }

  /// נעילות עלייה של תהליכים שמתו, ונמחקות מיד כדי שאותה הפעלה לא תוצע שוב.
  Future<List<SessionLock>> _takeAbandonedStartupLocks() async {
    final abandoned = <SessionLock>[];
    try {
      final dir = Directory(logsDirectory);
      if (!await dir.exists()) return abandoned;
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        if (entity is! File ||
            !name.startsWith(startupLockPrefix) ||
            !name.endsWith(startupLockSuffix)) {
          continue;
        }
        try {
          final lock = SessionLock.tryParse(await entity.readAsString());
          if (lock != null && lock.pid == _currentPid) continue;
          if (lock != null && _isStillRunning(lock)) {
            final age = _processStartedAt.difference(lock.startedAt);
            if (age < staleStartupLockAge) continue;
          } else if (lock != null) {
            abandoned.add(lock);
          }
          await entity.delete();
        } on FileSystemException {
          // נעולה או נמחקה בינתיים — תיבדק בהפעלה הבאה.
        }
      }
    } on FileSystemException {
      // תיקייה לא קריאה אינה ראיה.
    }
    return abandoned;
  }

  /// התקיעה האחרונה שהתהליך הנוכחי רשם, אחרי שהגלאי הנייטיב דיווח שהשתחררה.
  Future<CrashCandidate?> detectRecoveredHang({Duration? duration}) async {
    final blocks = await _errorBlocksSince(_processStartedAt, until: null);
    final hangs = blocks.where((b) => b.isAppHang);
    if (hangs.isEmpty) return null;
    return CrashCandidate.hang(
      signature: hangs.last.signature,
      hangDuration: duration,
      entries: blocks,
    );
  }

  bool _isStillRunning(SessionLock lock) {
    try {
      if (!_isProcessAlive(lock.pid)) return false;
      // תהליך שנוצר אחרי הנעילה קיבל pid ממוחזר; בעל הנעילה כבר מת.
      final created = _processCreatedAt(lock.pid);
      return created == null ||
          !created.isAfter(lock.startedAt.add(const Duration(seconds: 2)));
    } catch (_) {
      // בלי בדיקה אמינה: נעילה שנכתבה לפני שהתהליך הזה עלה שייכת להפעלה קודמת.
      return !lock.startedAt.isBefore(_processStartedAt);
    }
  }

  Future<List<ErrorLogBlock>> _errorBlocksSince(
    DateTime since, {
    required DateTime? until,
  }) async {
    try {
      final file = File(errorLogPath);
      if (!await file.exists()) return const [];
      final stat = await file.stat();
      if (stat.modified.isBefore(since)) return const [];
      // הלוג אינו מוגבל בגודלו והבדיקה רצה בעלייה: רק הזנב, והפענוח ב-isolate.
      final content = await _readTail(file, maxErrorLogReadBytes);
      return await _blocksInIsolate(content, since, until);
    } catch (error) {
      debugPrint('UncleanExitDetector: errors.txt unreadable: $error');
      return const [];
    }
  }

  static const int maxErrorLogReadBytes = 4 * 1000 * 1000;

  /// סטטית: סגירה בתוך מתודת מופע עלולה ללכוד את `this` שאינו ניתן להעברה.
  static Future<List<ErrorLogBlock>> _blocksInIsolate(
    String content,
    DateTime since,
    DateTime? until,
  ) => Isolate.run(
    () =>
        parseErrorLogBlocks(content)
            .where(
              (b) =>
                  b.timestamp != null &&
                  !b.timestamp!.isBefore(since) &&
                  // רשומות של התהליך הנוכחי אינן ראיה לקריסה של הקודם.
                  (until == null || b.timestamp!.isBefore(until)),
            )
            .toList()
          ..sort((a, b) => a.timestamp!.compareTo(b.timestamp!)),
  );

  static Future<String> _readTail(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final start = length > maxBytes ? length - maxBytes : 0;
      await raf.setPosition(start);
      return utf8.decode(await raf.read(length - start), allowMalformed: true);
    } finally {
      await raf.close();
    }
  }

  /// sentry-native כותב `last_crash` ו-minidumps תחת `.sentry-native`.
  /// [newest] — ה-dump החדש ביותר מאז [since], לחתימה.
  Future<({bool found, File? newest})> _minidumpSince(DateTime since) async {
    var found = false;
    File? newest;
    DateTime? newestModified;
    for (final dir in _sentryDirs ?? defaultSentryDatabaseDirs()) {
      try {
        // ב-ARM64 (breakpad) ה-dump נמצא רק בתוך envelope; שולפים אותו לתיקייה משלו.
        await recoverBreakpadMinidumps(dir, since);
        final lastCrash = File(p.join(dir, 'last_crash'));
        if (await lastCrash.exists() &&
            !(await lastCrash.stat()).modified.isBefore(since)) {
          found = true;
        }
        for (final name in ['reports', recoveredMinidumpsDirName]) {
          final reports = Directory(p.join(dir, name));
          if (!await reports.exists()) continue;
          await for (final entity in reports.list()) {
            if (entity is! File || !entity.path.endsWith('.dmp')) continue;
            final modified = (await entity.stat()).modified;
            if (modified.isBefore(since)) continue;
            found = true;
            if (newestModified == null || modified.isAfter(newestModified)) {
              newest = entity;
              newestModified = modified;
            }
          }
        }
      } catch (_) {
        // תיקייה נעולה/חסרה אינה ראיה.
      }
    }
    return (found: found, newest: newest);
  }

  /// מסד sentry-native בתיקיית הלוגים. ברירת המחדל שלו יחסית לתיקיית העבודה,
  /// שב-Program Files אינה ניתנת לכתיבה — ואז קריסה נייטיבית לא נרשמת כלל.
  static String sentryDatabasePath() =>
      p.join(p.dirname(ErrorLogFile.resolvePath()), '.sentry-native');

  /// [sentryDatabasePath], ואחריו המיקום של גרסאות שלא קבעו אותו.
  static List<String> defaultSentryDatabaseDirs() {
    final dirs = <String>{};
    try {
      dirs.add(sentryDatabasePath());
    } catch (_) {}
    try {
      dirs.add(
        p.join(p.dirname(Platform.resolvedExecutable), '.sentry-native'),
      );
    } catch (_) {}
    try {
      dirs.add(p.join(Directory.current.path, '.sentry-native'));
    } catch (_) {}
    return dirs.toList();
  }

  /// ב-Windows: OpenProcess+GetExitCodeProcess (קריאות kernel זולות, לא COM);
  /// גישה נדחית = חי. בלינוקס `/proc`; אחרת זורק ונופלים להשוואת זמנים.
  static bool defaultIsProcessAlive(int processId) {
    if (Platform.isWindows) return _isAliveWindows(processId);
    if (Platform.isLinux || Platform.isAndroid) {
      return Directory('/proc/$processId').existsSync();
    }
    throw UnsupportedError('no process probe on ${Platform.operatingSystem}');
  }

  /// זמן יצירת התהליך ב-Windows (GetProcessTimes), או null.
  static DateTime? defaultProcessCreatedAt(int processId) {
    if (!Platform.isWindows) return null;
    final handle = OpenProcess(
      PROCESS_QUERY_LIMITED_INFORMATION,
      false,
      processId,
    );
    if (!handle.value.isValid) return null;
    final times = calloc<FILETIME>(4);
    try {
      if (!GetProcessTimes(
        handle.value,
        times,
        times + 1,
        times + 2,
        times + 3,
      ).value) {
        return null;
      }
      final ticks = (times.ref.dwHighDateTime << 32) | times.ref.dwLowDateTime;
      return DateTime.utc(1601).add(Duration(microseconds: ticks ~/ 10));
    } finally {
      calloc.free(times);
      handle.value.close();
    }
  }

  static bool _isAliveWindows(int processId) {
    final handle = OpenProcess(
      PROCESS_QUERY_LIMITED_INFORMATION,
      false,
      processId,
    );
    if (!handle.value.isValid) {
      return handle.error == ERROR_ACCESS_DENIED;
    }
    final exitCode = calloc<Uint32>();
    try {
      final ok = GetExitCodeProcess(handle.value, exitCode);
      return !ok.value || exitCode.value == STILL_ACTIVE;
    } finally {
      calloc.free(exitCode);
      handle.value.close();
    }
  }
}

/// מגביל דיווחי קריסה אוטומטיים: פעם אחת לכל חתימה בכל גרסה, ועד 3 ביום.
class AutoCrashReportThrottle {
  AutoCrashReportThrottle({required this.filePath, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// קובץ ברירת המחדל, ליד errors.txt.
  factory AutoCrashReportThrottle.defaultLocation({
    DateTime Function()? clock,
  }) => AutoCrashReportThrottle(
    filePath: p.join(
      p.dirname(ErrorLogFile.resolvePath()),
      'app_report_throttle.json',
    ),
    clock: clock,
  );

  static const int maxPerDay = 3;

  final String filePath;
  final DateTime Function() _clock;

  /// האם מותר לשלוח דיווח אוטומטי על [signatureHash] בגרסה [appVersion].
  Future<bool> canReport({
    required String signatureHash,
    required String appVersion,
  }) async {
    final state = await _read();
    final sent = (state['signatures'] as Map)[appVersion];
    if (sent is List && sent.contains(signatureHash)) return false;
    final today = (state['days'] as Map)[_today()];
    return !(today is int && today >= maxPerDay);
  }

  /// רושם דיווח אוטומטי שנשלח (או נשמר בתור).
  Future<void> recordReported({
    required String signatureHash,
    required String appVersion,
  }) async {
    final state = await _read();
    // רק הגרסה הנוכחית והיום הנוכחי רלוונטיים; השאר נזרק כדי שהקובץ לא יגדל.
    final signatures = state['signatures'] as Map;
    final list = <String>{
      ...((signatures[appVersion] as List?) ?? const []).whereType<String>(),
      signatureHash,
    }.toList();
    final days = state['days'] as Map;
    final today = _today();
    final count = (days[today] is int ? days[today] as int : 0) + 1;
    final updated = {
      'signatures': {appVersion: list},
      'days': {today: count},
    };
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(updated), flush: true);
    } catch (error) {
      debugPrint('AutoCrashReportThrottle: write failed: $error');
    }
  }

  String _today() {
    final now = _clock();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map && json['signatures'] is Map && json['days'] is Map) {
          return Map<String, dynamic>.from(json);
        }
      }
    } catch (_) {
      // קובץ פגום מתנהג כריק.
    }
    return {'signatures': <String, dynamic>{}, 'days': <String, dynamic>{}};
  }
}
