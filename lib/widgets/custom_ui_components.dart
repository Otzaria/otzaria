import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/mixins/dialog_navigation_mixin.dart';
import 'package:otzaria/theme/theme_exports.dart';

// ── קבועי סגנון גלובליים ─────────────────────────────────────────────────────
/// סגנון כותרת בשורת הגדרה — alias ל-[AppTextStyles.settingTitle]
const kSettingsTitleStyle = AppTextStyles.settingTitle;

/// סגנון תת-כותרת בשורת הגדרה — alias ל-[AppTextStyles.settingSubtitle]
const kSettingsSubtitleStyle = AppTextStyles.settingSubtitle;

/// רווח אנכי סטנדרטי בין כרטיסי הגדרות
const kSettingsCardSpacing = SizedBox(height: AppTokens.spaceMD);

// ── קבועי גודל SegmentedButton ────────────────────────────────────────────────
/// רוחב בסיס לכפתור עם אייקון (px)
const _kSegmentBaseWidthWithIcon = 80.0;

/// רוחב בסיס לכפתור ללא אייקון (px)
const _kSegmentBaseWidthNoIcon = 60.0;

/// הכפלת אורך תווי התווית לחישוב רוחב (px לתו)
const _kSegmentCharWidthMultiplier = 8.0;

/// ריפוד כולל נוסף לרוחב הכולל של כל הכפתורים (px)
const _kSegmentGroupPadding = 24.0;

/// רוחב מינימלי לקבוצת הכפתורים (px)
const _kSegmentMinTotalWidth = 180.0;

/// רוחב מקסימלי לקבוצת הכפתורים (px)
const _kSegmentMaxTotalWidth = 400.0;

/// סף רוחב להחלטה על פריסה צרה (px נוסף מעבר לרוחב הכפתורים)
const _kSegmentNarrowLayoutThreshold = 200.0;

// ── דיאלוגים ─────────────────────────────────────────────────────────────────

/// דיאלוג עם פעולה אחת (כפתור אישור בלבד)
class SingleActionDialog extends StatefulWidget {
  final dynamic title;
  final String content;
  final Widget? customContent;
  final String confirmText;

