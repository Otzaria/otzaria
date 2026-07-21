import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/misc/overlay_scroll_anchor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AppContextMenuRegion — תפריט הקשר (right-click) בסגנון האפליקציה
//
// שימוש:
//   AppContextMenuRegion(
//     menuBuilder: (context) => [
//       AppContextMenuEntry(label: 'העתק', icon: FluentIcons.copy_24_regular, onTap: ...),
//       const AppContextMenuEntry.divider(),
//       AppContextMenuEntry(
//         label: 'מפרשים',
//         icon: FluentIcons.book_24_regular,
//         children: [...],
//       ),
//     ],
//     child: myWidget,
//   )
// ═══════════════════════════════════════════════════════════════════════════

class AppContextMenuRegion extends StatefulWidget {
  final Widget child;
  final List<AppContextMenuEntry> Function(BuildContext, Offset) menuBuilder;
  final Map<String, GlobalKey>? menuItemKeysByLabel;

  /// נקרא בלחיצה ימנית (לפני פתיחת התפריט), דרך [Listener] שאינו תלוי בזירת
  /// ה-gestures — ולכן נורה גם כאשר הבחירה נשמרת ו-[SelectableRegion] נחסם.
  /// משמש לשמירת ההקשר (למשל אינדקס השורה) עבור פעולות התפריט.
  final GestureTapDownCallback? onSecondaryTapDown;

  /// מקבל את מיקום הלחיצה הגלובלי ומחזיר `true` כאשר יש לשמר את הבחירה הקיימת
  /// (הלחיצה נופלת על הטקסט המסומן). במצב זה לחיצה ימנית זוכה באופן מיידי (eager)
  /// בכפתור הימני, וכך מונעת מ-[SelectableRegion] של Flutter לאסוף/לשחרר את
  /// הבחירה (התנהגות ברירת המחדל ב-Windows). כשהלחיצה מחוץ לטקסט המסומן — מחזיר
  /// `false`, וה-recognizer אינו מתערב כך שההתנהגות הרגילה (ביטול) נשמרת.
  final bool Function(Offset globalPosition)?
  shouldPreserveSelectionOnSecondaryTap;

  const AppContextMenuRegion({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.menuItemKeysByLabel,
    this.onSecondaryTapDown,
    this.shouldPreserveSelectionOnSecondaryTap,
  });

  @override
  State<AppContextMenuRegion> createState() => AppContextMenuRegionState();
}

class AppContextMenuRegionState extends State<AppContextMenuRegion> {
  static const double _contextMenuScreenPadding = 8;
  static const double _contextMenuMaxWidth = 320;

  bool _isMenuOpen = false;
  bool _isMenuVisible = false;
  OverlayEntry? _menuOverlayEntry;
  final GlobalKey _menuPanelKey = GlobalKey();
  Offset? _currentMenuOffset;
  double? _menuAnchorX;

  /// עוגן-גלילה שנלכד בנקודת פתיחת התפריט (לפני שה-overlay כיסה אותה) —
  /// חלונית תצוגה מקדימה שקובעה תזוז איתו בזמן גלילת הדף.
  OverlayScrollAnchor? _menuOpenScrollAnchor;

  @override
  void dispose() {
    _removeContextMenuOverlay();
    super.dispose();
  }

  void _removeContextMenuOverlay() {
    _menuOverlayEntry?.remove();
    _menuOverlayEntry = null;
    _currentMenuOffset = null;
    _menuAnchorX = null;
    _isMenuVisible = false;
  }

  void _closeContextMenu() {
    _removeContextMenuOverlay();
    if (_isMenuOpen && mounted) {
      setState(() => _isMenuOpen = false);
    }
  }

  void closeMenu() {
    _closeContextMenu();
  }

  Future<void> showMenu() async {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    await _openContextMenu(
      renderObject.localToGlobal(
        renderObject.size.center(
          Offset.zero,
        ),
      ),
    );
  }

  Future<void> openMenuAt(Offset globalPosition) =>
      _openContextMenu(globalPosition);

  double _resolveContextMenuMaxWidth(
    double overlayWidth,
    AppMenuMetrics metrics,
  ) {
    final availableWidth = overlayWidth - (_contextMenuScreenPadding * 2);
    return availableWidth
        .clamp(metrics.menuMinWidth, _contextMenuMaxWidth)
        .toDouble();
  }

