import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_metrics.dart';
import 'menu_models.dart';
import 'menu_presentation.dart';
import 'menu_rows.dart';
import 'submenu_button.dart';

part 'context_menu_gestures.dart';
part 'context_menu_entries.dart';
part 'context_menu_rows.dart';
part 'lazy_submenu_button.dart';

class ContextMenuRegion extends StatefulWidget {
  final MenuPresentation presentation;
  final MenuEscapeRegistrar registerEscape;
  final void Function(BuildContext context, Offset position)? onMenuOpening;
  final MenuPreviewWrapper? previewWrapper;
  final Widget child;
  final List<AppContextMenuEntry> Function(BuildContext, Offset) menuBuilder;
  final Map<String, GlobalKey>? menuItemKeysByLabel;

  final GestureTapDownCallback? onSecondaryTapDown;

  /// נקרא כשהסמן נכנס לאזור. משמש לטעינה מקדימה של תוכן שהתפריט יצטרך —
  /// כך הוא נבנה עם נתונים מוכנים במקום להציג "טוען…".
  final VoidCallback? onHoverEnter;

  /// האם לחיצה ארוכה במגע או בעט פותחת את תפריט ההקשר.
  final bool openOnLongPress;

  final bool Function(Offset globalPosition)?
  shouldPreserveSelectionOnSecondaryTap;

  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.menuBuilder,
    required this.presentation,
    required this.registerEscape,
    this.onMenuOpening,
    this.previewWrapper,
    this.menuItemKeysByLabel,
    this.onSecondaryTapDown,
    this.onHoverEnter,
    this.shouldPreserveSelectionOnSecondaryTap,
    this.openOnLongPress = true,
  });

  @override
  State<ContextMenuRegion> createState() => ContextMenuRegionState();
}

class ContextMenuRegionState extends State<ContextMenuRegion> {
  static const double _contextMenuScreenPadding = 8;
  static const double _contextMenuMaxWidth = 320;

  // ה-Listener של אזור מקונן רץ לפני של העוטף; התפריט הקרוב ביותר גובר.
  static PointerEvent? _menuOpenedForEvent;

  bool _isMenuOpen = false;
  bool _isMenuVisible = false;
  OverlayEntry? _menuOverlayEntry;
  final GlobalKey _menuPanelKey = GlobalKey();
  Offset? _currentMenuOffset;
  double? _menuAnchorX;

  VoidCallback? _unregisterEscape;

  MenuPresentation get presentation => widget.presentation;

