import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

/// פתיחה זמנית של חלונית הניווט בריחוף על [NavPanelToggleButton]: החלונית
/// מרחפת מעל התוכן בלי הצללה, ונסגרת כשהעכבר יוצא ממנה.
class NavPanelPeekController extends ValueNotifier<bool> {
  NavPanelPeekController() : super(false);

  static const Duration openDelay = Duration(milliseconds: 120);

  /// זמן להגיע מהכפתור לחלונית. יציאה מהחלונית עצמה סוגרת מיד.
  static const Duration buttonToPaneGrace = Duration(milliseconds: 150);

  Timer? _timer;
  Timer? _leftPaneRecently;

  void buttonHoverChanged(bool inside) {
    _timer?.cancel();
    if (inside) {
      if (value) return;
      // חזרה מהחלונית אל הכפתור פותחת מיד, אחרת החלונית נסגרת ונפתחת שוב.
      if (_leftPaneRecently?.isActive ?? false) {
        value = true;
      } else {
        _timer = Timer(openDelay, () => value = true);
      }
    } else if (value) {
      _timer = Timer(buttonToPaneGrace, () => value = false);
    }
  }

  void paneHoverChanged(bool inside) {
    _timer?.cancel();
    if (inside) return;
    if (value) {
      _leftPaneRecently?.cancel();
      _leftPaneRecently = Timer(buttonToPaneGrace, () {});
    }
    value = false;
  }

  void dismiss() {
    _timer?.cancel();
    _leftPaneRecently?.cancel();
    value = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _leftPaneRecently?.cancel();
    super.dispose();
  }
}

/// חלונית הניווט האחידה של האפליקציה — מקור האמת היחיד למראה שלה.
///
/// עוטפת את [AdaptiveSidePane] (שנשאר המכניקה: פריסה רספונסיבית, גרירה,
/// overlay במסך צר) וקובעת בעצמה את כל ההיבטים העיצוביים: הצמדה לסרגל העליון,
/// צבע הרקע והפינה הקעורה במפגש עם התוכן. מסך צריכה לא מגדיר אותם שוב.
///
/// חלונית פתוחה ([isOpen]) דוחקת את התוכן. [peek] פותח אותה זמנית מעל התוכן.
/// תוכן החלונית נבנה מ-[NavTreeTile] / [NavTreeHeader] / [NavTreeGroupCard],
/// והכפתור שפותח אותה הוא [NavPanelToggleButton].
class NavSidePanel extends StatefulWidget {
  final bool isOpen;
  final bool maintainState;
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

  /// מדווח רק על פריסת החלונית הפתוחה, לא על פתיחה בריחוף.
  final ValueChanged<bool>? onLayoutModeChanged;
  final bool autoHandleResponsiveVisibility;
  final NavPanelPeekController? peek;

  const NavSidePanel({
    super.key,
    required this.isOpen,
    this.maintainState = false,
    required this.mainContent,
    required this.paneContent,
    required this.onClose,
    this.alignment = AlignmentDirectional.centerEnd,
    this.paneWidth = LayoutConstraints.sidePaneWidth,
    this.minMainContentWidth = LayoutConstraints.mainContentMinWidth,
    this.onOpen,
    this.isResizable = false,
    this.minPaneWidth = 220,
    this.maxPaneWidth,
    this.onPaneWidthChanged,
    this.onPaneResizeEnd,
    this.onLayoutModeChanged,
    this.autoHandleResponsiveVisibility = true,
    this.peek,
  });

  /// רקע חלונית הניווט — צבע הסרגל העליון, כדי שהחלונית תיראה כהמשך שלו.
  static Color background(BuildContext context) =>
      AppSurfaces.navPanelBackground(context);

  @override
  State<NavSidePanel> createState() => _NavSidePanelState();
}