  const SingleActionDialog({
    super.key,
    required this.title,
    required this.content,
    this.customContent,
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
        content: widget.customContent ?? Text(widget.content),
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

/// דיאלוג עם שתי פעולות (ביטול ואישור)
class TwoActionsDialog extends StatefulWidget {
  final dynamic title;
  final String content;
  final Widget? customContent;
  final String cancelText;
  final String confirmText;

  const TwoActionsDialog({
    super.key,
    required this.title,
    required this.content,
    this.customContent,
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
        content: widget.customContent ?? Text(widget.content),
        actions: [
          // כפתור ביטול — tonal
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            style: FilledButton.styleFrom(
                backgroundColor: cs.secondaryContainer,
                foregroundColor: cs.onSecondaryContainer),
            child: Text(widget.cancelText),
          ),
          // כפתור אישור — primary
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

/// דיאלוג אזהרה — כפתור ביטול כהה (הפעולה הבטוחה), אישור אדום
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
          // ביטול — כהה (primary), "הפעולה הבטוחה"
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: FilledButton.styleFrom(
                backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
            child: Text(widget.cancelText),
          ),
          // אישור — שקוף אדום (מסוכן)
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

// ── כפתורים ───────────────────────────────────────────────────────────────────

/// כפתור פעולה מומלצת (Primary)
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

/// כפתור פעולה ניטרלית (Tonal)
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

// ── פונקציות עזר לדיאלוגים ────────────────────────────────────────────────────

Future<bool?> showSingleActionDialog({
  required BuildContext context,
  required String title,
  String content = '',
  Widget? customContent,
  String confirmText = 'אישור',
  bool barrierDismissible = true,
}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => SingleActionDialog(
          title: title,
          content: content,
          customContent: customContent,
          confirmText: confirmText),
    );

Future<bool?> showTwoActionsDialog({
  required BuildContext context,
  required String title,
  required String content,
  Widget? customContent,
  String cancelText = 'ביטול',
  String confirmText = 'אישור',
  bool barrierDismissible = true,
}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => TwoActionsDialog(
          title: title,
          content: content,
          customContent: customContent,
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

Future<bool?> showRestartRequiredDialog({
  required BuildContext context,
  String title = 'נדרשת הפעלה מחדש',
  String? content,
  String? confirmText,
}) =>
    showSingleActionDialog(
      context: context,
      title: title,
      content: content ??
          (canRestartApplication()
              ? 'הספרייה נמצאה בהצלחה.\nלחץ על הכפתור להפעלה מחדש של התוכנה.'
              : 'הספרייה נמצאה בהצלחה.\nלחץ על הכפתור לסגירת האפליקציה, ולאחר מכן פתח אותה מחדש.'),
      confirmText: confirmText ??
          (canRestartApplication()
              ? 'הפעל מחדש את התוכנה'
              : 'סגור את האפליקציה'),
      barrierDismissible: false,
    );

Future<bool?> showDbCopyRequiredDialog({
  required BuildContext context,
  required String sizeText,
  bool barrierDismissible = false,
}) =>
    showTwoActionsDialog(
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
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 12),
          const Text(
            'לחץ על כפתור למטה, נווט לאותה תיקייה ובחר את הקובץ seforim.db — האפליקציה תעתיק אותו לאחסון הפנימי.',
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 6),
          const Text(
            '(אפשרות "נסה מחק מקור" — ניסיון למחוק לאחר העתקה. עשויה שלא להצליח בכל גרסאות Android.)',
            style: TextStyle(fontSize: 12),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );

// ── SegmentedSettingsTile ─────────────────────────────────────────────────────

// Widget להגדרה עם [SegmentedButton] — בהתאם לספציפיקציית M3:
// https://m3.material.io/components/segmented-buttons/overview
//
// - ✓ מסמן את האפשרות הנבחרת
// - גבולות חיצוניים קבועים (מונע קפיצת פריסה בעת בחירה)
// - פריסה אדפטיבית: כותרת מעל ב-narrow (כולל אייקון), ListTile ב-wide
// - ניווט מקלדת: חצים ← → לבחירה, Enter/Space לאישור
//
// **שימוש:**
// ```dart
// SegmentedSettingsTile<int>(
//   title: 'שיטת גימטריה',
//   options: [
//     SegmentOption(value: 0, label: 'רגיל'),
//     SegmentOption(value: 1, label: 'קטנה'),
//   ],
//   currentValue: 0,
//   onChanged: (v) => setState(() => _method = v),
// )
// ```
class SegmentedSettingsTile<T> extends StatefulWidget {
  final dynamic title;
  final String? subtitle;
  final IconData? icon;
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;

  const SegmentedSettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.options,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  State<SegmentedSettingsTile<T>> createState() =>
      _SegmentedSettingsTileState<T>();
}

class _SegmentedSettingsTileState<T> extends State<SegmentedSettingsTile<T>> {
  final FocusNode _focusNode = FocusNode();
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusedIndex =
        widget.options.indexWhere((o) => o.value == widget.currentValue);
    if (_focusedIndex < 0) _focusedIndex = 0;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasIcons = widget.options.any((o) => o.icon != null);
    final maxLen = widget.options
        .map((o) => o.label.length)
        .reduce((a, b) => a > b ? a : b);
    final btnWidth =
        (hasIcons ? _kSegmentBaseWidthWithIcon : _kSegmentBaseWidthNoIcon) +
            maxLen * _kSegmentCharWidthMultiplier;
    final totalW = (btnWidth * widget.options.length + _kSegmentGroupPadding)
        .clamp(_kSegmentMinTotalWidth, _kSegmentMaxTotalWidth);

    return LayoutBuilder(builder: (ctx, constraints) {
      final isNarrow =
          constraints.maxWidth < totalW + _kSegmentNarrowLayoutThreshold;
      final button = _buildButton(cs, hasIcons, totalW);

      if (isNarrow) {
        // ── פריסה צרה: כותרת + תת-כותרת מעל הכפתור, אייקון בשורה עם הכותרת
        return Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // תיקון באג 5: Row עם אייקון (אם קיים) + כותרת + תת-כותרת
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 24),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _titleOnlyWidget(ctx),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle!,
                            style: kSettingsSubtitleStyle.copyWith(
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          ),
        );
      }

      // ── פריסה רחבה: ListTile רגיל — title בלבד, subtitle דרך ListTile
      // תיקון באג 1: _titleOnlyWidget מחזיר רק את הכותרת,
      // ה-subtitle מועבר ל-ListTile בנפרד — מונע הצגה כפולה.
      return ListTile(
        leading: widget.icon != null ? Icon(widget.icon) : null,
        title: _titleOnlyWidget(ctx),
        subtitle: widget.subtitle != null
            ? Text(widget.subtitle!, style: kSettingsSubtitleStyle)
            : null,
        trailing: button,
      );
    });
  }

  /// מחזיר **רק** את הכותרת (title) — ללא תת-כותרת.
  /// נדרש כדי למנוע כפילות ב-ListTile שמציג subtitle בעצמו.
  Widget _titleOnlyWidget(BuildContext context) {
    if (widget.title is! String) return widget.title as Widget;
    return Text(widget.title as String, style: kSettingsTitleStyle);
  }

  // M3 SegmentedButton: secondaryContainer = selected, surface = unselected
  // Tokens: https://m3.material.io/components/segmented-buttons/specs
  // AppTokens.radiusSM חייב להיות שווה ל-8. אם לא — הפינות ישתנו ויזואלית.
  Widget _buildButton(ColorScheme cs, bool hasIcons, double totalW) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(() =>
              _focusedIndex = (_focusedIndex + 1) % widget.options.length);
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
          setState(() => _focusedIndex =
              (_focusedIndex - 1 + widget.options.length) %
                  widget.options.length);
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.enter ||
            ev.logicalKey == LogicalKeyboardKey.space) {
          widget.onChanged(widget.options[_focusedIndex].value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: totalW,
        child: SegmentedButton<T>(
          showSelectedIcon: true,
          selectedIcon: const Icon(Icons.check, size: 16),
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(const Size(0, 40)),
            maximumSize:
                WidgetStateProperty.all(const Size(double.infinity, 40)),
            shape: WidgetStateProperty.all(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusSM))),
            // M3 selected: secondaryContainer/onSecondaryContainer
            backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.selected)) {
                return cs.secondaryContainer;
              }
              return cs.surface;
            }),
            foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.selected)) {
                return cs.onSecondaryContainer;
              }
              return cs.onSurfaceVariant;
            }),
          ),
          segments: widget.options
              .map((o) => ButtonSegment<T>(
                    value: o.value,
                    label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(o.label, style: kSettingsTitleStyle)),
                    icon: hasIcons
                        ? (o.icon != null
                            ? Icon(o.icon, size: 18)
                            : const SizedBox(width: 18))
                        : null,
                  ))
              .toList(),
          selected: {widget.currentValue},
          onSelectionChanged: (s) => widget.onChanged(s.first),
        ),
      ),
    );
  }
}

