// lib/widgets/dialogs/app_dialogs.dart
//
// דיאלוגים גנריים של האפליקציה — M3-styled.
//
// מכיל:
//  • [SingleActionDialog] — דיאלוג עם כפתור אישור בלבד
//  • [TwoActionsDialog]   — דיאלוג עם ביטול + אישור (M3 FilledButton)
//  • [WarningDialog]      — דיאלוג אזהרה: ביטול (primary), אישור (error/שקוף)
//
// **הבדל מ-ConfirmationDialog:**
//  [ConfirmationDialog] (confirmation_dialog.dart) משתמש ב-TextButton ומאפשר
//  [isDangerous] / [confirmColor] — מתאים לניווט מקלדת עם הדגשת פוקוס.
//  [TwoActionsDialog] / [WarningDialog] כאן מסוגננים לחלוטין בסגנון M3
//  FilledButton ומתאימים לדיאלוגים פשוטים ללא ניווט מקלדת מיוחד.
//
// **שימוש:**
// ```dart
// await showSingleActionDialog(context: context, title: '...', content: '...');
// await showTwoActionsDialog(context: context, title: '...', content: '...');
// await showWarningDialog(context: context, title: '...', content: '...');
// ```

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/mixins/dialog_navigation_mixin.dart';

// ── SingleActionDialog ────────────────────────────────────────────────────────

/// דיאלוג עם פעולה אחת (כפתור אישור בלבד)
class SingleActionDialog extends StatefulWidget {
  final dynamic title;
  final String content;
  final String confirmText;

  const SingleActionDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmText = 'אישור',
  });

  @override
  State<SingleActionDialog> createState() => _SingleActionDialogState();
}

class _SingleActionDialogState extends State<SingleActionDialog>
    with DialogNavigationMixin {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return buildKeyboardNavigator(
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
      child: AlertDialog(
        title: widget.title is String ? Text(widget.title) : widget.title,
        content: Text(widget.content),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
            child: Text(widget.confirmText),
          ),
        ],
      ),
    );
  }
}

// ── TwoActionsDialog ──────────────────────────────────────────────────────────

/// דיאלוג עם שתי פעולות (ביטול ואישור) — סגנון M3 FilledButton
class TwoActionsDialog extends StatefulWidget {
  final dynamic title;
  final String content;
  final String cancelText;
  final String confirmText;

  const TwoActionsDialog({
    super.key,
    required this.title,
    required this.content,
    this.cancelText = 'ביטול',
    this.confirmText = 'אישור',
  });

  @override
  State<TwoActionsDialog> createState() => _TwoActionsDialogState();
}

class _TwoActionsDialogState extends State<TwoActionsDialog>
    with DialogNavigationMixin {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return buildKeyboardNavigator(
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
      child: AlertDialog(
        title: widget.title is String ? Text(widget.title) : widget.title,
        content: Text(widget.content),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            style: FilledButton.styleFrom(
                backgroundColor: cs.secondaryContainer,
                foregroundColor: cs.onSecondaryContainer),
            child: Text(widget.cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
            child: Text(widget.confirmText),
          ),
        ],
      ),
    );
  }
}

// ── WarningDialog ─────────────────────────────────────────────────────────────

/// דיאלוג אזהרה — כפתור ביטול כהה (הפעולה הבטוחה), אישור אדום (מסוכן)
class WarningDialog extends StatefulWidget {
  final dynamic title;
  final String content;
  final String? subtitle;
  final String cancelText;
  final String confirmText;

  const WarningDialog({
    super.key,
    required this.title,
    required this.content,
    this.subtitle,
    this.cancelText = 'ביטול',
    this.confirmText = 'המשך',
  });

  @override
  State<WarningDialog> createState() => _WarningDialogState();
}

class _WarningDialogState extends State<WarningDialog>
    with DialogNavigationMixin {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return buildKeyboardNavigator(
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
      child: AlertDialog(
        title: widget.title is String ? Text(widget.title) : widget.title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.content),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(widget.subtitle!,
                  style: TextStyle(color: cs.error, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: FilledButton.styleFrom(
                backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
            child: Text(widget.cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(widget.confirmText),
          ),
        ],
      ),
    );
  }
}

// ── Helper functions ──────────────────────────────────────────────────────────

Future<bool?> showSingleActionDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmText = 'אישור',
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => SingleActionDialog(
          title: title, content: content, confirmText: confirmText),
    );

Future<bool?> showTwoActionsDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelText = 'ביטול',
  String confirmText = 'אישור',
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => TwoActionsDialog(
          title: title,
          content: content,
          cancelText: cancelText,
          confirmText: confirmText),
    );

Future<bool?> showWarningDialog({
  required BuildContext context,
  required String title,
  required String content,
  String? subtitle,
  String cancelText = 'ביטול',
  String confirmText = 'המשך',
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => WarningDialog(
          title: title,
          content: content,
          subtitle: subtitle,
          cancelText: cancelText,
          confirmText: confirmText),
    );
