import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';

/// שאלת הסגירה של טופס ששואל בעצמו ([DialogDismissGuard.onDismissRequest]).
typedef DialogDismissRequest = FutureOr<void> Function();

/// שאלת "לסגור בלי לשמור?" של [DialogDismissGuard.isDirty]. true = לסגור.
/// ברירת המחדל, `confirmDiscardChanges`, ב-`app_dialogs.dart`: היא בנויה על
/// `AppDialog`, שעוטף את עצמו בשומר, ולכן מוזרקת ולא מיובאת.
typedef DialogDiscardConfirm = Future<bool?> Function(BuildContext context);

/// שומר אחד לכל דרכי היציאה מדיאלוג שעוברות ב-[Navigator.maybePop]: X,
/// ביטול, Escape, לחיצה בחוץ וחזרה. כש-[canDismiss] false היציאה חסומה (תהליך
/// פעיל); כש-[isDirty] true נשאלת קודם שאלת אישור. אישור הדיאלוג סוגר
/// ב-[Navigator.pop] ישיר ולא עובר כאן.
///
/// סגירת החלון עוברת באותה יציאה: [confirmWindowClose].
class DialogDismissGuard extends StatefulWidget {
  const DialogDismissGuard({
    super.key,
    required this.child,
    this.isDirty = false,
    this.canDismiss = true,
    this.onDismissRequest,
    this.confirmDiscard,
  }) : assert(!isDirty || confirmDiscard != null);

  /// כמו הבנאי, כשמצב השינויים מגיע כ-[ValueListenable] ולא בבנייה מחדש.
  static Widget listenable({
    required ValueListenable<bool>? isDirty,
    bool canDismiss = true,
    DialogDismissRequest? onDismissRequest,
    DialogDiscardConfirm? confirmDiscard,
    required Widget child,
  }) {
    assert(isDirty == null || confirmDiscard != null);
    if (isDirty == null) {
      return DialogDismissGuard(
        canDismiss: canDismiss,
        onDismissRequest: onDismissRequest,
        child: child,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: isDirty,
      builder: (_, dirty, child) => DialogDismissGuard(
        isDirty: dirty,
        canDismiss: canDismiss,
        confirmDiscard: confirmDiscard,
        child: child!,
      ),
      child: child,
    );
  }

  final Widget child;

  /// גם קיצורי הניווט, שסוגרים דיאלוגים לפני מעבר, נעצרים כשהוא true.
  final bool isDirty;

  final bool canDismiss;

  /// במקום הסגירה: היציאה קוראת לו, והקורא סוגר ב-[Navigator.pop] — לטופס
  /// ששואל שאלת סגירה משלו. סגירת החלון ממתינה לו, וממשיכה רק אם נסגר.
  final DialogDismissRequest? onDismissRequest;

  /// השאלה כש-[isDirty] true.
  final DialogDiscardConfirm? confirmDiscard;

  /// לפני סגירת חלון (כפתור הסגירה, Alt+F4, יציאה מהתוכנה): כל דיאלוג פתוח
  /// שיש בו שינויים שלא נשמרו עובר את היציאה שלו, מהעליון לתחתון — "לסגור
  /// בלי לשמור?", או שאלת הטופס עצמו. באישור הדיאלוג נסגר, כמו ב-Escape.
  ///
  /// [window] — רק הדיאלוגים של החלון הזה; null — בכל החלונות (יציאה).
  /// false — המשתמש בחר להמשיך לערוך, והחלון נשאר פתוח.
  static Future<bool> confirmWindowClose({AppWindowKeys? window}) async {
    for (final guard in _DialogDismissGuardState._open.reversed.toList()) {
      if (!guard.mounted) continue;
      if (window != null &&
          !identical(AppWindowKeys.of(guard.context), window)) {
        continue;
      }
      if (!await guard._dismissForWindowClose()) return false;
    }
    return true;
  }

  @override
  State<DialogDismissGuard> createState() => _DialogDismissGuardState();
}

class _DialogDismissGuardState extends State<DialogDismissGuard> {
  /// השומרים הפתוחים, לפי סדר הפתיחה.
  static final List<_DialogDismissGuardState> _open = [];

  ModalRoute<Object?>? _route;

  /// יציאה שכבר שואלת: Escape וסגירת החלון מחכים לאותה תשובה.
  Future<bool>? _dismissing;

  @override
  void initState() {
    super.initState();
    _open.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _open.remove(this);
    super.dispose();
  }

  bool get _isOpen => mounted && (_route?.isActive ?? false);

  /// true — הדיאלוג נסגר.
  Future<bool> _dismiss(Object? result) => _dismissing ??= _runDismiss(
    result,
  ).whenComplete(() => _dismissing = null);

  Future<bool> _runDismiss(Object? result) async {
    final onDismissRequest = widget.onDismissRequest;
    if (onDismissRequest != null) {
      await onDismissRequest();
    } else {
      if (widget.isDirty && await widget.confirmDiscard!(context) != true) {
        return false;
      }
      if (mounted) Navigator.of(context).pop(result);
    }
    return !_isOpen;
  }

  Future<bool> _dismissForWindowClose() {
    final route = _route;
    final asks = widget.isDirty || widget.onDismissRequest != null;
    // בלי שינויים, בזמן תהליך שחוסם יציאה, או מחוץ לדיאלוג (מסך שלם):
    // הסגירה ממשיכה כמו קודם.
    if (!asks || !widget.canDismiss || route is! PopupRoute || !_isOpen) {
      return Future.value(true);
    }
    // תפריט או דיאלוג נקי מעל הדיאלוג נסגרים איתו; השאלה נפתחת מעליו.
    if (_dismissing == null && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route);
    }
    return _dismiss(null);
  }

  void _onBlockedPop(Object? result) {
    if (widget.canDismiss) unawaited(_dismiss(result));
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop:
        widget.canDismiss && !widget.isDirty && widget.onDismissRequest == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _onBlockedPop(result);
    },
    child: widget.child,
  );
}
