import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/theme/app_shadows.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

/// מסמן לסרגל העליון של חלונית בטאב מפוצל שהיא ניתנת לגרירה החוצה: כל
/// [AppTopBar] שמתחתיו פותח בידית גרירה.
///
/// עוטף כל חלונית תמיד — גם כשהטאב אינו מפוצל — כדי שפיצול ופירוק לא ישנו
/// את צורת העץ ויבנו מחדש את הספר; רק [enabled] מתחלף.
class PaneDragHandleScope extends InheritedWidget {
  /// החלונית שהסרגל שלה יקבל ידית גרירה.
  final OpenedTab pane;

  /// `true` רק כשהחלונית חלק מטאב מפוצל.
  final bool enabled;

  PaneDragHandleScope({
    super.key,
    required this.pane,
    required this.enabled,
    required Widget child,
  }) : super(
         child: AppTopBarScope(leading: _topBarItems, child: child),
       );

  static List<AppTopBarItem> _topBarItems(BuildContext context, bool compact) {
    final pane = paneOf(context);
    return [
      if (pane != null) AppTopBarItem(widget: PaneDragHandleButton(pane: pane)),
    ];
  }

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

  /// ידית קטנה (אייקון [AppTokens.iconXS] וריפוד [AppTokens.spaceXS]), לידית
  /// שצפה מעל תוכן ([FloatingPaneDragHandle] במגע).
  final bool dense;

  /// נקראת כשגרירה מתחילה ([FloatingPaneDragHandle] משאירה את הידית גלויה
  /// בזמן הגרירה).
  final VoidCallback? onDragStarted;

  /// נקראת כשגרירה נגמרת, בין שהתקבלה ובין שבוטלה.
  final VoidCallback? onDragEnd;

