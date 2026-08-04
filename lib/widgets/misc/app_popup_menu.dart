import 'dart:async';
import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/settings/settings_exports.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AppMenuEntry — נתוני פריט בתפריט
// ═══════════════════════════════════════════════════════════════════════════

class AppMenuEntry<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
  final bool isDestructive;
  final Widget? trailing;

  /// תוכן מותאם להצגה במקום [label] (החיפוש עדיין מתבצע לפי [label]).
  final Widget? labelWidget;

  /// שמור מקום ריק בעמודת סימן ה-✓ גם כשהשורה אינה נבחרת.
  final bool reserveTrailingGap;

  /// רוחב בפיקסלים המוקצה ל-[trailing] בחישוב [labelMaxWidth].
  /// 0 = ברירת מחדל (iconSize + 8).
  final double trailingReservedWidth;

  /// תת-כותרת המשויכת לאפשרות זו — נלקחת אוטומטית ע"י
  /// [SettingsActionTile.dropdownTile] כשלא סופק subtitle מפורש.
  final String? subtitle;

  const AppMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
    this.isDestructive = false,
    this.trailing,
    this.labelWidget,
    this.reserveTrailingGap = false,
    this.trailingReservedWidth = 0,
    this.subtitle,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// AppContextMenuIconAction — פעולת אייקון בודדת בשורת האייקונים העליונה
// (סגנון Windows 11: שורת כפתורי אייקון בראש תפריט ההקשר)
// ═══════════════════════════════════════════════════════════════════════════

class AppContextMenuIconAction {
  /// כיתוב קצר (מילה אחת) שמוצג מתחת לאייקון. בהיעדרו מוצג [tooltip].
  final String? label;

  /// טקסט הרחבה שמוצג בריחוף על האייקון. null/ריק → אין tooltip.
  final String? tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  /// כשמוגדר, האייקון פותח תת-תפריט (עם חץ למטה) במקום פעולה ישירה.
  final List<AppContextMenuSubAction> Function()? submenuBuilder;

  const AppContextMenuIconAction({
    required this.icon,
    this.label,
    this.tooltip,
    this.onTap,
    this.enabled = true,
    this.submenuBuilder,
  });
}

class AppContextMenuColorAction {
  final String id;
  final Color color;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;

  const AppContextMenuColorAction({
    required this.id,
    required this.color,
    required this.label,
    this.icon,
    this.onTap,
    this.selected = false,
  });
}

/// פריט פעולה פשוט בתת-תפריט של כפתור אייקון בשורה העליונה.
/// מכיל בדיוק את מה שתת-התפריט מרנדר — בלי divider/trailing/קינון של
/// [AppContextMenuEntry] שלא נתמכים שם.
class AppContextMenuSubAction {
  final String label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback? onTap;

