import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';
import 'package:otzaria/widgets/dialogs/dialog_dismiss_guard.dart';

/// שואל אם מותר לסגור את [tabs], בתוך החלון של [context].
typedef ViewWindowCloseConfirm =
    Future<bool> Function(BuildContext context, List<OpenedTab> tabs);

/// סגירת חלון Dart: רק מה ששייך לחלון הזה, כולל סשני התיקון שבכרטיסיות
/// שלו. העבודה של התהליך (שומר התוספים, יציאה) שייכת לחלון הראשי.
class ViewWindowCloseFlow {
  ViewWindowCloseFlow({
    required this.entry,
    ViewWindowCloseConfirm? confirm,
    Future<void> Function()? flush,
    Future<void> Function(int slot)? discardSession,
    this._opener,
  }) : _confirm = confirm ?? _confirmUnsavedTabs,
       _flush = flush ?? PreCloseRegistry.runAll,
       _discardSession = discardSession ?? WindowSessionStore.instance.delete;

  final ViewWindowEntry entry;
  final ViewWindowCloseConfirm _confirm;
  final Future<void> Function() _flush;
  final Future<void> Function(int slot) _discardSession;
  final ViewWindowOpener? _opener;
  bool _running = false;
  final Completer<bool> _abandoned = Completer<bool>();

  /// עץ החלון פורק (אתחול מחדש): שאלה פתוחה נחשבת לביטול ומשחררת את התור.
  void abandon() {
    if (!_abandoned.isCompleted) _abandoned.complete(false);
  }

  static Future<bool> _confirmUnsavedTabs(
    BuildContext context,
    List<OpenedTab> tabs,
  ) => confirmCloseTabs(
    context,
    tabs,
    subtitle: unsavedChangesWindowCloseSubtitle,
  );

  /// קודם הדיאלוגים הפתוחים בחלון (מה שהוקלד בהם, DD-08), ואז הכרטיסיות.
  Future<bool> _confirmDialogsThenTabs(
    BuildContext context,
    List<OpenedTab> tabs,
  ) async {
    if (!await DialogDismissGuard.confirmWindowClose(window: entry.keys)) {
      return false;
    }
    return !context.mounted || await _confirm(context, tabs);
  }

  /// מחזיר false כשהמשתמש ביטל; לחיצה חוזרת בזמן ריצה אינה עושה דבר.
  Future<bool> run() async {
    if (_running || _abandoned.isCompleted) return false;
    _running = true;
    var destroyed = false;
    try {
      final opener = _opener ?? ViewWindowOpener.instance;
      return await opener.serializeClose(() async {
        if (_abandoned.isCompleted) return false;
        final endProcess = opener.endProcess;
        final isLast =
            endProcess != null && await opener.isLastVisibleWindow(entry);
        if (_abandoned.isCompleted) return false;
        // macOS: נשארים ב-Dock, והסשן נשמר להפעלה הבאה כמו בחלון הראשי.
        final staysInDock = isLast && opener.keepsProcessAfterLastWindow;
        if (endProcess != null && isLast && !staysInDock) {
          // החלון האחרון על המסך: יציאה מהתוכנה, עם השאלות של יציאה. אם חזרה — בוטלה.
          AppWindowKeys.activateWindow(entry.id);
          await endProcess();
          return false;
        }
        final context = entry.keys.navigator.currentContext;
        var tabs = const <OpenedTab>[];
        if (context != null && context.mounted) {
          tabs = context.read<TabsBloc>().state.tabs;
          // דיאלוג שה-Navigator שלו נהרס אינו חוזר; בלי זה התור ננעל לכל החלונות.
          final confirmed = await Future.any([
            _confirmDialogsThenTabs(context, tabs),
            _abandoned.future,
          ]);
          if (!confirmed || _abandoned.isCompleted) return false;
        }
        // מכאן החלון אינו יעד להעברה: הכרטיסיה לא הייתה נשמרת.
        entry.closing = true;
        try {
          // שוטף את כל החלונות; כתיבה מיותרת בחלון אחר אינה מזיקה.
          await _flush();
        } on PreCloseFlushFailure catch (e) {
          debugPrint('view window close: flush failed: $e');
        }
        if (_abandoned.isCompleted) return false;
        // מכאן הסגירה שאושרה מושלמת גם אם העץ נבנה מחדש.
        await opener.rememberClosed(entry.slot, keptRow: staysInDock);
        // סגירה מכוונת מוחקת את הסשן; קודם endSession, ששמירה באמצע לא תחזיר אותו.
        entry.endSession();
        try {
          if (!staysInDock) await _discardSession(entry.slot);
        } catch (e) {
          // השורה תאומץ בהפעלה הבאה; החלון נסגר בכל מקרה.
          debugPrint('view window close: discard failed: $e');
        }
        endWindowCorrectionSessions(tabs);
        entry.handle.destroy();
        destroyed = true;
        return true;
      });
    } finally {
      if (!destroyed) entry.closing = false;
      _running = false;
    }
  }
}
