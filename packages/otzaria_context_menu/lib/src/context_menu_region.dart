import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_metrics.dart';
import 'menu_models.dart';
import 'menu_placement.dart';
import 'menu_presentation.dart';
import 'menu_rows.dart';
import 'submenu_button.dart';

part 'context_menu_gestures.dart';
part 'context_menu_entries.dart';
part 'context_menu_rows.dart';
part 'lazy_submenu_button.dart';

/// פותח את תפריט ההקשר של האזור הקרוב ביותר לרכיב הממוקד (מקש Menu או
/// Shift+F10), כמקבילה למקלדת ללחיצה ימנית.
class _OpenContextMenuIntent extends Intent {
  const _OpenContextMenuIntent();
}

class ContextMenuRegion extends StatefulWidget {
  final MenuPresentation presentation;
  final MenuEscapeRegistrar registerEscape;
  final void Function(BuildContext context, Offset position)? onMenuOpening;
  final MenuPreviewWrapper? previewWrapper;
  final VoidCallback? onMenuClosed;
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

  /// האזור הזה (למשל שורה נבחרת בקורא) קודם לאחרים כשמקש התפריט נלחץ והפוקוס
  /// על רכיב שמעל כמה אזורים: נפתח האזור הנראה העליון מבין המועדפים, ורק אם
  /// אין אחד כזה (או שאינו נראה) האזור הנראה העליון מכולם.
  final bool keyboardPreferred;

  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.menuBuilder,
    required this.presentation,
    required this.registerEscape,
    this.onMenuOpening,
    this.previewWrapper,
    this.onMenuClosed,
    this.menuItemKeysByLabel,
    this.onSecondaryTapDown,
    this.onHoverEnter,
    this.shouldPreserveSelectionOnSecondaryTap,
    this.openOnLongPress = true,
    this.keyboardPreferred = false,
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

  // נקודת הנגיעה (בקואורדינטות ה-overlay) כשהתפריט נפתח באצבע; אחרת null.
  // התפריט נפתח לצד האצבע ולא מתחתיה, כדי שהיא לא תכסה את הפריטים.
  Offset? _fingerAnchor;

  // סוג ההתקן של הנגיעה האחרונה באזור: onLongPressStart לא מדווח אותו.
  PointerDeviceKind? _lastPointerKind;
  final GlobalKey _menuPanelKey = GlobalKey();
  Offset? _currentMenuOffset;
  double? _menuAnchorX;

  VoidCallback? _unregisterEscape;

  // תפריט שנפתח במקלדת מקבל פוקוס (חיצים/Enter) ומחזיר אותו לפותח בסגירה.
  // תפריט שנפתח בעכבר/מגע לא לוקח פוקוס, כדי לשמור את הבחירה בטקסט.
  FocusScopeNode? _menuFocusScope;
  FocusNode? _restoreFocusTo;
  bool _isDisposing = false;

