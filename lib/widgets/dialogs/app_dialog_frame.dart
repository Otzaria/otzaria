// lib/widgets/dialogs/app_dialog_frame.dart
// המסגרת של כל הדיאלוגים: רצועת כותרת עם תג אייקון, גוף ושורת פעולות, בארבעה
// גדלים (DD-07).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/dialogs/dialog_dismiss_guard.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';

/// גודל דיאלוג (DD-07). הרוחב קבוע, והגובה לפי התוכן עד [maxHeightFactor]
/// מגובה החלון, או קבוע ([AppDialogFrame.height]) עד גובה החלון. [full] ממלא
/// את החלון פחות הריפוד החיצוני.
///
/// בחלון צר ([WindowClass.isCompact], DD-16): [small] ו-[medium] ברוחב החלון
/// פחות 16, ו-[large] ו-[full] במסך מלא. גם בחלון נמוך ([WindowClass.isShortOf],
/// טלפון לרוחב או חלון שטוח), בכל רוחב, [large] ו-[full] במסך מלא: שם הגובה
/// הוא האילוץ, והשוליים והפינות לוקחים ממנו (q12 Q8).
enum AppDialogSize {
  /// אישור, אזהרה, קלט, בחירה, התקדמות. בלי X: סוגרים בביטול או ב-Escape.
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

  /// הגובה המרבי של דיאלוג לפי תוכן, כחלק מגובה החלון.
  static const double maxHeightFactor = 0.85;

  /// הריפוד סביב הדיאלוג בחלון רחב.
  static const EdgeInsets inset = EdgeInsets.all(AppTokens.spaceMD);

  /// הריפוד סביב small/medium בחלון צר: 8 מכל צד.
  static const EdgeInsets compactInset = EdgeInsets.symmetric(
    horizontal: AppTokens.spaceSM,
    vertical: AppTokens.spaceLG,
  );
}

