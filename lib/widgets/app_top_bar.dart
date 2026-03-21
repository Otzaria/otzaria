// lib/widgets/app_top_bar.dart
//
// AppTopBar — סרגל עליון בסגנון Chrome/M3
//
// תכונות:
// • 2 מצבים: compact (מחשב/עכבר) ו-touch (מסך מגע)
// • כפתורי אייקון עגולים עם אינדיקציית בחירה
// • מפרידים אנכיים בין קבוצות פעולות
// • שורה שניה צמודה שנעלמת בגלילה ומופיעה בגלילה הפוכה
// • תמיכה מלאה ב-RTL
// • הסתגלות לנושא בהיר/כהה
//
// **שימוש בסיסי:**
// ```dart
// AppTopBar(
//   isCompact: settingsState.compactMenuMode,
//   leadingItems: [AppTopBarItem(widget: myButton)],
//   center: OtzariaSearchField(...),
//   trailingItems: [
//     AppTopBarItem(widget: iconBtn1),
//     AppTopBarItem(widget: iconBtn2, dividerBefore: true),
//   ],
//   secondaryRow: mySecondaryWidget,
//   secondaryRowVisible: _myVisibilityNotifier,
// )
// ```
//
// **שליטה בשורה השניה דרך גלילה:**
// ```dart
// NotificationListener<ScrollNotification>(
//   onNotification: (n) {
//     if (n is ScrollUpdateNotification) {
//       final d = n.scrollDelta ?? 0;
//       if (d > 3)  _secondaryRowVisible.value = false;
//       if (d < -3) _secondaryRowVisible.value = true;
//     }
//     return false;
//   },
//   child: myScrollableBody,
// )
// ```

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppTopBarItem
// ─────────────────────────────────────────────────────────────────────────────

/// פריט יחיד בסרגל העליון.
///
/// [dividerBefore] = true → מציג מפריד אנכי לפני הפריט (לא על הראשון).
class AppTopBarItem {
  final Widget widget;
  final bool dividerBefore;

  const AppTopBarItem({
    required this.widget,
    this.dividerBefore = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  AppTopBar
// ─────────────────────────────────────────────────────────────────────────────

/// סרגל עליון בסגנון Chrome/M3 עם תמיכה מלאה ב-RTL ושורה שניה מתנועעת.
///
/// **מצבים (נשלט ע"י [isCompact]):**
/// • false (touch): גובה 56px, כפתורים 44px, מסך מגע
/// • true  (desktop): גובה 44px, כפתורים 32px עגולים בסגנון Chrome
///
/// **פריסה ב-RTL:**
/// ```
/// [trailing ← ───────── center ───────── → leading]
/// [─────────────── secondary row ─────────────────]
/// ```
///
/// **צבע הסרגל:**
/// בכהה: `surfaceContainerLow` (כהה מהתוכן — כמו Chrome dark)
/// בבהיר: `surfaceContainerHigh` (מוגבה מהתוכן — כמו Chrome light)
class AppTopBar extends StatefulWidget {
  /// פריטים בצד המוביל (ב-RTL: ימין)
  final List<AppTopBarItem> leadingItems;

  /// ווידג'ט מרכזי — לרוב שדה חיפוש
  final Widget? center;

  /// פריטים בצד הנגרר (ב-RTL: שמאל)
  final List<AppTopBarItem> trailingItems;

  /// שורה שניה — מוסתרת/מוצגת על פי [secondaryRowVisible]
  final Widget? secondaryRow;

  /// שולט בנראות השורה השניה.
  /// `true`=מוצגת, `false`=מוסתרת (אנימציה).
  /// null → תמיד מוצגת.
  final ValueNotifier<bool>? secondaryRowVisible;

  /// true = desktop/עכבר (דק, בסגנון Chrome)
  /// false = touch/מגע (סטנדרטי M3)
  final bool isCompact;

  const AppTopBar({
    super.key,
    this.leadingItems = const [],
    this.center,
    this.trailingItems = const [],
    this.secondaryRow,
    this.secondaryRowVisible,
    this.isCompact = false,
  });

  /// גובה הסרגל הראשי בלבד (לצורך חישובי Scaffold/Sliver חיצוניים)
  static double barHeight(bool isCompact) =>
      isCompact ? _kCompactHeight : _kTouchHeight;

  @override
  State<AppTopBar> createState() => _AppTopBarState();
}

// ── קבועים ──────────────────────────────────────────────────────────────────

const double _kTouchHeight = 56.0;
const double _kCompactHeight = 44.0;
const Duration _kAnimDuration = Duration(milliseconds: 220);

// ── _AppTopBarState ──────────────────────────────────────────────────────────

class _AppTopBarState extends State<AppTopBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final initialValue =
        widget.secondaryRowVisible?.value != false ? 1.0 : 0.0;
    _anim = AnimationController(
      vsync: this,
      duration: _kAnimDuration,
      value: initialValue,
    );
    _progress = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    widget.secondaryRowVisible?.addListener(_onVisibilityChanged);
  }

  @override
  void didUpdateWidget(AppTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secondaryRowVisible != widget.secondaryRowVisible) {
      oldWidget.secondaryRowVisible?.removeListener(_onVisibilityChanged);
      widget.secondaryRowVisible?.addListener(_onVisibilityChanged);
      _syncToNotifier();
    }
  }

