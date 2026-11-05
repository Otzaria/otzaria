// lib/widgets/dialogs/app_dialogs.dart
// דיאלוגים גנריים של האפליקציה — M3-styled.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';

export 'package:otzaria/widgets/dialogs/app_dialog_frame.dart'
    show AppDialogSize;

// ── AppDialog ─────────────────────────────────────────────────────────────────

enum _DialogVariant { singleAction, twoActions, warning }

/// אייקוני המשפחות (DD-07): התג כשלפעולה אין אייקון שאומר משהו.
abstract final class AppDialogIcons {
  static const IconData info = FluentIcons.info_24_regular;
  static const IconData confirm = FluentIcons.question_circle_24_regular;
  static const IconData warning = FluentIcons.warning_24_regular;
  static const IconData input = FluentIcons.edit_24_regular;
  static const IconData selection = FluentIcons.list_24_regular;
  static const IconData progress = FluentIcons.hourglass_half_24_regular;
}

/// דיאלוג גנרי M3 לפי חוזה המקלדת של [DialogKeyboardNavigator], מעל
/// [AppDialogFrame]: רצועת כותרת ותג אייקון תמיד. השתמש בבנאים הממוינים:
/// - [AppDialog.singleAction] — כפתור אישור בלבד
/// - [AppDialog.twoActions] — ביטול + אישור
/// - [AppDialog.warning] — ביטול (primary/בטוח) + אישור (error/מסוכן)
class AppDialog extends StatefulWidget {
  final String title;
  final String? content;
  final Widget? customContent;

  /// null = תווית ברירת המחדל בשפת הממשק.
  final String? confirmText;
  final String? cancelText;
  final String? subtitle;
  final bool handleEnterKey;
  final _DialogVariant _variant;

  /// תג האייקון בכותרת: מה מאשרים. null = אייקון המשפחה ([AppDialogIcons]).
  final IconData? icon;

  /// ווידג'ט בסוף הכותרת, לפני ה-X.
  final Widget? headerTrailing;

  /// small לאישור ולהודעה; medium/large לתוכן מותאם רחב.
  final AppDialogSize size;

  /// הגוף גולל בתוך ריפוד הדיאלוג ([AppDialogFrame.scrollable]), כך שפס
  /// הגלילה יושב בשוליים ולא מעל הטקסט. להודעה ארוכה ב-[customContent].
  final bool scrollable;

  // מאפשר לעצור סגירת הדיאלוג — למשל כשוולידציה נכשלת. null = סגור תמיד.
  final bool Function()? onConfirm;

  /// כל עוד true, ביטול, X, Escape ולחיצה בחוץ שואלים לפני הסגירה.
  final ValueListenable<bool>? isDirty;

  const AppDialog.singleAction({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    this.confirmText,
    this.onConfirm,
    this.icon,
    this.headerTrailing,
    this.size = AppDialogSize.small,
    this.scrollable = false,
  }) : assert(
         content != null || customContent != null,
         'content או customContent חייבים להיות מוגדרים',
       ),
       _variant = _DialogVariant.singleAction,
       cancelText = null,
       subtitle = null,
       handleEnterKey = true,
       isDirty = null;

  const AppDialog.twoActions({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    this.cancelText,
    this.confirmText,
    this.handleEnterKey = true,
    this.isDirty,
    this.icon,
    this.headerTrailing,
    this.size = AppDialogSize.small,
    this.scrollable = false,
  }) : assert(
         content != null || customContent != null,
         'content או customContent חייבים להיות מוגדרים',
       ),
       _variant = _DialogVariant.twoActions,
       subtitle = null,
       onConfirm = null;

