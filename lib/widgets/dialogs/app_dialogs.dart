// lib/widgets/dialogs/app_dialogs.dart
// דיאלוגים גנריים של האפליקציה — M3-styled.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/dialogs/dialog_dismiss_guard.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';

// ── AppDialog ─────────────────────────────────────────────────────────────────

enum _DialogVariant { singleAction, twoActions, warning }

/// דיאלוג גנרי M3 לפי חוזה המקלדת של [DialogKeyboardNavigator]. השתמש בבנאים
/// הממוינים:
/// - [AppDialog.singleAction] — כפתור אישור בלבד
/// - [AppDialog.twoActions] — ביטול + אישור
/// - [AppDialog.warning] — ביטול (primary/בטוח) + אישור (error/מסוכן)
class AppDialog extends StatefulWidget {
  final dynamic title;
  final String? content;
  final Widget? customContent;
  final String confirmText;
  final String cancelText;
  final String? subtitle;
  final TextDirection? textDirection;
  final bool handleEnterKey;
  final _DialogVariant _variant;

  /// תג אייקון בכותרת. באזהרה: אייקון אזהרה כברירת מחדל.
  final IconData? icon;

  /// כותרת ברצועה מלאה — אייקון, איקס סגירה וקו חוצץ — לדיאלוגים עם תוכן
  /// גדול. דיאלוג קטן נשאר עם כותרת פשוטה.
  final bool headerBand;

  // מאפשר לעצור סגירת הדיאלוג — למשל כשוולידציה נכשלת. null = סגור תמיד.
  final bool Function()? onConfirm;

  /// כל עוד true, ביטול, X, Escape ולחיצה בחוץ שואלים לפני הסגירה.
  final ValueListenable<bool>? isDirty;

  const AppDialog.singleAction({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    this.confirmText = 'אישור',
    this.textDirection,
    this.onConfirm,
    this.icon,
    this.headerBand = false,
  }) : assert(
         content != null || customContent != null,
         'content או customContent חייבים להיות מוגדרים',
       ),
       _variant = _DialogVariant.singleAction,
       cancelText = '',
       subtitle = null,
       handleEnterKey = true,
       isDirty = null;

  const AppDialog.twoActions({
    super.key,
    required this.title,
    required this.content,
    this.customContent,
    this.cancelText = 'ביטול',
    this.confirmText = 'אישור',
    this.textDirection,
    this.handleEnterKey = true,
    this.isDirty,
    this.icon,
    this.headerBand = false,
  }) : _variant = _DialogVariant.twoActions,
       subtitle = null,
       onConfirm = null;

  const AppDialog.warning({
    super.key,
    required this.title,
    required this.content,
    this.customContent,
    this.cancelText = 'ביטול',
    this.confirmText = 'המשך',
    this.subtitle,
    this.textDirection,
    this.icon = FluentIcons.warning_24_regular,
  }) : headerBand = false,
       _variant = _DialogVariant.warning,
       handleEnterKey = true,
       onConfirm = null,
       isDirty = null;

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  void _handleConfirm() {
    if (widget.onConfirm != null && !widget.onConfirm!()) return;
    Navigator.of(context).pop(true);
  }

