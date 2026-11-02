// lib/widgets/dialogs/app_dialog_frame.dart
// מסגרת לדיאלוגים בינוניים וגדולים: רצועת כותרת אחידה, גוף ושורת פעולות.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/dialogs/dialog_dismiss_guard.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';

/// [Dialog] עם [AppDialogHeader] — אייקון בתחילת הכותרת, איקס סגירה בסופה וקו
/// חוצץ מתחתיה — ואחריה [child] ושורת [actions] אופציונלית. לדיאלוגים שאינם
/// קטנים ושנבנו ידנית; דיאלוג קטן נשאר עם [AppDialogTitle].
class AppDialogFrame extends StatelessWidget {
  const AppDialogFrame({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.titleMaxLines,
    this.subtitle,
    this.trailing,
    this.tone = AppDialogHeaderTone.primary,
    this.actions,
    this.width = 560,
    this.height,
    this.padding = const EdgeInsets.all(AppTokens.spaceMD),
    this.scrollable = false,
    this.insetPadding = const EdgeInsets.all(AppTokens.spaceMD),
    this.backgroundColor,
    this.closeEnabled = true,
    this.isDirty,
  });

  final String title;
  final Widget child;
  final IconData? icon;

  /// מגביל כותרת ארוכה בלי להקטין את הכתב; הטקסט המלא מוצג ברמז.
  final int? titleMaxLines;

  final String? subtitle;
  final Widget? trailing;
  final AppDialogHeaderTone tone;

  /// כפתורי פעולה בשורה בתחתית, צמודים לסוף השורה.
  final List<Widget>? actions;

  /// רוחב מבוקש; במסך צר הדיאלוג מצטמצם לרוחב הפנוי.
  final double width;

  /// null = גובה לפי התוכן. עם ערך — הגוף ממלא את הגובה שנשאר.
  final double? height;

  final EdgeInsetsGeometry padding;

  /// עוטף את [child] בגלילה עם פס גלוי. false כשהתוכן גולל בעצמו.
  final bool scrollable;

  final EdgeInsets insetPadding;
  final Color? backgroundColor;

  /// false חוסם את כל דרכי היציאה, לא רק את ה-X — למשל בזמן שליחה.
  final bool closeEnabled;

  /// כל עוד true, X, Escape ולחיצה בחוץ שואלים לפני הסגירה.
  final ValueListenable<bool>? isDirty;

  @override
  Widget build(BuildContext context) {
    final fixedHeight = height != null;
    final body = scrollable
        ? PanelScrollableContent(
            thumbVisibility: true,
            padding: padding,
            child: child,
          )
        : Padding(padding: padding, child: child);
    final content = Column(
      mainAxisSize: fixedHeight ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogHeader(
          icon: icon,
          title: title,
          titleMaxLines: titleMaxLines,
          subtitle: subtitle,
          trailing: trailing,
          tone: tone,
          compact: true,
          closeEnabled: closeEnabled,
        ),
        if (fixedHeight) Expanded(child: body) else Flexible(child: body),
        if (actions != null && actions!.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppTokens.spaceMD,
              0,
              AppTokens.spaceMD,
              AppTokens.spaceMD,
            ),
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
          constraints: BoxConstraints(maxWidth: width),
          child: fixedHeight
              ? SizedBox(height: height, child: content)
              : content,
        ),
      ),
    );
    return DialogDismissGuard.listenable(
      canDismiss: closeEnabled,
      isDirty: isDirty,
      child: DialogKeyboardNavigator(child: dialog),
    );
  }
}