/// אפשרות יחידה ב-[SegmentedSettingsTile]
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentOption({required this.value, required this.label, this.icon});
}

// ── CustomSwitch ───────────────────────────────────────────────────────────────

// [Switch] תואם M3 עם thumb/track/overlay מוגדרים לפי:
// https://m3.material.io/components/switch/specs
//
// תיקון hover במצב כהה: ברירת המחדל של Flutter משתמשת ב-primary חזק מדי.
// הפתרון: overlayColor מינימלי שמכסה רק hovered — 8% שקיפות דינמי לפי מצב המתג.
class CustomSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool autofocus;
  final FocusNode? focusNode;

  const CustomSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Switch(
      value: value,
      onChanged: onChanged,
      autofocus: autofocus,
      focusNode: focusNode,
      // M3 thumb tokens: onPrimary (on), outline (off), onSurface·38 (disabled)
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.38);
        }
        if (s.contains(WidgetState.selected)) return cs.onPrimary;
        if (s.contains(WidgetState.hovered)) return cs.onSurfaceVariant;
        return cs.outline;
      }),
      // M3 track tokens: primary (on), surfaceContainerHighest (off)
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return cs.surfaceContainerHighest.withValues(alpha: 0.12);
        }
        if (s.contains(WidgetState.selected)) return cs.primary;
        return cs.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return Colors.transparent;
        return cs.outline;
      }),
      // עובד אוטומטית ב-light וב-dark כי מתבסס על ColorScheme.
      // null = Flutter מסתדר לבד בשאר המצבים (focus, pressed).
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered)) {
          return (value ? cs.primary : cs.onSurface).withValues(alpha: 0.12);
        }
        return null;
      }),
    );
  }
}

