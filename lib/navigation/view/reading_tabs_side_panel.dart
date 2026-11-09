import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/navigation/view/tab_search_menu.dart';
import 'package:otzaria/navigation/view/vertical_reading_tab_strip.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

/// עמודת כרטיסיות קבועה מעל התוכן; ריחוף אינו משנה את המקום השמור לצדה.
class ReadingTabsSidePanel extends StatefulWidget {
  final bool show;
  final Widget child;

  const ReadingTabsSidePanel({
    super.key,
    required this.show,
    required this.child,
  });

  @override
  State<ReadingTabsSidePanel> createState() => _ReadingTabsSidePanelState();
}

class _ReadingTabsSidePanelState extends State<ReadingTabsSidePanel> {
  /// ערך חי מונע אובדן דלתאות באותו פריים; ההגדרה נשמרת רק בסיום גרירה.
  final ValueNotifier<double?> _draggingWidth = ValueNotifier(null);
  final Set<int> _pressedPointers = {};
  Timer? _hoverTimer;
  bool _hovered = false;
  bool _hoverExpanded = false;
  bool _everShown = false;

  @override
  void initState() {
    super.initState();
    _everShown = widget.show;
  }

  @override
  void didUpdateWidget(ReadingTabsSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !_everShown) _everShown = true;
    if (!widget.show) {
      _hoverTimer?.cancel();
      _hovered = false;
      _hoverExpanded = false;
      _pressedPointers.clear();
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _draggingWidth.dispose();
    super.dispose();
  }

  void _updateHover() {
    _hoverTimer?.cancel();
    if (!mounted || !widget.show || _pressedPointers.isNotEmpty) return;
    final expand =
        _hovered &&
        context.read<SettingsBloc>().state.readingTabsColumnCollapsed;
    if (_hoverExpanded == expand) return;
    _hoverTimer = Timer(AppTokens.animNormal, () {
      if (mounted) setState(() => _hoverExpanded = expand);
    });
  }

  void _onPointerReleased(PointerEvent event) {
    _pressedPointers.remove(event.pointer);
    _updateHover();
  }

  void _onDragStart(double current) => _draggingWidth.value = current;