  const PaneDragHandleButton({
    super.key,
    required this.pane,
    this.dense = false,
    this.onDragStarted,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    final handle = Tooltip(
      // במגע ה־Tooltip היה זוכה בלחיצה הארוכה לפני ה־LongPressDraggable (הוא
      // עמוק יותר בעץ, והטיימר שלו קודם), ולכן לחיצה ארוכה הציגה את ההסבר
      // ולא התחילה גרירה. manual: במגע ההסבר לא מופיע, אבל נשאר השם הנגיש
      // של הידית. במחשב (עכבר) ההסבר מופיע בריחוף כמו קודם.
      triggerMode: isDesktop ? null : TooltipTriggerMode.manual,
      message: context.settingsText(
        'גרור אל שורת הכרטיסיות כדי להחזיר לכרטיסייה נפרדת',
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: dense
              ? const EdgeInsets.all(AppTokens.spaceXS)
              : const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceXS,
                  vertical: AppTokens.spaceSM,
                ),
          child: Icon(
            FluentIcons.re_order_dots_vertical_24_regular,
            size: dense ? AppTokens.iconXS : AppTokens.iconSM,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    final feedback = _PaneDragFeedback(title: pane.title);
    final whenDragging = Opacity(opacity: 0.35, child: handle);
    final onEnd = onDragEnd;
    final DragEndCallback? dragEnd = onEnd == null ? null : (_) => onEnd();

    // במגע נדרשת לחיצה ארוכה — כמו ברצועת הכרטיסיות — כדי שהקשה או גלילה
    // לא יתחילו גרירה בטעות.
    if (!isDesktop) {
      return LongPressDraggable<OpenedTab>(
        data: pane,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: whenDragging,
        onDragStarted: onDragStarted,
        onDragEnd: dragEnd,
        child: handle,
      );
    }
    return Draggable<OpenedTab>(
      data: pane,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: whenDragging,
      onDragStarted: onDragStarted,
      onDragEnd: dragEnd,
      child: handle,
    );
  }
}

bool _isDesktop(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.windows ||
  TargetPlatform.linux ||
  TargetPlatform.macOS => true,
  _ => false,
};

/// ידית הגרירה של חלונית בלי [AppTopBar], כמו תוסף (#2635): צפה בפינה
/// העליונה בצד ההתחלה, באותו מקום שבו הידית יושבת בסרגל של ספר.
///
/// במחשב היא מופיעה רק כשהעכבר ברצועה העליונה של החלונית
/// ([hoverStripHeight], לכל רוחבה). במנוחה היא שקופה ולא תופסת לחיצות, ולכן
/// לא מסתירה ולא חוסמת את תוכן התוסף.
///
/// במגע אין ריחוף: הידית מופיעה, בגרסה הקטנה ([PaneDragHandleButton.dense]),
/// אחרי נגיעה באותה רצועה, ונעלמת [touchRevealDuration] אחריה. הנגיעה עצמה
/// מגיעה גם לתוסף: היא רק נשמעת ([Listener] שקוף), לא נבלעת. בזמן גרירה
/// הידית נשארת, והספירה מתחילה מחדש כשהגרירה נגמרת.
///
/// [child] הוא תמיד הילד הראשון של אותו [Stack], גם כשהחלונית אינה מפוצלת
/// והידית לא נבנית: פיצול ופירוק לא בונים מחדש את ה-WebView.
class FloatingPaneDragHandle extends StatefulWidget {
  final Widget child;

  /// false: בלי ידית, למשל כלי שיש לו [AppTopBar] משלו.
  final bool enabled;

  /// גובה הרצועה העליונה שהריחוף בה (או במגע, נגיעה בה) מציג את הידית:
  /// הריווח מעליה, הידית
  /// עצמה ([AppTokens.iconSM] וריפוד [AppTokens.spaceSM] מעל ומתחת) ועוד
  /// [AppTokens.spaceSM].
  static const double hoverStripHeight =
      AppTokens.spaceXS +
      AppTokens.iconSM +
      2 * AppTokens.spaceSM +
      AppTokens.spaceSM;

  /// במגע: כמה זמן הידית נשארת אחרי נגיעה ברצועה העליונה, או אחרי שגרירה
  /// נגמרה. אין טוקן משך של "כמה שניות" (AppTokens.anim* הם משכי אנימציה של
  /// עשיריות שנייה); 3 שניות הן גם משך ברירת המחדל של הודעה קצרה (snack).
  static const Duration touchRevealDuration = Duration(seconds: 3);

  const FloatingPaneDragHandle({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<FloatingPaneDragHandle> createState() => _FloatingPaneDragHandleState();
}

class _FloatingPaneDragHandleState extends State<FloatingPaneDragHandle> {
  bool _hovered = false;

  /// מגע: נגיעה ברצועה הציגה את הידית, ו־[_hideTimer] עוד לא הסתיים.
  bool _revealed = false;

  /// מגע: גרירה של הידית בעיצומה. הידית נשארת עד סופה.
  bool _dragging = false;

  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  /// מציג את הידית במגע ומתחיל מחדש את הספירה עד שתיעלם.
  void _reveal() {
    _hideTimer?.cancel();
    _hideTimer = Timer(FloatingPaneDragHandle.touchRevealDuration, () {
      _hideTimer = null;
      if (mounted && !_dragging) setState(() => _revealed = false);
    });
    if (!_revealed) setState(() => _revealed = true);
  }

  void _onDragStarted() {
    _hideTimer?.cancel();
    _hideTimer = null;
    setState(() => _dragging = true);
  }

  void _onDragEnd() {
    if (!mounted) return;
    setState(() => _dragging = false);
    _reveal();
  }

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _track(PointerEvent event) => _setHovered(
    event.localPosition.dy < FloatingPaneDragHandle.hoverStripHeight,
  );

  @override
  Widget build(BuildContext context) {
    final pane = widget.enabled ? PaneDragHandleScope.paneOf(context) : null;
    final touch = !_isDesktop(context);
    final visible = _hovered || (touch && (_revealed || _dragging));
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      // לא חוסם ריחוף ולחיצות מתחת: רק מאזין.
      opaque: false,
      onEnter: _track,
      onHover: _track,
      onExit: (_) => _setHovered(false),
      // מגע: רק מאזין לנגיעה ברצועה. Listener לא משתתף בזירת המחוות, ולכן
      // אותה נגיעה מגיעה גם לתוסף.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (touch &&
              pane != null &&
              event.localPosition.dy <
                  FloatingPaneDragHandle.hoverStripHeight) {
            _reveal();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (pane != null)
              PositionedDirectional(
                top: AppTokens.spaceXS,
                start: AppTokens.spaceXS,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: AppTokens.animFast,
                    // רקע משלה: מעל דף של תוסף אין ערובה לניגודיות.
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      elevation: AppTokens.elevation1,
                      shadowColor: AppShadows.color(cs),
                      borderRadius: AppTokens.borderRadiusAll,
                      child: PaneDragHandleButton(
                        pane: pane,
                        dense: touch,
                        onDragStarted: touch ? _onDragStarted : null,
                        onDragEnd: touch ? _onDragEnd : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
