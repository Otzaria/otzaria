import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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

/// עמודת כרטיסיות העיון שבין סרגל הניווט לתוכן המסך.
///
/// חייבת להישאר ילד קבוע ב-Row של המסך הראשי: היעלמות מהעץ בונה מחדש את
/// ה-PageView ומאבדת את ה-State של הכרטיסיות. לכן ההסתרה היא רוחב מונפש ל-0.
class ReadingTabsSidePanel extends StatefulWidget {
  final bool show;

  const ReadingTabsSidePanel({super.key, required this.show});

  @override
  State<ReadingTabsSidePanel> createState() => _ReadingTabsSidePanelState();
}

class _ReadingTabsSidePanelState extends State<ReadingTabsSidePanel> {
  /// הרוחב בזמן גרירה בלבד — האירוע ל-Bloc נשלח רק בסופה, כדי לא לשמור
  /// בהגדרות בכל תזוזת מצביע.
  ///
  /// [ValueNotifier] ולא שדה שנקרא ב-build: שני אירועי תזוזה באותו פריים קוראים
  /// את הערך המעודכן, אחרת הדלתא הראשונה נמחקת והעמודה מפגרת אחרי הסמן.
  final ValueNotifier<double?> _draggingWidth = ValueNotifier(null);

  /// לא בונים את תוכן העמודה לפני שהוצגה לראשונה.
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
  }

  @override
  void dispose() {
    _draggingWidth.dispose();
    super.dispose();
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
      builder: (context, dragging, _) {
        final width = collapsed
            ? kCollapsedTabsColumnWidth
            : (dragging ?? savedWidth);

        return AnimatedContainer(
          // בזמן גרירת הידית הרוחב עוקב אחרי הסמן מיידית; ההנפשה שמורה
          // להצגה/הסתרה ולכיווץ.
          duration: dragging == null ? AppTokens.animPanelSlide : Duration.zero,
          curve: Curves.easeInOut,
          width: widget.show ? width : 0,
          child: ClipRect(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: width,
              alignment: AlignmentDirectional.centerStart,
              child: _everShown
                  ? _buildContent(context, width: width, collapsed: collapsed)
                  : const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required double width,
    required bool collapsed,
  }) {
    return SizedBox(
      width: width,
      child: ColoredBox(
        color: AppSurfaces.panelBackground(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  _buildHeader(context, collapsed: collapsed),
                  const Divider(height: 1),
                  Expanded(
                    child: KeyedSubtree(
                      key: tourReadingTabsSideTargetKey,
                      child: VerticalReadingTabStrip(
                        collapsed: collapsed,
                        width: width,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ידית שינוי הרוחב יושבת בקצה הפנימי (שמאל ב-RTL). במצב מכווץ
            // הרוחב קבוע, ולכן הידית אינה נבנית כלל — אחרת היא גוזלת מרוחב
            // העמודה הצרה ומזיזה את האייקונים מהמרכז.
            if (!collapsed)
              ResizableDragHandle(
                isVertical: true,
                showDivider: true,
                onDragStart: () => _onDragStart(width),
                onDragDelta: _onDragDelta,
                onDragEnd: _onDragEnd,
              ),
          ],
        ),
      ),
    );
  }

  /// שורת הכפתורים שבראש העמודה. במצב מכווץ אין מקום לשני כפתורים זה לצד זה,
  /// ולכן הם נערמים זה מעל זה — וחיפוש הכרטיסיות נשאר נגיש.
  Widget _buildHeader(BuildContext context, {required bool collapsed}) {
    final buttons = [
      _buildCollapseButton(context, collapsed: collapsed),
      const TabSearchButton(),
    ];

    if (collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final button in buttons) Center(child: button)],
      );
    }

    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: buttons,
      ),
    );
  }

  Widget _buildCollapseButton(BuildContext context, {required bool collapsed}) {
    return IconButton(
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      tooltip: collapsed
          ? context.settingsText('הרחב את עמודת הכרטיסיות')
          : context.settingsText('כווץ את עמודת הכרטיסיות'),
      icon: RtlIcon(
        collapsed
            ? FluentIcons.panel_left_24_regular
            : FluentIcons.panel_right_24_regular,
      ),
      onPressed: () => context.read<SettingsBloc>().add(
        UpdateReadingTabsColumnCollapsed(!collapsed),
      ),
    );
  }
}