/// [Dialog] עם [AppDialogHeader] — תג אייקון בתחילת הכותרת, איקס סגירה בסופה
/// (מ-[AppDialogSize.medium]) וקו חוצץ מתחתיה — ואחריה [child] ושורת [actions]
/// אופציונלית.
class AppDialogFrame extends StatelessWidget {
  const AppDialogFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.titleMaxLines,
    this.size = AppDialogSize.medium,
    this.subtitle,
    this.subtitleMaxLines,
    this.leading,
    this.trailing,
    this.tabs,
    this.tone = AppDialogHeaderTone.primary,
    this.fitTitle = false,
    this.actions,
    this.height,
    this.padding = AppTokens.dialogPadding,
    this.scrollable = false,
    this.backgroundColor,
    this.closeEnabled = true,
    this.showClose,
    this.onClose,
    this.isDirty,
    this.onDismissRequest,
    this.onConfirm,
    this.handleEnterKey = true,
    this.dismissResult,
    this.surfaceKey,
  }) : assert(isDirty == null || onDismissRequest == null);

  final String title;

  /// תג האייקון: מה הדיאלוג עושה. בלי אייקון שאומר משהו — אייקון המשפחה.
  final IconData icon;
  final Widget child;

  /// מגביל כותרת ארוכה בלי להקטין את הכתב; הטקסט המלא מוצג ברמז.
  final int? titleMaxLines;

  final AppDialogSize size;
  final String? subtitle;

  /// null = בלי הגבלה. שם ספר ארוך בשורת המשנה מוגבל לשורה אחת.
  final int? subtitleMaxLines;

  /// פקדים בתחילת הרצועה, לפני התג — למשל ניווט בתצוגה מקדימה.
  final Widget? leading;

  /// ווידג'ט בין הכותרת לאיקס, למשל מונה.
  final Widget? trailing;

  /// שורת לשוניות (`TabBar`) מתחת לרצועה. [child] הוא ה-`TabBarView`, ולכן
  /// דיאלוג עם לשוניות מקבל [height] או [AppDialogSize.full].
  final Widget? tabs;
  final AppDialogHeaderTone tone;

  /// הכותרת בשורה אחת שמצטמצמת לרוחב, לכותרות עם שם ספר ארוך.
  final bool fitTitle;

  /// כפתורי פעולה בשורה בתחתית, צמודים לסוף השורה.
  final List<Widget>? actions;

  /// null = גובה לפי התוכן. עם ערך — גובה קבוע, עד גובה החלון, והגוף ממלא
  /// את מה שנשאר מתחת לרצועה.
  final double? height;

  final EdgeInsetsGeometry padding;

  /// עוטף את [child] בגלילה עם פס גלוי. false כשהתוכן גולל בעצמו.
  final bool scrollable;

  final Color? backgroundColor;

  /// false חוסם את כל דרכי היציאה, לא רק את ה-X — למשל בזמן שליחה.
  final bool closeEnabled;

  /// X בכותרת. null = לפי הגודל: בלי X ב-[AppDialogSize.small], שנסגר בכפתור
  /// ביטול או סגירה, ב-Escape או בלחיצה בחוץ (DD-07).
  final bool? showClose;

  /// ברירת מחדל: [Navigator.maybePop], כמו Escape.
  final VoidCallback? onClose;

  /// כל עוד true, X, Escape ולחיצה בחוץ שואלים לפני הסגירה.
  final ValueListenable<bool>? isDirty;

  /// במקום [isDirty], לטופס ששואל שאלת סגירה משלו: X, Escape, לחיצה בחוץ
  /// וחזרה קוראים לו, והדיאלוג נסגר רק כשהקורא סוגר אותו.
  final DialogDismissRequest? onDismissRequest;

  /// הפעולה הראשית: Enter בשדה חד־שורתי, או כשאין רכיב ממוקד שמגיב ל-Enter.
  final VoidCallback? onConfirm;

  /// false = Enter מגיע רק לרכיב הממוקד, גם כש-[onConfirm] מוגדר.
  final bool handleEnterKey;

  /// הערך שמוחזר ב-Escape.
  final Object? dismissResult;

  /// מפתח למשטח הדיאלוג עצמו, בלי השוליים סביבו — למשל לסימון בסיור.
  final Key? surfaceKey;

  /// בדסקטופ "מסך מלא" מתחיל מתחת לשורת הכותרת של החלון, כדי שהיא תישאר
  /// גלויה; בטלפון הוא ממלא את המסך.
  static EdgeInsets get _fullscreenInset =>
      !kIsWeb &&
          switch (defaultTargetPlatform) {
            TargetPlatform.windows ||
            TargetPlatform.linux ||
            TargetPlatform.macOS => true,
            _ => false,
          }
      ? const EdgeInsets.only(top: LayoutConstraints.windowCaptionHeight)
      : EdgeInsets.zero;

  @override
  Widget build(BuildContext context) {
    final windowClass = WindowClass.of(context);
    final compact = windowClass.isCompact;
    final fullscreen =
        (compact || WindowClass.isShortOf(context)) &&
        size.index >= AppDialogSize.large.index;
    final fills = fullscreen || size == AppDialogSize.full;
    final fixedHeight = fills || height != null;
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
          titleMaxLines: titleMaxLines,
          subtitle: subtitle,
          subtitleMaxLines: subtitleMaxLines,
          leading: leading,
          trailing: trailing,
          tone: tone,
          compact: true,
          fitTitle: fitTitle,
          closeEnabled: closeEnabled,
          showClose: showClose ?? size != AppDialogSize.small,
          onClose: onClose,
        ),
        ?tabs,
        Flexible(
          fit: fixedHeight ? FlexFit.tight : FlexFit.loose,
          child: body,
        ),
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

    final maxHeight = fills || height != null
        ? double.infinity
        : MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightFactor;
    final dialog = Dialog(
      insetPadding: fullscreen
          ? _fullscreenInset
          : compact
          ? AppDialogSize.compactInset
          : AppDialogSize.inset,
      shape: fullscreen ? const RoundedRectangleBorder() : null,
      backgroundColor: backgroundColor,
      clipBehavior: Clip.antiAlias,
      // כמו AlertDialog: קורא מסך מכריז על הכותרת ומצמצם את הפוקוס לדיאלוג.
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: title,
        explicitChildNodes: true,
        child: ConstrainedBox(
          key: surfaceKey,
          constraints: BoxConstraints(
            maxWidth: compact || fullscreen
                ? double.infinity
                : size.width ?? double.infinity,
            maxHeight: maxHeight,
          ),
          // SizedBox ו-SafeArea תמיד, כדי שמעבר מעל 600 (סיבוב טלפון, גרירת
          // חלון) ישמור את הגוף, את הפוקוס ואת מצב השדות.
          child: SizedBox(
            height: fixedHeight ? (fills ? double.infinity : height) : null,
            child: SafeArea(
              left: fullscreen,
              top: fullscreen,
              right: fullscreen,
              bottom: fullscreen,
              child: content,
            ),
          ),
        ),
      ),
    );
    return DialogDismissGuard.listenable(
      canDismiss: closeEnabled,
      isDirty: isDirty,
      onDismissRequest: onDismissRequest,
      child: DialogKeyboardNavigator(
        onConfirm: onConfirm,
        handleEnterKey: handleEnterKey,
        dismissResult: dismissResult,
        child: dialog,
      ),
    );
  }
}
