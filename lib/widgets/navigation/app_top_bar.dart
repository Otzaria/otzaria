// lib/widgets/app_top_bar.dart
//
// AppTopBar — סרגל עליון בסגנון Chrome / M3.
//
// שינויים v3:
// • תוקן: Colors.black → cs.shadow (לא hardcoded colors, עמידה ב-AGENTS.md)
// • תוקן: shadowColor משתמש ב-cs.shadow בהתאמה לבהיר/כהה
// • ללא שינוי ב-API.
//
// שינויים v4:
// • הוספת תלות אוטומטית ב-SettingsBloc לקביעת isCompact
// • הסרת הצורך להעביר isCompact מכל מסך

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/view/pane_drag_handle.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppTopBarItem
// ─────────────────────────────────────────────────────────────────────────────

class AppTopBarItem {
  final Widget widget;
  final bool dividerBefore;
  final bool flexible;

  const AppTopBarItem({
    required this.widget,
    this.dividerBefore = false,
    this.flexible = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  AppTopBar
// ─────────────────────────────────────────────────────────────────────────────

/// סרגל עליון אחיד לכל מסכי האפליקציה.
///
/// תכונות:
/// - שורה ראשית: [leadingItems] | [center] | [trailingItems]
/// - שורה שניה אופציונלית עם אנימציית גלילה (SizeTransition + FadeTransition)
/// - [isCompact] מתקבל אוטומטית מ-SettingsBloc (compactMenuMode)
/// - [secondaryRowVisible] – ValueNotifier חיצוני לשליטה בשורה שניה
/// - [scrollDebounceMs] – debounce למניעת flicker בגלילה (ברירת מחדל: 80ms)
class AppTopBar extends StatefulWidget {
  final List<AppTopBarItem> leadingItems;
  final Widget? center;
  final List<AppTopBarItem> trailingItems;
  final Widget? secondaryRow;
  final ValueNotifier<bool>? secondaryRowVisible;
  final ValueNotifier<double>? totalHeightNotifier;

  /// דיבאונס לעדכון השורה השניה (ms) — מונע rebuild חוזר בגלילה מהירה.
  final int scrollDebounceMs;

  /// override נקודתי לצבע הסרגל — נועד למסך הקריאה בלבד, כדי להתאים את
  /// הטופ-בר לרקע הקריאה שנבחר (ראו [AppSurfaces.readerTopBarBackground]).
  /// כשלא מועבר, נשאר `null` וחוזרים לברירת המחדל [AppSurfaces.topBarBackground].
  final Color? backgroundColor;

  /// כשמוגדר, AppTopBar משתמש בפריסה אדפטיבית שמגבילה את שני הצדדים
  /// ומשאירה לפחות את הרוחב הזה לאזור המרכז ככל שניתן.
  final double? minCenterWidth;

  const AppTopBar({
    super.key,
    this.leadingItems = const [],
    this.center,
    this.trailingItems = const [],
    this.secondaryRow,
    this.secondaryRowVisible,
    this.totalHeightNotifier,
    this.scrollDebounceMs = 80,
    this.backgroundColor,
    this.minCenterWidth,
  });

  /// גובה הסרגל לפי מצב compact
  static double barHeight(bool isCompact) =>
      isCompact ? _kCompactHeight : _kTouchHeight;

  /// הריווח האופקי בקצות הסרגל. ווידג'ט שצריך להתיישר לתוכן שמתחתיו
  /// (כמו סרגל חלונית הניווט) מפחית אותו מהרוחב/מהשוליים שלו.
  static double horizontalPadding(bool isCompact) => isCompact ? 6.0 : 8.0;

  /// סגנון טקסט אחיד לכותרת הסרגל העליון — ישמש בכל מסכי הקריאה.
  static TextStyle titleStyle(BuildContext context) {
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  /// סגנון טקסט אחיד לכותרת משנה/מחבר בסרגל העליון.
  static TextStyle subtitleStyle(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  @override
  State<AppTopBar> createState() => _AppTopBarState();
}

const double _kTouchHeight = 56.0;
const double _kCompactHeight = 44.0;
const Duration _kAnimDuration = Duration(milliseconds: 220);

class _AppTopBarState extends State<AppTopBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _progress;
  final GlobalKey _secondaryRowKey = GlobalKey();
  Timer? _debounceTimer;
  bool _pendingVisible = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.secondaryRowVisible?.value != false ? 1.0 : 0.0;
    _anim = AnimationController(
      vsync: this,
      duration: _kAnimDuration,
      value: initial,
    );
    _progress = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _anim.addListener(_notifyHeight);
    _pendingVisible = widget.secondaryRowVisible?.value ?? true;
    widget.secondaryRowVisible?.addListener(_onVisibilityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyHeight());
  }

  @override
  void didUpdateWidget(AppTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secondaryRowVisible != widget.secondaryRowVisible) {
      oldWidget.secondaryRowVisible?.removeListener(_onVisibilityChanged);
      widget.secondaryRowVisible?.addListener(_onVisibilityChanged);
      _pendingVisible = widget.secondaryRowVisible?.value ?? true;
      _scheduleHeightSync(() => _syncToNotifier(immediate: true));
    }
    if (oldWidget.secondaryRow != widget.secondaryRow ||
        oldWidget.totalHeightNotifier != widget.totalHeightNotifier) {
      _scheduleHeightSync(_notifyHeight);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.secondaryRowVisible?.removeListener(_onVisibilityChanged);
    _anim.removeListener(_notifyHeight);
    _anim.dispose();
    super.dispose();
  }

  void _notifyHeight() {
    final notifier = widget.totalHeightNotifier;
    if (notifier == null) return;

    // קבלת isCompact מה-context
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    final mainBarHeight = AppTopBar.barHeight(isCompact);
    double secondaryRowHeight = 0;
    if (widget.secondaryRow != null) {
      final renderObject = _secondaryRowKey.currentContext?.findRenderObject();
      if (renderObject is RenderBox) {
        secondaryRowHeight = renderObject.size.height;
      }
    }

    final totalHeight = mainBarHeight + (secondaryRowHeight * _anim.value);
    if (notifier.value != totalHeight) {
      notifier.value = totalHeight;
    }
  }

  void _scheduleHeightSync(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback();
    });
  }

  void _onVisibilityChanged() {
    final next = widget.secondaryRowVisible?.value ?? true;
    if (next == _pendingVisible) return;
    _pendingVisible = next;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      Duration(milliseconds: widget.scrollDebounceMs),
      () => _syncToNotifier(),
    );
  }

