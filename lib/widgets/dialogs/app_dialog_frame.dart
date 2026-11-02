// lib/widgets/dialogs/app_dialog_frame.dart
// המסגרת של כל הדיאלוגים: רצועת כותרת עם תג אייקון, גוף ושורת פעולות, בארבעה
// גדלים (DD-07).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/dialogs/dialog_dismiss_guard.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';

/// גודל דיאלוג (DD-07). הרוחב קבוע, והגובה לפי התוכן עד [maxHeightFactor]
/// מגובה החלון. [full] ממלא את החלון פחות הריפוד החיצוני.
enum AppDialogSize {
  /// אישור, אזהרה, קלט, בחירה, התקדמות.
  small(400),

  /// טופס של כמה שדות, הגדרה ממוקדת.
  medium(560),

  /// רשימות וניהול ("מסך כדיאלוג").
  large(720),

  /// תצוגה מקדימה עם חלונית הגדרות, עורך.
  full(null);

  const AppDialogSize(this.width);

  /// null = כל הרוחב הפנוי.
  final double? width;

  /// הגובה המרבי של דיאלוג שאינו [full], כחלק מגובה החלון.
  static const double maxHeightFactor = 0.85;
}

/// [Dialog] עם [AppDialogHeader] — תג אייקון בתחילת הכותרת, איקס סגירה בסופה
/// וקו חוצץ מתחתיה — ואחריה [child] ושורת [actions] אופציונלית.
class AppDialogFrame extends StatelessWidget {
  const AppDialogFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.size = AppDialogSize.medium,
    this.subtitle,
    this.trailing,
    this.tone = AppDialogHeaderTone.primary,
    this.fitTitle = false,
    this.actions,
    this.height,
    this.padding = AppTokens.dialogPadding,
    this.scrollable = false,
    this.insetPadding = const EdgeInsets.all(AppTokens.spaceMD),
    this.backgroundColor,
    this.closeEnabled = true,
    this.showClose = true,
    this.onClose,
    this.isDirty,
    this.onConfirm,
    this.handleEnterKey = true,
    this.dismissResult,
  });

  final String title;

  /// תג האייקון: מה הדיאלוג עושה. בלי אייקון שאומר משהו — אייקון המשפחה.
  final IconData icon;
  final Widget child;
  final AppDialogSize size;
  final String? subtitle;

  /// ווידג'ט בין הכותרת לאיקס, למשל מונה.
  final Widget? trailing;
  final AppDialogHeaderTone tone;

  /// הכותרת בשורה אחת שמצטמצמת לרוחב, לכותרות עם שם ספר ארוך.
  final bool fitTitle;

  /// כפתורי פעולה בשורה בתחתית, צמודים לסוף השורה.
  final List<Widget>? actions;

  /// null = גובה לפי התוכן. עם ערך — הגוף ממלא את הגובה שנשאר.
  final double? height;

  final EdgeInsetsGeometry padding;

  /// עוטף את [child] בגלילה עם פס גלוי. false כשהתוכן גולל בעצמו.
  final bool scrollable;

  final EdgeInsets insetPadding;
  final Color? backgroundColor;

  /// false חוסם את כל דרכי היציאה, לא רק את ה-X — למשל בזמן שליחה.
  final bool closeEnabled;

  /// false = בלי X בכותרת.
  final bool showClose;

  /// ברירת מחדל: [Navigator.maybePop], כמו Escape.
  final VoidCallback? onClose;

  /// כל עוד true, X, Escape ולחיצה בחוץ שואלים לפני הסגירה.
  final ValueListenable<bool>? isDirty;

  /// הפעולה הראשית: Enter בשדה חד־שורתי, או כשאין רכיב ממוקד שמגיב ל-Enter.
  final VoidCallback? onConfirm;

  /// false = Enter מגיע רק לרכיב הממוקד, גם כש-[onConfirm] מוגדר.
  final bool handleEnterKey;

  /// הערך שמוחזר ב-Escape.
  final Object? dismissResult;

  @override
  Widget build(BuildContext context) {
    final isFull = size == AppDialogSize.full;
    final fixedHeight = isFull || height != null;
    final body = scrollable
        ? PanelScrollableContent(
            thumbVisibility: true,
            padding: padding,
            child: child,
          )
        : Padding(padding: padding, child: child);
    final actionsPadding = AppTokens.dialogPadding.copyWith(top: 0);
    final content = Column(
      mainAxisSize: fixedHeight ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogHeader(
          icon: icon,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          tone: tone,
          compact: true,
          fitTitle: fitTitle,
          closeEnabled: closeEnabled,
          showClose: showClose,
          onClose: onClose,
        ),
        if (fixedHeight) Expanded(child: body) else Flexible(child: body),
        if (actions != null && actions!.isNotEmpty)
          Padding(
            padding: actionsPadding,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: AppTokens.spaceSM,
                runSpacing: AppTokens.spaceSM,
                children: actions!,
              ),
            ),
          ),
      ],
    );

    final maxHeight = isFull
        ? double.infinity
        : MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightFactor;
    final dialog = Dialog(
      insetPadding: insetPadding,
      backgroundColor: backgroundColor,
      clipBehavior: Clip.antiAlias,
      // כמו AlertDialog: קורא מסך מכריז על הכותרת ומצמצם את הפוקוס לדיאלוג.
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: title,
        explicitChildNodes: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size.width ?? double.infinity,
            maxHeight: maxHeight,
          ),
          child: fixedHeight
              ? SizedBox(height: height ?? double.infinity, child: content)
              : content,
        ),
      ),
    );
    return DialogDismissGuard.listenable(
      canDismiss: closeEnabled,
      isDirty: isDirty,
      child: DialogKeyboardNavigator(
        onConfirm: onConfirm,
        handleEnterKey: handleEnterKey,
        dismissResult: dismissResult,
        child: dialog,
      ),
    );
  }
}
