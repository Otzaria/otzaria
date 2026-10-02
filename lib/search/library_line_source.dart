import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/sqlite/sqlite_auto_extension.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// קריאות המנוע ש-[LibraryLineSource] נשען עליהן; מוחלפות בטסטים.
abstract interface class LineSourceEngine {
  Future<LineSourceStatus> status();

  Future<void> configure(String dbPath);

  Future<void> suspend();

  Future<void> resume();

  /// רושם את נקודת הכניסה של המנוע ב-SQLite של Dart ופותח חיבור שמפעיל אותה.
  Future<void> registerHostSqlite();
}

/// המנוע קורא את שורות התוצאה של ספרים שאונדקסו עם [TextStorage.libraryDb]
/// מ-seforim.db. מצבו גלובלי לתהליך; כל isolate מאזן רק את ההשעיות שלו.
abstract final class LibraryLineSource {
  static LineSourceEngine _engine = const _RustLineSourceEngine();
  static bool _hostApiReady = false;
  static Future<bool>? _hostRegistration;
  static bool _heldForExternalWrite = false;
  static Future<void> _queue = Future.value();

  /// מחליף את המנוע בטסטים ומאפס את המצב המקומי. [keepProcessMarkers] מדמה
  /// isolate נוסף באותו תהליך.
  @visibleForTesting
  static void debugReset({
    LineSourceEngine? engine,
    bool keepProcessMarkers = false,
  }) {
    _engine = engine ?? const _RustLineSourceEngine();
    _hostApiReady = false;
    _hostRegistration = null;
    _heldForExternalWrite = false;
    _queue = Future.value();
    _registrationFailureReported = false;
    _fallbacksReported = false;
    registrationFailureLog = _appendRegistrationFailureToErrorLog;
    fallbacksLog = _appendFallbacksToErrorLog;
    if (keepProcessMarkers) return;
    IsolateNameServer.removePortNameMapping(_registrationFailureMarker);
    IsolateNameServer.removePortNameMapping(_fallbacksMarker);
  }

  /// קובע את [hostApiReady] בטסטים שאינם טוענים את המנוע.
  @visibleForTesting
  static set debugHostApiReady(bool value) => _hostApiReady = value;

  /// האם המנוע יכול לקרוא את seforim.db. false עד ש-[ensureHostSqlite] הצליח
  /// — ובלעדיו אסור לאנדקס ספר בלי הטקסט שלו.
  static bool get hostApiReady => _hostApiReady;

  /// מוסר למנוע את ה-SQLite של Dart (אצלו אין SQLite משלו). חייב לרוץ לפני כל
  /// שימוש של המנוע ב-SQLite, כולל המילון המורפולוגי. אידמפוטנטי.
  static Future<bool> ensureHostSqlite() {
    if (_hostApiReady) return Future.value(true);
    return _hostRegistration ??= _registerHostSqlite().whenComplete(
      () => _hostRegistration = null,
    );
  }

  static Future<bool> _registerHostSqlite() async {
    try {
      if (!(await _engine.status()).hostApiReady) {
        await _engine.registerHostSqlite();
      }
      _hostApiReady = (await _engine.status()).hostApiReady;
      if (!_hostApiReady) {
        _reportRegistrationFailure(
          'המנוע לא קיבל את SQLite של Dart — אינדוקס עם טקסט',
          null,
        );
      }
    } catch (error, stackTrace) {
      if (!_isEngineNotLoaded(error)) {
        _reportRegistrationFailure(error, stackTrace);
      }
    }
    return _hostApiReady;
  }

  // כלי שורת פקודה וטסטים שלא טענו את המנוע ב-isolate הזה.
  static bool _isEngineNotLoaded(Object error) =>
      error is StateError &&
      error.message.startsWith('flutter_rust_bridge has not been initialized');

  static const _registrationFailureMarker =
      'otzaria.lineSource.registrationFailureLogged';
  static const _fallbacksMarker = 'otzaria.lineSource.fallbacksLogged';

  // כל חלון הוא isolate משלו; שם ב-IsolateNameServer משותף לכל התהליך.
  static bool _claimOncePerProcess(String name) {
    final port = ReceivePort();
    final claimed = IsolateNameServer.registerPortWithName(port.sendPort, name);
    port.close();
    return claimed;
  }

  /// כותב את כשל הרישום ל-errors.txt; מוחלף בטסטים.
  @visibleForTesting
  static void Function(Object error, StackTrace? stackTrace)
  registrationFailureLog = _appendRegistrationFailureToErrorLog;

  static bool _registrationFailureReported = false;

  // בלי הרישום, ספרים שאונדקסו בלי טקסט מוצגים "אינו זמין" — הסיבה חייבת
  // להגיע ל-errors.txt, פעם אחת לתהליך.
  static void _reportRegistrationFailure(Object error, StackTrace? stackTrace) {
    debugPrint('⚠️ מסירת SQLite של Dart למנוע נכשלה: $error');
    if (_registrationFailureReported) return;
    _registrationFailureReported = true;
    if (!_claimOncePerProcess(_registrationFailureMarker)) return;
    registrationFailureLog(error, stackTrace);
  }