  bool _isPointerInsideMenu(Offset globalPosition) {
    final renderObject = _menuPanelKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    final menuRect = MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      Offset.zero & renderObject.size,
    );
    return menuRect.contains(globalPosition);
  }

  (Offset, bool) _calculateMenuOffset(
    RenderBox overlayRenderBox,
    Offset overlayPosition,
    List<AppContextMenuEntry> entries,
    AppMenuMetrics metrics,
  ) {
    final estimatedHeight =
        entries.fold<double>(
          metrics.menuPadding.vertical,
          (sum, entry) =>
              sum +
              (entry.isDivider
                  ? metrics.dividerHeight
                  // שורת אייקונים גבוהה מפריט רגיל (אייקון + כיתוב + ריפודים).
                  : entry.iconRowActions != null
                  ? metrics.iconSize + 28
                  : metrics.itemHeight),
        ) +
        8;
    final spaceAbove = overlayPosition.dy;
    final spaceBelow = overlayRenderBox.size.height - overlayPosition.dy;
    final shouldOpenAbove =
        spaceBelow < estimatedHeight && spaceAbove > spaceBelow;
    final dx = overlayPosition.dx
        .clamp(
          _contextMenuScreenPadding,
          overlayRenderBox.size.width - _contextMenuScreenPadding,
        )
        .toDouble();
    final rawDy = shouldOpenAbove
        ? overlayPosition.dy - estimatedHeight
        : overlayPosition.dy;
    final maxDy =
        (overlayRenderBox.size.height -
                metrics.itemHeight -
                _contextMenuScreenPadding)
            .clamp(_contextMenuScreenPadding, double.infinity)
            .toDouble();
    final dy = rawDy.clamp(_contextMenuScreenPadding, maxDy).toDouble();

    return (Offset(dx, dy), shouldOpenAbove);
  }

  /// כשהתפריט נפתח כלפי מעלה, שורת האייקונים (שמטבעה בראש) מתרחקת מהעכבר.
  /// מעבירים אותה לתחתית כדי שתישאר צמודה לעכבר — כמו ב-Windows 11.
  List<AppContextMenuEntry> _iconRowAtBottom(
    List<AppContextMenuEntry> entries,
  ) {
    final index = entries.indexWhere((e) => e.iconRowActions != null);
    if (index < 0) return entries;
    final iconRow = entries[index];
    final rest = [
      for (var i = 0; i < entries.length; i++)
        if (i != index && !(i == index + 1 && entries[i].isDivider)) entries[i],
    ];
    final normalized = _normalizeEntries(rest);
    if (normalized.isEmpty) return [iconRow];
    return [...normalized, const AppContextMenuEntry.divider(), iconRow];
  }

  void _repositionContextMenuWithinOverlay(Size overlaySize) {
    final renderObject = _menuPanelKey.currentContext?.findRenderObject();
    final currentOffset = _currentMenuOffset;
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        currentOffset == null ||
        _menuOverlayEntry == null) {
      return;
    }

    final panelSize = renderObject.size;
    final maxDx =
        (overlaySize.width - panelSize.width - _contextMenuScreenPadding)
            .clamp(_contextMenuScreenPadding, double.infinity)
            .toDouble();
    final maxDy =
        (overlaySize.height - panelSize.height - _contextMenuScreenPadding)
            .clamp(_contextMenuScreenPadding, double.infinity)
            .toDouble();

    // RTL: right-align menu with anchor X; fall back to left-align if no space
    final anchorX = _menuAnchorX ?? currentOffset.dx;
    final rtlDx = anchorX - panelSize.width;
    final targetDx = rtlDx >= _contextMenuScreenPadding ? rtlDx : anchorX;

    final adjustedOffset = Offset(
      targetDx.clamp(_contextMenuScreenPadding, maxDx).toDouble(),
      currentOffset.dy.clamp(_contextMenuScreenPadding, maxDy).toDouble(),
    );

    _currentMenuOffset = adjustedOffset;
    _isMenuVisible = true;
    _menuOverlayEntry?.markNeedsBuild();
  }

  Future<void> _openContextMenu(Offset globalPosition) async {
    final entries = _normalizeEntries(
      widget.menuBuilder(context, globalPosition),
    );
    if (entries.isEmpty) return;

    _menuOpenScrollAnchor = OverlayScrollAnchor.capture(
      context,
      globalPosition,
    );

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayRenderObject = overlay.context.findRenderObject();
    if (overlayRenderObject is! RenderBox || !overlayRenderObject.hasSize) {
      return;
    }

    final overlayPosition = overlayRenderObject.globalToLocal(globalPosition);
    if (!overlayPosition.dx.isFinite || !overlayPosition.dy.isFinite) return;
    _menuAnchorX = overlayPosition.dx;
    final metrics =
        Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    final (menuOffset, openAbove) = _calculateMenuOffset(
      overlayRenderObject,
      overlayPosition,
      entries,
      metrics,
    );
    final orderedEntries = openAbove ? _iconRowAtBottom(entries) : entries;
    final menuStyle = _menuStyle(context, metrics);
    final maxMenuWidth = _resolveContextMenuMaxWidth(
      overlayRenderObject.size.width,
      metrics,
    );
    // גובה זמין מלא בחלון (לא רק המרחב שמתחת ללחיצה) — כך הפאנל נמדד לפי גובהו
    // הטבעי, ו-_repositionContextMenuWithinOverlay מושך אותו מעלה כדי שייכנס.
    final maxMenuHeight =
        (overlayRenderObject.size.height - _contextMenuScreenPadding * 2)
            .clamp(metrics.itemHeight, double.infinity)
            .toDouble();

    // Create controllers once per menu open — stable across overlay rebuilds
    final submenuControllers = <AppContextMenuEntry, MenuController>{
      for (final entry in orderedEntries)
        if (((entry.children != null && entry.children!.isNotEmpty) ||
                entry.childrenBuilder != null) &&
            entry.enabled)
          entry: MenuController(),
    };

    _removeContextMenuOverlay();
    _currentMenuOffset = menuOffset;

    _menuOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final currentMenuOffset = _currentMenuOffset ?? menuOffset;
        return Positioned.fill(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeContextMenu,
                child: const SizedBox.expand(),
              ),
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  if (_isPointerInsideMenu(event.position)) {
                    return;
                  }
                  _closeContextMenu();
                },
                child: const SizedBox.expand(),
              ),
              Positioned(
                left: currentMenuOffset.dx,
                top: currentMenuOffset.dy,
                child: Visibility(
                  visible: _isMenuVisible,
                  maintainSize: false,
                  maintainAnimation: false,
                  maintainState: true,
                  child: _AppContextMenuPanel(
                    key: _menuPanelKey,
                    entries: orderedEntries,
                    metrics: metrics,
                    menuStyle: menuStyle,
                    maxWidth: maxMenuWidth,
                    maxHeight: maxMenuHeight,
                    buildChildren: (panelContext, panelEntries) =>
                        _buildMenuPanelChildren(
                          panelContext,
                          panelEntries,
                          metrics,
                          maxMenuWidth,
                          submenuControllers,
                        ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    setState(() => _isMenuOpen = true);
    overlay.insert(_menuOverlayEntry!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isMenuOpen) return;
      _repositionContextMenuWithinOverlay(overlayRenderObject.size);
    });
  }

  MenuStyle _menuStyle(BuildContext context, AppMenuMetrics metrics) {
    final themeStyle = Theme.of(context).menuTheme.style;
    // alignment: Alignment.topLeft — מציב את הפינה השמאלית-עליונה של תת-התפריט
    // בנקודת הכפתור (קצה ימין של הכפתור), כך שהתפריט נפתח ימינה.
    // Flutter יהפוך אוטומטית שמאלה אם אין מקום בצד ימין.
    return (themeStyle ?? const MenuStyle()).copyWith(
      alignment: Alignment.topLeft,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      // לחיצה ארוכה פותחת תפריט הקשר רק במגע/עט; בעכבר/trackpad משתמשים בלחיצה
      // ימנית (מטופלת ב-Listener למטה), אחרת החזקת הלחיצה הייתה פותחת תפריט.
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
      onLongPressStart: (details) => _openContextMenu(details.globalPosition),
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          // recognizer שזוכה באופן מיידי בכפתור הימני כשיש בחירה פעילה, כדי
          // למנוע מ-SelectableRegion לשחרר את הבחירה (ראו תיעוד השדה).
          _PreserveSelectionSecondaryTapRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _PreserveSelectionSecondaryTapRecognizer
              >(
                () => _PreserveSelectionSecondaryTapRecognizer(
                  shouldPreserve: (globalPosition) =>
                      widget.shouldPreserveSelectionOnSecondaryTap?.call(
                        globalPosition,
                      ) ??
                      false,
                ),
                (instance) {},
              ),
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (event.buttons == kSecondaryButton) {
              widget.onSecondaryTapDown?.call(
                TapDownDetails(
                  globalPosition: event.position,
                  localPosition: event.localPosition,
                ),
              );
              _openContextMenu(event.position);
            }
          },
          child: widget.child,
        ),
      ),
    );
  }

  List<Widget> _buildMenuPanelChildren(
    BuildContext context,
    List<AppContextMenuEntry> entries,
    AppMenuMetrics metrics,
    double maxWidth,
    Map<AppContextMenuEntry, MenuController> submenuControllers,
  ) {
    // ה-MenuItemButton מוסיף itemPadding משלו (buildAppSubmenuItemStyle) על גבי
    // ה-padding של buildAppMenuRowContent — מחסירים אותו מרוחב התוכן כדי ש-cap
    // התווית לא יגלוש (כמו submenuContentMaxWidth בתת-התפריט).
    final contentMaxWidth = maxWidth - metrics.itemPadding.horizontal;
    return entries.map<Widget>((entry) {
      if (entry.colorRowActions != null) {
        return _AppContextMenuColorRow(
          actions: entry.colorRowActions!,
          metrics: metrics,
          maxWidth: maxWidth,
          closeMenu: _closeContextMenu,
        );
      }
      if (entry.iconRowActions != null) {
        return _AppContextMenuIconRow(
          actions: entry.iconRowActions!,
          metrics: metrics,
          menuStyle: _menuStyle(context, metrics),
          closeMenu: _closeContextMenu,
        );
      }

      if (entry.isDivider) {
        return SizedBox(
          height: metrics.dividerHeight,
          child: const Divider(height: 1),
        );
      }

      if (entry.childrenBuilder != null) {
        if (!entry.enabled) {
          return MenuItemButton(
            key: widget.menuItemKeysByLabel?[entry.label ?? ''],
            requestFocusOnHover: false,
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: null,
            child: buildAppMenuRowContent(
              context,
              metrics,
              maxWidth: contentMaxWidth,
              label: entry.label ?? '',
              labelWidget: entry.labelWidget,
              icon: entry.icon,
              trailing: entry.trailing,
              isDestructive: entry.isDestructive,
              enabled: false,
            ),
          );
        }

        final controller = submenuControllers[entry];
        return _LazyAppSubmenuButton(
          key: widget.menuItemKeysByLabel?[entry.label ?? ''],
          entry: entry,
          entriesBuilder: () => _normalizeEntries(entry.childrenBuilder!()),
          metrics: metrics,
          maxWidth: maxWidth,
          menuStyle: _menuStyle(context, metrics),
          controller: controller,
          onOpen: () {
            for (final ctrl in submenuControllers.values) {
              if (ctrl != controller && ctrl.isOpen) ctrl.close();
            }
          },
          buildChildren: (submenuEntries, submenuMaxWidth) =>
              _buildSubmenuChildren(
                context,
                submenuEntries,
                metrics,
                submenuMaxWidth,
              ),
        );
      }

      final rawChildren = entry.children;
      if (rawChildren != null && rawChildren.isNotEmpty) {
        final normalizedChildren = _normalizeEntries(rawChildren);
        final hasEnabledChildren = hasEnabledAppContextMenuEntries(
          normalizedChildren,
        );
        if (!entry.enabled || !hasEnabledChildren) {
          return MenuItemButton(
            key: widget.menuItemKeysByLabel?[entry.label ?? ''],
            requestFocusOnHover: false,
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: null,
            child: buildAppMenuRowContent(
              context,
              metrics,
              maxWidth: contentMaxWidth,
              label: entry.label ?? '',
              labelWidget: entry.labelWidget,
              icon: entry.icon,
              trailing: entry.trailing,
              isDestructive: entry.isDestructive,
              enabled: false,
            ),
          );
        }

        final controller = submenuControllers[entry];
        return _LazyAppSubmenuButton(
          key: widget.menuItemKeysByLabel?[entry.label ?? ''],
          entry: entry,
          entriesBuilder: () => normalizedChildren,
          metrics: metrics,
          maxWidth: maxWidth,
          menuStyle: _menuStyle(context, metrics),
          controller: controller,
          onOpen: () {
            for (final ctrl in submenuControllers.values) {
              if (ctrl != controller && ctrl.isOpen) ctrl.close();
            }
          },
          buildChildren: (submenuEntries, submenuMaxWidth) =>
              _buildSubmenuChildren(
                context,
                submenuEntries,
                metrics,
                submenuMaxWidth,
              ),
        );
      }

      if (entry.isHighlighted) {
        return _HoverableHighlightedRow(
          key: widget.menuItemKeysByLabel?[entry.label ?? ''],
          label: entry.label ?? '',
          icon: entry.icon,
          metrics: metrics,
          onTap: entry.enabled
              ? () {
                  _closeContextMenu();
                  entry.onTap?.call();
                }
              : null,
        );
      }

      return _wrapWithHoverPreview(
        entry,
        metrics,
        MenuItemButton(
          key: widget.menuItemKeysByLabel?[entry.label ?? ''],
          requestFocusOnHover: false,
          style: buildAppSubmenuItemStyle(context, metrics),
          onPressed: entry.enabled
              ? () {
                  _closeContextMenu();
                  entry.onTap?.call();
                }
              : null,
          child: buildAppMenuRowContent(
            context,
            metrics,
            maxWidth: contentMaxWidth,
            label: entry.label ?? '',
            labelWidget: entry.labelWidget,
            icon: entry.icon,
            trailing: entry.trailing,
            isSelected: entry.isSelected,
            isDestructive: entry.isDestructive,
            enabled: entry.enabled,
          ),
        ),
      );
    }).toList();
  }

  List<AppContextMenuEntry> _normalizeEntries(
    List<AppContextMenuEntry> entries,
  ) {
    final result = <AppContextMenuEntry>[];
    for (final e in entries) {
      if (e.isDivider) {
        if (result.isEmpty || result.last.isDivider) continue;
        result.add(e);
      } else {
        result.add(e);
      }
    }
    while (result.isNotEmpty && result.last.isDivider) {
      result.removeLast();
    }
    return result;
  }

  List<Widget> _buildSubmenuChildren(
    BuildContext context,
    List<AppContextMenuEntry> entries,
    AppMenuMetrics metrics,
    double maxWidth,
  ) {
    final submenuContentMaxWidth = maxWidth - metrics.itemPadding.horizontal;

    return entries.map((entry) {
      if (entry.colorRowActions != null) {
        return _AppContextMenuColorRow(
          actions: entry.colorRowActions!,
          metrics: metrics,
          maxWidth: maxWidth,
          closeMenu: _closeContextMenu,
        );
      }
      if (entry.isDivider) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Divider(height: 1),
        );
      }

      if (entry.childrenBuilder != null) {
        if (!entry.enabled) {
          return MenuItemButton(
            requestFocusOnHover: false,
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: null,
            child: buildAppMenuRowContent(
              context,
              metrics,
              maxWidth: submenuContentMaxWidth,
              label: entry.label ?? '',
              labelWidget: entry.labelWidget,
              icon: entry.icon,
              trailing: entry.trailing,
              isDestructive: entry.isDestructive,
              enabled: false,
            ),
          );
        }

        return _LazyAppSubmenuButton(
          entry: entry,
          entriesBuilder: () => _normalizeEntries(entry.childrenBuilder!()),
          metrics: metrics,
          maxWidth: submenuContentMaxWidth,
          menuStyle: _menuStyle(context, metrics),
          buildChildren: (submenuEntries, submenuMaxWidth) =>
              _buildSubmenuChildren(
                context,
                submenuEntries,
                metrics,
                submenuMaxWidth,
              ),
        );
      }

      final rawChildren = entry.children;
      if (rawChildren != null && rawChildren.isNotEmpty) {
        final normalizedChildren = _normalizeEntries(rawChildren);
        final hasEnabledChildren = hasEnabledAppContextMenuEntries(
          normalizedChildren,
        );
        if (!entry.enabled || !hasEnabledChildren) {
          return MenuItemButton(
            requestFocusOnHover: false,
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: null,
            child: buildAppMenuRowContent(
              context,
              metrics,
              maxWidth: submenuContentMaxWidth,
              label: entry.label ?? '',
              labelWidget: entry.labelWidget,
              icon: entry.icon,
              trailing: entry.trailing,
              isDestructive: entry.isDestructive,
              enabled: false,
            ),
          );
        }

        return _LazyAppSubmenuButton(
          entry: entry,
          entriesBuilder: () => normalizedChildren,
          metrics: metrics,
          maxWidth: submenuContentMaxWidth,
          menuStyle: _menuStyle(context, metrics),
          buildChildren: (submenuEntries, submenuMaxWidth) =>
              _buildSubmenuChildren(
                context,
                submenuEntries,
                metrics,
                submenuMaxWidth,
              ),
        );
      }

      return _wrapWithHoverPreview(
        entry,
        metrics,
        MenuItemButton(
          key: entry.key,
          requestFocusOnHover: false,
          style: buildAppSubmenuItemStyle(context, metrics),
          onPressed: entry.enabled
              ? () {
                  _closeContextMenu();
                  entry.onTap?.call();
                }
              : null,
          child: buildAppMenuRowContent(
            context,
            metrics,
            maxWidth: submenuContentMaxWidth,
            label: entry.label ?? '',
            labelWidget: entry.labelWidget,
            icon: entry.icon,
            trailing: entry.trailing,
            isSelected: entry.isSelected,
            isDestructive: entry.isDestructive,
            enabled: entry.enabled,
          ),
        ),
      );
    }).toList();
  }

  /// עוטף פריט עלה ב-[_MenuItemHoverPreview] כאשר הוגדר לו
  /// [AppContextMenuEntry.hoverPreviewBuilder] — חלונית תצוגה מקדימה ברפרוף.
  Widget _wrapWithHoverPreview(
    AppContextMenuEntry entry,
    AppMenuMetrics metrics,
    Widget child,
  ) {
    final previewBuilder = entry.hoverPreviewBuilder;
    if (previewBuilder == null || !entry.enabled) {
      return child;
    }
    return _MenuItemHoverPreview(
      previewBuilder: previewBuilder,
      metrics: metrics,
      pinScrollAnchor: () => _menuOpenScrollAnchor,
      onPinned: _closeContextMenu,
      child: child,
    );
  }
}

