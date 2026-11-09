import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart' as menu;
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_presentation.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/escape_layers.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/misc/overlay_scroll_anchor.dart';

export 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show AppSubmenuOpener;

VoidCallback _registerMenuEscape(OnKeyEventCallback handler) {
  EscapeLayers.add(handler);
  return () => EscapeLayers.remove(handler);
}

/// תפריט הקשר עם עיצוב האפליקציה ותצוגה מקדימה של ספרים.
class AppContextMenuRegion extends StatefulWidget {
  final Widget child;
  final List<AppContextMenuEntry> Function(BuildContext, Offset) menuBuilder;
  final Map<String, GlobalKey>? menuItemKeysByLabel;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onHoverEnter;
  final bool openOnLongPress;
  final bool Function(Offset)? shouldPreserveSelectionOnSecondaryTap;

  const AppContextMenuRegion({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.menuItemKeysByLabel,
    this.onSecondaryTapDown,
    this.onHoverEnter,
    this.shouldPreserveSelectionOnSecondaryTap,
    this.openOnLongPress = true,
  });

  @override
  State<AppContextMenuRegion> createState() => AppContextMenuRegionState();
}

class AppContextMenuRegionState extends State<AppContextMenuRegion> {
  final _menuKey = GlobalKey<menu.ContextMenuRegionState>();
  OverlayScrollAnchor? _menuOpenScrollAnchor;
  late menu.MenuPresentation _presentation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recreate only when inherited presentation dependencies change.
    // Rebuilding the reader must not rebuild an open menu's overlay merely
    // because new callback instances were allocated for the same theme.
    _presentation = createAppMenuPresentation(context);
  }

  // A stable instance-method tear-off avoids an unnecessary Escape handler
  // unregister/register cycle on every unrelated reader rebuild.
  VoidCallback _registerWindowEscape(OnKeyEventCallback handler) =>
      _registerMenuEscape(
        (event) => mounted && !AppWindowKeys.isActiveWindow(context)
            ? KeyEventResult.ignored
            : handler(event),
      );

  Future<void> showMenu() async => _menuKey.currentState?.showMenu();

  Future<void> openMenuAt(Offset globalPosition) async =>
      _menuKey.currentState?.openMenuAt(globalPosition);

  @override
  void dispose() {
    _menuOpenScrollAnchor = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;
    return menu.ContextMenuRegion(
      key: _menuKey,
      presentation: presentation,
      // ESC מחלון אחר (אותו FocusManager) לא סוגר תפריט בחלון הזה.
      registerEscape: _registerWindowEscape,
      menuBuilder: widget.menuBuilder,
      menuItemKeysByLabel: widget.menuItemKeysByLabel,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      onHoverEnter: widget.onHoverEnter,
      openOnLongPress: widget.openOnLongPress,
      shouldPreserveSelectionOnSecondaryTap:
          widget.shouldPreserveSelectionOnSecondaryTap,
      onMenuOpening: (context, position) {
        // הלכידה חייבת להקדים את ה-overlay כדי לפגוע בתוכן שמתחתיו.
        _menuOpenScrollAnchor = OverlayScrollAnchor.capture(context, position);
      },
      // Release the retained RenderBox and ScrollPosition when the menu closes.
      onMenuClosed: () => _menuOpenScrollAnchor = null,
      previewWrapper: (context, previewBuilder, onPinned, child) =>
          _MenuItemHoverPreview(
            previewBuilder: previewBuilder,
            metrics: presentation.metrics,
            pinScrollAnchor: () => _menuOpenScrollAnchor,
            onPinned: onPinned,
            child: child,
          ),
      child: widget.child,
    );
  }
}

class _MenuItemHoverPreview extends StatefulWidget {
  final WidgetBuilder previewBuilder;
  final AppMenuMetrics metrics;
  final Widget child;
  final OverlayScrollAnchor? Function()? pinScrollAnchor;
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
  static const Duration _showDelay = Duration(milliseconds: 400);

  Timer? _showTimer;
  Object? _panelToken;
  bool _pinned = false;

  @override
  void dispose() {
    _showTimer?.cancel();
    if (!_pinned && _panelToken != null) {
      LinkPreviewOverlay.dismiss(token: _panelToken);
    }
    super.dispose();
  }

  void _scheduleShow() {
    if (_panelToken != null) {
      LinkPreviewOverlay.cancelScheduledHide(_panelToken);
      return;
    }
    _showTimer?.cancel();
    _showTimer = Timer(_showDelay, () {
      if (mounted) _showPreview();
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _showTimer = null;
    if (_panelToken != null) LinkPreviewOverlay.scheduleHide(_panelToken);
  }

  Rect? _itemGlobalRect() {
    final itemRenderObject = context.findRenderObject();
    if (itemRenderObject is! RenderBox || !itemRenderObject.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      itemRenderObject.getTransformTo(null),
      Offset.zero & itemRenderObject.size,
    );
  }

  void _showPreview({bool touchTriggered = false}) {
    final itemRect = _itemGlobalRect();
    if (itemRect == null) return;
    _panelToken = LinkPreviewOverlay.showBesideMenuItem(
      context,
      contentBuilder: widget.previewBuilder,
      itemGlobalRect: itemRect,
      minWidth: widget.metrics.menuMinWidth,
      touchTriggered: touchTriggered,
      scrollAnchor: widget.pinScrollAnchor?.call(),
      onPinned: () {
        _pinned = true;
        widget.onPinned?.call();
      },
      onDismissed: () => _panelToken = null,
    );
  }

  void _handleLongPress() {
    if (_panelToken != null) return;
    _showTimer?.cancel();
    _showTimer = null;
    _showPreview(touchTriggered: true);
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
