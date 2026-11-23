import 'package:flutter/foundation.dart';
import 'package:otzaria/app_report/services/app_crash_session.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/crash_report_flow.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/app_report/view/crash_prompt_dialog.dart';

/// דיווח על תקיעה שהשתחררה בהפעלה הנוכחית. הגלאי מודיע דרך `otzaria/process_control`
/// ב-Windows ודרך `otzaria/hang_monitor` באנדרואיד; ANR עובר ישירות ל-[CrashReportFlow].
abstract class AppHangReport {
  static Future<void> onRecovered(
    Object? arguments, {
    AppCrashReportMode Function() readMode = CrashReportFlow.currentMode,
    Future<CrashCandidate?> Function(Duration duration)? detect,
    CrashReportFlow? flow,
  }) async {
    // בלי קריאת הלוג כשהמשתמש ביקש לא לדווח.
    if (readMode() == AppCrashReportMode.never) return;
    try {
      final rawMs = arguments is Map ? arguments['durationMs'] : null;
      final duration = Duration(milliseconds: rawMs is int ? rawMs : 0);
      final candidate = await (detect ?? _detect)(duration);
      if (candidate == null) return;
      await (flow ?? CrashReportFlow(showPrompt: promptOncePerSession)).handle(
        candidate,
      );
    } catch (error, stackTrace) {
      debugPrint('App hang report failed: $error\n$stackTrace');
    }
  }

  static bool _prompted = false;

  /// במצב "שאל" מוצגת הצעה אחת לכל היותר בהפעלה; הנייטיב רושם עד 5 תקיעות.
  static Future<bool> promptOncePerSession(
    CrashCandidate candidate, {
    Future<bool> Function(CrashCandidate candidate) show =
        showCrashPromptOnNavigator,
  }) async {
    if (_prompted) return false;
    _prompted = true;
    final shown = await show(candidate);
    // לא הוצגה (אין Navigator, או הצעה אחרת פתוחה) — התקיעה הבאה תנסה שוב.
    if (!shown) _prompted = false;
    return shown;
  }

  @visibleForTesting
  static void resetSessionForTesting() => _prompted = false;

  static Future<CrashCandidate?> _detect(Duration duration) =>
      AppCrashSession.detectRecoveredHang(duration: duration);
}