/// חוזה ציבורי עבור פריט תפריט שמסוגל לפתוח תת-תפריט באופן פרוגרמטי.
/// משמש את הסיור המודרך כדי לפתוח את תת-התפריט של "הצג לצד" בלי לעקוף
/// את בדיקת הטיפוסים דרך `dynamic`.
abstract interface class AppSubmenuOpener {
  void openSubmenu([VoidCallback? afterOpen]);
}

class _LazyAppSubmenuButton extends StatefulWidget {
  final AppContextMenuEntry entry;
  final List<AppContextMenuEntry> Function() entriesBuilder;
  final AppMenuMetrics metrics;
  final double maxWidth;
  final MenuStyle menuStyle;
  final MenuController? controller;
  final VoidCallback? onOpen;
  final List<Widget> Function(List<AppContextMenuEntry>, double) buildChildren;

  const _LazyAppSubmenuButton({
    super.key,
    required this.entry,
    required this.entriesBuilder,
    required this.metrics,
    required this.maxWidth,
    required this.menuStyle,
    required this.buildChildren,
    this.controller,
    this.onOpen,
  });

  @override
  State<_LazyAppSubmenuButton> createState() => _LazyAppSubmenuButtonState();
}

class _LazyAppSubmenuButtonState extends State<_LazyAppSubmenuButton>
    implements AppSubmenuOpener {
  List<AppContextMenuEntry>? _entries;
  List<Widget>? _menuChildren;
  bool? _hasEnabledChildren;
  bool? _openToRight;

  // SubmenuButton קוראת requestFocus() על ה-focusNode בעת ריחוף ופתיחת תת-תפריט.
  // בלי canRequestFocus:false היא הייתה גוזלת פוקוס מ-SelectableRegion וגורמת
  // ל-clearSelection() — סימון הטקסט הוויזואלי היה נעלם בעת פתיחת תת-תפריט.
  late final FocusNode _submenuButtonFocusNode = FocusNode(
    debugLabel: 'AppContextMenuSubmenuButton',
    canRequestFocus: false,
  );

  // השבתת הפוקוס לעיל מבטלת גם את הפתיחה-בריחוף המובנית של SubmenuButton
  // (שמסתמכת על requestFocus). לכן פותחים את התת-תפריט בריחוף ידנית דרך
  // ה-controller — open() אינו מבקש פוקוס, כך שהבחירה ב-SelectableRegion נשמרת.
  Timer? _hoverOpenTimer;

  // מנוי לרענון תגובתי של הילדים (למשל רשימת "כרטיסיות פתוחות").
  StreamSubscription<Object?>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    // טעינה מוקדמת של הילדים כדי למנוע תפריט ריק
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menuChildren == null) {
        _ensureMenuChildrenLoaded();
      }
    });
    // רענון הילדים בכל פעימה של הסטרים — בונה מחדש מ-entriesBuilder עם נתונים
    // טריים. הסטרים פולט אחרי עדכון מקור הנתונים, כך שהרשימה מעודכנת.
    _refreshSubscription = widget.entry.childrenRefreshStream?.listen(
      (_) => _refreshChildren(),
    );
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    _hoverOpenTimer?.cancel();
    _submenuButtonFocusNode.dispose();
    super.dispose();
  }

  void _refreshChildren() {
    if (!mounted) return;
    _entries = null;
    _menuChildren = null;
    _hasEnabledChildren = null;
    _ensureMenuChildrenLoaded();
  }

  // פתיחה-בריחוף: השהיה קצרה כדי שמעבר עכבר חולף לא יפתח תת-תפריט.
  // הערך תואם את מנגנון התת-תפריט השני בפרויקט (_SubmenuItemWidget).
  void _scheduleHoverOpen() {
    _ensureMenuChildrenLoaded();
    _hoverOpenTimer?.cancel();
    _hoverOpenTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final controller = widget.controller;
      if (controller != null && !controller.isOpen) {
        // open() מפעיל את SubmenuButton.onOpen → סוגר תתי-תפריט אחאים פתוחים.
        openSubmenu();
      }
    });
  }

  void _cancelHoverOpen() {
    _hoverOpenTimer?.cancel();
    _hoverOpenTimer = null;
  }

  @override
  void openSubmenu([VoidCallback? afterOpen]) {
    if (_menuChildren == null) {
      _ensureMenuChildrenLoaded();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.controller?.open();
        afterOpen?.call();
      });
    } else {
      widget.controller?.open();
      afterOpen?.call();
    }
  }

  void _ensureMenuChildrenLoaded() {
    if (_menuChildren != null) {
      return;
    }

    final entries = _entries ??= widget.entriesBuilder();
    final hasEnabledChildren = hasEnabledAppContextMenuEntries(entries);
    setState(() {
      _hasEnabledChildren = hasEnabledChildren;
      _openToRight = _shouldOpenToRight();
      _menuChildren = hasEnabledChildren
          ? widget.buildChildren(entries, widget.maxWidth)
          : const <Widget>[];
    });
  }

  bool _shouldOpenToRight() {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayRenderObject = overlay?.context.findRenderObject();
    final itemRenderObject = context.findRenderObject();
    if (overlayRenderObject is! RenderBox ||
        itemRenderObject is! RenderBox ||
        !overlayRenderObject.hasSize ||
        !itemRenderObject.hasSize) {
      return !isRtl;
    }

    final itemRect = MatrixUtils.transformRect(
      itemRenderObject.getTransformTo(overlayRenderObject),
      Offset.zero & itemRenderObject.size,
    );
    final spaceLeft = itemRect.left;
    final spaceRight = overlayRenderObject.size.width - itemRect.right;

    if (isRtl) {
      return spaceLeft < widget.maxWidth && spaceRight > spaceLeft;
    }
    return !(spaceRight < widget.maxWidth && spaceLeft > spaceRight);
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final openToRight = _openToRight ?? !isRtl;
    final menuTextDirection = openToRight
        ? TextDirection.ltr
        : TextDirection.rtl;
    final submenuAlignment = openToRight
        ? Alignment.topRight
        : Alignment.topLeft;
    final contentTextDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final submenuArrow =
        widget.entry.trailing ??
        Icon(
          isRtl
              ? FluentIcons.chevron_right_16_regular
              : FluentIcons.chevron_left_16_regular,
          size: widget.metrics.iconSize,
        );
    final menuChildren = (_menuChildren ?? const <Widget>[])
        .map(
          (child) => Directionality(
            textDirection: contentTextDirection,
            child: child,
          ),
        )
        .toList();

    if (_hasEnabledChildren == false) {
      return MenuItemButton(
        requestFocusOnHover: false,
        style: buildAppSubmenuItemStyle(context, widget.metrics),
        onPressed: null,
        child: buildAppMenuRowContent(
          context,
          widget.metrics,
          maxWidth: widget.maxWidth - widget.metrics.itemPadding.horizontal,
          label: widget.entry.label ?? '',
          labelWidget: widget.entry.labelWidget,
          icon: widget.entry.icon,
          trailing: widget.entry.trailing,
          isDestructive: widget.entry.isDestructive,
          enabled: false,
        ),
      );
    }

    final submenuButton = MouseRegion(
      onEnter: (_) => _scheduleHoverOpen(),
      onExit: (_) => _cancelHoverOpen(),
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: (_) => _ensureMenuChildrenLoaded(),
        child: SubmenuButton(
          controller: widget.controller,
          focusNode: _submenuButtonFocusNode,
          onOpen: () {
            _ensureMenuChildrenLoaded();
            final shouldOpenToRight = _shouldOpenToRight();
            if (_openToRight != shouldOpenToRight) {
              setState(() => _openToRight = shouldOpenToRight);
            }
            widget.onOpen?.call();
          },
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          style: buildAppSubmenuItemStyle(context, widget.metrics),
          menuStyle: widget.menuStyle.copyWith(
            alignment: submenuAlignment,
          ),
          menuChildren: menuChildren,
          child: Directionality(
            textDirection: contentTextDirection,
            child: buildAppMenuRowContent(
              context,
              widget.metrics,
              maxWidth: widget.maxWidth - widget.metrics.itemPadding.horizontal,
              label: widget.entry.label ?? '',
              labelWidget: widget.entry.labelWidget,
              icon: widget.entry.icon,
              trailing: submenuArrow,
              isDestructive: widget.entry.isDestructive,
              enabled: widget.entry.enabled,
            ),
          ),
        ),
      ),
    );

    return Directionality(
      textDirection: menuTextDirection,
      child: submenuButton,
    );
  }
}

