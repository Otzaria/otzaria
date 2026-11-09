import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'menu_presentation.dart';
import 'menu_rows.dart';

/// תת־תפריט Flutter משותף לתפריטי הקשר ולתפריטים הנפתחים מכפתור.
class AppSubmenuButton extends StatefulWidget {
  const AppSubmenuButton({
    super.key,
    required this.child,
    required this.menuChildren,
    required this.controller,
    required this.presentation,
    required this.maxWidth,
    this.preserveFocus = true,
    this.menuStyle,
    this.style,
    this.onOpen,
    this.onClose,
    this.childBuilder,
  });

  final Widget child;
  final List<Widget> menuChildren;
  final MenuController controller;
  final MenuPresentation presentation;
  final double maxWidth;
  final bool preserveFocus;
  final MenuStyle? menuStyle;
  final ButtonStyle? style;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final Widget Function(BuildContext context, bool openToRight)? childBuilder;

  @override
  State<AppSubmenuButton> createState() => _AppSubmenuButtonState();
}

class _AppSubmenuButtonState extends State<AppSubmenuButton> {
  static const _hoverDelay = Duration(milliseconds: 500);
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'AppSubmenuButton',
    canRequestFocus: !widget.preserveFocus,
  );
  final _menuChildKey = GlobalKey();
  Timer? _hoverTimer;
  bool? _openToRight;

  bool _trackingPointer = false;

  // Only an open, focusable submenu needs global pointer tracking. Hundreds
  // of closed submenu items should not each process every mouse event.
  void _setTrackingPointer(bool track) {
    if (_trackingPointer == track) return;
    final router = GestureBinding.instance.pointerRouter;
    if (track) {
      router.addGlobalRoute(_handlePointerEvent);
    } else {
      router.removeGlobalRoute(_handlePointerEvent);
    }
    _trackingPointer = track;
  }

  @override
  void didUpdateWidget(AppSubmenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preserveFocus != widget.preserveFocus) {
      _cancelOpen();
      _focusNode.canRequestFocus = !widget.preserveFocus;
      // Changing the FocusScope wrapper recreates the closed menu anchor.
      // Controller replacement alone retains its open state and tracking.
      _setTrackingPointer(false);
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _setTrackingPointer(false);
    _focusNode.dispose();
    super.dispose();
  }

  bool _shouldOpenToRight() {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final overlay = Overlay.maybeOf(context);
    final overlayBox = overlay?.context.findRenderObject();
    final itemBox = context.findRenderObject();
    if (overlayBox is! RenderBox ||
        itemBox is! RenderBox ||
        !overlayBox.hasSize ||
        !itemBox.hasSize) {
      return !isRtl;
    }
    final rect = MatrixUtils.transformRect(
      itemBox.getTransformTo(overlayBox),
      Offset.zero & itemBox.size,
    );
    final left = rect.left;
    final right = overlayBox.size.width - rect.right;
    return isRtl
        ? left < widget.maxWidth && right > left
        : !(right < widget.maxWidth && left > right);
  }

  void _scheduleOpen() {
    _cancelOpen();
    if (!widget.preserveFocus || widget.menuChildren.isEmpty) return;
    // Focus-disabled buttons cannot use Flutter's hover-to-focus opening.
    _hoverTimer = Timer(_hoverDelay, () {
      if (mounted && !widget.controller.isOpen) widget.controller.open();
    });
  }

  void _cancelOpen() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
  }

  bool _containsPointer(BuildContext context, Offset position) {
    final box = context.findRenderObject();
    return box is RenderBox &&
        box.hasSize &&
        MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        ).contains(position);
  }

  void _handlePointerEvent(PointerEvent event) {
    if (!widget.controller.isOpen ||
        event is PointerSignalEvent ||
        (event.kind != PointerDeviceKind.mouse &&
            event.kind != PointerDeviceKind.stylus) ||
        event.viewId != View.of(context).viewId) {
      return;
    }
    var inside =
        event is! PointerRemovedEvent &&
        _containsPointer(context, event.position);
    if (!inside && event is! PointerRemovedEvent) {
      // The Material surface includes padding around the child rows.
      _menuChildKey.currentContext?.visitAncestorElements((element) {
        if (element.widget is! Material) return true;
        inside = _containsPointer(element, event.position);
        return false;
      });
    }
    if (inside) {
      _cancelOpen();
    } else {
      _hoverTimer ??= Timer(const Duration(milliseconds: 400), () {
        widget.controller.close();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final openToRight = _openToRight ?? direction == TextDirection.ltr;
    final menuStyle =
        widget.menuStyle ??
        Theme.of(context).menuTheme.style ??
        const MenuStyle();
    final button = Directionality(
      textDirection: openToRight ? TextDirection.ltr : TextDirection.rtl,
      child: MouseRegion(
        onEnter: (_) => _scheduleOpen(),
        onExit: (_) {
          if (widget.preserveFocus) _cancelOpen();
        },
        child: SubmenuButton(
          controller: widget.controller,
          focusNode: _focusNode,
          hoverOpenDelay: _hoverDelay,
          onOpen: () {
            final side = _shouldOpenToRight();
            if (_openToRight != side) setState(() => _openToRight = side);
            _setTrackingPointer(!widget.preserveFocus);
            widget.onOpen?.call();
          },
          onClose: () {
            _cancelOpen();
            _setTrackingPointer(false);
            widget.onClose?.call();
          },
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          style:
              widget.style ??
              buildAppSubmenuItemStyle(
                context,
                widget.presentation.metrics,
                presentation: widget.presentation,
              ),
          menuStyle: menuStyle.copyWith(
            alignment: openToRight ? Alignment.topRight : Alignment.topLeft,
          ),
          menuChildren: [
            for (final (index, child) in widget.menuChildren.indexed)
              Directionality(
                key: index == 0 ? _menuChildKey : null,
                textDirection: direction,
                child: child,
              ),
          ],
          child: Directionality(
            textDirection: direction,
            child:
                widget.childBuilder?.call(context, openToRight) ?? widget.child,
          ),
        ),
      ),
    );
    return widget.preserveFocus
        ? FocusScope(
            skipTraversal: true,
            descendantsAreFocusable: false,
            child: button,
          )
        : button;
  }
}
