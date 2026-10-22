import 'dart:async';
import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart' as menu;
import 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show AppMenuEntry;
import 'package:otzaria/widgets/misc/app_menu_presentation.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/settings/settings_exports.dart';

export 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show
        AppMenuEntry,
        AppContextMenuEntry,
        AppContextMenuIconAction,
        AppContextMenuColorAction,
        AppContextMenuSubAction,
        hasEnabledAppContextMenuEntries,
        calculateAppMenuLabelMaxWidth,
        calculateAppMenuPreferredWidth;

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

  /// נקרא גם בבחירה וגם בביטול, ומאפשר למארח להחזיר את הפוקוס לרכיב הפותח.
  final VoidCallback? onMenuClosed;

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
    this.onMenuClosed,
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
    widget.onMenuClosed?.call();

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
    } else if (widget.iconData != null) {
      // מצב Toolbar: BarButton.icon עם אייקון מסוגנן. חייב לגבור על מצב מגע —
      // כפתור טקסט רחב מפוצץ את תקציב הרוחב של הסרגל וגורם overflow (#891).
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
  // ה-route של התפריט נבנה תחת ה-Navigator ולא יורש את ה-Directionality של
  // הפותח (למשל הגדרות באנגלית) — לוכדים ועוטפים כל פריט.
  final textDirection = Directionality.of(context);
  final items = itemsBuilder(metrics)
      .map<PopupMenuEntry<T>>(
        (item) => _DirectionalMenuEntry<T>(
          textDirection: textDirection,
          inner: item,
        ),
      )
      .toList();
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

class _DirectionalMenuEntry<T> extends PopupMenuEntry<T> {
  final PopupMenuEntry<T> inner;
  final TextDirection textDirection;

  const _DirectionalMenuEntry({
    required this.inner,
    required this.textDirection,
  });

  @override
  double get height => inner.height;

  @override
  bool represents(T? value) => inner.represents(value);

  @override
  State<_DirectionalMenuEntry<T>> createState() =>
      _DirectionalMenuEntryState<T>();
}

class _DirectionalMenuEntryState<T> extends State<_DirectionalMenuEntry<T>> {
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.textDirection,
    child: widget.inner,
  );
}

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

  // רוחב התוכן והטריגר מוגבל ל-overlay כדי שלא יגלוש מעבר לחלון.
  final preferredWidth = menu.calculateAppMenuPreferredWidth(metrics, entries);
  final filterRowWidth = hasFilters
      ? _calculateFilterRowWidth(metrics, filterLabels)
      : 0.0;
  final effectiveWidth = [
    menuMinWidth ?? 0.0,
    preferredWidth,
    filterRowWidth,
    targetRect.width,
  ].reduce(max).clamp(0.0, overlay.size.width);
  // קצה ההתחלה של התפריט מיושר לקצה ההתחלה של הכפתור (לפי כיוון הפותח),
  // והתפריט מתרחב לכיוון הקריאה. בחריגה מהחלון — מיישרים לקצה הנגדי.
  final textDirection = Directionality.of(context);
  final isRtl = textDirection == TextDirection.rtl;
  final alignedLeft = isRtl
      ? targetRect.right - effectiveWidth
      : targetRect.left;
  final overflows = isRtl
      ? alignedLeft < 0
      : alignedLeft + effectiveWidth > overlay.size.width;
  final fallbackLeft = isRtl
      ? targetRect.left
      : targetRect.right - effectiveWidth;
  final maxLeft = max(0.0, overlay.size.width - effectiveWidth);
  final menuLeft = (overflows ? fallbackLeft : alignedLeft).clamp(0.0, maxLeft);

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
      textDirection: textDirection,
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
  final TextDirection textDirection;
  final List<String>? filterLabels;
  final List<bool Function(AppMenuEntry<T>)?>? filterPredicates;
  final int initialFilter;

  _AnchoredSearchMenuRoute({
    required this.anchorRect,
    required this.entries,
    required this.initialValue,
    required this.searchHint,
    required this.metrics,
    required this.textDirection,
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
    // ה-route לא יורש את ה-Directionality של הפותח — משחזרים אותו כאן.
    return Directionality(
      textDirection: textDirection,
      child: _AnchoredSearchMenuContent<T>(
        anchorRect: anchorRect,
        entries: entries,
        initialValue: initialValue,
        searchHint: searchHint,
        metrics: metrics,
        animation: animation,
        filterLabels: filterLabels,
        filterPredicates: filterPredicates,
        initialFilter: initialFilter,
      ),
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
                          OtzariaIcons.search_24_regular,
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
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              context.settingsText('אין תוצאות'),
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
                                    // חישוב רוחב התווית כבר מחסיר את ריפוד השורה.
                                    builder: (ctx, constraints) =>
                                        buildAppMenuRowContent(
                                          context,
                                          widget.metrics,
                                          label: entry.label,
                                          labelWidget: entry.labelWidget,
                                          maxWidth: constraints.maxWidth,
                                          icon: entry.icon,
                                          iconColor: entry.iconColor,
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

Widget buildAppMenuRowContent(
  BuildContext context,
  AppMenuMetrics metrics, {
  required String label,
  double? maxWidth,
  Widget? labelWidget,
  IconData? icon,
  Color? iconColor,
  Widget? trailing,
  bool isSelected = false,
  bool isDestructive = false,
  bool enabled = true,
  bool reserveTrailingGap = false,
  double trailingReservedWidth = 0,
}) => menu.buildAppMenuRowContent(
  context,
  metrics,
  presentation: createAppMenuPresentation(context, metrics: metrics),
  label: label,
  maxWidth: maxWidth,
  labelWidget: labelWidget,
  icon: icon,
  iconColor: iconColor,
  trailing: trailing,
  isSelected: isSelected,
  isDestructive: isDestructive,
  enabled: enabled,
  reserveTrailingGap: reserveTrailingGap,
  trailingReservedWidth: trailingReservedWidth,
);

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
      iconColor: entry.iconColor,
      trailing: entry.trailing,
      isSelected: isSelected,
      isDestructive: entry.isDestructive,
      enabled: entry.enabled,
    ),
  );
}

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

class AppMenuRowEntry<T> extends PopupMenuEntry<T> {
  final Widget child;

  @override
  final double height;

  const AppMenuRowEntry({
    super.key,
    required this.child,
    required this.height,
  });

  @override
  bool represents(T? value) => false;

  @override
  State<AppMenuRowEntry<T>> createState() => _AppMenuRowEntryState<T>();
}

class _AppMenuRowEntryState<T> extends State<AppMenuRowEntry<T>> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: SizedBox(height: widget.height, child: widget.child),
    );
  }
}

