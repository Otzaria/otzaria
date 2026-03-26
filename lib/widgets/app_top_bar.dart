// lib/widgets/app_top_bar.dart
//
// AppTopBar — סרגל עליון בסגנון Chrome / M3.
//
// שינויים v3:
// • תוקן: Colors.black → cs.shadow (לא hardcoded colors, עמידה ב-AGENTS.md)
// • תוקן: shadowColor משתמש ב-cs.shadow בהתאמה לבהיר/כהה
// • ללא שינוי ב-API.

import 'dart:async';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppTopBarItem
// ─────────────────────────────────────────────────────────────────────────────

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

/// סרגל עליון אחיד לכל מסכי האפליקציה.
///
/// תכונות:
/// - שורה ראשית: [leadingItems] | [center] | [trailingItems]
/// - שורה שניה אופציונלית עם אנימציית גלילה (SizeTransition + FadeTransition)
/// - [isCompact] – מצב desktop (44px) לעומת touch (56px)
/// - [secondaryRowVisible] – ValueNotifier חיצוני לשליטה בשורה שניה
/// - [scrollDebounceMs] – debounce למניעת flicker בגלילה (ברירת מחדל: 80ms)
class AppTopBar extends StatefulWidget {
  final List<AppTopBarItem> leadingItems;
  final Widget? center;
  final List<AppTopBarItem> trailingItems;
  final Widget? secondaryRow;
  final ValueNotifier<bool>? secondaryRowVisible;
  final bool isCompact;

  /// דיבאונס לעדכון השורה השניה (ms) — מונע rebuild חוזר בגלילה מהירה.
  final int scrollDebounceMs;

  const AppTopBar({
    super.key,
    this.leadingItems = const [],
    this.center,
    this.trailingItems = const [],
    this.secondaryRow,
    this.secondaryRowVisible,
    this.isCompact = false,
    this.scrollDebounceMs = 80,
  });

  /// גובה הסרגל לפי מצב compact
  static double barHeight(bool isCompact) =>
      isCompact ? _kCompactHeight : _kTouchHeight;

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
  Timer? _debounceTimer;
  bool _pendingVisible = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.secondaryRowVisible?.value != false ? 1.0 : 0.0;
    _anim = AnimationController(
        vsync: this, duration: _kAnimDuration, value: initial);
    _progress = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _pendingVisible = widget.secondaryRowVisible?.value ?? true;
    widget.secondaryRowVisible?.addListener(_onVisibilityChanged);
  }

  @override
  void didUpdateWidget(AppTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secondaryRowVisible != widget.secondaryRowVisible) {
      oldWidget.secondaryRowVisible?.removeListener(_onVisibilityChanged);
      widget.secondaryRowVisible?.addListener(_onVisibilityChanged);
      _syncToNotifier(immediate: true);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.secondaryRowVisible?.removeListener(_onVisibilityChanged);
    _anim.dispose();
    super.dispose();
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

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: SizedBox(
        height: widget.isCompact ? 18.0 : 24.0,
        child: VerticalDivider(
          width: 9.0,
          thickness: 1.0,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.32),
        ),
      ),
    );
  }

  List<Widget> _itemsToWidgets(
      BuildContext context, List<AppTopBarItem> items) {
    final List<Widget> result = [];
    for (final item in items) {
      if (item.dividerBefore && result.isNotEmpty) {
        result.add(_buildDivider(context));
      }
      result.add(item.widget);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCompact = widget.isCompact;
    // ✅ תוקן: barColor ו-shadowColor משתמשים בצבעי theme
    final barColor = cs.secondaryContainer;
    final shadowColor = cs.shadow.withValues(alpha: 0.14);
    final barH = isCompact ? _kCompactHeight : _kTouchHeight;
    final hPad = isCompact ? 6.0 : 8.0;
    final vPad = isCompact ? 4.0 : 8.0;

    final mainBar = Material(
      color: barColor,
      elevation: 2.0,
      shadowColor: shadowColor,
      surfaceTintColor: Colors.transparent,
      child: SizedBox(
        height: barH,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Row(
            children: [
              ..._itemsToWidgets(context, widget.leadingItems),
              if (widget.leadingItems.isNotEmpty) const SizedBox(width: 4.0),
              Expanded(child: widget.center ?? const SizedBox.shrink()),
              if (widget.trailingItems.isNotEmpty) const SizedBox(width: 4.0),
              ..._itemsToWidgets(context, widget.trailingItems),
            ],
          ),
        ),
      ),
    );

    if (widget.secondaryRow == null) return mainBar;

    // שורה שניה עם אנימציה —
    // SizeTransition מבטיח שהתוכן מתחת לסרגל לא ייחתך ולא יקפוץ
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mainBar,
        SizeTransition(
          sizeFactor: _progress,
          axisAlignment: -1.0,
          child: FadeTransition(
            opacity: _progress,
            child: Material(
              color: barColor,
              elevation: 1.0,
              shadowColor: cs.shadow.withValues(alpha: 0.08),
              surfaceTintColor: Colors.transparent,
              child: widget.secondaryRow!,
            ),
          ),
        ),
      ],
    );
  }
}
