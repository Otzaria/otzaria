// lib/tools/calendar/widgets/calendar_top_bar.dart
//
// סרגל עליון ללוח השנה — מבוסס AppTopBar.
//
// פריסה — מסך רחב (RTL):
// ┌──────────────────────────────────────────────────────────────────────┐
// │ [שבוע|חודש]  ║  [← תאריך קבוע →  היום  📅]  ║  [⏰][📋][⚙️] ║ [🖨️] │
// └──────────────────────────────────────────────────────────────────────┘
//
// פריסה — מסך צר (שורה שניה):
// שורה 1: [← תאריך קבוע →]
// שורה 2: [שבוע|חודש | היום | 📅 | 🖨️ | ⏰ | 📋 | ⚙️]
//
// החיצים ותאריך תמיד בשורה עליונה, במיקום קבוע שלא זז עם שינוי אורך התאריך.

import 'dart:math' as math;
import 'package:otzaria/theme/app_tokens.dart';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/dialogs/jump_to_date_dialog.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_date_picker_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

// הרוחב שמתחתיו עוברים לשורה שנייה
const double _kTopBarNarrowBreakpoint = 540.0;
const double _kTopBarMediumBreakpoint = 860.0;
const double _kMonthDateAreaWidth = 252.0;
const double _kWeekDateAreaWidth = 344.0;
const double _kMonthDateNavGap = 20.0;
const double _kWeekDateNavGap = 12.0;

class CalendarTopBar extends StatefulWidget {
  final CalendarState state;
  final VoidCallback onJumpToToday;
  final VoidCallback onPreviousPeriod;
  final VoidCallback onNextPeriod;
  final ValueChanged<CalendarView> onViewChanged;
  final CalendarSidePanelView activeSidePanelView;
  final bool isSidePanelVisible;
  final bool isSettingsPanelOpen;
  final VoidCallback onToggleTimesPanel;
  final VoidCallback onToggleEventsPanel;
  final VoidCallback onToggleSettingsPanel;
  final VoidCallback onPrint;
  final VoidCallback onToggleSidebar;
  final bool isJumpToDateSearchOpen;
  final VoidCallback onToggleJumpToDateSearch;
  final VoidCallback onCloseJumpToDateSearch;
  final DateTime? Function(String input) parseInputDate;
  final ValueChanged<DateTime> onJumpToDateSelected;

  const CalendarTopBar({
    super.key,
    required this.state,
    required this.onJumpToToday,
    required this.onPreviousPeriod,
    required this.onNextPeriod,
    required this.onViewChanged,
    required this.activeSidePanelView,
    required this.isSidePanelVisible,
    required this.isSettingsPanelOpen,
    required this.onToggleTimesPanel,
    required this.onToggleEventsPanel,
    required this.onToggleSettingsPanel,
    required this.onPrint,
    required this.onToggleSidebar,
    required this.isJumpToDateSearchOpen,
    required this.onToggleJumpToDateSearch,
    required this.onCloseJumpToDateSearch,
    required this.parseInputDate,
    required this.onJumpToDateSelected,
  });

  @override
  State<CalendarTopBar> createState() => _CalendarTopBarState();
}