ButtonStyle buildAppSubmenuItemStyle(
  BuildContext context,
  AppMenuMetrics metrics,
) => menu.buildAppSubmenuItemStyle(
  context,
  metrics,
  presentation: createAppMenuPresentation(context, metrics: metrics),
);

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
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final presentation = createAppMenuPresentation(
      context,
      metrics: widget.metrics,
    );
    final itemStyle = buildAppSubmenuItemStyle(context, widget.metrics)
        .copyWith(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    return menu.AppSubmenuButton(
      controller: _controller,
      presentation: presentation,
      preserveFocus: false,
      maxWidth: min(320, MediaQuery.sizeOf(context).width - 16),
      menuStyle: Theme.of(context).menuTheme.style,
      style: itemStyle,
      menuChildren: [
        for (final entry in widget.menuChildren)
          if (entry is PopupMenuItem<T>)
            MenuItemButton(
              style: itemStyle,
              onPressed: !entry.enabled
                  ? null
                  : () {
                      _controller.close();
                      Navigator.of(context).pop();
                      entry.onTap?.call();
                      final value = entry.value;
                      if (value != null) widget.onSelected?.call(value);
                    },
              child: entry.child ?? const SizedBox.shrink(),
            )
          else
            entry,
      ],
      childBuilder: (context, openToRight) => buildAppMenuRowContent(
        context,
        widget.metrics,
        label: widget.label,
        icon: widget.icon,
        trailing: presentation.submenuArrowBuilder(
          context,
          openToRight,
          widget.metrics.iconSize,
          null,
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
