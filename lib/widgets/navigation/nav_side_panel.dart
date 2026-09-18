import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/misc/animated_pin_button.dart';

/// חלונית הניווט האחידה של האפליקציה — מקור האמת היחיד למראה שלה.
///
/// עוטפת את [AdaptiveSidePane] (שנשאר המכניקה: פריסה רספונסיבית, גרירה,
/// overlay במסך צר) וקובעת בעצמה את כל ההיבטים העיצוביים: הצמדה לסרגל העליון,
/// צבע הרקע והפינה הקעורה במפגש עם התוכן. מסך צריכה לא מגדיר אותם שוב.
///
/// תוכן החלונית נבנה מ-[NavTreeTile] / [NavTreeHeader] / [NavTreeGroupCard],
/// והכפתור שפותח אותה הוא [NavPanelToggleButton].
class NavSidePanel extends StatelessWidget {
  final bool isOpen;
  final Widget mainContent;
  final Widget paneContent;
  final AlignmentDirectional alignment;
  final double paneWidth;
  final double minMainContentWidth;
  final VoidCallback onClose;
  final VoidCallback? onOpen;
  final bool isResizable;
  final double minPaneWidth;
  final double? maxPaneWidth;
  final ValueChanged<double>? onPaneWidthChanged;
  final VoidCallback? onPaneResizeEnd;
  final ValueChanged<bool>? onLayoutModeChanged;
  final bool autoHandleResponsiveVisibility;

  /// חלונית לא נעוצה מרחפת מעל התוכן ונסגרת בלחיצה עליו; נעוצה דוחקת אותו.
  /// נעיצה גלובלית בהגדרות גוברת.
  final bool isPinned;

  const NavSidePanel({
    super.key,
    required this.isOpen,
    required this.mainContent,
    required this.paneContent,
    required this.onClose,
    this.alignment = AlignmentDirectional.centerEnd,
    this.paneWidth = 340,
    this.minMainContentWidth = 500,
    this.onOpen,
    this.isResizable = false,
    this.minPaneWidth = 220,
    this.maxPaneWidth,
    this.onPaneWidthChanged,
    this.onPaneResizeEnd,
    this.onLayoutModeChanged,
    this.autoHandleResponsiveVisibility = true,
    this.isPinned = true,
  });

  /// רקע חלונית הניווט — צבע הסרגל העליון, כדי שהחלונית תיראה כהמשך שלו.
  static Color background(BuildContext context) =>
      AppSurfaces.navPanelBackground(context);

  @override
  Widget build(BuildContext context) {
    return AdaptiveSidePane(
      isOpen: isOpen,
      alignment: alignment,
      // ההצמדה, הצבע ומרווח פס הגלילה הם העיצוב האחיד — לא פרמטרים של המסך.
      attachToTopEdge: true,
      floatOverContent:
          !isPinned && !(Settings.getValue<bool>('key-pin-sidebar') ?? false),
      paneColor: background(context),
      scrollbarTopMargin: 0,
      mainContent: mainContent,
      paneContent: paneContent,
      paneWidth: paneWidth,
      minMainContentWidth: minMainContentWidth,
      onClose: onClose,
      onOpen: onOpen,
      isResizable: isResizable,
      minPaneWidth: minPaneWidth,
      maxPaneWidth: maxPaneWidth,
      onPaneWidthChanged: onPaneWidthChanged,
      onPaneResizeEnd: onPaneResizeEnd,
      onLayoutModeChanged: onLayoutModeChanged,
      autoHandleResponsiveVisibility: autoHandleResponsiveVisibility,
    );
  }
}

/// שורת הלשוניות של חלונית הניווט.
///
/// אייקון הלשונית הנבחרת מתחלף ל-filled כשסופק [NavPanelTab.iconFilled].
/// כפתור הנעיצה אינו כאן — הוא פעולה של החלונית כולה ולכן יושב בסרגל העליון,
/// ליד [NavPanelToggleButton].
class NavPanelTabHeader extends StatefulWidget {
  final TabController controller;
  final List<NavPanelTab> tabs;

  const NavPanelTabHeader({
    super.key,
    required this.controller,
    required this.tabs,
  });