class _AppContextMenuPanel extends StatelessWidget {
  final List<AppContextMenuEntry> entries;
  final AppMenuMetrics metrics;
  final MenuStyle? menuStyle;
  final double maxWidth;
  final double maxHeight;
  final List<Widget> Function(BuildContext, List<AppContextMenuEntry>)
  buildChildren;

  const _AppContextMenuPanel({
    super.key,
    required this.entries,
    required this.metrics,
    required this.menuStyle,
    required this.maxWidth,
    required this.maxHeight,
    required this.buildChildren,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // descendantsAreFocusable:false מונע מ-SubmenuButton לגזול פוקוס מ-SelectableRegion
    // דרך ה-_buttonFocusNode הפנימי שלו (שאינו נשלט מחוץ ל-Flutter).
    // trade-off: ניווט מקלדת (Tab/חצים) בתוך התפריט אינו פועל — מקובל עבור תפריט הקשר.
    return FocusScope(
      skipTraversal: true,
      descendantsAreFocusable: false,
      child: Material(
        color:
            menuStyle?.backgroundColor?.resolve(const <WidgetState>{}) ??
            colorScheme.surfaceContainer,
        elevation:
            menuStyle?.elevation?.resolve(const <WidgetState>{})?.toDouble() ??
            3,
        shape:
            menuStyle?.shape?.resolve(const <WidgetState>{}) ??
            RoundedRectangleBorder(
              borderRadius: AppTokens.borderRadiusAll,
            ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: metrics.menuMinWidth,
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: SingleChildScrollView(
              padding: metrics.menuPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buildChildren(context, entries),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _PreserveSelectionSecondaryTapRecognizer — חוסם שחרור בחירה בלחיצה ימנית
//
// ב-Windows, ה-TapGestureRecognizer של SelectableRegion יורה onSecondaryTapDown
// אחרי kPressTimeout (100ms) גם בלי לזכות בזירה, ומפעיל _collapseSelectionAt —
// כך שלחיצה ימנית רגילה (החזקה >100ms) משחררת את הבחירה. recognizer זה זוכה
// באופן מיידי (eager) בכפתור הימני כאשר קיימת בחירה, וכך SelectableRegion נדחה
// מהזירה לפני שה-deadline שלו חולף — והבחירה נשמרת. כשאין בחירה הוא אינו מצטרף
// לזירה, וההתנהגות הרגילה נשמרת.
// ═══════════════════════════════════════════════════════════════════════════

class _PreserveSelectionSecondaryTapRecognizer extends EagerGestureRecognizer {
  _PreserveSelectionSecondaryTapRecognizer({required this.shouldPreserve})
    : super(
        allowedButtonsFilter: (buttons) => buttons & kSecondaryButton != 0,
      );

  final bool Function(Offset globalPosition) shouldPreserve;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (shouldPreserve(event.position)) {
      super.addAllowedPointer(event); // resolve(accepted) — זכייה מיידית
    }
    // אחרת: לא מצטרפים לזירה — SelectableRegion מטפל כרגיל (בחירה ריקה ממילא).
  }

  @override
  String get debugDescription => 'preserve-selection secondary tap';
}

// ═══════════════════════════════════════════════════════════════════════════
// _HoverableHighlightedRow — שורת תפריט מודגשת בעיצוב pill
// משמשת לפריטים עם isHighlighted: true (כגון "פתח חלונית" ו"בחר מפרשים מרובים")
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// _MenuItemHoverPreview — חלונית תצוגה מקדימה צפה ברפרוף על פריט תפריט
//
// עוטף פריט עלה בתפריט ההקשר. ברפרוף על הפריט נפתחת, לאחר השהיה קצרה,
// חלונית צפה לצד הפריט עם התוכן שמחזיר previewBuilder. החלונית נעלמת כאשר
// הסמן עוזב גם את הפריט וגם את החלונית עצמה (מעבר ביניהן אינו סוגר אותה).
// ═══════════════════════════════════════════════════════════════════════════

class _MenuItemHoverPreview extends StatefulWidget {
  final WidgetBuilder previewBuilder;
  final AppMenuMetrics metrics;
  final Widget child;

  /// עוגן-הגלילה שנלכד בפתיחת התפריט — מועבר לחלונית המקובעת כדי שתזוז
  /// עם גלילת הדף. פונקציה ולא ערך, כי הלכידה נעשית אחרי בניית הפריטים.
  final OverlayScrollAnchor? Function()? pinScrollAnchor;

  /// נקרא אחרי קיבוע התצוגה המקדימה — סוגר את התפריט שמתחתיה.
  final VoidCallback? onPinned;

  const _MenuItemHoverPreview({
    required this.previewBuilder,
    required this.metrics,
    required this.child,
    this.pinScrollAnchor,
    this.onPinned,
  });

  @override
  State<_MenuItemHoverPreview> createState() => _MenuItemHoverPreviewState();
}

class _MenuItemHoverPreviewState extends State<_MenuItemHoverPreview> {
  // השהיית פתיחה — שרפרוף חולף על פריט לא יציף חלוניות.
  static const Duration _showDelay = Duration(milliseconds: 400);
  // השהיית סגירה — מספיקה כדי לחצות את הרווח שבין הפריט לחלונית.
  static const Duration _hideDelay = Duration(milliseconds: 250);
  static const double _panelMaxWidth = 380;
  static const double _panelMaxHeight = 360;
  static const double _screenPadding = 8;
  static const double _anchorGap = 6;

  OverlayEntry? _previewEntry;
  Timer? _showTimer;
  Timer? _hideTimer;
  final GlobalKey _panelKey = GlobalKey();
  Offset? _panelOffset;
  Size? _panelSize;
  bool _panelVisible = false;
  // נפתח בלחיצה ארוכה (מגע) ולא ברפרוף — נסגר בהקשה מחוץ לחלונית.
  bool _touchTriggered = false;

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _removePreview();
    super.dispose();
  }

  void _removePreview() {
    _previewEntry?.remove();
    _previewEntry = null;
    _panelOffset = null;
    _panelSize = null;
    _panelVisible = false;
    _touchTriggered = false;
  }

  void _scheduleShow() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_previewEntry != null) return;
    _showTimer?.cancel();
    _showTimer = Timer(_showDelay, () {
      if (mounted) _showPreview();
    });
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _showTimer = null;
    if (_previewEntry == null) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      _removePreview();
    });
  }

  Rect? _itemRectInOverlay(RenderBox overlayBox) {
    final itemRenderObject = context.findRenderObject();
    if (itemRenderObject is! RenderBox || !itemRenderObject.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      itemRenderObject.getTransformTo(overlayBox),
      Offset.zero & itemRenderObject.size,
    );
  }

  void _showPreview() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayRenderObject = overlay?.context.findRenderObject();
    if (overlay == null ||
        overlayRenderObject is! RenderBox ||
        !overlayRenderObject.hasSize) {
      return;
    }

    final itemRect = _itemRectInOverlay(overlayRenderObject);
    if (itemRect == null) return;

    final overlaySize = overlayRenderObject.size;
    final maxWidth = (overlaySize.width - _screenPadding * 2)
        .clamp(0.0, _panelMaxWidth)
        .toDouble();
    final maxHeight = (overlaySize.height - _screenPadding * 2)
        .clamp(0.0, _panelMaxHeight)
        .toDouble();
    if (maxWidth <= 0 || maxHeight <= 0) return;

    // מדידה ראשונית בפינת המסך — שם האילוצים מקסימליים, כך שהגודל הטבעי
    // שנמדד תקף גם במיקום הסופי (שתמיד מותיר לפחות את אותו מרחב).
    _panelOffset = const Offset(_screenPadding, _screenPadding);
    _panelVisible = false;

    _previewEntry = OverlayEntry(
      builder: (overlayContext) {
        final offset =
            _panelOffset ?? const Offset(_screenPadding, _screenPadding);
        final panel = Positioned(
          left: offset.dx,
          top: offset.dy,
          child: Visibility(
            visible: _panelVisible,
            maintainSize: false,
            maintainAnimation: false,
            maintainState: true,
            child: MouseRegion(
              onEnter: (_) => _cancelHide(),
              onExit: (_) => _scheduleHide(),
              // התוכן נטען אסינכרונית — כשהוא מגיע, החלונית גדלה אחרי
              // שכבר מוקמה לפי גודל הטעינה הקטן ועלולה להיחתך בתחתית
              // המסך. שינוי גודל מפעיל הצמדה מחדש (בסוף הפריים — הנוטיפיקציה
              // נורית בזמן layout, כשעדכון ה-overlay אסור).
              child: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _previewEntry == null) return;
                    _repositionNextToItem(overlayRenderObject, itemRect);
                  });
                  return true;
                },
                child: SizeChangedLayoutNotifier(
                  child: _buildPanel(maxWidth, maxHeight),
                ),
              ),
            ),
          ),
        );
        if (!_touchTriggered) return panel;
        // במגע אין onExit לסגירה — מחסום שקוף מאחורי החלונית סוגר בהקשה בחוץ.
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _removePreview,
              ),
            ),
            panel,
          ],
        );
      },
    );
    overlay.insert(_previewEntry!);

    // מיקום דו-שלבי: בנייה סמויה למדידת הגודל בפועל, ואז הצמדה לצד הפריט.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _previewEntry == null) return;
      _repositionNextToItem(overlayRenderObject, itemRect);
    });
  }

  void _repositionNextToItem(RenderBox overlayBox, Rect itemRect) {
    final panelRenderObject = _panelKey.currentContext?.findRenderObject();
    if (panelRenderObject is! RenderBox ||
        !panelRenderObject.hasSize ||
        _previewEntry == null) {
      return;
    }

    final panelSize = panelRenderObject.size;
    final overlaySize = overlayBox.size;

    // העדפת צד: שמאלית לפריט (המשך כיוון הפתיחה הטבעי ב-RTL), אחרת ימינה,
    // ואם אין מקום מלא באף צד — הצמדה לקצה המסך בצד המרווח יותר.
    final leftCandidate = itemRect.left - _anchorGap - panelSize.width;
    final rightCandidate = itemRect.right + _anchorGap;
    final double dx;
    if (leftCandidate >= _screenPadding) {
      dx = leftCandidate;
    } else if (rightCandidate + panelSize.width <=
        overlaySize.width - _screenPadding) {
      dx = rightCandidate;
    } else {
      final spaceLeft = itemRect.left;
      final spaceRight = overlaySize.width - itemRect.right;
      dx = spaceLeft > spaceRight
          ? _screenPadding
          : (overlaySize.width - panelSize.width - _screenPadding)
                .clamp(_screenPadding, double.infinity)
                .toDouble();
    }

    final maxDy = (overlaySize.height - panelSize.height - _screenPadding)
        .clamp(_screenPadding, double.infinity)
        .toDouble();
    final dy = itemRect.top.clamp(_screenPadding, maxDy).toDouble();

    _panelOffset = Offset(dx, dy);
    _panelSize = panelSize;
    _panelVisible = true;
    _previewEntry?.markNeedsBuild();
  }

  Widget _buildPanel(double maxWidth, double maxHeight) {
    final colorScheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => _pinPreview(),
      child: Material(
        key: _panelKey,
        color: colorScheme.surfaceContainer,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: widget.metrics.menuMinWidth,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Builder(builder: widget.previewBuilder),
          ),
        ),
      ),
    );
  }

  /// לחיצה בתוך התצוגה המקדימה מקבעת אותה: היא מקודמת לחלונית עצמאית
  /// (ששורדת את סגירת התפריט, נסגרת בהקשה מחוץ לה וזזה עם הגלילה),
  /// והתפריט שמתחתיה נסגר.
  void _pinPreview() {
    final offset = _panelOffset;
    if (offset == null || !_panelVisible) return;
    LinkPreviewOverlay.showPinned(
      context,
      contentBuilder: widget.previewBuilder,
      panelPosition: offset,
      scrollAnchor: widget.pinScrollAnchor?.call(),
      panelSize: _panelSize,
    );
    _removePreview();
    widget.onPinned?.call();
  }

  // במגע אין רפרוף עכבר (גם במסכי מגע של דסקטופ); לחיצה ארוכה מחליפה אותו
  // כטריגר. בעכבר הריחוף כבר הציג, ולכן הקריאה כאן חוזרת מוקדם.
  void _handleLongPress() {
    if (_previewEntry != null) return;
    _showTimer?.cancel();
    _showTimer = null;
    _touchTriggered = true;
    _showPreview();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: _handleLongPress,
      child: MouseRegion(
        onEnter: (_) => _scheduleShow(),
        onExit: (_) => _scheduleHide(),
        child: widget.child,
      ),
    );
  }
}

