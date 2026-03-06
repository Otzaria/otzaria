import 'package:flutter/material.dart';
import 'package:otzaria/widgets/mixins/dialog_navigation_mixin.dart';

// ── Re-export: תאימות לאחור ────────────────────────────────────────────────
// קבועי kSettings* וווידג'טי SegmentedSettingsTile/SwitchSettingsTile/CustomSwitch
// עברו ל: lib/settings/widgets/settings_ui_components.dart
// הייבוא הזה שומר על תאימות — כל הקוד הקיים ממשיך לעבוד ללא שינוי.
// קוד חדש מומלץ לייבא ישירות מהמקור:
//   import 'package:otzaria/settings/widgets/settings_ui_components.dart';
export 'package:otzaria/settings/widgets/settings_ui_components.dart';

// ════════════════════════════════════════════════════════════════════════════
// DIALOGS — דיאלוגים גנריים
// ════════════════════════════════════════════════════════════════════════════

/// דיאלוג עם פעולה אחת (כפתור אישור בלבד).
/// M3: FilledButton עם primary/onPrimary.
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

/// דיאלוג עם שתי פעולות — ביטול (tonal) + אישור (primary).
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

/// דיאלוג אזהרה — ביטול (primary = הפעולה הבטוחה), אישור (error = מסוכן).
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

// ════════════════════════════════════════════════════════════════════════════
// BUTTONS — כפתורי פעולה
// ════════════════════════════════════════════════════════════════════════════

/// כפתור פעולה מומלצת — M3 FilledButton (primary/onPrimary).
class RecommendedActionButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;

  const RecommendedActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
        backgroundColor: cs.primary, foregroundColor: cs.onPrimary);
    if (isLoading) {
      return FilledButton(
          onPressed: null,
          style: style,
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: cs.onPrimary)));
    }
    if (icon != null) {
      return FilledButton.icon(
          onPressed: onPressed,
          style: style,
          icon: Icon(icon),
          label: Text(text));
    }
    return FilledButton(onPressed: onPressed, style: style, child: Text(text));
  }
}

/// כפתור פעולה ניטרלית — M3 FilledButton.tonal (secondaryContainer).
class NeutralActionButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;

  const NeutralActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer);
    if (isLoading) {
      return FilledButton.tonal(
          onPressed: null,
          style: style,
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: cs.onSecondaryContainer)));
    }
    if (icon != null) {
      return FilledButton.tonalIcon(
          onPressed: onPressed,
          style: style,
          icon: Icon(icon),
          label: Text(text));
    }
    return FilledButton.tonal(
        onPressed: onPressed, style: style, child: Text(text));
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HELPERS — פונקציות עזר לדיאלוגים
// ════════════════════════════════════════════════════════════════════════════

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
