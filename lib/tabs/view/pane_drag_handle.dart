import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/theme/app_shadows.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

/// מסמן לסרגל העליון של חלונית בטאב מפוצל שהיא ניתנת לגרירה החוצה.
///
/// עוטף כל חלונית תמיד — גם כשהטאב אינו מפוצל — כדי שפיצול ופירוק לא ישנו
/// את צורת העץ ויבנו מחדש את הספר; רק [enabled] מתחלף.
class PaneDragHandleScope extends InheritedWidget {
  /// החלונית שהסרגל שלה יקבל ידית גרירה.
  final OpenedTab pane;

  /// `true` רק כשהחלונית חלק מטאב מפוצל.
  final bool enabled;

  const PaneDragHandleScope({
    super.key,
    required this.pane,
    required this.enabled,
    required super.child,
  });

  /// החלונית לגרירה, או `null` כשאין טאב מפוצל בהקשר הזה.
  static OpenedTab? paneOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PaneDragHandleScope>();
    return (scope?.enabled ?? false) ? scope!.pane : null;
  }

  @override
  bool updateShouldNotify(PaneDragHandleScope oldWidget) =>
      enabled != oldWidget.enabled || !identical(pane, oldWidget.pane);
}

/// ידית גרירה של חלונית מפוצלת — גרירתה אל שורת הכרטיסיות מפרידה את
/// החלונית חזרה לכרטיסייה עצמאית (המחווה ההפוכה לגרירה שיצרה את הפיצול).
class PaneDragHandleButton extends StatelessWidget {
  final OpenedTab pane;

  const PaneDragHandleButton({super.key, required this.pane});

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isDesktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    final handle = Tooltip(
      message: context.settingsText(
        'גרור אל שורת הכרטיסיות כדי להחזיר לכרטיסייה נפרדת',
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Icon(
            FluentIcons.re_order_dots_vertical_24_regular,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    final feedback = _PaneDragFeedback(title: pane.title);
    final whenDragging = Opacity(opacity: 0.35, child: handle);

    // במגע נדרשת לחיצה ארוכה — כמו ברצועת הכרטיסיות — כדי שהקשה או גלילה
    // לא יתחילו גרירה בטעות.
    if (!isDesktop) {
      return LongPressDraggable<OpenedTab>(
        data: pane,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: whenDragging,
        child: handle,
      );
    }
    return Draggable<OpenedTab>(
      data: pane,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: whenDragging,
      child: handle,
    );
  }
}

/// כרטיס צף עם שם החלונית, תחת הסמן בזמן הגרירה.
///
/// מוצג ב-[Overlay] ולכן אינו יורש כיווניות ו-[Material] — בלי העטיפה
/// המפורשת הצבעים והכיוון נופלים לברירות מחדל.
class _PaneDragFeedback extends StatelessWidget {
  final String title;

  const _PaneDragFeedback({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: Directionality.of(context),
      // העוגן הוא נקודת המצביע, ולכן הכרטיס מוזז כדי לרחף סביבה.
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          elevation: AppTokens.elevation2,
          shadowColor: AppShadows.color(theme.colorScheme),
          borderRadius: AppTokens.borderRadiusAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              title,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