  void _syncToNotifier({bool immediate = false}) {
    if (!mounted) return;
    final visible = widget.secondaryRowVisible?.value ?? true;
    if (immediate) {
      _anim.value = visible ? 1.0 : 0.0;
    } else {
      visible ? _anim.animateTo(1.0) : _anim.animateTo(0.0);
    }
  }

  // ── עזרי בנייה ──────────────────────────────────────────────────────────

  List<Widget> _itemsToWidgets(
    BuildContext context,
    List<AppTopBarItem> items,
  ) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    final List<Widget> result = [];
    final double buttonSpacing = isCompact ? 4.0 : 8.0;
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.dividerBefore && result.isNotEmpty) {
        result.add(_buildDivider(context, isCompact));
      }
      if (result.isNotEmpty) {
        result.add(SizedBox(width: buttonSpacing));
      }
      result.add(
        item.flexible
            ? Flexible(
                fit: FlexFit.loose,
                child: item.widget,
              )
            : item.widget,
      );
    }
    return result;
  }

  Widget _buildDivider(BuildContext context, bool isCompact) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: SizedBox(
        height: isCompact ? 20.0 : 24.0,
        child: VerticalDivider(
          width: 1.0,
          thickness: 1.0,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsBloc, SettingsState>(
      listenWhen: (prev, next) => prev.compactMenuMode != next.compactMenuMode,
      listener: (context, _) {
        // גובה הסרגל השתנה — מעדכנים את totalHeightNotifier אחרי הframe
        _scheduleHeightSync(_notifyHeight);
      },
      builder: (context, settingsState) {
        final isCompact = settingsState.compactMenuMode;
        final cs = Theme.of(context).colorScheme;
        final barColor =
            widget.backgroundColor ?? AppSurfaces.topBarBackground(context);
        final shadowColor = cs.shadow.withValues(alpha: 0.14);
        final barH = isCompact ? _kCompactHeight : _kTouchHeight;
        final hPad = AppTopBar.horizontalPadding(isCompact);
        final vPad = isCompact ? 4.0 : 8.0;

        // בחלונית של טאב מפוצל הפריט הראשון הוא ידית גרירה שמחזירה את
        // החלונית לשורת הכרטיסיות.
        final dragPane = PaneDragHandleScope.paneOf(context);

        // במסך מלא לחצן היציאה משולב כפריט ראשון בסרגל (ולא כלחצן צף),
        // כדי שלא יכסה ולא יחסום לחיצות על פריטים אחרים.
        final leadingItems = [
          if (dragPane != null)
            AppTopBarItem(widget: PaneDragHandleButton(pane: dragPane)),
          if (settingsState.isFullscreen)
            AppTopBarItem(
              widget: BarButton.icon(
                tooltip: 'צא ממסך מלא',
                icon: FluentIcons.full_screen_minimize_24_regular,
                compact: isCompact,
                onPressed: () => FullscreenHelper.toggleFullscreen(
                  context,
                  false,
                ),
              ),
            ),
          ...widget.leadingItems,
        ];

        final leadingWidget = leadingItems.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: _itemsToWidgets(context, leadingItems),
              );

        final trailingWidget = widget.trailingItems.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: _itemsToWidgets(
                  context,
                  widget.trailingItems,
                ),
              );

        final Widget toolbar = widget.minCenterWidth == null
            ? NavigationToolbar(
                middleSpacing: 8.0,
                leading: leadingWidget,
                middle: widget.center,
                trailing: trailingWidget,
              )
            : _AdaptiveTopBarToolbar(
                leading: leadingWidget,
                middle: widget.center,
                trailing: trailingWidget,
                middleSpacing: 8.0,
                minMiddleWidth: widget.minCenterWidth!,
                minTrailingWidth: trailingWidget == null
                    ? 0.0
                    : BarButton.toolbarWidth(isCompact),
              );

        final mainBar = Material(
          color: barColor,
          elevation: 2.0,
          shadowColor: shadowColor,
          surfaceTintColor: Colors.transparent,
          child: SizedBox(
            height: barH,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              child: toolbar,
            ),
          ),
        );

        // תמיד מחזירים Column כדי לשמור על מיקום יציב של mainBar (position 0).
        // שינוי מ-Material ישיר ל-Column גורם ל-Flutter למחוק ולאחזר את mainBar
        // (ולאבד פוקוס מקלדת). עם Column קבוע, mainBar תמיד ב-position 0
        // ו-Flutter שומר על ה-element (ועל הפוקוס) גם כשהשורה השניה מופיעה/נעלמת.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mainBar,
            if (widget.secondaryRow != null)
              SizeTransition(
                sizeFactor: _progress,
                alignment: AlignmentDirectional.topStart,
                child: FadeTransition(
                  opacity: _progress,
                  child: SizedBox(
                    width: double.infinity,
                    child: Material(
                      key: _secondaryRowKey,
                      color: barColor,
                      elevation: 1.0,
                      shadowColor: cs.shadow.withValues(alpha: 0.08),
                      surfaceTintColor: Colors.transparent,
                      child: widget.secondaryRow!,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _AdaptiveTopBarSlot {
  leading,
  middle,
  trailing,
}

class _AdaptiveTopBarToolbar extends StatelessWidget {
  final Widget? leading;
  final Widget? middle;
  final Widget? trailing;
  final double middleSpacing;
  final double minMiddleWidth;
  final double minTrailingWidth;

  const _AdaptiveTopBarToolbar({
    required this.leading,
    required this.middle,
    required this.trailing,
    required this.middleSpacing,
    required this.minMiddleWidth,
    required this.minTrailingWidth,
  });

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _AdaptiveTopBarLayout(
        textDirection: Directionality.of(context),
        middleSpacing: middleSpacing,
        minMiddleWidth: minMiddleWidth,
        minTrailingWidth: minTrailingWidth,
      ),
      children: [
        if (leading != null)
          LayoutId(
            id: _AdaptiveTopBarSlot.leading,
            child: leading!,
          ),
        if (middle != null)
          LayoutId(
            id: _AdaptiveTopBarSlot.middle,
            child: middle!,
          ),
        if (trailing != null)
          LayoutId(
            id: _AdaptiveTopBarSlot.trailing,
            child: trailing!,
          ),
      ],
    );
  }
}

class _AdaptiveTopBarLayout extends MultiChildLayoutDelegate {
  final TextDirection textDirection;
  final double middleSpacing;
  final double minMiddleWidth;
  final double minTrailingWidth;

  _AdaptiveTopBarLayout({
    required this.textDirection,
    required this.middleSpacing,
    required this.minMiddleWidth,
    required this.minTrailingWidth,
  });

  @override
  void performLayout(Size size) {
    var leadingSize = Size.zero;
    var trailingSize = Size.zero;
    var middleSize = Size.zero;

    final hasMiddle = hasChild(_AdaptiveTopBarSlot.middle);
    final hasTrailing = hasChild(_AdaptiveTopBarSlot.trailing);

    final middleReserve = hasMiddle ? minMiddleWidth : 0.0;
    final spacingReserve = hasMiddle ? middleSpacing * 2 : 0.0;
    final trailingReserve = hasTrailing ? minTrailingWidth : 0.0;

    if (hasChild(_AdaptiveTopBarSlot.leading)) {
      final maxLeadingWidth = math.max(
        0.0,
        size.width - middleReserve - spacingReserve - trailingReserve,
      );

      leadingSize = layoutChild(
        _AdaptiveTopBarSlot.leading,
        BoxConstraints(
          maxWidth: maxLeadingWidth,
          maxHeight: size.height,
        ),
      );
    }

    if (hasTrailing) {
      final maxTrailingWidth = math.max(
        0.0,
        size.width - leadingSize.width - middleReserve - spacingReserve,
      );

      trailingSize = layoutChild(
        _AdaptiveTopBarSlot.trailing,
        BoxConstraints(
          maxWidth: maxTrailingWidth,
          maxHeight: size.height,
        ),
      );
    }

    if (hasMiddle) {
      final maxMiddleWidth = math.max(
        0.0,
        size.width - leadingSize.width - trailingSize.width - spacingReserve,
      );

      middleSize = layoutChild(
        _AdaptiveTopBarSlot.middle,
        BoxConstraints(
          maxWidth: maxMiddleWidth,
          maxHeight: size.height,
        ),
      );
    }

    final leadingX = textDirection == TextDirection.rtl
        ? size.width - leadingSize.width
        : 0.0;

    final trailingX = textDirection == TextDirection.rtl
        ? 0.0
        : size.width - trailingSize.width;

    if (hasChild(_AdaptiveTopBarSlot.leading)) {
      positionChild(
        _AdaptiveTopBarSlot.leading,
        Offset(
          leadingX,
          (size.height - leadingSize.height) / 2,
        ),
      );
    }

    if (hasTrailing) {
      positionChild(
        _AdaptiveTopBarSlot.trailing,
        Offset(
          trailingX,
          (size.height - trailingSize.height) / 2,
        ),
      );
    }

    if (hasMiddle) {
      final leftBoundary = textDirection == TextDirection.rtl
          ? trailingSize.width + middleSpacing
          : leadingSize.width + middleSpacing;

      final rightBoundary = textDirection == TextDirection.rtl
          ? size.width - leadingSize.width - middleSpacing
          : size.width - trailingSize.width - middleSpacing;

      final idealX = (size.width - middleSize.width) / 2;

      final maxX = math.max(
        leftBoundary,
        rightBoundary - middleSize.width,
      );

      final middleX = idealX.clamp(leftBoundary, maxX).toDouble();

      positionChild(
        _AdaptiveTopBarSlot.middle,
        Offset(
          middleX,
          (size.height - middleSize.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(
    covariant _AdaptiveTopBarLayout oldDelegate,
  ) {
    return oldDelegate.textDirection != textDirection ||
        oldDelegate.middleSpacing != middleSpacing ||
        oldDelegate.minMiddleWidth != minMiddleWidth ||
        oldDelegate.minTrailingWidth != minTrailingWidth;
  }
}