  const AppContextMenuSubAction({
    required this.label,
    this.icon,
    this.enabled = true,
    this.onTap,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// AppContextMenuEntry — פריט בתפריט הקשר (right-click)
// ═══════════════════════════════════════════════════════════════════════════

class AppContextMenuEntry {
  final Key? key;
  final String? label;
  final Widget? labelWidget;
  final IconData? icon;
  final bool enabled;
  final bool isDivider;
  final bool isDestructive;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final Widget? trailing;
  // תת-פריטים לתפריט משנה
  final List<AppContextMenuEntry>? children;
  // בנייה עצלה של תת-פריטים לתפריט משנה.
  final List<AppContextMenuEntry> Function()? childrenBuilder;
  // תת-תפריט תגובתי שמתעדכן בזמן אמת (למשל רשימת כרטיסיות פתוחות)
  final Stream<Object?>? childrenRefreshStream;
  // חלונית תצוגה מקדימה צפה שנפתחת ברפרוף על השורה בתפריט.
  final WidgetBuilder? hoverPreviewBuilder;

  /// כשמוגדר, הערך מרונדר כשורה אופקית של כפתורי אייקון בראש התפריט
  /// (סגנון Windows 11) במקום שורת טקסט רגילה.
  final List<AppContextMenuIconAction>? iconRowActions;
  final List<AppContextMenuColorAction>? colorRowActions;

  const AppContextMenuEntry({
    required this.label,
    this.key,
    this.labelWidget,
    this.icon,
    this.enabled = true,
    this.isDestructive = false,
    this.isSelected = false,
    this.isHighlighted = false,
    this.onTap,
    this.trailing,
    this.children,
    this.childrenBuilder,
    this.childrenRefreshStream,
    this.hoverPreviewBuilder,
  }) : iconRowActions = null,
       colorRowActions = null,
       isDivider = false;

  /// שורת כפתורי אייקון בראש התפריט (סגנון Windows 11).
  const AppContextMenuEntry.iconRow(List<AppContextMenuIconAction> actions)
    : assert(actions.length > 0, 'iconRow דורש לפחות פעולה אחת'),
      iconRowActions = actions,
      colorRowActions = null,
      key = null,
      label = null,
      labelWidget = null,
      icon = null,
      enabled = true,
      isDivider = false,
      isDestructive = false,
      isSelected = false,
      isHighlighted = false,
      onTap = null,
      trailing = null,
      children = null,
      childrenBuilder = null,
      childrenRefreshStream = null,
      hoverPreviewBuilder = null;

  const AppContextMenuEntry.colorRow(List<AppContextMenuColorAction> actions)
    : assert(actions.length > 0, 'colorRow דורש לפחות צבע אחד'),
      colorRowActions = actions,
      iconRowActions = null,
      key = null,
      label = null,
      labelWidget = null,
      icon = null,
      enabled = true,
      isDivider = false,
      isDestructive = false,
      isSelected = false,
      isHighlighted = false,
      onTap = null,
      trailing = null,
      children = null,
      childrenBuilder = null,
      childrenRefreshStream = null,
      hoverPreviewBuilder = null;

  const AppContextMenuEntry.divider()
    : key = null,
      label = null,
      labelWidget = null,
      icon = null,
      enabled = false,
      isDivider = true,
      isDestructive = false,
      isSelected = false,
      isHighlighted = false,
      onTap = null,
      trailing = null,
      children = null,
      childrenBuilder = null,
      childrenRefreshStream = null,
      hoverPreviewBuilder = null,
      iconRowActions = null,
      colorRowActions = null;
}

bool hasEnabledAppContextMenuEntries(List<AppContextMenuEntry> entries) {
  return entries.any((entry) => !entry.isDivider && entry.enabled);
}

// ═══════════════════════════════════════════════════════════════════════════
// AppPopupMenuButton — כפתור שפותח תפריט
// ═══════════════════════════════════════════════════════════════════════════

class AppPopupMenuButton<T> extends StatefulWidget {
  final List<AppMenuEntry<T>>? entries;
  final List<PopupMenuEntry<T>> Function(BuildContext context)? itemBuilder;
  final ValueChanged<T>? onSelected;
  final Widget? child;
  final Widget? icon;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final PopupMenuPosition position;
  final Offset offset;
  final bool enabled;
  final T? initialValue;

  /// כשמוגדר, הכפתור יוצג כ-BarButton.icon (סרגל) במקום IconButton.
  /// הערך [icon] (Widget) ישמש כ-iconWidget ב-BarButton.icon.
  final IconData? iconData;

  /// כשמוגדר, הכפתור יוצג עם רקע טוני קבוע (secondaryContainer),
  /// ובריחוף יוצג צבע מוגבר — שימושי לכפתורי מצב פעיל (כמו מיון).
  final bool highlighted;

  const AppPopupMenuButton({
    super.key,
    this.entries,
    this.itemBuilder,
    this.onSelected,
    this.child,
    this.icon,
    this.tooltip,
    this.padding,
    this.constraints,
    this.position = PopupMenuPosition.under,
    this.offset = const Offset(0, 4),
    this.enabled = true,
    this.initialValue,
    this.iconData,
    this.highlighted = false,
  });

  @override
  State<AppPopupMenuButton<T>> createState() => _AppPopupMenuButtonState<T>();
}

class _AppPopupMenuButtonState<T> extends State<AppPopupMenuButton<T>> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _isMenuOpen = false;

  bool get _isTouchMode {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  bool get _hasCompactConstraints {
    final constraints = widget.constraints;
    if (constraints == null) return false;
    final minWidth = constraints.minWidth;
    final maxWidth = constraints.maxWidth;
    final minHeight = constraints.minHeight;
    final maxHeight = constraints.maxHeight;
    final width = minWidth > 0 ? minWidth : maxWidth;
    final height = minHeight > 0 ? minHeight : maxHeight;
    return width > 0 && width <= 40 && height > 0 && height <= 40;
  }

  List<PopupMenuEntry<T>> _buildItems(
    BuildContext context,
    AppMenuMetrics metrics,
  ) {
    return widget.itemBuilder?.call(context) ??
        widget.entries!
            .map<PopupMenuEntry<T>>(
              (entry) => buildAppPopupMenuItem<T>(
                context,
                entry,
                metrics,
                widget.initialValue,
              ),
            )
            .toList();
  }

  Future<void> _showAdaptiveMenu() async {
    if (!widget.enabled) return;
    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null) return;

    setState(() => _isMenuOpen = true);
    final selected = await showAnchoredAppMenu<T>(
      context: context,
      anchorContext: anchorContext,
      itemsBuilder: (metrics) => _buildItems(context, metrics),
      position: widget.position,
      offset: widget.offset,
    );
    if (mounted) setState(() => _isMenuOpen = false);

    if (selected != null) {
      widget.onSelected?.call(selected);
    }
  }

  Future<void> showMenu() => _showAdaptiveMenu();

  @override
  Widget build(BuildContext context) {
    assert(widget.entries != null || widget.itemBuilder != null);

    Widget trigger;
    if (widget.child != null) {
      trigger = InkWell(
        onTap: widget.enabled ? _showAdaptiveMenu : null,
        borderRadius: AppTokens.borderRadiusAll,
        child: widget.child,
      );
    } else if (_isTouchMode &&
        widget.tooltip != null &&
        !_hasCompactConstraints) {
      trigger = TextButton.icon(
        onPressed: widget.enabled ? _showAdaptiveMenu : null,
        icon: widget.icon ?? const Icon(FluentIcons.more_vertical_24_regular),
        label: Text(
          widget.tooltip!,
        ),
      );
    } else if (widget.iconData != null) {
      // מצב Toolbar: BarButton.icon עם אייקון מסוגנן
      final isCompact = context.read<SettingsBloc>().state.compactMenuMode;
      trigger = Opacity(
        opacity: widget.enabled ? 1.0 : 0.38,
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: BarButton.icon(
            tooltip: widget.tooltip ?? '',
            icon: widget.iconData!,
            iconWidget: widget.icon,
            compact: isCompact,
            selected: _isMenuOpen,
            onPressed: _showAdaptiveMenu,
          ),
        ),
      );
    } else if (widget.highlighted) {
      final cs = Theme.of(context).colorScheme;
      trigger = IconButton(
        onPressed: widget.enabled ? _showAdaptiveMenu : null,
        padding: widget.padding ?? EdgeInsets.zero,
        constraints: widget.constraints,
        tooltip: widget.tooltip,
        style: IconButton.styleFrom(
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
        ),
        icon: widget.icon ?? const Icon(FluentIcons.more_vertical_24_regular),
      );
    } else {
      trigger = IconButton(
        onPressed: widget.enabled ? _showAdaptiveMenu : null,
        padding: widget.padding ?? EdgeInsets.zero,
        constraints: widget.constraints,
        tooltip: widget.tooltip,
        icon: widget.icon ?? const Icon(FluentIcons.more_vertical_24_regular),
      );
    }

    if (widget.child == null &&
        widget.constraints != null &&
        trigger is! IconButton) {
      trigger = ConstrainedBox(
        constraints: widget.constraints!,
        child: Center(child: trigger),
      );
    }

    return KeyedSubtree(
      key: _anchorKey,
      child: trigger,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// showAnchoredAppMenu — פתיחת תפריט עוגן לרכיב קיים
// ═══════════════════════════════════════════════════════════════════════════

Future<T?> showAnchoredAppMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<PopupMenuEntry<T>> Function(AppMenuMetrics metrics)
  itemsBuilder,
  PopupMenuPosition position = PopupMenuPosition.under,
  Offset offset = const Offset(0, 4),
  T? initialValue,
  double? minWidth,
}) async {
  final metrics =
      Theme.of(context).extension<AppMenuMetrics>() ??
      AppMenuMetrics.create(compactMenus: false);
  final items = itemsBuilder(metrics);
  if (items.isEmpty) return null;

  final renderBox = anchorContext.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final targetRect = MatrixUtils.transformRect(
    renderBox.getTransformTo(overlay),
    Offset.zero & renderBox.size,
  );

  final menuHeight =
      items.fold<double>(
        metrics.menuPadding.vertical,
        (sum, item) => sum + item.height,
      ) +
      8;
  final spaceAbove = targetRect.top;
  final spaceBelow = overlay.size.height - targetRect.bottom;
  final preferBelow = position == PopupMenuPosition.under;
  final shouldOpenBelow = preferBelow
      ? (spaceBelow >= menuHeight || spaceBelow >= spaceAbove)
      : !(spaceAbove >= menuHeight || spaceAbove >= spaceBelow);

  final anchorTop = shouldOpenBelow
      ? targetRect.bottom + offset.dy
      : (targetRect.top - menuHeight - offset.dy).clamp(
          0.0,
          overlay.size.height,
        );

  final anchorRect = RelativeRect.fromRect(
    Rect.fromLTWH(targetRect.left, anchorTop, targetRect.width, 0),
    Offset.zero & overlay.size,
  );

  return showMenu<T>(
    context: context,
    position: anchorRect,
    items: items,
    initialValue: initialValue,
    // רוחב מינימלי: רוחב הטריגר, או רוחב התוכן הרצוי (calculateAppMenuPreferredWidth) — הגדול מביניהם.
    // התוכן בפועל עדיין קובע את הרוחב הסופי (IntrinsicWidth בתוך _PopupMenu).
    constraints: BoxConstraints(
      minWidth: max(targetRect.width, minWidth ?? 0.0),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// showAnchoredAppSearchMenu — תפריט עם שדה חיפוש מוצמד בראש
//
// שדה החיפוש לא נגלל יחד עם הרשימה — תמיד גלוי בראש התפריט.
// כתיבה בו מסננת את הפריטים בזמן אמת.
// ═══════════════════════════════════════════════════════════════════════════

Future<T?> showAnchoredAppSearchMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<AppMenuEntry<T>> entries,
  T? initialValue,
  String searchHint = 'חיפוש',
  PopupMenuPosition position = PopupMenuPosition.under,
  Offset offset = const Offset(0, 4),
  List<String>? filterLabels,
  List<bool Function(AppMenuEntry<T>)?>? filterPredicates,
  int initialFilter = 0,
  double? menuMinWidth,
}) async {
  if (entries.isEmpty) return null;

  final metrics =
      Theme.of(context).extension<AppMenuMetrics>() ??
      AppMenuMetrics.create(compactMenus: false);

  final renderBox = anchorContext.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final targetRect = MatrixUtils.transformRect(
    renderBox.getTransformTo(overlay),
    Offset.zero & renderBox.size,
  );

  // גובה מקסימלי: שדה חיפוש + שורת סינון (אם יש) + עד 8 פריטים + ריפוד
  const double searchBarHeight = 56.0;
  const double filterRowHeight = 40.0;
  const int maxItemsVisible = 8;
  final hasFilters = filterLabels != null && filterLabels.isNotEmpty;
  final maxMenuHeight =
      searchBarHeight +
      (hasFilters ? filterRowHeight : 0.0) +
      (metrics.itemHeight * maxItemsVisible) +
      metrics.menuPadding.vertical +
      8;

  final spaceBelow = overlay.size.height - targetRect.bottom - offset.dy;
  final spaceAbove = targetRect.top - offset.dy;
  final preferBelow = position == PopupMenuPosition.under;
  final shouldOpenBelow = preferBelow
      ? (spaceBelow >= maxMenuHeight || spaceBelow >= spaceAbove)
      : !(spaceAbove >= maxMenuHeight || spaceAbove >= spaceBelow);

  final availableHeight = shouldOpenBelow ? spaceBelow : spaceAbove;
  // אל תחרוג ממה שזמין; קח את המינימום בין הזמין לבין הגובה המבוקש.
  // הרשימה הפנימית גלילה, אז גם תפריט נמוך נשאר שמיש.
  final menuHeight = min(availableHeight, maxMenuHeight);

  final menuTop = shouldOpenBelow
      ? targetRect.bottom + offset.dy
      : targetRect.top - menuHeight - offset.dy;

  // הרוחב הוא הגדול מבין: הרוחב שהמפעיל ביקש (menuMinWidth), הרוחב הדרוש
  // לפריט הארוך ביותר, רוחב שורת צ'יפי הסינון (כדי שכולם ייראו בלי גלילה),
  // ורוחב השדה המפעיל. מוגבל לרוחב ה-overlay כדי שה-clamp לא יקבל גבול שלילי.
  final preferredWidth = calculateAppMenuPreferredWidth(metrics, entries);
  final filterRowWidth = hasFilters
      ? _calculateFilterRowWidth(metrics, filterLabels)
      : 0.0;
  final effectiveWidth = [
    menuMinWidth ?? 0.0,
    preferredWidth,
    filterRowWidth,
    targetRect.width,
  ].reduce(max).clamp(0.0, overlay.size.width);
  // ברירת מחדל (RTL): הקצה הימני של התפריט מיושר לקצה הימני של הכפתור,
  // והתפריט מתרחב שמאלה. אם ההתרחבות שמאלה חורגת מקצה החלון — מיישרים לקצה
  // השמאלי של הכפתור ומתרחבים ימינה (פנימה), כדי שהתפריט לא יבלוט מהחלון.
  final rawMenuLeft = targetRect.right - effectiveWidth;
  final maxLeft = max(0.0, overlay.size.width - effectiveWidth);
  final menuLeft = (rawMenuLeft >= 0 ? rawMenuLeft : targetRect.left).clamp(
    0.0,
    maxLeft,
  );

  return Navigator.of(context).push<T>(
    _AnchoredSearchMenuRoute<T>(
      anchorRect: Rect.fromLTWH(
        menuLeft,
        menuTop,
        effectiveWidth,
        menuHeight,
      ),
      entries: entries,
      initialValue: initialValue,
      searchHint: searchHint,
      metrics: metrics,
      filterLabels: filterLabels,
      filterPredicates: filterPredicates,
      initialFilter: initialFilter,
    ),
  );
}

class _AnchoredSearchMenuRoute<T> extends PopupRoute<T> {
  final Rect anchorRect;
  final List<AppMenuEntry<T>> entries;
  final T? initialValue;
  final String searchHint;
  final AppMenuMetrics metrics;
  final List<String>? filterLabels;
  final List<bool Function(AppMenuEntry<T>)?>? filterPredicates;
  final int initialFilter;

  _AnchoredSearchMenuRoute({
    required this.anchorRect,
    required this.entries,
    required this.initialValue,
    required this.searchHint,
    required this.metrics,
    this.filterLabels,
    this.filterPredicates,
    this.initialFilter = 0,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _AnchoredSearchMenuContent<T>(
      anchorRect: anchorRect,
      entries: entries,
      initialValue: initialValue,
      searchHint: searchHint,
      metrics: metrics,
      animation: animation,
      filterLabels: filterLabels,
      filterPredicates: filterPredicates,
      initialFilter: initialFilter,
    );
  }
}

class _AnchoredSearchMenuContent<T> extends StatefulWidget {
  final Rect anchorRect;
  final List<AppMenuEntry<T>> entries;
  final T? initialValue;
  final String searchHint;
  final AppMenuMetrics metrics;
  final Animation<double> animation;
  final List<String>? filterLabels;
  final List<bool Function(AppMenuEntry<T>)?>? filterPredicates;
  final int initialFilter;

  const _AnchoredSearchMenuContent({
    required this.anchorRect,
    required this.entries,
    required this.initialValue,
    required this.searchHint,
    required this.metrics,
    required this.animation,
    this.filterLabels,
    this.filterPredicates,
    this.initialFilter = 0,
  });

  @override
  State<_AnchoredSearchMenuContent<T>> createState() =>
      _AnchoredSearchMenuContentState<T>();
}

class _AnchoredSearchMenuContentState<T>
    extends State<_AnchoredSearchMenuContent<T>> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;
  late final ScrollController _scrollController;
  String _query = '';
  late int _activeFilter;

  @override
  void initState() {
    super.initState();
    final filterCount = widget.filterLabels?.length ?? 0;
    _activeFilter = filterCount == 0
        ? 0
        : widget.initialFilter.clamp(0, filterCount - 1);
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
    _scrollController = ScrollController();
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      _scrollToInitialValue();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_query == _searchController.text) return;
    setState(() => _query = _searchController.text);
  }

  void _scrollToInitialValue() {
    if (widget.initialValue == null) return;
    if (!_scrollController.hasClients) return;

    final filtered = _filteredEntries;
    final idx = filtered.indexWhere((e) => e.value == widget.initialValue);
    if (idx < 0) return;

    final targetOffset =
        (idx * widget.metrics.itemHeight) - (widget.metrics.itemHeight * 2);
    final maxOffset = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(targetOffset.clamp(0.0, maxOffset));
  }

  List<AppMenuEntry<T>> get _filteredEntries {
    var entries = widget.entries;

    final predicates = widget.filterPredicates;
    if (predicates != null &&
        _activeFilter < predicates.length &&
        predicates[_activeFilter] != null) {
      final predicate = predicates[_activeFilter]!;
      entries = entries.where(predicate).toList();
    }

    if (_query.isEmpty) return entries;
    final lowerQuery = _query.toLowerCase();
    return entries
        .where((e) => e.label.toLowerCase().contains(lowerQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filteredEntries;
    final menuColor = Theme.of(context).popupMenuTheme.color ?? cs.surface;

    return Stack(
      children: [
        Positioned(
          left: widget.anchorRect.left,
          top: widget.anchorRect.top,
          width: widget.anchorRect.width,
          height: widget.anchorRect.height,
          child: FadeTransition(
            opacity: widget.animation,
            child: Material(
              elevation: 8,
              borderRadius: AppTokens.borderRadiusAll,
              color: menuColor,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // שדה חיפוש מוצמד בראש
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: RtlTextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      style: TextStyle(
                        fontSize: widget.metrics.fontSize,
                        color: cs.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.searchHint,
                        hintStyle: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: widget.metrics.fontSize,
                        ),
                        isDense: true,
                        prefixIcon: Icon(
                          FluentIcons.search_24_regular,
                          size: widget.metrics.iconSize,
                          color: cs.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: cs.onSurface.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: AppTokens.borderRadiusAll,
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  // שורת סינון (chip-ים) — מוצגת רק אם הועברו filterLabels
                  if (widget.filterLabels != null &&
                      widget.filterLabels!.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (
                              int i = 0;
                              i < widget.filterLabels!.length;
                              i++
                            ) ...[
                              if (i > 0) const SizedBox(width: 6),
                              FilterChip(
                                label: Text(
                                  widget.filterLabels![i],
                                  style: TextStyle(
                                    fontSize: widget.metrics.fontSize - 1,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                                selected: _activeFilter == i,
                                onSelected: (_) {
                                  setState(() => _activeFilter = i);
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted &&
                                        _scrollController.hasClients) {
                                      _scrollController.jumpTo(0);
                                    }
                                  });
                                },
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                showCheckmark: false,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  // רשימה נגללת
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'אין תוצאות',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: widget.metrics.fontSize,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: widget.metrics.menuPadding,
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final entry = filtered[i];
                              final isSelected =
                                  widget.initialValue != null &&
                                  entry.value == widget.initialValue;
                              return InkWell(
                                onTap: entry.enabled
                                    ? () =>
                                          Navigator.of(context).pop(entry.value)
                                    : null,
                                child: SizedBox(
                                  width: double.infinity,
                                  height: widget.metrics.itemHeight,
                                  child: LayoutBuilder(
                                    // constraints.maxWidth הוא הרוחב החיצוני (לפני
                                    // ריפוד ה-Container שבתוך buildAppMenuRowContent) —
                                    // בדיוק מה ש-calculateAppMenuLabelMaxWidth מצפה
                                    // לקבל, כי הוא כבר מחסיר את itemPadding בעצמו.
                                    builder: (ctx, constraints) =>
                                        buildAppMenuRowContent(
                                          context,
                                          widget.metrics,
                                          label: entry.label,
                                          labelWidget: entry.labelWidget,
                                          maxWidth: constraints.maxWidth,
                                          icon: entry.icon,
                                          trailing: entry.trailing,
                                          isSelected: isSelected,
                                          isDestructive: entry.isDestructive,
                                          enabled: entry.enabled,
                                          reserveTrailingGap:
                                              entry.reserveTrailingGap,
                                          trailingReservedWidth:
                                              entry.trailingReservedWidth,
                                        ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppMenuRowContent — בניית שורת תוכן בתפריט
//
// שינויים:
// • הרקע הנבחר ממלא שורה שלמה (ללא borderRadius, ללא גבול)
// • סימן ✓ תמיד מופיע לפריט נבחר
// ═══════════════════════════════════════════════════════════════════════════

/// המרחק בין סוף התוכן לסימן ה-✓ — משותף לרינדור בפועל
/// ([buildAppMenuRowContent]) ולחישוב הרוחב ([calculateAppMenuPreferredWidth])
/// כדי ששניהם יישארו מסונכרנים.
const double _kCheckmarkGap = 4;

/// משקל הגופן של פריט נבחר — משותף לרינדור בפועל ולחישוב הרוחב, כדי שהמדידה
/// תשקף את הרוחב הרחב יותר של הטקסט המודגש (אחרת הפריט הארוך ביותר עלול
/// לגלוש על סימן ה-✓ כשהוא נבחר, כי הגופן המודגש רחב יותר מהרגיל).
const FontWeight _kSelectedItemFontWeight = FontWeight.w600;

Widget buildAppMenuRowContent(
  BuildContext context,
  AppMenuMetrics metrics, {
  required String label,
  double? maxWidth,
  Widget? labelWidget,
  IconData? icon,
  Widget? trailing,
  bool isSelected = false,
  bool isDestructive = false,
  bool enabled = true,
  bool reserveTrailingGap = false,
  double trailingReservedWidth = 0,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final foregroundColor = !enabled
      ? colorScheme.onSurface.withValues(alpha: 0.38)
      : isDestructive
      ? colorScheme.error
      : isSelected
      ? colorScheme.primary
      : colorScheme.onSurface;

  final hasTrailingWidget = isSelected || trailing != null;
  // selected+trailing מציג גם trailing וגם checkmark → slot נוסף.
  // non-selected+trailing+reserve מציג trailing + SizedBox ריק → slot נוסף.
  final hasExtraSlot =
      (isSelected && trailing != null) ||
      (!isSelected && reserveTrailingGap && trailing != null);
  final labelMaxWidth = calculateAppMenuLabelMaxWidth(
    metrics,
    maxWidth: maxWidth,
    hasLeadingIcon: icon != null,
    hasTrailingWidget: hasTrailingWidget,
    trailingWidth: trailingReservedWidth,
    hasExtraSlot: hasExtraSlot,
  );
  final labelTextStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: metrics.fontSize,
    fontWeight: isSelected ? _kSelectedItemFontWeight : metrics.itemFontWeight,
    color: foregroundColor,
  );
  final labelChild =
      labelWidget ??
      Text(
        label,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );

  final row = Row(
    mainAxisSize: (isSelected || trailing != null)
        ? MainAxisSize.max
        : MainAxisSize.min,
    children: [
      if (icon != null) ...[
        RtlIcon(icon, size: metrics.iconSize, color: foregroundColor),
        const SizedBox(width: 8),
      ],
      DefaultTextStyle.merge(
        style: labelTextStyle,
        child: labelMaxWidth == null
            ? labelChild
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: labelMaxWidth),
                child: labelChild,
              ),
      ),
      if (isSelected && trailing != null) ...[
        const Spacer(),
        IconTheme.merge(
          data: IconThemeData(
            size: metrics.iconSize,
            color: foregroundColor,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foregroundColor),
            child: trailing,
          ),
        ),
        const SizedBox(width: _kCheckmarkGap),
        Icon(
          FluentIcons.checkmark_circle_24_filled,
          size: metrics.iconSize,
          color: foregroundColor,
        ),
      ] else if (isSelected) ...[
        const Spacer(),
        const SizedBox(width: _kCheckmarkGap),
        Icon(
          FluentIcons.checkmark_circle_24_filled,
          size: metrics.iconSize,
          color: foregroundColor,
        ),
      ] else if (trailing != null) ...[
        const Spacer(),
        IconTheme.merge(
          data: IconThemeData(
            size: metrics.iconSize,
            color: foregroundColor,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foregroundColor),
            child: trailing,
          ),
        ),
        if (reserveTrailingGap) SizedBox(width: metrics.iconSize + 8),
      ],
    ],
  );

  return Container(
    constraints: BoxConstraints(
      minWidth: metrics.menuMinWidth,
      minHeight: metrics.itemHeight,
    ),
    padding: metrics.itemPadding,
    alignment: AlignmentDirectional.centerStart,
    child: row,
  );
}

double? calculateAppMenuLabelMaxWidth(
  AppMenuMetrics metrics, {
  required double? maxWidth,
  required bool hasLeadingIcon,
  required bool hasTrailingWidget,
  double trailingWidth = 0,
  bool hasExtraSlot = false,
}) {
  if (maxWidth == null) return null;

  final trailingSlot = hasTrailingWidget
      ? (trailingWidth > 0 ? trailingWidth : metrics.iconSize + 8)
      : 0.0;
  final occupiedWidth =
      metrics.itemPadding.horizontal +
      (hasLeadingIcon ? metrics.iconSize + 8 : 0) +
      trailingSlot +
      (hasExtraSlot ? metrics.iconSize + 8 : 0);
  final availableWidth = maxWidth - occupiedWidth;
  if (availableWidth <= 0) return null;

  return availableWidth;
}

/// מחשב את הרוחב הדרוש להצגת הפריט הארוך ביותר ב-[entries] בלי קיצוץ —
/// משמש גם לקביעת רוחב התפריט וגם לרוחב הכפתור הפותח אותו (AppDropdownField).
double calculateAppMenuPreferredWidth<T>(
  AppMenuMetrics metrics,
  List<AppMenuEntry<T>> entries,
) {
  if (entries.isEmpty) return metrics.menuMinWidth;

  // נמדד במשקל של פריט נבחר (מודגש) — כל פריט עשוי להיות זה שנבחר,
  // והגופן המודגש רחב יותר מהרגיל.
  final textStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: metrics.fontSize,
    fontWeight: _kSelectedItemFontWeight,
  );

  var maxLabelWidth = 0.0;
  for (final entry in entries) {
    final painter = TextPainter(
      text: TextSpan(text: entry.label, style: textStyle),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout();
    if (painter.width > maxLabelWidth) maxLabelWidth = painter.width;
  }

  final hasIcon = entries.any((entry) => entry.icon != null);

  var maxTrailingWidth = 0.0;
  var hasExtraSlot = false;
  for (final entry in entries) {
    if (entry.trailing != null) {
      final tWidth = entry.trailingReservedWidth > 0
          ? entry.trailingReservedWidth
          : metrics.iconSize + 8;
      if (tWidth > maxTrailingWidth) maxTrailingWidth = tWidth;
      if (entry.reserveTrailingGap) hasExtraSlot = true;
    }
  }

  // תמיד משוריין מקום לסימן ה-✓ שמוצג ליד הפריט הנבחר, יהיה אשר יהיה.
  final occupiedWidth =
      metrics.itemPadding.horizontal +
      (hasIcon ? metrics.iconSize + 8 : 0) +
      metrics.iconSize +
      _kCheckmarkGap +
      maxTrailingWidth +
      (hasExtraSlot ? metrics.iconSize + 8 : 0);

  return max(metrics.menuMinWidth, maxLabelWidth + occupiedWidth);
}

/// מחשב את רוחב שורת צ'יפי הסינון (סכום כל הצ'יפים + רווחים + ריפוד השורה),
/// כדי שרוחב התפריט יבטיח שכל הצ'יפים ייראו בלי גלילה אופקית.
/// הקבועים תואמים את רינדור הצ'יפים ב-[_AnchoredSearchMenuContent].
double _calculateFilterRowWidth(AppMenuMetrics metrics, List<String> labels) {
  // ריפוד ה-Padding העוטף (EdgeInsets.fromLTRB(8, 0, 8, 4)) + רווח בין צ'יפים.
  const double rowHorizontalPadding = 16.0;
  const double chipGap = 6.0;
  // מסגרת הצ'יפ: labelPadding (8+8) + padding (2+2) בניכוי צמצום compact, עם מרווח ביטחון.
  const double chipChrome = 22.0;

  final chipTextStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: metrics.fontSize - 1,
  );

  var total = rowHorizontalPadding;
  for (var i = 0; i < labels.length; i++) {
    if (i > 0) total += chipGap;
    final painter = TextPainter(
      text: TextSpan(text: labels[i], style: chipTextStyle),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout();
    total += painter.width + chipChrome;
  }
  return total;
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppPopupMenuItem
// ═══════════════════════════════════════════════════════════════════════════

PopupMenuEntry<T> buildAppPopupMenuItem<T>(
  BuildContext context,
  AppMenuEntry<T> entry,
  AppMenuMetrics metrics,
  T? selectedValue, {
  Key? key,
}) {
  final isSelected = selectedValue != null && entry.value == selectedValue;

  return PopupMenuItem<T>(
    key: key,
    value: entry.value,
    enabled: entry.enabled,
    height: metrics.itemHeight,
    // padding: EdgeInsets.zero — הריפוד מנוהל ב-buildAppMenuRowContent
    // כדי שהצבע הנבחר יכסה שורה שלמה
    padding: EdgeInsets.zero,
    child: buildAppMenuRowContent(
      context,
      metrics,
      label: entry.label,
      labelWidget: entry.labelWidget,
      icon: entry.icon,
      trailing: entry.trailing,
      isSelected: isSelected,
      isDestructive: entry.isDestructive,
      enabled: entry.enabled,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppCustomPopupMenuItem
// ═══════════════════════════════════════════════════════════════════════════

PopupMenuEntry<T> buildAppCustomPopupMenuItem<T>({
  required BuildContext context,
  required AppMenuMetrics metrics,
  required Widget child,
  bool enabled = false,
  double? height,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return PopupMenuItem<T>(
    enabled: enabled,
    height: height ?? metrics.itemHeight,
    padding: padding,
    child: child,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppSubmenuItemStyle
// ═══════════════════════════════════════════════════════════════════════════

ButtonStyle buildAppSubmenuItemStyle(
  BuildContext context,
  AppMenuMetrics metrics,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return ButtonStyle(
    padding: WidgetStatePropertyAll(metrics.itemPadding),
    minimumSize: WidgetStatePropertyAll(
      Size(metrics.menuMinWidth, metrics.itemHeight),
    ),
    visualDensity: metrics.visualDensity,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusAll,
      ),
    ),
    alignment: Alignment.centerRight,
    textStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: 'Roboto',
        fontSize: metrics.fontSize,
        fontWeight: metrics.itemFontWeight,
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.38);
      }
      return colorScheme.onSurface;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.38);
      }
      return colorScheme.onSurface;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return colorScheme.onSurface.withValues(alpha: 0.08);
      }
      if (states.contains(WidgetState.pressed)) {
        return colorScheme.onSurface.withValues(alpha: 0.12);
      }
      return null;
    }),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// buildAppSubmenuPopupMenuItem
// ═══════════════════════════════════════════════════════════════════════════

PopupMenuEntry<T> buildAppSubmenuPopupMenuItem<T>({
  required BuildContext context,
  required AppMenuMetrics metrics,
  required String label,
  IconData? icon,
  required List<PopupMenuEntry<T>> menuChildren,
  ValueChanged<T>? onSelected,
}) {
  return buildAppCustomPopupMenuItem<T>(
    context: context,
    metrics: metrics,
    enabled: onSelected != null,
    child: _SubmenuItemWidget<T>(
      metrics: metrics,
      label: label,
      icon: icon,
      menuChildren: menuChildren,
      onSelected: onSelected,
    ),
  );
}

/// ווידג'ט פנימי לפריט תת-תפריט שתומך בפתיחה גם בלחיצה וגם ב-hover.
class _SubmenuItemWidget<T> extends StatefulWidget {
  final AppMenuMetrics metrics;
  final String label;
  final IconData? icon;
  final List<PopupMenuEntry<T>> menuChildren;
  final ValueChanged<T>? onSelected;

  const _SubmenuItemWidget({
    required this.metrics,
    required this.label,
    this.icon,
    required this.menuChildren,
    this.onSelected,
  });

  @override
  State<_SubmenuItemWidget<T>> createState() => _SubmenuItemWidgetState<T>();
}

class _SubmenuItemWidgetState<T> extends State<_SubmenuItemWidget<T>> {
  bool _submenuOpen = false;
  Timer? _hoverTimer;
  Timer? _closeTimer;
  OverlayEntry? _overlayEntry;
  Completer<T?>? _completer;

  void _scheduleSubmenuOnHover(BuildContext innerContext) {
    // חילוץ כל המידע מה-context לפני ה-async gap
    final renderBox = innerContext.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(innerContext);
    if (renderBox == null || overlayState == null) return;
    final overlay = overlayState.context.findRenderObject() as RenderBox;

    _closeTimer?.cancel();
    _closeTimer = null;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _openSubmenuFromData(renderBox, overlay);
      }
    });
  }

  void _cancelHoverDelay() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    // סגירת הסאבמנו כשיוצאים מהפריט (אם לא נכנסים לסאבמנו עצמו)
    // נשתמש בעיכוב ארוך יותר כדי לאפשר כניסה לסאבמנו
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _submenuOpen) {
        _closeSubmenu();
      }
    });
  }

  void _closeSubmenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _completer?.complete(null);
    _completer = null;
    _submenuOpen = false;
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _closeTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    // שחרור מי שממתין ל-future של הסאבמנו (_openSubmenuFromData) — בלי זה
    // ה-await נשאר תלוי לנצח כשה-widget נזרק בזמן שהסאבמנו פתוח.
    if (!(_completer?.isCompleted ?? true)) {
      _completer!.complete(null);
    }
    _completer = null;
    super.dispose();
  }

  Future<void> _openSubmenuFromData(
    RenderBox renderBox,
    RenderBox overlay,
  ) async {
    if (_submenuOpen) return;
    final overlaySize = overlay.size;
    if (!renderBox.attached) return;
    final itemRect = MatrixUtils.transformRect(
      renderBox.getTransformTo(overlay),
      Offset.zero & renderBox.size,
    );

    // showMenu תמיד פותח למטה/מעלה — לא הצידה.
    // כדי לפתוח הצידה, נשתמש ב-OverlayEntry ישירות.
    const double estimatedSubmenuWidth = 250.0;
    final spaceToRight = overlaySize.width - itemRect.right;
    final spaceToLeft = itemRect.left;
    final openToRight =
        spaceToRight >= estimatedSubmenuWidth || spaceToRight >= spaceToLeft;

    // צבע רקע מה-theme (כמו showMenu)
    final menuColor =
        Theme.of(context).popupMenuTheme.color ??
        Theme.of(context).colorScheme.surface;
    final menuBorderRadius = AppTokens.borderRadiusAll;
    final menuPadding = widget.metrics.menuPadding;

    _submenuOpen = true;
    _completer = Completer<T?>();

    // הצמדת התת-תפריט לפריט האב: בפתיחה ימינה הקצה השמאלי צמוד לימין הפריט;
    // בפתיחה שמאלה הקצה הימני צמוד לשמאל הפריט (עיגון לפי הקצה, לא לפי רוחב
    // משוער, כדי שלא ייווצר מרווח כשהתת-תפריט צר מ-estimatedSubmenuWidth).
    final menuTop = itemRect.top.clamp(0.0, overlaySize.height - 10.0);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        // לא משתמשים ב-Positioned.fill עם GestureDetector כשכבת סגירה: היא
        // הייתה גוזלת את הקליק הראשון מכל פריט בתפריט-האב, ויוצרת חוויית
        // "קליק אחד לסגירה, קליק שני לבחירה". בלעדיה, קליק על פריט אב יעבור
        // ישירות לתפריט האב, שיסגור בעצמו את עצמו (וב-dispose ינוקה גם
        // ה-overlay הזה). סגירה ביציאה מהעכבר עדיין מתבצעת ע"י _closeTimer.
        return Stack(
          children: [
            Positioned(
              left: openToRight ? itemRect.right : null,
              right: openToRight ? null : (overlaySize.width - itemRect.left),
              top: menuTop,
              child: MouseRegion(
                // כניסה לסאבמנו מבטלת את סגירת ה-hover
                onEnter: (_) {
                  _hoverTimer?.cancel();
                  _hoverTimer = null;
                  _closeTimer?.cancel();
                  _closeTimer = null;
                },
                onExit: (_) {
                  // יציאה מהסאבמנו — סגור אחרי עיכוב קצר
                  _closeTimer?.cancel();
                  _closeTimer = Timer(const Duration(milliseconds: 400), () {
                    if (mounted && _submenuOpen) {
                      _closeSubmenu();
                    }
                  });
                },
                child: Material(
                  elevation: 8,
                  borderRadius: menuBorderRadius,
                  color: menuColor,
                  child: Padding(
                    padding: menuPadding,
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.menuChildren.map((menuEntry) {
                          if (menuEntry is PopupMenuItem<T>) {
                            return InkWell(
                              borderRadius: AppTokens.borderRadiusAll,
                              onTap: menuEntry.enabled
                                  ? () {
                                      final value = menuEntry.value;
                                      _closeSubmenu();
                                      if (value != null) {
                                        if (mounted) {
                                          Navigator.of(context).pop();
                                        }
                                        widget.onSelected?.call(value);
                                      }
                                    }
                                  : null,
                              child: menuEntry.child ?? const SizedBox.shrink(),
                            );
                          }
                          return const SizedBox.shrink();
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    await _completer!.future;
    _submenuOpen = false;
  }

  Future<void> _openSubmenu(BuildContext innerContext) async {
    if (_submenuOpen) return;
    final renderBox = innerContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final overlayState = Overlay.maybeOf(innerContext);
    if (overlayState == null) return;
    final overlay = overlayState.context.findRenderObject() as RenderBox;
    await _openSubmenuFromData(renderBox, overlay);
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (innerContext) => MouseRegion(
        onEnter: (_) => _scheduleSubmenuOnHover(innerContext),
        onExit: (_) => _cancelHoverDelay(),
        child: InkWell(
          onTap: () => _openSubmenu(innerContext),
          borderRadius: AppTokens.borderRadiusAll,
          child: buildAppMenuRowContent(
            context,
            widget.metrics,
            label: widget.label,
            icon: widget.icon,
            trailing: Icon(
              // החץ מצביע לכיוון פתיחת התת-תפריט (ימינה)
              FluentIcons.chevron_right_24_regular,
              size: widget.metrics.iconSize * 0.75,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// showAppMenu — הצגת תפריט במיקום מוחלט
// ═══════════════════════════════════════════════════════════════════════════

Future<T?> showAppMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<AppMenuEntry<T>> entries,
}) {
  final metrics =
      Theme.of(context).extension<AppMenuMetrics>() ??
      AppMenuMetrics.create(compactMenus: false);
  return showMenu<T>(
    context: context,
    position: position,
    items: entries
        .map<PopupMenuEntry<T>>(
          (entry) => buildAppPopupMenuItem<T>(context, entry, metrics, null),
        )
        .toList(),
  );
}