// ── SwitchSettingsTile ────────────────────────────────────────────────────────

/// [ListTile] עם [CustomSwitch] — עקבי עם כל שורות on/off בהגדרות.
class SwitchSettingsTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const SwitchSettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      trailing: CustomSwitch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
      onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  כלי עזר לתצוגת טאבי הכלים
// ════════════════════════════════════════════════════════════════════════════

/// צבע רקע כרטיסי תוצאות בכלי האפליקציה — תואם לסגנון SettingsCard
Color toolCardColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainer
      : theme.colorScheme.surface;
}

// ── כפתורי פעולה לכלים ─────────────────────────────────────────────────────

/// כפתור העתקת תוצאה — בהיר (Tonal/secondaryContainer) עם אייקון העתק.
///
/// השימוש: העברת callback שמבצע את הקפיאה ומציג אישור.
class ToolCopyButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const ToolCopyButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'העתק',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: const Icon(FluentIcons.copy_24_regular, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// כפתור פתיחת מקור — כהה (primary) עם אייקון פתיחה וריחוף 'פתח מקור'.
class ToolNavigateButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const ToolNavigateButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'פתח מקור',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: const Icon(FluentIcons.open_24_regular, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ── ToolPanelWrapper ────────────────────────────────────────────────────────

/// עוטף תוכן כלי ברקע מסך ההגדרות ומרכז אותו אופקית עם הגבלת רוחב.
///
/// [hasNavigationBar] = true  → רק רקע, ללא הגבלת רוחב (מתאים כשיש TabBar/Sidebar).
/// [hasNavigationBar] = false → רקע + Align(topCenter) + maxWidth 860px.
///
/// **שימוש:**
/// ```dart
/// // מסך עצמאי
/// return ToolPanelWrapper(child: Column(...));
///
/// // מסך עם TabBar
/// Scaffold(
///   body: Column(
///     children: [
///       TabBar(...),  // מחוץ ל-Wrapper — מלא רוחב
///       Expanded(
///         child: ToolPanelWrapper(hasNavigationBar: true, child: TabBarView(...)),
///       ),
///     ],
///   ),
/// )
/// ```
class ToolPanelWrapper extends StatelessWidget {
  final Widget child;
  final bool hasNavigationBar;

  const ToolPanelWrapper({
    super.key,
    required this.child,
    this.hasNavigationBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = AppSurfaces.panelBackground(context);

    if (hasNavigationBar) {
      return ColoredBox(color: bgColor, child: child);
    }

    return ColoredBox(
      color: bgColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: LayoutConstraints.panelContentMaxWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}