class _CalendarTopBarState extends State<CalendarTopBar>
    with WidgetsBindingObserver {
  late final TextEditingController _jumpDateController;
  late final FocusNode _jumpDateFocusNode;
  late final FocusNode _dialogFocusNode;
  late DateTime _pendingJumpDate;
  bool _jumpShowHebrew = true;
  final GlobalKey _jumpSearchBarKey = GlobalKey();
  final OverlayPortalController _overlayPortalController =
      OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _jumpDateController = TextEditingController();
    _jumpDateFocusNode = FocusNode(debugLabel: 'calendarJumpDateSearch');
    _dialogFocusNode = FocusNode(debugLabel: 'calendarJumpDateDialog');
    _pendingJumpDate = widget.state.selectedGregorianDate;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // סגירה רק בהעברה אמיתית לרקע (paused). inactive/hidden נשלחים גם כשהחלון
    // מאבד פוקוס ל-OS — ואז החיפוש צריך להישאר פתוח, כמו כל דיאלוג.
    if (state == AppLifecycleState.paused && widget.isJumpToDateSearchOpen) {
      widget.onCloseJumpToDateSearch();
    }
  }

  @override
  void didUpdateWidget(covariant CalendarTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isJumpToDateSearchOpen && widget.isJumpToDateSearchOpen) {
      _prepareJumpDateSearch();
      // show() נדחה ל-postFrameCallback כדי לוודא שה-layout של שדה החיפוש
      // הסתיים לפני ש-_buildDialogOverlay מנסה לקרוא localToGlobal.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _overlayPortalController.show();
        _jumpDateFocusNode.requestFocus();
      });
    }
    if (oldWidget.isJumpToDateSearchOpen && !widget.isJumpToDateSearchOpen) {
      // hide() נדחה ל-postFrameCallback כדי להימנע מקריאת setState
      // על ה-OverlayPortal בזמן שה-build frame עדיין פעיל.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_overlayPortalController.isShowing) {
          _overlayPortalController.hide();
        }
      });
    }
    if (oldWidget.state.selectedGregorianDate !=
            widget.state.selectedGregorianDate &&
        !widget.isJumpToDateSearchOpen) {
      _pendingJumpDate = widget.state.selectedGregorianDate;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _jumpDateController.dispose();
    _jumpDateFocusNode.dispose();
    _dialogFocusNode.dispose();
    super.dispose();
  }

  String _formatWeekHebrewRange(CalendarState state) {
    final selected = state.selectedGregorianDate;
    final weekStart = selected.subtract(Duration(days: selected.weekday % 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final startJewish = JewishDate.fromDateTime(weekStart);
    final endJewish = JewishDate.fromDateTime(weekEnd);

    final sameHebrewMonth =
        startJewish.getJewishMonth() == endJewish.getJewishMonth() &&
        startJewish.getJewishYear() == endJewish.getJewishYear();

    if (sameHebrewMonth) {
      return '${formatHebrewDay(startJewish.getJewishDayOfMonth())}-${formatHebrewDay(endJewish.getJewishDayOfMonth())} '
          '${getHebrewMonthNameFor(startJewish)} '
          '${numberToHebrewWithoutQuotes(startJewish.getJewishYear())}';
    }

    return '${formatHebrewDay(startJewish.getJewishDayOfMonth())} ${getHebrewMonthNameFor(startJewish)} '
        '${numberToHebrewWithoutQuotes(startJewish.getJewishYear())}'
        ' - '
        '${formatHebrewDay(endJewish.getJewishDayOfMonth())} ${getHebrewMonthNameFor(endJewish)} '
        '${numberToHebrewWithoutQuotes(endJewish.getJewishYear())}';
  }

  String _formatWeekGregorianRange(CalendarState state) {
    final selected = state.selectedGregorianDate;
    final weekStart = selected.subtract(Duration(days: selected.weekday % 7));
    final weekEnd = weekStart.add(const Duration(days: 6));

    final sameGregorianMonth =
        weekStart.month == weekEnd.month && weekStart.year == weekEnd.year;

    if (sameGregorianMonth) {
      return '${weekStart.day}-${weekEnd.day} ${getGregorianMonthName(weekStart.month)} ${weekStart.year}';
    }

    return '${weekStart.day} ${getGregorianMonthName(weekStart.month)} ${weekStart.year}'
        ' - '
        '${weekEnd.day} ${getGregorianMonthName(weekEnd.month)} ${weekEnd.year}';
  }

  Widget _buildDateText(BuildContext context) {
    final s = widget.state;
    final showOhrPrefix =
        s.calendarView != CalendarView.week &&
        shouldShowOhrPrefixForCalendarHeader(state: s);
    final heb = s.calendarView == CalendarView.week
        ? _formatWeekHebrewRange(s)
        : '${showOhrPrefix ? 'אור ל' : ''}${formatHebrewDay(s.selectedJewishDate.getJewishDayOfMonth())} '
              '${getHebrewMonthNameFor(s.selectedJewishDate)} '
              '${numberToHebrewWithoutQuotes(s.selectedJewishDate.getJewishYear())}';
    final greg = s.calendarView == CalendarView.week
        ? _formatWeekGregorianRange(s)
        : '${s.selectedGregorianDate.day} ${getGregorianMonthName(s.selectedGregorianDate.month)} ${s.selectedGregorianDate.year}';

    final defaultStyle = Theme.of(context).textTheme.bodyMedium!;
    final baseStyle = s.calendarView == CalendarView.week
        ? defaultStyle.copyWith(
            fontSize: ((defaultStyle.fontSize ?? 14) - 1).clamp(12.0, 14.0),
          )
        : defaultStyle;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: RichText(
        overflow: TextOverflow.visible,
        maxLines: 1,
        text: TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text: heb,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const TextSpan(text: '  •  '),
            TextSpan(
              text: greg,
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }

  String _formatInputDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _buildCurrentDateHint() {
    final s = widget.state;
    final heb = s.calendarView == CalendarView.week
        ? _formatWeekHebrewRange(s)
        : '${formatHebrewDay(s.selectedJewishDate.getJewishDayOfMonth())} '
              '${getHebrewMonthNameFor(s.selectedJewishDate)} '
              '${numberToHebrewWithoutQuotes(s.selectedJewishDate.getJewishYear())}';
    final greg = s.calendarView == CalendarView.week
        ? _formatWeekGregorianRange(s)
        : '${s.selectedGregorianDate.day} ${getGregorianMonthName(s.selectedGregorianDate.month)} ${s.selectedGregorianDate.year}';
    return '$heb • $greg';
  }

  void _prepareJumpDateSearch() {
    _pendingJumpDate = clampJumpToDate(widget.state.selectedGregorianDate);
    _jumpShowHebrew = calendarDefaultShowHebrew(widget.state.calendarType);
    _jumpDateController.clear();
  }

  void _handleJumpDateChanged(String value) {
    final input = value.trim();
    if (input.isEmpty) {
      setState(() {
        _pendingJumpDate = widget.state.selectedGregorianDate;
      });
      return;
    }
    final result = widget.parseInputDate(input);
    if (result == null) return;
    setState(() {
      _pendingJumpDate = clampJumpToDate(result);
    });
  }

  void _refocusSearchWithSelection() {
    _jumpDateFocusNode.requestFocus();
    _jumpDateController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _jumpDateController.text.length,
    );
  }

  void _submitJumpDateSearch() {
    final input = _jumpDateController.text.trim();
    final result = input.isEmpty
        ? _pendingJumpDate
        : widget.parseInputDate(input);
    if (result == null) {
      UiSnack.showError(ToolsMessages.dateParseFailed);
      _refocusSearchWithSelection();
      return;
    }
    if (!isJumpToDateInRange(result)) {
      UiSnack.showError(ToolsMessages.dateOutOfRange);
      _refocusSearchWithSelection();
      return;
    }
    widget.onCloseJumpToDateSearch();
    widget.onJumpToDateSelected(result);
  }

  void _focusDialog() {
    FocusManager.instance.primaryFocus?.unfocus();
    _dialogFocusNode.requestFocus();
  }

  void _movePendingDateByDays(int days) {
    setState(() {
      _pendingJumpDate = clampJumpToDate(
        _pendingJumpDate.add(Duration(days: days)),
      );
      _jumpDateController.text = _formatInputDate(_pendingJumpDate);
    });
  }

  KeyEventResult _handleDialogKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.onCloseJumpToDateSearch();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submitJumpDateSearch();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _movePendingDateByDays(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _movePendingDateByDays(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _movePendingDateByDays(-7);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _movePendingDateByDays(7);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ── Overlay dialog ────────────────────────────────────────────────────────

  Widget _buildDialogOverlay(BuildContext overlayCtx) {
    final anchorBox =
        _jumpSearchBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchorBox == null || !anchorBox.hasSize) return const SizedBox.shrink();

    // קואורדינטות גלובליות (ה-Overlay בד"כ מכסה כל המסך)
    final anchorOffset = anchorBox.localToGlobal(Offset.zero);
    final anchorSize = anchorBox.size;
    final screenSize = MediaQuery.sizeOf(context);
    // תיקון narrow screen: הבטח שהגבול העליון של clamp לא יהיה קטן מהתחתון
    final maxAllowedWidth = math.max(1.0, screenSize.width - 32.0);
    final safeDialogWidth = math.min(
      anchorSize.width.clamp(320.0, 420.0),
      maxAllowedWidth,
    );
    final rawLeft = anchorOffset.dx + anchorSize.width - safeDialogWidth;
    final maxLeft = math.max(16.0, screenSize.width - safeDialogWidth - 16.0);
    final dialogLeft = rawLeft.clamp(16.0, maxLeft);
    final dialogTop = anchorOffset.dy + anchorSize.height + 4;
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Barrier — translucent: מזהה את ה-tap (לסגירה) אך מאפשר
        // לאירועים לעבור דרכו גם לוידג'טים שמתחת (כגון לוח השנה).
        Positioned(
          top: anchorOffset.dy + anchorSize.height,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onCloseJumpToDateSearch,
          ),
        ),
        // הדיאלוג — עטוף ב-Focus+CallbackShortcuts לקיצורי מקלדת
        Positioned(
          left: dialogLeft,
          top: dialogTop,
          width: safeDialogWidth,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape):
                  widget.onCloseJumpToDateSearch,
              const SingleActivator(LogicalKeyboardKey.enter):
                  _submitJumpDateSearch,
            },
            child: Focus(
              focusNode: _dialogFocusNode,
              onKeyEvent: _handleDialogKeyEvent,
              child: Material(
                elevation: 8,
                shadowColor: cs.shadow,
                borderRadius: AppTokens.borderRadiusAll,
                color: cs.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'מעבר לתאריך',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            CalendarTypeToggleButton(
                              showHebrew: _jumpShowHebrew,
                              onPressed: () => setState(
                                () => _jumpShowHebrew = !_jumpShowHebrew,
                              ),
                            ),
                          ],
                        ),
                      ),
                      JumpToDatePanel(
                        selectedDate: _pendingJumpDate,
                        currentDate: widget.state.selectedGregorianDate,
                        showHebrew: _jumpShowHebrew,
                        onDateChanged: (date) {
                          setState(() {
                            _pendingJumpDate = date;
                            _jumpDateController.text = _formatInputDate(date);
                          });
                        },
                        onCancel: widget.onCloseJumpToDateSearch,
                        onConfirm: _submitJumpDateSearch,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// עוטף פעולה כך שאם החיפוש פתוח — יסגר לפני הפעולה
  VoidCallback _withClose(VoidCallback action) {
    if (!widget.isJumpToDateSearchOpen) return action;
    return () {
      widget.onCloseJumpToDateSearch();
      action();
    };
  }

  Widget _buildInlineSearchField(
    BuildContext context, {
    required double width,
  }) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            widget.onCloseJumpToDateSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            widget.onCloseJumpToDateSearch,
      },
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _focusDialog();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          key: _jumpSearchBarKey,
          width: width,
          child: OtzariaSearchField(
            controller: _jumpDateController,
            focusNode: _jumpDateFocusNode,
            autofocus: true,
            slim: context.read<SettingsBloc>().state.compactMenuMode,
            hintText: _buildCurrentDateHint(),
            onChanged: _handleJumpDateChanged,
            onSubmitted: (_) => _submitJumpDateSearch(),
            onClear: () {
              _handleJumpDateChanged('');
              _jumpDateFocusNode.requestFocus();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSyncStatus(BuildContext context) {
    final state = widget.state;
    if (!state.googleCalendarEnabled) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final isSyncing = state.googleCalendarSyncInProgress;
    final hasError =
        state.googleCalendarSyncError != null &&
        state.googleCalendarSyncError!.isNotEmpty;

    final backgroundColor = hasError
        ? scheme.errorContainer.withValues(alpha: 0.75)
        : isSyncing
        ? scheme.primaryContainer.withValues(alpha: 0.75)
        : scheme.secondaryContainer.withValues(alpha: 0.55);
    final foregroundColor = hasError
        ? scheme.onErrorContainer
        : isSyncing
        ? scheme.onPrimaryContainer
        : scheme.onSecondaryContainer;

    final tooltip = hasError
        ? state.googleCalendarSyncError!
        : isSyncing
        ? 'סנכרון Google פעיל'
        : state.googleCalendarConnected
        ? 'Google Calendar מחובר'
        : 'Google Calendar מופעל אך לא מחובר';

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppTokens.borderRadiusAll,
            border: Border.all(
              color: foregroundColor.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSyncing)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
              else
                Icon(
                  hasError
                      ? FluentIcons.warning_24_regular
                      : state.googleCalendarConnected
                      ? FluentIcons.arrow_sync_circle_24_filled
                      : FluentIcons.arrow_sync_24_regular,
                  size: 14,
                  color: foregroundColor,
                ),
              const SizedBox(width: 6),
              Text(
                isSyncing ? 'מסנכרן' : (hasError ? 'שגיאת סנכרון' : 'Google'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return OverlayPortal(
      controller: _overlayPortalController,
      overlayChildBuilder: _buildDialogOverlay,
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          final isCompact = settingsState.compactMenuMode;

          // ── כפתורים משותפים ───────────────────────────────────────────────
          final prevBtn = BarButton.icon(
            compact: isCompact,
            tooltip: 'קודם',
            icon: FluentIcons.chevron_left_24_regular,
            onPressed: _withClose(widget.onPreviousPeriod),
          );
          final nextBtn = BarButton.icon(
            compact: isCompact,
            tooltip: 'הבא',
            icon: FluentIcons.chevron_right_24_regular,
            onPressed: _withClose(widget.onNextPeriod),
          );
          final todayBtn = BarButton.text(
            text: 'היום',
            icon: FluentIcons.calendar_today_24_regular,
            onPressed: _withClose(widget.onJumpToToday),
          );
          // כשהחיפוש פתוח — כפתור ה-jump הופך לכפתור סגירה עם אייקון X
          final jumpBtn = BarButton.icon(
            compact: isCompact,
            tooltip: widget.isJumpToDateSearchOpen
                ? 'סגור מעבר לתאריך'
                : 'מעבר לתאריך',
            icon: widget.isJumpToDateSearchOpen
                ? FluentIcons.dismiss_24_regular
                : FluentIcons.calendar_search_20_regular,
            iconWidget: widget.isJumpToDateSearchOpen
                ? Icon(
                    FluentIcons.dismiss_24_regular,
                    size: isCompact ? 16 : 20,
                  )
                : Icon(
                    FluentIcons.calendar_search_20_regular,
                    size: isCompact ? 16 : 20,
                  ),
            selected: widget.isJumpToDateSearchOpen,
            onPressed: widget.onToggleJumpToDateSearch,
          );
          final settingsBtn = BarButton.icon(
            compact: isCompact,
            tooltip: 'הגדרות לוח שנה',
            icon: widget.isSettingsPanelOpen
                ? FluentIcons.settings_24_filled
                : FluentIcons.settings_24_regular,
            selected: widget.isSettingsPanelOpen,
            onPressed: _withClose(widget.onToggleSettingsPanel),
          );
          final eventsBtn = BarButton.icon(
            compact: isCompact,
            tooltip: 'אירועים',
            icon:
                widget.isSidePanelVisible &&
                    widget.activeSidePanelView == CalendarSidePanelView.events
                ? FluentIcons.task_list_square_rtl_24_filled
                : FluentIcons.task_list_square_rtl_24_regular,
            selected:
                widget.isSidePanelVisible &&
                widget.activeSidePanelView == CalendarSidePanelView.events,
            onPressed: _withClose(widget.onToggleEventsPanel),
          );
          final timesBtn = BarButton.icon(
            compact: isCompact,
            tooltip: 'זמנים',
            icon:
                widget.isSidePanelVisible &&
                    widget.activeSidePanelView == CalendarSidePanelView.times
                ? FluentIcons.clock_24_filled
                : FluentIcons.clock_24_regular,
            selected:
                widget.isSidePanelVisible &&
                widget.activeSidePanelView == CalendarSidePanelView.times,
            onPressed: _withClose(widget.onToggleTimesPanel),
          );
          final printBtn = BarButton.icon(
            compact: isCompact,
            tooltip: 'הדפסה',
            icon: FluentIcons.print_24_regular,
            onPressed: _withClose(widget.onPrint),
          );
          final viewSwitcher = _buildViewSwitcher(state);
          final trailingActions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGoogleSyncStatus(context),
              printBtn,
              _buildTopBarDivider(context, isCompact),
              timesBtn,
              eventsBtn,
              _buildTopBarDivider(context, isCompact),
              settingsBtn,
            ],
          );
          final dateAreaWidth = state.calendarView == CalendarView.week
              ? _kWeekDateAreaWidth
              : _kMonthDateAreaWidth;
          final dateNavGap = state.calendarView == CalendarView.week
              ? _kWeekDateNavGap
              : _kMonthDateNavGap;
          // ── אזור התאריך/חיפוש — todayBtn ו-jumpBtn תמיד צמודים לתאריך ──────
          // סדר (RTL): todayBtn | jumpBtn | ← prevBtn  תאריך  nextBtn →
          final dateNavGroup = widget.isJumpToDateSearchOpen
              ? _buildInlineSearchField(
                  context,
                  width: dateAreaWidth + (dateNavGap * 2) + 64,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    todayBtn,
                    const SizedBox(width: 4),
                    jumpBtn,
                    const SizedBox(width: 4),
                    prevBtn,
                    SizedBox(width: dateNavGap),
                    ConstrainedBox(
                      constraints: BoxConstraints(minWidth: dateAreaWidth),
                      child: IntrinsicWidth(
                        child: Center(child: _buildDateText(context)),
                      ),
                    ),
                    SizedBox(width: dateNavGap),
                    nextBtn,
                  ],
                );

          return LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < _kTopBarNarrowBreakpoint;
              final isMedium =
                  constraints.maxWidth >= _kTopBarNarrowBreakpoint &&
                  constraints.maxWidth < _kTopBarMediumBreakpoint;

              // isNarrow ו-isMedium — אותו layout דו-שורתי:
              // שורה 1: viewSwitcher + trailingActions
              // שורה 2: todayBtn | jumpBtn | ← תאריך → (dateNavGroup כולל הכל)
              if (isNarrow || isMedium) {
                final dateRow = Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: dateNavGroup,
                    ),
                  ),
                );

                return AppTopBar(
                  center: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runAlignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      viewSwitcher,
                      trailingActions,
                    ],
                  ),
                  secondaryRow: dateRow,
                );
              }

              // wide (≥ _kTopBarMediumBreakpoint): NavigationToolbar ממרכז
              // את dateNavGroup גאומטרית בסרגל, viewSwitcher ו-trailingActions בצדדים.
              return AppTopBar(
                leadingItems: [
                  AppTopBarItem(widget: viewSwitcher),
                ],
                center: Align(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: dateNavGroup,
                  ),
                ),
                trailingItems: [
                  AppTopBarItem(widget: trailingActions),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTopBarDivider(BuildContext context, bool isCompact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: isCompact ? 18.0 : 24.0,
        child: VerticalDivider(
          width: 9.0,
          thickness: 1.0,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.32),
        ),
      ),
    );
  }

  // ── View switcher ─────────────────────────────────────────────────────────

  Widget _buildViewSwitcher(CalendarState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewBtn(
          label: 'שבוע',
          regularIcon: FluentIcons.calendar_week_start_24_regular,
          filledIcon: FluentIcons.calendar_week_start_24_filled,
          selected: state.calendarView == CalendarView.week,
          onPressed: _withClose(() => widget.onViewChanged(CalendarView.week)),
        ),
        _ViewBtn(
          label: 'חודש',
          regularIcon: FluentIcons.calendar_month_24_regular,
          filledIcon: FluentIcons.calendar_month_24_filled,
          selected: state.calendarView == CalendarView.month,
          onPressed: _withClose(() => widget.onViewChanged(CalendarView.month)),
        ),
      ],
    );
  }
}

// ── _ViewBtn ──────────────────────────────────────────────────────────────────

class _ViewBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final IconData regularIcon;
  final IconData filledIcon;

  const _ViewBtn({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.regularIcon,
    required this.filledIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected
        ? Color.alphaBlend(
            cs.secondaryContainer.withValues(alpha: 0.82),
            cs.surfaceContainerHigh,
          )
        : Colors.transparent;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final borderColor = selected
        ? cs.outlineVariant.withValues(alpha: 0.38)
        : Colors.transparent;
    final shadowColor = selected
        ? cs.shadow.withValues(alpha: 0.08)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppTokens.borderRadiusAll,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppTokens.borderRadiusAll,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RtlIcon(
                selected ? filledIcon : regularIcon,
                size: 16,
                color: fg,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