  const AppDialog.warning({
    super.key,
    required this.title,
    required this.content,
    this.customContent,
    this.cancelText,
    this.confirmText,
    this.subtitle,
    this.icon,
  }) : _variant = _DialogVariant.warning,
       headerTrailing = null,
       size = AppDialogSize.small,
       handleEnterKey = true,
       onConfirm = null,
       isDirty = null,
       scrollable = false;

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
    final theme = Theme.of(context);
    final isWarning = widget._variant == _DialogVariant.warning;
    return AppDialogFrame(
      title: widget.title,
      icon:
          widget.icon ??
          switch (widget._variant) {
            _DialogVariant.singleAction => AppDialogIcons.info,
            _DialogVariant.twoActions => AppDialogIcons.confirm,
            _DialogVariant.warning => AppDialogIcons.warning,
          },
      tone: isWarning ? AppDialogHeaderTone.error : AppDialogHeaderTone.primary,
      trailing: widget.headerTrailing,
      size: widget.size,
      scrollable: widget.scrollable,
      isDirty: widget.isDirty,
      onClose: _cancel,
      onConfirm: _handleConfirm,
      handleEnterKey: widget.handleEnterKey,
      dismissResult: false,
      actions: _buildActions(),
      // גוף הטקסט כמו ב-AlertDialog של M3.
      child: DefaultTextStyle.merge(
        style:
            theme.dialogTheme.contentTextStyle ??
            theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
        child: _buildContent(theme.colorScheme),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    if (widget.customContent != null) return widget.customContent!;
    final text = Text(widget.content!);
    if (widget._variant == _DialogVariant.warning && widget.subtitle != null) {
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            text,
            const SizedBox(height: 8),
            Text(
              widget.subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(child: text);
  }

  String get _confirmLabel =>
      widget.confirmText ??
      context.settingsText(
        widget._variant == _DialogVariant.warning ? 'המשך' : 'אישור',
      );

  String get _cancelLabel => widget.cancelText ?? context.settingsText('ביטול');

  List<Widget> _buildActions() => switch (widget._variant) {
    _DialogVariant.singleAction => [
      ActionButton.recommended(
        autofocus: widget.customContent == null,
        text: _confirmLabel,
        onPressed: _handleConfirm,
      ),
    ],
    _DialogVariant.twoActions => [
      ActionButton.neutral(
        text: _cancelLabel,
        onPressed: _cancel,
      ),
      ActionButton.recommended(
        autofocus: true,
        text: _confirmLabel,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
    _DialogVariant.warning => [
      ActionButton.recommended(
        autofocus: true,
        text: _cancelLabel,
        onPressed: _cancel,
      ),
      ActionButton.warning(
        text: _confirmLabel,
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
  String? confirmText,
  bool barrierDismissible = true,
  bool Function()? onConfirm,
  IconData? icon,
  AppDialogSize size = AppDialogSize.small,
  bool scrollable = false,
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
      onConfirm: onConfirm,
      icon: icon,
      size: size,
      scrollable: scrollable,
    ),
  ),
);

Future<bool?> showTwoActionsDialog({
  required BuildContext context,
  required String title,
  String? content,
  Widget? customContent,
  String? cancelText,
  String? confirmText,
  bool barrierDismissible = true,
  bool handleEnterKey = true,
  ValueListenable<bool>? isDirty,
  IconData? icon,
  AppDialogSize size = AppDialogSize.small,
  bool scrollable = false,
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
      handleEnterKey: handleEnterKey,
      isDirty: isDirty,
      icon: icon,
      size: size,
      scrollable: scrollable,
    ),
  ),
);

Future<bool?> showWarningDialog({
  required BuildContext context,
  required String title,
  required String content,
  String? subtitle,
  String? cancelText,
  String? confirmText,
  bool barrierDismissible = true,
  IconData? icon,
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
      confirmText: confirmText ?? context.settingsText('איפוס'),
      icon: icon,
    ),
  ),
);

// ── showChoiceDialog ─────────────────────────────────────────────────────────

/// אפשרות אחת בדיאלוג בחירה בין כמה פעולות.
class AppDialogChoice<T> {
  const AppDialogChoice({
    required this.value,
    required this.label,
    this.recommended = false,
  });

  final T value;
  final String label;

  /// הפעולה הראשית (כפתור מלא וממוקד). לכל היותר אחת.
  final bool recommended;
}

/// בחירה בין כמה פעולות שוות, למשל "טקסט / Word / ביטול". מחזיר את הערך של
/// הבחירה, או null בביטול, ב-Escape ובלחיצה בחוץ.
Future<T?> showChoiceDialog<T>({
  required BuildContext context,
  required String title,
  String? content,
  Widget? customContent,
  required List<AppDialogChoice<T>> choices,
  String? cancelText,
  IconData? icon,
  bool barrierDismissible = true,
  AppDialogSize size = AppDialogSize.small,
}) {
  assert(content != null || customContent != null);
  assert(choices.where((c) => c.recommended).length <= 1);
  return showDialogUntilTornDown<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => _withOpenerDirection(
      context,
      Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return AppDialogFrame(
            title: title,
            icon: icon ?? AppDialogIcons.confirm,
            size: size,
            actions: [
              ActionButton.neutral(
                text: cancelText ?? context.settingsText('ביטול'),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              for (final choice in choices)
                choice.recommended
                    ? ActionButton.recommended(
                        autofocus: true,
                        text: choice.label,
                        onPressed: () =>
                            Navigator.of(context).pop(choice.value),
                      )
                    : ActionButton.neutral(
                        text: choice.label,
                        onPressed: () =>
                            Navigator.of(context).pop(choice.value),
                      ),
            ],
            child: DefaultTextStyle.merge(
              style:
                  theme.dialogTheme.contentTextStyle ??
                  theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              child:
                  customContent ??
                  SingleChildScrollView(
                    child: Text(content!),
                  ),
            ),
          );
        },
      ),
    ),
  );
}
