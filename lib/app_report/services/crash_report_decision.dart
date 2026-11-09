import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// מצב הדיווח אחרי קריסה, כפי שהוא שמור בהגדרות.
enum AppCrashReportMode {
  ask('ask'),
  always('always'),
  never('never');

  const AppCrashReportMode(this.wireName);

  final String wireName;

  static AppCrashReportMode parse(Object? raw) =>
      AppCrashReportMode.values.firstWhere(
        (mode) => mode.wireName == raw,
        orElse: () => AppCrashReportMode.ask,
      );
}

/// הפעולה שההפעלה הנוכחית תבצע בעקבות קריסה של ההפעלה הקודמת.
enum CrashReportAction { none, prompt, sendAutomatically, suggestFasterDrive }

/// ההכרעה מה לעשות עם קריסה שזוהתה: מצב ההגדרה × המועמד × המגבלה.
abstract class CrashReportDecision {
  static const String fallbackTitle = 'סגירה לא צפויה';

  static CrashReportAction decide({
    required AppCrashReportMode mode,
    required CrashCandidate? candidate,
    required bool throttleAllows,
    bool isPortable = false,
  }) {
    if (candidate == null || mode == AppCrashReportMode.never) {
      return CrashReportAction.none;
    }
    if (isPortable && isLikelySlowDrive(candidate)) {
      return CrashReportAction.suggestFasterDrive;
    }
    if (mode == AppCrashReportMode.always) {
      return throttleAllows
          ? CrashReportAction.sendAutomatically
          : CrashReportAction.none;
    }
    return CrashReportAction.prompt;
  }

  /// 0xc0000006 מעיד על כשל בקריאת דף מהדיסק. תקיעה לבדה אינה ראיה לכשל בכונן.
  static bool isLikelySlowDrive(CrashCandidate candidate) =>
      _isInPageError(candidate.signature) ||
      _isInPageError(candidate.minidumpSignature);

  static bool _isInPageError(CrashSignature? signature) =>
      signature?.exceptionType.startsWith(_inPageError) ?? false;

  static const String _inPageError = '0xc0000006';

  /// האתר מוסיף "[קריסה]" לכל דיווח אוטומטי, ולכן הכותרת אומרת שזו תקיעה.
  static const String hangTitle = 'התוכנה נתקעה';

  /// כותרת הדיווח: סוג החריגה מהחתימה, ואם אין — נוסח כללי.
  static String titleFor(CrashCandidate candidate) {
    if (candidate.isHang) {
      final seconds = candidate.hangDuration?.inSeconds ?? 0;
      return seconds > 0 ? '$hangTitle ($seconds שניות)' : hangTitle;
    }
    final exceptionType = candidate.signature?.exceptionType.trim() ?? '';
    return exceptionType.isEmpty ? fallbackTitle : exceptionType;
  }

  static AppReportType reportTypeFor(CrashCandidate candidate) =>
      candidate.isHang ? AppReportType.performance : AppReportType.crash;

  /// מפתח המגבלה. קריסה בלי חתימה מקובצת תחת הכותרת הכללית.
  static String throttleKeyFor(CrashCandidate candidate) {
    final signature = candidate.signature;
    if (signature == null || signature.exceptionType.trim().isEmpty) {
      return candidate.isHang ? hangTitle : fallbackTitle;
    }
    return signature.hash;
  }
}