  /// כותב את ספירת הנפילות ל-errors.txt; מוחלף בטסטים.
  @visibleForTesting
  static void Function(BigInt count) fallbacksLog = _appendFallbacksToErrorLog;

  static bool _fallbacksReported = false;

  /// מדווח, פעם אחת לתהליך, על ספרים רשמיים שהמנוע אינדקס עם הטקסט שלהם
  /// כי לא יכול היה לאמת אותם מול המסד. נקרא בסוף ריצת אינדוקס.
  static Future<void> reportLibraryFallbacks() async {
    if (_fallbacksReported) return;
    final BigInt count;
    try {
      count = (await _engine.status()).libraryFallbacks;
    } catch (error) {
      _logFailure('קריאת מצב מקור השורות', error);
      return;
    }
    if (count == BigInt.zero) return;
    _fallbacksReported = true;
    debugPrint('⚠️ $count ספרים אונדקסו עם הטקסט שלהם במקום ממסד הספרייה');
    if (!_claimOncePerProcess(_fallbacksMarker)) return;
    fallbacksLog(count);
  }

  static void _appendFallbacksToErrorLog(BigInt count) {
    if (kDebugMode) return;
    try {
      ErrorLogFile.append(
        title: 'Indexing Warning',
        error: 'Library books indexed with their text in the index: $count',
        details: const {
          'Phase': 'indexing',
          'Component': 'Search line source (library fallback)',
        },
      );
    } catch (_) {
      // כשל בכתיבת הלוג אינו עוצר את האינדוקס.
    }
  }

  static void _appendRegistrationFailureToErrorLog(
    Object error,
    StackTrace? stackTrace,
  ) {
    if (kDebugMode) return;
    try {
      ErrorLogFile.append(
        title: 'Initialization Warning',
        error: error,
        stackTrace: stackTrace,
        details: const {
          'Phase': 'initialize',
          'Component': 'Search line source (host SQLite)',
        },
      );
    } catch (_) {
      // כשל בכתיבת הלוג אינו עוצר את אתחול המנוע.
    }
  }

  /// מגדיר למנוע את נתיב seforim.db. הפתיחה עצלה; נתיב חדש מנקה את הקאשים.
  static Future<void> configure(String dbPath) async {
    if (dbPath.isEmpty) return;
    try {
      await _engine.configure(dbPath);
    } catch (error) {
      _logFailure('הגדרת מקור השורות', error);
    }
  }

  /// סוגר את seforim.db במנוע עד [releaseExternalWriteHold]. אידמפוטנטי.
  static Future<void> holdForExternalWrite() => _serial(() async {
    if (_heldForExternalWrite) return;
    _heldForExternalWrite = await _trySuspend();
  });

  /// מבטל את [holdForExternalWrite]; בלי החזקה פעילה אינו עושה דבר.
  static Future<void> releaseExternalWriteHold() => _serial(() async {
    if (!_heldForExternalWrite) return;
    _heldForExternalWrite = false;
    await _tryResume();
  });

  /// סוגר עכשיו את seforim.db במנוע, כדי שאפשר יהיה להחליף או למחוק אותו.
  /// החיפוש הבא יפתח אותו מחדש.
  static Future<void> closeNow() => _serial(() async {
    if (_heldForExternalWrite) return;
    if (await _trySuspend()) await _tryResume();
  });

  // סדר הקריאות למנוע חייב להישמר: resume שעוקף suspend היה נדחה כלא-מאוזן.
  static Future<void> _serial(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  static Future<bool> _trySuspend() async {
    try {
      await _engine.suspend();
      return true;
    } catch (error) {
      _logFailure('השעיית מקור השורות', error);
      return false;
    }
  }

  static Future<void> _tryResume() async {
    try {
      await _engine.resume();
    } catch (error) {
      _logFailure('חידוש מקור השורות', error);
    }
  }

  // StateError: המנוע לא נטען ב-isolate הזה (טסטים, כלי שורת פקודה) — אין מה לסגור.
  static void _logFailure(String what, Object error) {
    if (error is StateError) return;
    debugPrint('⚠️ $what נכשל: $error');
  }
}

class _RustLineSourceEngine implements LineSourceEngine {
  const _RustLineSourceEngine();

  @override
  Future<LineSourceStatus> status() => lineSourceStatus();

  @override
  Future<void> configure(String dbPath) => configureLineSource(dbPath: dbPath);

  @override
  Future<void> suspend() => suspendLineSource();

  @override
  Future<void> resume() => resumeLineSource();

  @override
  Future<void> registerHostSqlite() async {
    final entry = sqliteHostEntryAddress();
    // 0: למנוע SQLite משלו.
    if (entry == BigInt.zero) return;
    final address = entry.toInt();
    // ה-open שמפעיל את הרישום רץ מחוץ ל-UI isolate.
    await Isolate.run(() => registerSqliteAutoExtension(address));
  }
}
