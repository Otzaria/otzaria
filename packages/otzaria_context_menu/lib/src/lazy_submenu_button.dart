part of 'context_menu_region.dart';

class _LazyAppSubmenuButton extends StatefulWidget {
  final AppContextMenuEntry entry;
  final List<AppContextMenuEntry> Function() entriesBuilder;
  final AppMenuMetrics metrics;
  final MenuPresentation presentation;
  final double maxWidth;
  final MenuStyle menuStyle;
  final MenuController? controller;
  final VoidCallback onControllerUnmounted;
  final VoidCallback? onOpen;
  final List<Widget> Function(
    List<AppContextMenuEntry> entries,
    double maxWidth,
    VoidCallback rebuildSubmenu,
  )
  buildChildren;

  const _LazyAppSubmenuButton({
    required this.presentation,
    super.key,
    required this.entry,
    required this.entriesBuilder,
    required this.metrics,
    required this.maxWidth,
    required this.menuStyle,
    required this.buildChildren,
    required this.onControllerUnmounted,
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
  StreamSubscription<Object?>? _refreshSubscription;
  MenuPresentation get presentation => widget.presentation;

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
    widget.onControllerUnmounted();
    super.dispose();
  }

  void _refreshChildren() {
    if (!mounted) return;
    _entries = null;
    _menuChildren = null;
    _hasEnabledChildren = null;
    _ensureMenuChildrenLoaded();
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
      _menuChildren = hasEnabledChildren
          ? widget.buildChildren(entries, widget.maxWidth, _refreshChildren)
          : const <Widget>[];
    });
  }

  @override
  void didUpdateWidget(_LazyAppSubmenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.onControllerUnmounted();
    }
    if (oldWidget.entry.childrenRefreshStream !=
        widget.entry.childrenRefreshStream) {
      _refreshSubscription?.cancel();
      _refreshSubscription = widget.entry.childrenRefreshStream?.listen(
        (_) => _refreshChildren(),
      );
    }
    if (oldWidget.entry != widget.entry ||
        oldWidget.presentation != widget.presentation ||
        oldWidget.maxWidth != widget.maxWidth) {
      _refreshChildren();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget row(BuildContext context, Widget? trailing, bool enabled) =>
        buildAppMenuRowContent(
          context,
          widget.metrics,
          presentation: presentation,
          maxWidth: widget.maxWidth - widget.metrics.itemPadding.horizontal,
          label: widget.entry.label ?? '',
          labelWidget: widget.entry.labelWidget,
          icon: widget.entry.icon,
          trailing: trailing,
          isDestructive: widget.entry.isDestructive,
          enabled: enabled,
        );
    if (_hasEnabledChildren == false) {
      return MenuItemButton(
        requestFocusOnHover: false,
        style: buildAppSubmenuItemStyle(
          context,
          widget.metrics,
          presentation: presentation,
        ),
        onPressed: null,
        child: row(context, widget.entry.trailing, false),
      );
    }
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => _ensureMenuChildrenLoaded(),
      child: AppSubmenuButton(
        controller: widget.controller!,
        presentation: presentation,
        maxWidth: widget.maxWidth,
        preserveFocus: true,
        menuStyle: widget.menuStyle,
        menuChildren: _menuChildren ?? const <Widget>[],
        onOpen: () {
          _ensureMenuChildrenLoaded();
          widget.onOpen?.call();
        },
        childBuilder: (context, openToRight) => row(
          context,
          widget.entry.trailing ??
              presentation.submenuArrowBuilder(
                context,
                openToRight,
                widget.metrics.iconSize,
                null,
              ),
          widget.entry.enabled,
        ),
        child: const SizedBox.shrink(),
      ),
    );
  }
}