  @override
  State<NavPanelTabHeader> createState() => _NavPanelTabHeaderState();
}

/// לשונית בכותרת חלונית הניווט.
typedef NavPanelTab = ({IconData icon, IconData? iconFilled, String? label});

class _NavPanelTabHeaderState extends State<NavPanelTabHeader> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(NavPanelTabHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final sel = widget.controller.index;
    // הלשוניות נסרקות אחרי שורות הרשימה (NavTreeFocusGroup.traversalOrder).
    return FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: SizedBox(
        height: AppTokens.panelTabHeight,
        child: TabBar(
          controller: widget.controller,
          splashBorderRadius: AppTokens.borderRadiusAll,
          tabs: [
            for (var i = 0; i < widget.tabs.length; i++)
              _tab(widget.tabs[i], i == sel),
          ],
        ),
      ),
    );
  }

  Tab _tab(NavPanelTab data, bool sel) {
    final iconData = (sel && data.iconFilled != null)
        ? data.iconFilled!
        : data.icon;
    final iconWidget = AnimatedSwitcher(
      duration: AppTokens.animFast,
      child: Icon(
        iconData,
        key: ValueKey<IconData>(iconData),
        size: AppTokens.panelTabIconSize,
      ),
    );
    final lbl = data.label;
    if (lbl == null) {
      return Tab(icon: iconWidget, height: AppTokens.panelTabHeight);
    }
    return Tab(
      icon: iconWidget,
      iconMargin: AppTokens.panelTabIconMargin,
      height: AppTokens.panelTabHeight,
      child: Text(
        lbl,
        style: const TextStyle(fontSize: AppTokens.panelTabFontSize),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// כפתור נעיצת חלונית הניווט. נעיצה גלובלית בהגדרות כופה נעוץ ומשביתה אותו.
class NavPanelPinButton extends StatelessWidget {
  final bool isPinned;
  final VoidCallback? onToggle;

  const NavPanelPinButton({
    super.key,
    required this.isPinned,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final globalPin = Settings.getValue<bool>('key-pin-sidebar') ?? false;
    final effectivePinned = isPinned || globalPin;
    return AnimatedPinButton(
      isPinned: effectivePinned,
      tooltip: effectivePinned ? 'בטל נעיצה' : 'נעץ את החלונית',
      onPressed: globalPin ? null : onToggle,
    );
  }
}

/// הכפתור היחיד לפתיחת/סגירת חלונית הניווט, בכל המסכים.
class NavPanelToggleButton extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onToggle;

  const NavPanelToggleButton({
    super.key,
    required this.isOpen,
    required this.onToggle,
  });

  /// האם לשקף את הגליף אופקית, כך שהחץ שבו יצביע לכיוון שאליו החלונית תזוז
  /// בלחיצה (issue #1417).
  ///
  /// הגליף מצויר עם חץ שמאלה: חלונית סגורה בצד הסוף של ממשק RTL (ימין)
  /// נפתחת שמאלה, ולכן שם הוא מוצג כפי שהוא. חלונית פתוחה נסגרת לכיוון
  /// ההפוך — החץ מתהפך; ובממשק LTR, שבו צד הסוף הוא שמאל, שני המצבים
  /// מתהפכים.
  static bool shouldMirror({
    required bool isOpen,
    required TextDirection textDirection,
  }) => isOpen == (textDirection == TextDirection.rtl);

  @override
  Widget build(BuildContext context) {
    final mirror = shouldMirror(
      isOpen: isOpen,
      textDirection: Directionality.of(context),
    );
    return IconButton(
      tooltip: isOpen ? 'הסתר ניווט' : 'הצג ניווט',
      onPressed: onToggle,
      visualDensity: VisualDensity.standard,
      splashRadius: 22,
      color: Theme.of(context).colorScheme.onSecondaryContainer,
      icon: AnimatedSwitcher(
        duration: AppTokens.animFast,
        child: Transform.flip(
          key: ValueKey(isOpen),
          flipX: mirror,
          child: Icon(
            isOpen
                ? OtzariaIcons.text_continuous_24_filled
                : OtzariaIcons.text_continuous_24_regular,
            size: 24,
          ),
        ),
      ),
    );
  }
}
