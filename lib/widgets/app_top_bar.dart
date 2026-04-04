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
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';

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

  const AppTopBar({
    super.key,
    this.leadingItems = const [],
    this.center,
    this.trailingItems = const [],
    this.secondaryRow,
    this.secondaryRowVisible,
    this.totalHeightNotifier,
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
  final GlobalKey _secondaryRowKey = GlobalKey();
  Timer? _debounceTimer;
  bool _pendingVisible = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.secondaryRowVisible?.value != false ? 1.0 : 0.0;
    _anim = AnimationController(
        vsync: this, duration: _kAnimDuration, value: initial);
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
      _syncToNotifier(immediate: true);
    }
    if (oldWidget.secondaryRow != widget.secondaryRow ||
        oldWidget.totalHeightNotifier != widget.totalHeightNotifier) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyHeight());
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
      BuildContext context, List<AppTopBarItem> items) {
    final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
    final List<Widget> result = [];
    for (final item in items) {
      if (item.dividerBefore && result.isNotEmpty) {
        result.add(_buildDivider(context, isCompact));
      }
      result.add(item.widget);
    }
    return result;
  }

  Widget _buildDivider(BuildContext context, bool isCompact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: SizedBox(
        height: isCompact ? 18.0 : 24.0,
        child: VerticalDivider(
          width: 9.0,
          thickness: 1.0,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.32),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsBloc, SettingsState>(
      listenWhen: (prev, next) =>
          prev.compactMenuMode != next.compactMenuMode,
      listener: (context, _) {
        // גובה הסרגל השתנה — מעדכנים את totalHeightNotifier אחרי הframe
        WidgetsBinding.instance.addPostFrameCallback((_) => _notifyHeight());
      },
      builder: (context, settingsState) {
        final isCompact = settingsState.compactMenuMode;
        final cs = Theme.of(context).colorScheme;
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
                  if (widget.leadingItems.isNotEmpty)
                    const SizedBox(width: 8.0),
                  Expanded(child: widget.center ?? const SizedBox.shrink()),
                  if (widget.trailingItems.isNotEmpty)
                    const SizedBox(width: 8.0),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mainBar,
            SizeTransition(
              sizeFactor: _progress,
              axisAlignment: -1.0,
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