class _HoverableHighlightedRow extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final AppMenuMetrics metrics;

  const _HoverableHighlightedRow({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusAll,
        child: Ink(
          height: metrics.itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: primary, width: 1.5),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: metrics.fontSize,
                  color: primary,
                ),
              ),
              if (icon != null) ...[
                const Spacer(),
                const SizedBox(width: 6),
                Icon(icon, size: metrics.iconSize, color: primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _AppContextMenuIconRow — שורת כפתורי אייקון בראש התפריט (סגנון Windows 11)
// ═══════════════════════════════════════════════════════════════════════════

class _AppContextMenuColorRow extends StatelessWidget {
  final List<AppContextMenuColorAction> actions;
  final AppMenuMetrics metrics;
  final double maxWidth;
  final VoidCallback closeMenu;

  const _AppContextMenuColorRow({
    required this.actions,
    required this.metrics,
    required this.maxWidth,
    required this.closeMenu,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(
        key: const ValueKey('context-color-row'),
        height: metrics.itemHeight,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in actions)
                  Tooltip(
                    message: action.label,
                    child: Semantics(
                      button: true,
                      selected: action.selected,
                      label: action.label,
                      child: InkWell(
                        key: ValueKey('context-color-${action.id}'),
                        onTap: action.onTap == null
                            ? null
                            : () {
                                closeMenu();
                                action.onTap!.call();
                              },
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox.square(
                          dimension: 32,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: action.icon == null
                                    ? action.color
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: action.selected
                                      ? colorScheme.primary
                                      : colorScheme.outlineVariant,
                                  width: action.selected ? 3 : 1,
                                ),
                              ),
                              child: action.icon == null
                                  ? null
                                  : Icon(
                                      action.icon,
                                      size: 18,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppContextMenuIconRow extends StatelessWidget {
  final List<AppContextMenuIconAction> actions;
  final AppMenuMetrics metrics;
  final MenuStyle menuStyle;
  final VoidCallback closeMenu;

  const _AppContextMenuIconRow({
    required this.actions,
    required this.metrics,
    required this.menuStyle,
    required this.closeMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      // Center ממרכז את שורת האייקונים בלי להפוך את ה-Row ל-mainAxisSize.max
      // (max בתוך פאנל IntrinsicWidth שבר את הבחירה בעת פתיחת התפריט).
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              _IconRowButton(
                action: action,
                metrics: metrics,
                menuStyle: menuStyle,
                closeMenu: closeMenu,
              ),
          ],
        ),
      ),
    );
  }
}

class _IconRowButton extends StatelessWidget {
  final AppContextMenuIconAction action;
  final AppMenuMetrics metrics;
  final MenuStyle menuStyle;
  final VoidCallback closeMenu;

  const _IconRowButton({
    required this.action,
    required this.metrics,
    required this.menuStyle,
    required this.closeMenu,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasSubmenu = action.submenuBuilder != null;
    final enabled = action.enabled && (action.onTap != null || hasSubmenu);
    final color = enabled
        ? colorScheme.onSurface
        : Theme.of(context).disabledColor;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, size: metrics.iconSize, color: color),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  action.label ?? action.tooltip ?? '',
                  style: TextStyle(fontSize: 11, color: color),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasSubmenu)
                Icon(
                  FluentIcons.chevron_down_12_regular,
                  size: 12,
                  color: color,
                ),
            ],
          ),
        ],
      ),
    );

    Widget button;
    if (hasSubmenu) {
      button = _IconRowSubmenu(
        action: action,
        metrics: metrics,
        menuStyle: menuStyle,
        closeMenu: closeMenu,
        enabled: enabled,
        // minWidth מאפשר גדילה עם textScaler; maxWidth מונע מ-label ארוך/טקסט
        // מוגדל מאוד להרחיב את הכפתורים מעבר לרוחב התפריט (הכיתוב נחתך במקום).
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, maxWidth: 96),
          child: content,
        ),
      );
    } else {
      button = InkWell(
        onTap: enabled
            ? () {
                closeMenu();
                action.onTap?.call();
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, maxWidth: 96),
          child: content,
        ),
      );
    }

    final tooltip = action.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      button = Tooltip(message: tooltip, child: button);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: button,
    );
  }
}

/// כפתור אייקון בשורה העליונה שפותח תת-תפריט (סגנון Windows 11).
/// משתמש ב-[MenuAnchor] שפותח את האפשרויות מתחת לכפתור; בחירת פריט סוגרת
/// את כל תפריט ההקשר דרך [closeMenu].
class _IconRowSubmenu extends StatelessWidget {
  final AppContextMenuIconAction action;
  final AppMenuMetrics metrics;
  final MenuStyle menuStyle;
  final VoidCallback closeMenu;
  final bool enabled;
  final Widget child;

  const _IconRowSubmenu({
    required this.action,
    required this.metrics,
    required this.menuStyle,
    required this.closeMenu,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final entries = action.submenuBuilder!();
    return MenuAnchor(
      style: menuStyle,
      menuChildren: [
        for (final entry in entries)
          MenuItemButton(
            requestFocusOnHover: false,
            style: buildAppSubmenuItemStyle(context, metrics),
            onPressed: entry.enabled
                ? () {
                    closeMenu();
                    entry.onTap?.call();
                  }
                : null,
            child: buildAppMenuRowContent(
              context,
              metrics,
              label: entry.label,
              icon: entry.icon,
              enabled: entry.enabled,
            ),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }
}