  static const _keyboardShortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.contextMenu): _OpenContextMenuIntent(),
    SingleActivator(LogicalKeyboardKey.f10, shift: true):
        _OpenContextMenuIntent(),
  };

  late final Map<Type, Action<Intent>> _keyboardActions = {
    _OpenContextMenuIntent: CallbackAction<_OpenContextMenuIntent>(
      onInvoke: (_) {
        _openFromKeyboard();
        return null;
      },
    ),
  };

  MenuPresentation get presentation => widget.presentation;

  // אזורים מחוברים, לטיפול ב-Shift+F10/Menu כשהפוקוס יושב על רכיב שמעליהם
  // (למשל ה-Focus של הקורא כולו): Shortcuts שבתוך האזור לא רואה אז את המקש.
  static final Set<ContextMenuRegionState> _mountedRegions = {};

  @override
  void initState() {
    super.initState();
    if (_mountedRegions.isEmpty) {
      FocusManager.instance.addEarlyKeyEventHandler(_openFromAncestorFocus);
    }
    _mountedRegions.add(this);
  }

  /// מקש התפריט (Menu או Shift+F10) כשהפוקוס על צומת שהאזורים בתוכו, לא
  /// מעליו: פותח את האזור הנראה העליון בתוכו. כשהפוקוס בתוך אזור, או כשאין
  /// בתוכו אזור, לא עושה כלום ו-Shortcuts של האזור מטפל כרגיל.
  static KeyEventResult _openFromAncestorFocus(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final isMenuKey =
        event.logicalKey == LogicalKeyboardKey.contextMenu ||
        (event.logicalKey == LogicalKeyboardKey.f10 &&
            keyboard.isShiftPressed &&
            !keyboard.isControlPressed &&
            !keyboard.isAltPressed &&
            !keyboard.isMetaPressed);
    if (event is! KeyDownEvent || !isMenuKey) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    final focusContext = focused?.context;
    if (focused == null ||
        focused is FocusScopeNode ||
        focusContext == null ||
        !focusContext.mounted ||
        focusContext.findAncestorStateOfType<ContextMenuRegionState>() !=
            null) {
      return KeyEventResult.ignored;
    }
    final focusElement = focusContext as Element;
    ContextMenuRegionState? top;
    Rect? topRect;
    var topPreferred = false;
    for (final region in _mountedRegions) {
      if (!region.mounted ||
          !(ModalRoute.isCurrentOf(region.context) ?? true)) {
        continue;
      }
      var inside = false;
      region.context.visitAncestorElements((ancestor) {
        inside = identical(ancestor, focusElement);
        return !inside;
      });
      final rect = inside ? region._visibleRect(region.context) : null;
      if (rect == null || rect.isEmpty) continue;
      // מועדף (שורה נבחרת) קודם לכל לא-מועדף; בין שווים, העליון קודם.
      final preferred = region.widget.keyboardPreferred;
      final better = top == null
          ? true
          : preferred != topPreferred
          ? preferred
          : rect.top < topRect!.top ||
                (rect.top == topRect.top && rect.left < topRect.left);
      if (better) {
        top = region;
        topRect = rect;
        topPreferred = preferred;
      }
    }
    if (top == null) return KeyEventResult.ignored;
    top._openFromKeyboard(
      anchor: topRect!.center,
      restoreFocusTo: focused,
    );
    return KeyEventResult.handled;
  }

  /// החלק הנראה (בתוך ה-overlay) של [target], או null כשאינו נראה.
  Rect? _visibleRect(BuildContext target) {
    final overlayBox = Overlay.maybeOf(
      context,
      rootOverlay: true,
    )?.context.findRenderObject();
    final box = target.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        overlayBox is! RenderBox ||
        !overlayBox.hasSize) {
      return null;
    }
    final viewport = overlayBox.localToGlobal(Offset.zero) & overlayBox.size;
    final visible = (box.localToGlobal(Offset.zero) & box.size).intersect(
      viewport,
    );
    return visible.width < 0 || visible.height < 0 ? null : visible;
  }

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

  @visibleForTesting
  int get debugTrackedSubmenuControllerCount => _submenuControllers.length;

  @override
  void dispose() {
    _isDisposing = true;
    _mountedRegions.remove(this);
    if (_mountedRegions.isEmpty) {
      FocusManager.instance.removeEarlyKeyEventHandler(_openFromAncestorFocus);
    }
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
    final hadOpenMenu = _menuOverlayEntry != null;
    _unregisterEscape?.call();
    _unregisterEscape = null;
    _submenuControllers.clear();
    final overlayEntry = _menuOverlayEntry;
    _menuOverlayEntry = null;
    // OverlayEntry is a Listenable; removing it from the overlay does not
    // dispose the entry or its listeners.
    overlayEntry?.remove();
    overlayEntry?.dispose();
    _currentMenuOffset = null;
    _menuAnchorX = null;
    _fingerAnchor = null;
    _isMenuVisible = false;
    _releaseMenuFocus();
    if (hadOpenMenu) widget.onMenuClosed?.call();
  }

  void _releaseMenuFocus() {
    final scope = _menuFocusScope;
    final restoreTo = _isDisposing ? null : _restoreFocusTo;
    _menuFocusScope = null;
    _restoreFocusTo = null;
    if (scope == null) return;
    // רק אחרי שהפריים הסיר את התפריט מהעץ: צמתי פוקוס לא נפטרים כשעדיין מחוברים.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scope.dispose();
      _restoreFocus(restoreTo);
    });
  }

  void _restoreFocus(FocusNode? target) {
    final targetContext = target?.context;
    if (target == null ||
        targetContext == null ||
        // פעולה בתפריט יכולה להסיר את הפותח מהעץ (סגירת כרטיסייה, מחיקת הערה).
        !targetContext.mounted ||
        !target.canRequestFocus ||
        target.hasPrimaryFocus) {
      return;
    }
    // פעולה בתפריט שפתחה דיאלוג/מסך או העבירה פוקוס בעצמה גוברת על ההחזרה.
    if (!(ModalRoute.isCurrentOf(targetContext) ?? true)) return;
    final current = FocusManager.instance.primaryFocus;
    if (current != null && current is! FocusScopeNode) return;
    target.requestFocus();
  }

  void _focusFirstMenuItem() {
    final scope = _menuFocusScope;
    if (!mounted || !_isMenuOpen || scope == null) return;
    final scopeContext = scope.context;
    if (scopeContext == null) return;
    final policy =
        FocusTraversalGroup.maybeOf(scopeContext) ??
        ReadingOrderTraversalPolicy();
    (policy.findFirstFocus(scope) ?? scope).requestFocus();
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

  /// פותח את התפריט ב-[globalPosition]. [kind] הוא סוג המצביע שגרם לפתיחה:
  /// במגע התפריט נפתח לצד האצבע ולא מתחתיה.
  Future<void> openMenuAt(Offset globalPosition, {PointerDeviceKind? kind}) =>
      _openContextMenu(globalPosition, kind: kind);

  /// פתיחה במקלדת: התפריט נפתח ליד הרכיב הממוקד (בקצה ההתחלה שלו לפי
  /// כיוון הקריאה), מקבל פוקוס, וסגירתו מחזירה את הפוקוס לרכיב. כמו בלחיצה
  /// ימנית, [ContextMenuRegion.onSecondaryTapDown] נקרא עם נקודת העוגן, כי
  /// אתרים מכינים בו את הקשר התפריט (השורה, הבחירה).
  ///
  /// [anchor] ו-[restoreFocusTo] נקבעים כשהפוקוס על רכיב שמעל האזור, ולא
  /// בתוכו.
  Future<void> _openFromKeyboard({
    Offset? anchor,
    FocusNode? restoreFocusTo,
  }) async {
    final regionBox = context.findRenderObject();
    if (regionBox is! RenderBox || !regionBox.hasSize) return;
    final focused = restoreFocusTo ?? FocusManager.instance.primaryFocus;
    var position = anchor;
    if (position == null) {
      var target = _visibleRect(focused?.context ?? context) ?? Rect.zero;
      if (target.isEmpty) target = _visibleRect(context) ?? Rect.zero;
      if (target.isEmpty) return;
      final isRtl = Directionality.of(context) == TextDirection.rtl;
      position = Offset(isRtl ? target.right : target.left, target.bottom);
    }
    widget.onSecondaryTapDown?.call(
      TapDownDetails(
        globalPosition: position,
        localPosition: regionBox.globalToLocal(position),
      ),
    );
    await _openContextMenu(position, restoreFocusTo: focused);
  }

  double _resolveContextMenuMaxWidth(double overlayWidth) {
    // On very narrow windows, the available viewport takes precedence over
    // the normal menu minimum. Do not render a menu wider than its overlay.
    final availableWidth = overlayWidth - (_contextMenuScreenPadding * 2);
    return availableWidth.clamp(0.0, _contextMenuMaxWidth).toDouble();
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
              (entry.deferredEntry != null
                  ? 0
                  : entry.isDivider
                  ? metrics.dividerHeight
                  // שורת אייקונים גבוהה מפריט רגיל (אייקון + כיתוב + ריפודים).
                  : entry.iconRowActions != null
                  ? metrics.iconSize + 28
                  : metrics.itemHeight),
        ) +
        8;
    if (_fingerAnchor != null) {
      // הרוחב עוד לא ידוע (התפריט נמדד אחרי הבנייה הראשונה) — מעריכים במקסימום.
      final placement = placeMenuAwayFromFinger(
        overlay: overlayRenderBox.size,
        anchor: overlayPosition,
        panel: Size(
          _resolveContextMenuMaxWidth(overlayRenderBox.size.width),
          estimatedHeight,
        ),
        isRtl: Directionality.of(context) == TextDirection.rtl,
        screenPadding: _contextMenuScreenPadding,
      );
      return (
        placement.topLeft,
        placement.side == TouchMenuSide.above ||
            (placement.side == TouchMenuSide.fallback &&
                placement.topLeft.dy < overlayPosition.dy),
      );
    }
    final spaceAbove = overlayPosition.dy;
    final spaceBelow = overlayRenderBox.size.height - overlayPosition.dy;
    final shouldOpenAbove =
        spaceBelow < estimatedHeight && spaceAbove > spaceBelow;
    final maxAnchorX = (overlayRenderBox.size.width - _contextMenuScreenPadding)
        .clamp(_contextMenuScreenPadding, double.infinity)
        .toDouble();
    final dx = overlayPosition.dx
        .clamp(_contextMenuScreenPadding, maxAnchorX)
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
    final finger = _fingerAnchor;
    if (finger != null) {
      _currentMenuOffset = placeMenuAwayFromFinger(
        overlay: overlaySize,
        anchor: finger,
        panel: panelSize,
        isRtl: Directionality.of(context) == TextDirection.rtl,
        screenPadding: _contextMenuScreenPadding,
      ).topLeft;
      _isMenuVisible = true;
      _menuOverlayEntry?.markNeedsBuild();
      return;
    }
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
    FocusNode? restoreFocusTo,
    PointerDeviceKind? kind,
  }) async {
    final entries = _normalizeEntries(
      widget.menuBuilder(context, globalPosition),
    );
    if (entries.isEmpty) return;
    _menuOpenedForEvent = trigger;

    // Release old menu resources before capturing the new scroll anchor.
    _removeContextMenuOverlay();
    widget.onMenuOpening?.call(context, globalPosition);

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayRenderObject = overlay.context.findRenderObject();
    if (overlayRenderObject is! RenderBox || !overlayRenderObject.hasSize) {
      return;
    }

    final overlayPosition = overlayRenderObject.globalToLocal(globalPosition);
    if (!overlayPosition.dx.isFinite || !overlayPosition.dy.isFinite) return;
    final focusScope = restoreFocusTo == null
        ? null
        : FocusScopeNode(debugLabel: 'ContextMenu');
    _menuFocusScope = focusScope;
    _restoreFocusTo = restoreFocusTo;
    _menuAnchorX = overlayPosition.dx;
    _fingerAnchor = kind == PointerDeviceKind.touch ? overlayPosition : null;
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

    _currentMenuOffset = menuOffset;
    _submenuControllers.addAll({
      for (final controller in submenuControllers.values) controller: 0,
      for (final controllers in iconRowControllers.values)
        for (final controller in controllers) controller: 0,
    });

    _menuOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final metrics = presentation.metrics;
        final menuStyle = _menuStyle(context);
        final maxMenuWidth = _resolveContextMenuMaxWidth(
          overlayRenderObject.size.width,
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
                          focusScopeNode: focusScope,
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
      if (focusScope != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _focusFirstMenuItem(),
        );
      }
    });
  }

  MenuStyle _menuStyle(BuildContext context) {
    final themeStyle = Theme.of(context).menuTheme.style;
    return (themeStyle ?? const MenuStyle()).copyWith(
      alignment: Alignment.topLeft,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _keyboardShortcuts,
      child: Actions(actions: _keyboardActions, child: _buildGestures()),
    );
  }

  Widget _buildGestures() {
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
          ? (details) => _openContextMenu(
              details.globalPosition,
              kind: _lastPointerKind,
            )
          : null,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          // recognizer שזוכה באופן מיידי בכפתור הימני כשיש בחירה פעילה, כדי
          // למנוע מ-SelectableRegion לשחרר את הבחירה.
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
                    onOpenMenu: (position, kind) =>
                        _openContextMenu(position, kind: kind),
                    startScroll: _startPreservedSelectionScroll,
                  ),
                  (instance) {},
                ),
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _lastPointerKind = event.kind;
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