  void _onDragDelta(double delta) {
    final current = _draggingWidth.value;
    if (current == null) return;
    // ב-RTL העמודה בימין והקצה הנגרר בשמאלה — גרירה שמאלה מרחיבה אותה.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final next = (current + (isRtl ? -delta : delta)).clamp(
      SettingsRepository.minReadingTabsColumnWidth,
      SettingsRepository.maxReadingTabsColumnWidth,
    );
    _draggingWidth.value = next.toDouble();
  }

  void _onDragEnd() {
    final width = _draggingWidth.value;
    if (width == null) return;
    context.read<SettingsBloc>().add(UpdateReadingTabsColumnWidth(width));
    _draggingWidth.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = context.select<SettingsBloc, bool>(
      (b) => b.state.readingTabsColumnCollapsed,
    );
    final savedWidth = context.select<SettingsBloc, double>(
      (b) => b.state.readingTabsColumnWidth,
    );

    return ValueListenableBuilder<double?>(
      valueListenable: _draggingWidth,
      child: widget.child,
      builder: (context, dragging, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final expandedWidth = (dragging ?? savedWidth).clamp(
              0.0,
              constraints.maxWidth,
            );
            final floating = collapsed && _hoverExpanded;
            final visuallyCollapsed = collapsed && !floating;
            final width = visuallyCollapsed
                ? kCollapsedTabsColumnWidth
                : expandedWidth;
            final reservedWidth = collapsed
                ? kCollapsedTabsColumnWidth
                : expandedWidth;
            final duration = dragging == null
                ? AppMotion.duration(context, AppTokens.animPanelSlide)
                : Duration.zero;

            return Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeInOut,
                      width: widget.show ? reservedWidth : 0,
                    ),
                    Expanded(child: child!),
                  ],
                ),
                // העמודה והתוכן נשארים באותם סלוטים גם בהסתרה ובנעיצה.
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !widget.show,
                    child: ExcludeFocus(
                      excluding: !widget.show,
                      child: ExcludeSemantics(
                        excluding: !widget.show,
                        child: MouseRegion(
                          onEnter: (event) {
                            if (event.kind != PointerDeviceKind.mouse) return;
                            _hovered = true;
                            _updateHover();
                          },
                          onExit: (event) {
                            if (event.kind != PointerDeviceKind.mouse) return;
                            _hovered = false;
                            _updateHover();
                          },
                          child: Listener(
                            onPointerDown: (event) {
                              _pressedPointers.add(event.pointer);
                              _hoverTimer?.cancel();
                            },
                            onPointerUp: _onPointerReleased,
                            onPointerCancel: _onPointerReleased,
                            child: AnimatedContainer(
                              duration: duration,
                              curve: Curves.easeInOut,
                              width: widget.show ? width : 0,
                              child: Material(
                                color: AppSurfaces.readerBackground(context),
                                elevation: floating ? AppTokens.elevation2 : 0,
                                child: ClipRect(
                                  child: OverflowBox(
                                    minWidth: width,
                                    maxWidth: width,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: _everShown
                                        ? _buildContent(
                                            context,
                                            width: width,
                                            collapsed: visuallyCollapsed,
                                            savedCollapsed: collapsed,
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ),
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
      },
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required double width,
    required bool collapsed,
    required bool savedCollapsed,
  }) {
    return SizedBox(
      width: width,
      // קו דק בקצה הפנימי מפריד בין העמודה לתוכן: שניהם ברקע הקריאה. מצויר
      // מעל ידית שינוי הרוחב, שיושבת באותו קצה.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: BorderDirectional(
            end: BorderSide(
              color:
                  AppSurfaces.regionBorder(context) ??
                  Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        // רקע הקריאה, כמו מאחורי הרצועה האופקית: הריחוף (8% onSurface) יוצא
        // אפור ונבדל מהכרטיסיה הפעילה שבצבע הסרגל (DD-06).
        child: ColoredBox(
          color: AppSurfaces.readerBackground(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context, collapsed: savedCollapsed),
                    const Divider(height: 1),
                    Expanded(
                      child: KeyedSubtree(
                        key: TourTargetKeys.of(context).readingTabsSide,
                        child: VerticalReadingTabStrip(
                          collapsed: collapsed,
                          width: width,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // במצב שמור מכווץ אין ידית גם בריחוף; הקו הוא של העמודה.
              // במצב מורחב הידית גלויה במנוחה כדי לסמן שאפשר לשנות רוחב.
              if (!savedCollapsed)
                ResizableDragHandle(
                  isVertical: true,
                  showDivider: false,
                  showIdleGrip: true,
                  onDragStart: () => _onDragStart(width),
                  onDragDelta: _onDragDelta,
                  onDragEnd: _onDragEnd,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required bool collapsed,
  }) {
    return ListenableBuilder(
      listenable: PluginNewTabPageRegistry.instance,
      builder: (context, _) {
        final buttons = [
          _buildCollapseButton(context, collapsed: collapsed),
          const TabSearchButton(),
          if (PluginNewTabPageRegistry.instance.hasActiveRegistration)
            AppIconButton(
              size: AppIconButtonSize.small,
              tooltip: context.settingsText('כרטיסייה חדשה'),
              icon: const Icon(FluentIcons.add_24_regular),
              onPressed: () => PluginNewTabPageRegistry.instance.open(
                windowKeys: AppWindowKeys.of(context),
                viewId: View.of(context).viewId,
              ),
            ),
        ];
        if (collapsed) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            // הכפתורים נשארים במקומם בריחוף, וכך גם הכרטיסיה שמתחת לסמן.
            children: [
              for (final button in buttons)
                SizedBox(
                  width: kCollapsedTabsColumnWidth,
                  child: Center(child: button),
                ),
            ],
          );
        }
        return SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: buttons,
          ),
        );
      },
    );
  }

  Widget _buildCollapseButton(BuildContext context, {required bool collapsed}) {
    return AppIconButton(
      size: AppIconButtonSize.small,
      tooltip: collapsed
          ? context.settingsText('הרחב את עמודת הכרטיסיות')
          : context.settingsText('כווץ את עמודת הכרטיסיות'),
      icon: RtlIcon(
        collapsed
            ? FluentIcons.panel_left_24_regular
            : FluentIcons.panel_right_24_regular,
      ),
      onPressed: () {
        if (!collapsed) {
          _hoverTimer?.cancel();
          _hovered = false;
          setState(() => _hoverExpanded = false);
        }
        context.read<SettingsBloc>().add(
          UpdateReadingTabsColumnCollapsed(!collapsed),
        );
      },
    );
  }
}