  @override
  void didUpdateWidget(ContextMenuRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isMenuOpen && oldWidget.registerEscape != widget.registerEscape) {
      _unregisterEscape?.call();
      _unregisterEscape = widget.registerEscape(_handleEscape);
    }
    if (oldWidget.presentation != widget.presentation) _rebuildOpenMenu();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildOpenMenu();
  }

  void _rebuildOpenMenu() {
    if (_menuOverlayEntry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menuOverlayEntry?.markNeedsBuild();
    });
  }

  final _submenuControllers = <MenuController, int>{};

  @override
  void dispose() {
    _removeContextMenuOverlay();
    super.dispose();
  }

  // התפריט אינו מקבל פוקוס (כדי לשמור את הבחירה), לכן Escape נתפס לפני עץ
  // הפוקוס ונבלע — שלא ינקה גם הדגשה/בחירה או יצא ממסך מלא.
  KeyEventResult _handleEscape(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      final openSubmenus = _submenuControllers.entries
          .where((entry) => entry.key.isOpen)
          .toList();
      if (openSubmenus.isEmpty) {
        _closeContextMenu();
      } else {
        final deepest = openSubmenus
            .map((entry) => entry.value)
            .reduce((a, b) => a > b ? a : b);
        for (final entry in openSubmenus) {
          if (entry.value == deepest) entry.key.close();
        }
      }
    }
    return KeyEventResult.handled;
  }

  void _removeContextMenuOverlay() {
    _unregisterEscape?.call();
    _unregisterEscape = null;
    _submenuControllers.clear();
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

  Future<void> showMenu() async {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    await _openContextMenu(
      renderObject.localToGlobal(renderObject.size.center(Offset.zero)),
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

    // Anchor toward the opener's reading direction, flipping only when
    // there is insufficient room. RTL grows left; LTR grows right.
    final anchorX = _menuAnchorX ?? currentOffset.dx;
    final leftDx = anchorX - panelSize.width;
    final rightDx = anchorX;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final targetDx = isRtl
        ? (leftDx >= _contextMenuScreenPadding ? leftDx : rightDx)
        : (rightDx + panelSize.width <=
                  overlaySize.width - _contextMenuScreenPadding
              ? rightDx
              : leftDx);

    final adjustedOffset = Offset(
      targetDx.clamp(_contextMenuScreenPadding, maxDx).toDouble(),
      currentOffset.dy.clamp(_contextMenuScreenPadding, maxDy).toDouble(),
    );

    _currentMenuOffset = adjustedOffset;
    _isMenuVisible = true;
    _menuOverlayEntry?.markNeedsBuild();
  }

  Future<void> _openContextMenu(
    Offset globalPosition, {
    PointerEvent? trigger,
  }) async {
    final entries = _normalizeEntries(
      widget.menuBuilder(context, globalPosition),
    );
    if (entries.isEmpty) return;
    _menuOpenedForEvent = trigger;

    widget.onMenuOpening?.call(context, globalPosition);

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayRenderObject = overlay.context.findRenderObject();
    if (overlayRenderObject is! RenderBox || !overlayRenderObject.hasSize) {
      return;
    }

    final overlayPosition = overlayRenderObject.globalToLocal(globalPosition);
    if (!overlayPosition.dx.isFinite || !overlayPosition.dy.isFinite) return;
    _menuAnchorX = overlayPosition.dx;
    final metrics = presentation.metrics;
    final (menuOffset, openAbove) = _calculateMenuOffset(
      overlayRenderObject,
      overlayPosition,
      entries,
      metrics,
    );
    final orderedEntries = openAbove ? _iconRowAtBottom(entries) : entries;
    final submenuControllers = <AppContextMenuEntry, MenuController>{
      for (final entry in orderedEntries)
        if (((entry.children != null && entry.children!.isNotEmpty) ||
                entry.childrenBuilder != null) &&
            entry.enabled)
          entry: MenuController(),
    };
    final iconRowControllers = <AppContextMenuEntry, List<MenuController>>{
      for (final entry in orderedEntries)
        if (entry.iconRowActions case final actions?)
          entry: [for (final _ in actions) MenuController()],
    };

    _removeContextMenuOverlay();
    _currentMenuOffset = menuOffset;
    _submenuControllers.addAll({
      for (final controller in submenuControllers.values) controller: 0,
      for (final controllers in iconRowControllers.values)
        for (final controller in controllers) controller: 0,
    });

    _menuOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final metrics = presentation.metrics;
        final menuStyle = _menuStyle(context, metrics);
        final maxMenuWidth = _resolveContextMenuMaxWidth(
          overlayRenderObject.size.width,
          metrics,
        );
        final maxMenuHeight =
            (overlayRenderObject.size.height - _contextMenuScreenPadding * 2)
                .clamp(metrics.itemHeight, double.infinity)
                .toDouble();
        final currentMenuOffset = _currentMenuOffset ?? menuOffset;
        return InheritedTheme.captureAll(
          context,
          Directionality(
            textDirection: Directionality.of(context),
            child: Positioned.fill(
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
                      // MenuAnchor מאזין לגלילה האופקית בשורת האייקונים בלבד;
                      // גלילת הפאנל צריכה לסגור גם היא את תתי־התפריטים שלה.
                      child: NotificationListener<ScrollStartNotification>(
                        onNotification: (notification) {
                          if (notification.depth == 0 &&
                              notification.metrics.axis == Axis.vertical) {
                            for (final controller
                                in iconRowControllers.values.expand(
                                  (row) => row,
                                )) {
                              if (controller.isOpen) controller.close();
                            }
                          }
                          return false;
                        },
                        child: _AppContextMenuPanel(
                          presentation: presentation,
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
                                iconRowControllers,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    setState(() => _isMenuOpen = true);
    overlay.insert(_menuOverlayEntry!);
    _unregisterEscape = widget.registerEscape(_handleEscape);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isMenuOpen) return;
      _repositionContextMenuWithinOverlay(overlayRenderObject.size);
    });
  }

  MenuStyle _menuStyle(BuildContext context, AppMenuMetrics metrics) {
    final themeStyle = Theme.of(context).menuTheme.style;
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
      onLongPressStart: widget.openOnLongPress
          ? (details) => _openContextMenu(details.globalPosition)
          : null,
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
          // המקבילה ללחיצה ארוכה במגע/עט: זוכה בזירה לפני ה-deadline של
          // SelectableRegion כשההחזקה על הבחירה, ופותחת את התפריט בעצמה.
          if (widget.openOnLongPress)
            _PreserveSelectionLongPressRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  _PreserveSelectionLongPressRecognizer
                >(
                  () => _PreserveSelectionLongPressRecognizer(
                    shouldPreserve: (globalPosition) =>
                        widget.shouldPreserveSelectionOnSecondaryTap?.call(
                          globalPosition,
                        ) ??
                        false,
                    onOpenMenu: _openContextMenu,
                    startScroll: _startPreservedSelectionScroll,
                  ),
                  (instance) {},
                ),
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            // כל Listener מקבל עותק מותמר של האירוע; original משותף לכולם.
            final original = event.original ?? event;
            if (event.buttons == kSecondaryButton &&
                !identical(original, _menuOpenedForEvent)) {
              widget.onSecondaryTapDown?.call(
                TapDownDetails(
                  globalPosition: event.position,
                  localPosition: event.localPosition,
                ),
              );
              _openContextMenu(event.position, trigger: original);
            }
          },
          child: _wrapWithHoverEnter(widget.child),
        ),
      ),
    );
  }

  ({Drag drag, Axis axis})? _startPreservedSelectionScroll(
    DragStartDetails details,
    VoidCallback onCanceled,
  ) {
    final position =
        Scrollable.maybeOf(context)?.position ??
        _descendantScrollPositionAt(details.globalPosition);
    if (position == null) return null;
    return (
      drag: position.drag(details, onCanceled),
      axis: axisDirectionToAxis(position.axisDirection),
    );
  }

  ScrollPosition? _descendantScrollPositionAt(Offset globalPosition) {
    ScrollPosition? result;
    void visit(Element element) {
      if (element case StatefulElement(state: final ScrollableState state)) {
        final renderObject = state.context.findRenderObject();
        if (renderObject is RenderBox &&
            renderObject.hasSize &&
            renderObject.size.contains(
              renderObject.globalToLocal(globalPosition),
            )) {
          result = state.position;
        }
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return result;
  }

  Widget _wrapWithHoverEnter(Widget child) {
    final onHoverEnter = widget.onHoverEnter;
    if (onHoverEnter == null) return child;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => onHoverEnter(),
      child: child,
    );
  }
}

abstract interface class AppSubmenuOpener {
  void openSubmenu([VoidCallback? afterOpen]);
}