  @override
  void dispose() {
    widget.secondaryRowVisible?.removeListener(_onVisibilityChanged);
    _anim.dispose();
    super.dispose();
  }

  void _onVisibilityChanged() => _syncToNotifier();

  void _syncToNotifier() {
    if (!mounted) return;
    final visible = widget.secondaryRowVisible?.value ?? true;
    visible ? _anim.animateTo(1.0) : _anim.animateTo(0.0);
  }

  // ── עזרי בנייה ──────────────────────────────────────────────────────────

  Widget _buildDivider() {
    final isCompact = widget.isCompact;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: SizedBox(
        height: isCompact ? 18.0 : 24.0,
        child: VerticalDivider(
          width: 9.0,
          thickness: 1.0,
          color:
              Theme.of(context).colorScheme.outline.withValues(alpha: 0.32),
        ),
      ),
    );
  }

  List<Widget> _itemsToWidgets(List<AppTopBarItem> items) {
    final List<Widget> result = [];
    for (final item in items) {
      if (item.dividerBefore && result.isNotEmpty) {
        result.add(_buildDivider());
      }
      result.add(item.widget);
    }
    return result;
  }

  /// צבע הסרגל — מובחן מרקע התוכן (כמו Chrome)
  Color _resolveBarColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // כהה: surfaceContainerLow (כהה מהsurface) — כמו Chrome dark
    // בהיר: surfaceContainerHigh (בהיר/מוגבה יותר)
    return isDark ? cs.surfaceContainerLow : cs.surfaceContainerHigh;
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.isCompact;
    final barColor = _resolveBarColor(context);
    final barH = isCompact ? _kCompactHeight : _kTouchHeight;
    final hPad = isCompact ? 6.0 : 8.0;
    final vPad = isCompact ? 4.0 : 8.0;

    final mainBar = Material(
      color: barColor,
      elevation: 2.0,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      surfaceTintColor: Colors.transparent,
      child: SizedBox(
        height: barH,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Row(
            children: [
              // פריטים מובילים
              ..._itemsToWidgets(widget.leadingItems),
              if (widget.leadingItems.isNotEmpty) const SizedBox(width: 4.0),

              // מרכז — מתרחב
              Expanded(child: widget.center ?? const SizedBox.shrink()),

              // פריטים נגררים
              if (widget.trailingItems.isNotEmpty) const SizedBox(width: 4.0),
              ..._itemsToWidgets(widget.trailingItems),
            ],
          ),
        ),
      ),
    );

    // ללא שורה שניה — החזר רק את הסרגל הראשי
    if (widget.secondaryRow == null) return mainBar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mainBar,
        // שורה שניה: SizeTransition + FadeTransition
        SizeTransition(
          sizeFactor: _progress,
          axisAlignment: -1.0, // התרחבות מהצד העליון
          child: FadeTransition(
            opacity: _progress,
            child: Material(
              color: barColor,
              elevation: 1.0,
              shadowColor: Colors.black.withValues(alpha: 0.08),
              surfaceTintColor: Colors.transparent,
              child: widget.secondaryRow!,
            ),
          ),
        ),
      ],
    );
  }
}