  void _cancel() => Navigator.of(context).maybePop(false);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dialog = DialogKeyboardNavigator(
      onConfirm: _handleConfirm,
      dismissResult: false,
      handleEnterKey: widget.handleEnterKey,
      child: AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        clipBehavior: widget.headerBand ? Clip.antiAlias : Clip.none,
        titlePadding: widget.headerBand ? EdgeInsets.zero : null,
        contentPadding: widget.headerBand ? AppTokens.dialogPadding : null,
        title: widget.title is String && widget.headerBand
            ? AppDialogHeader(
                icon: widget.icon,
                title: widget.title as String,
                compact: true,
              )
            : widget.title is String
            ? AppDialogTitle(
                widget.title as String,
                icon: widget.icon,
                tone: widget._variant == _DialogVariant.warning
                    ? AppDialogHeaderTone.error
                    : AppDialogHeaderTone.primary,
                textDirection: widget.textDirection,
              )
            : widget.title as Widget,
        content: _buildContent(cs),
        actions: _buildActions(),
      ),
    );
    return DialogDismissGuard.listenable(
      isDirty: widget.isDirty,
      child: dialog,
    );
  }

  Widget _buildContent(ColorScheme cs) {
    if (widget.customContent != null) return widget.customContent!;
    if (widget._variant == _DialogVariant.warning && widget.subtitle != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.content!, textDirection: widget.textDirection),
          const SizedBox(height: 8),
          Text(
            widget.subtitle!,
            style: TextStyle(color: cs.error, fontSize: 13),
            textDirection: widget.textDirection,
          ),
        ],
      );
    }
    return Text(widget.content!, textDirection: widget.textDirection);
  }

  List<Widget> _buildActions() => switch (widget._variant) {
    _DialogVariant.singleAction => [
      ActionButton.recommended(
        autofocus: widget.customContent == null,
        text: widget.confirmText,
        onPressed: _handleConfirm,
      ),
    ],
    _DialogVariant.twoActions => [
      ActionButton.neutral(
        text: widget.cancelText,
        onPressed: _cancel,
      ),
      ActionButton.recommended(
        autofocus: true,
        text: widget.confirmText,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
    _DialogVariant.warning => [
      ActionButton.recommended(
        autofocus: true,
        text: widget.cancelText,
        onPressed: _cancel,
      ),
      ActionButton.warning(
        text: widget.confirmText,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  };
}

// ── show* functions ───────────────────────────────────────────────────────────

/// דיאלוג נבנה ב-Overlay של ה-Navigator ולכן אינו יורש את ה-Directionality
/// של המסך שפתח אותו. בלי זה, דיאלוג שנפתח ממסך ההגדרות באנגלית היה מוצג RTL.
Widget _withOpenerDirection(BuildContext context, Widget child) =>
    Directionality(
      textDirection: Directionality.of(context),
      child: child,
    );

Future<bool?> showSingleActionDialog({
  required BuildContext context,
  required String title,
  String? content,
  Widget? customContent,
  String confirmText = 'אישור',
  TextDirection? textDirection,
  bool barrierDismissible = true,
  bool Function()? onConfirm,
  IconData? icon,
  bool headerBand = false,
}) => showDialogUntilTornDown<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (_) => _withOpenerDirection(
    context,
    AppDialog.singleAction(
      title: title,
      content: content,
      customContent: customContent,
      confirmText: confirmText,
      textDirection: textDirection,
      onConfirm: onConfirm,
      icon: icon,
      headerBand: headerBand,
    ),
  ),
);

Future<bool?> showTwoActionsDialog({
  required BuildContext context,
  required String title,
  required String content,
  Widget? customContent,
  String cancelText = 'ביטול',
  String confirmText = 'אישור',
  TextDirection? textDirection,
  bool barrierDismissible = true,
  bool handleEnterKey = true,
  ValueListenable<bool>? isDirty,
  IconData? icon,
  bool headerBand = false,
}) => showDialogUntilTornDown<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (_) => _withOpenerDirection(
    context,
    AppDialog.twoActions(
      title: title,
      content: content,
      customContent: customContent,
      cancelText: cancelText,
      confirmText: confirmText,
      textDirection: textDirection,
      handleEnterKey: handleEnterKey,
      isDirty: isDirty,
      icon: icon,
      headerBand: headerBand,
    ),
  ),
);

Future<bool?> showWarningDialog({
  required BuildContext context,
  required String title,
  required String content,
  String? subtitle,
  String cancelText = 'ביטול',
  String confirmText = 'איפוס',
  TextDirection? textDirection,
  bool barrierDismissible = true,
}) => showDialogUntilTornDown<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (_) => _withOpenerDirection(
    context,
    AppDialog.warning(
      title: title,
      content: content,
      subtitle: subtitle,
      cancelText: cancelText,
      confirmText: confirmText,
      textDirection: textDirection,
    ),
  ),
);
