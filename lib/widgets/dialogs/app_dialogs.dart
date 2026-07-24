// lib/widgets/dialogs/app_dialogs.dart
// דיאלוגים גנריים של האפליקציה — M3-styled.
//
// [AppDialog] — דיאלוג יחיד עם שלושה בנאים ממוינים:
//  • [AppDialog.singleAction] — כפתור אישור בלבד
//  • [AppDialog.twoActions]   — ביטול (tonal) + אישור (primary)
//  • [AppDialog.warning]      — ביטול (primary) + אישור (TextButton error)
//
// כל הוריאנטים כוללים ניווט מקלדת (חיצים, Enter, Escape) והדגשת פוקוס חזותית.

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';

// ── AppDialog ─────────────────────────────────────────────────────────────────

enum _DialogVariant { singleAction, twoActions, warning }

/// דיאלוג גנרי M3 עם ניווט מקלדת מלא והדגשת פוקוס. השתמש בבנאים הממוינים:
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

  // מאפשר לעצור סגירת הדיאלוג — למשל כשוולידציה נכשלת. null = סגור תמיד.
  final bool Function()? onConfirm;

  const AppDialog.singleAction({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    this.confirmText = 'אישור',
    this.textDirection,
    this.onConfirm,
  }) : assert(
         content != null || customContent != null,
         'content או customContent חייבים להיות מוגדרים',
       ),
       _variant = _DialogVariant.singleAction,
       cancelText = '',
       subtitle = null,
       handleEnterKey = true;

  const AppDialog.twoActions({
    super.key,
    required this.title,
    required this.content,
    this.customContent,
    this.cancelText = 'ביטול',
    this.confirmText = 'אישור',
    this.textDirection,
    this.handleEnterKey = true,
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
  }) : _variant = _DialogVariant.warning,
       handleEnterKey = true,
       onConfirm = null;

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  // 0 = cancel/first, 1 = confirm/second
  // warning: safer default = cancel (0); others: confirm (1)
  late int _focusedIndex;

  late final FocusNode _confirmFocusNode;
  FocusNode? _cancelFocusNode;

  @override
  void initState() {
    super.initState();
    _confirmFocusNode = FocusNode();
    if (widget._variant != _DialogVariant.singleAction) {
      _cancelFocusNode = FocusNode();
    }
    _focusedIndex = widget._variant == _DialogVariant.warning ? 0 : 1;
  }

  @override
  void dispose() {
    _confirmFocusNode.dispose();
    _cancelFocusNode?.dispose();
    super.dispose();
  }

  void _moveFocus(int newIndex) {
    setState(() => _focusedIndex = newIndex);
    (newIndex == 1 ? _confirmFocusNode : _cancelFocusNode)?.requestFocus();
  }

  void _handleConfirm() {
    if (widget.onConfirm != null && !widget.onConfirm!()) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DialogKeyboardNavigator(
      focusedIndex: _focusedIndex,
      onFocusChange: _moveFocus,
      onConfirm: _handleConfirm,
      onCancel: () => Navigator.of(context).pop(false),
      handleEnterKey: widget.handleEnterKey,
      child: AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        title: widget.title is String
            ? Text(widget.title as String, textDirection: widget.textDirection)
            : widget.title as Widget,
        content: _buildContent(cs),
        actions: _buildActions(),
      ),
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
        focusNode: _confirmFocusNode,
        autofocus: widget.customContent == null,
        text: widget.confirmText,
        onPressed: _handleConfirm,
      ),
    ],
    _DialogVariant.twoActions => [
      ActionButton.neutral(
        focusNode: _cancelFocusNode,
        text: widget.cancelText,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      ActionButton.recommended(
        focusNode: _confirmFocusNode,
        autofocus: true,
        text: widget.confirmText,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
    _DialogVariant.warning => [
      ActionButton.recommended(
        focusNode: _cancelFocusNode,
        autofocus: true,
        text: widget.cancelText,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      ActionButton.warning(
        focusNode: _confirmFocusNode,
        text: widget.confirmText,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  };
}

// ── show* functions ───────────────────────────────────────────────────────────

Future<bool?> showSingleActionDialog({
  required BuildContext context,
  required String title,
  String? content,
  Widget? customContent,
  String confirmText = 'אישור',
  TextDirection? textDirection,
  bool barrierDismissible = true,
  bool Function()? onConfirm,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (_) => AppDialog.singleAction(
    title: title,
    content: content,
    customContent: customContent,
    confirmText: confirmText,
    textDirection: textDirection,
    onConfirm: onConfirm,
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
}) => showDialog<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (_) => AppDialog.twoActions(
    title: title,
    content: content,
    customContent: customContent,
    cancelText: cancelText,
    confirmText: confirmText,
    textDirection: textDirection,
    handleEnterKey: handleEnterKey,
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
}) => showDialog<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (_) => AppDialog.warning(
    title: title,
    content: content,
    subtitle: subtitle,
    cancelText: cancelText,
    confirmText: confirmText,
    textDirection: textDirection,
  ),
);

Future<bool?> showDbCopyRequiredDialog({
  required BuildContext context,
  required String sizeText,
  bool barrierDismissible = false,
}) => showTwoActionsDialog(
  context: context,
  title: 'נדרשת העתקה של קובץ הספרייה',
  content: '',
  barrierDismissible: barrierDismissible,
  cancelText: 'העתק (שמור מקור)',
  confirmText: 'העתק + נסה מחק מקור',
  customContent: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'לא ניתן לגשת ישירות לקובץ seforim.db (גודל: $sizeText) מכיוון שהוא נמצא באחסון חיצוני ב-Android.',
      ),
      const SizedBox(height: 12),
      const Text(
        'לחץ על כפתור למטה, נווט לאותה תיקייה ובחר את הקובץ seforim.db — האפליקציה תעתיק אותו לאחסון הפנימי.',
      ),
      const SizedBox(height: 6),
      const Text(
        '(אפשרות "נסה מחק מקור" — ניסיון למחוק לאחר העתקה. עשויה שלא להצליח בכל גרסאות Android.)',
        style: TextStyle(fontSize: 12),
      ),
    ],
  ),
);