class _NavSidePanelState extends State<NavSidePanel> {
  // פריסה צפה נשארת עד סוף אנימציית הסגירה, ונבנית סגורה פריים אחד לפני
  // הפתיחה — אחרת החלונית קופצת במקום להחליק.
  bool _floating = false;
  bool _peekShown = false;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    widget.peek?.addListener(_onPeekChanged);
  }

  @override
  void didUpdateWidget(NavSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peek != widget.peek) {
      oldWidget.peek?.removeListener(_onPeekChanged);
      widget.peek?.addListener(_onPeekChanged);
    }
    if (widget.isOpen && !oldWidget.isOpen) {
      _settleTimer?.cancel();
      _floating = false;
      _peekShown = false;
      final peek = widget.peek;
      if (peek != null && peek.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) => peek.dismiss());
      }
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.peek?.removeListener(_onPeekChanged);
    super.dispose();
  }

  void _onPeekChanged() {
    if (!mounted) return;
    final peeking = widget.peek!.value && !widget.isOpen;
    _settleTimer?.cancel();
    if (peeking) {
      if (_floating) {
        setState(() => _peekShown = true);
        return;
      }
      setState(() => _floating = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.peek!.value && !widget.isOpen) {
          setState(() => _peekShown = true);
        }
      });
      return;
    }
    if (_peekShown) setState(() => _peekShown = false);
    if (_floating) {
      _settleTimer = Timer(
        AppMotion.duration(context, AppTokens.animPanelSlide),
        () {
          if (mounted) setState(() => _floating = false);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final floating = _floating && !widget.isOpen;
    final peek = widget.peek;
    return AdaptiveSidePane(
      isOpen: widget.isOpen || (floating && _peekShown),
      maintainState: widget.maintainState,
      alignment: widget.alignment,
      // ההצמדה, הצבע ומרווח פס הגלילה הם העיצוב האחיד — לא פרמטרים של המסך.
      attachToTopEdge: true,
      floatOverContent: floating,
      showScrim: !floating,
      onPaneHoverChanged: floating ? peek?.paneHoverChanged : null,
      paneColor: NavSidePanel.background(context),
      scrollbarTopMargin: 0,
      mainContent: widget.mainContent,
      paneContent: widget.paneContent,
      paneWidth: widget.paneWidth,
      minMainContentWidth: widget.minMainContentWidth,
      onClose: floating && peek != null ? peek.dismiss : widget.onClose,
      onOpen: widget.onOpen,
      isResizable: widget.isResizable,
      minPaneWidth: widget.minPaneWidth,
      maxPaneWidth: widget.maxPaneWidth,
      onPaneWidthChanged: widget.onPaneWidthChanged,
      onPaneResizeEnd: widget.onPaneResizeEnd,
      onLayoutModeChanged: floating ? null : widget.onLayoutModeChanged,
      autoHandleResponsiveVisibility: widget.autoHandleResponsiveVisibility,
    );
  }
}

/// שורת הלשוניות של חלונית הניווט.
///
/// אייקון הלשונית הנבחרת מתחלף ל-filled כשסופק [NavPanelTab.iconFilled].
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
      duration: AppMotion.duration(context, AppTokens.animFast),
      child: Icon(
        iconData,
        key: ValueKey<IconData>(iconData),
        size: AppTokens.panelTabIconSize,
      ),
    );
    return PanelTab.buildTab(iconWidget, data.label);
  }
}

/// הכפתור היחיד לפתיחת/סגירת חלונית הניווט, בכל המסכים. עם [peek], ריחוף
/// על הכפתור פותח את החלונית הסגורה זמנית.
class NavPanelToggleButton extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onToggle;
  final NavPanelPeekController? peek;

  const NavPanelToggleButton({
    super.key,
    required this.isOpen,
    required this.onToggle,
    this.peek,
  });

  /// האם להציג את הגליף שחץ שלו פונה ימינה (`text_continuous_ltr`), במקום
  /// זה שחץ שלו פונה שמאלה (`text_continuous_rtl`), כך שהחץ יצביע לכיוון
  /// שאליו החלונית תזוז בלחיצה (issue #1417).
  ///
  /// חלונית סגורה בצד הסוף של ממשק RTL (ימין) נפתחת שמאלה, ולכן שם מוצג
  /// ה-rtl. חלונית פתוחה נסגרת לכיוון ההפוך — ה-ltr; ובממשק LTR, שבו צד
  /// הסוף הוא שמאל, שני המצבים מתהפכים.
  static bool useLtrGlyph({
    required bool isOpen,
    required TextDirection textDirection,
  }) => isOpen == (textDirection == TextDirection.rtl);

  @override
  Widget build(BuildContext context) {
    final ltrGlyph = useLtrGlyph(
      isOpen: isOpen,
      textDirection: Directionality.of(context),
    );
    final peek = this.peek;
    final label = isOpen
        ? context.settingsText('הסתר ניווט')
        : context.settingsText('הצג ניווט');
    // החלונית שנפתחת בריחוף תופסת את מקום ה-tooltip.
    final hidesTooltip = peek != null && !isOpen;
    final button = Semantics(
      label: hidesTooltip ? label : null,
      child: IconButton(
        tooltip: hidesTooltip ? null : label,
        onPressed: () {
          peek?.dismiss();
          onToggle();
        },
        visualDensity: VisualDensity.standard,
        splashRadius: 22,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
        icon: AnimatedSwitcher(
          duration: AppMotion.duration(context, AppTokens.animFast),
          child: Icon(
            key: ValueKey(isOpen),
            _glyph(isOpen: isOpen, ltr: ltrGlyph),
            size: 24,
          ),
        ),
      ),
    );
    if (peek == null) return button;
    return MouseRegion(
      onEnter: (_) {
        if (!isOpen) peek.buttonHoverChanged(true);
      },
      onExit: (_) => peek.buttonHoverChanged(false),
      child: button,
    );
  }

  static IconData _glyph({required bool isOpen, required bool ltr}) {
    if (ltr) {
      return isOpen
          ? OtzariaIcons.text_continuous_ltr_24_filled
          : OtzariaIcons.text_continuous_ltr_24_regular;
    }
    return isOpen
        ? OtzariaIcons.text_continuous_rtl_24_filled
        : OtzariaIcons.text_continuous_rtl_24_regular;
  }
}
