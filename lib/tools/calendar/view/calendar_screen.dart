import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/printing_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/widgets/app_floating_panel.dart';
import 'package:otzaria/widgets/inputs/segmented_button_tile.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/utils/daf_yomi_navigator.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_day_cell.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_zman_alert_dialog.dart';
import 'package:otzaria/tools/calendar/view/panels/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/view/calendar_print_helper.dart'
    as print_helper;

export 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

class CalendarWidget extends StatefulWidget {
  const CalendarWidget({super.key});

  @override
  State<CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends State<CalendarWidget> {
  late final FocusNode _keyboardFocusNode;
  Timer? _keyRepeatTimer;
  LogicalKeyboardKey? _currentPressedKey;
  bool _isJumpToDateDialogOpen = false;
  bool _isSidebarVisible = true;
  CalendarSidePanelView _sidePanelView = CalendarSidePanelView.times;

  final List<String> hebrewDays = kHebrewDays;
  final List<String> hebrewMonths = kHebrewMonths;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  void _stopKeyRepeat() {
    _keyRepeatTimer?.cancel();
    _keyRepeatTimer = null;
    _currentPressedKey = null;
  }

  void _handleFocusChange() {
    if (!_keyboardFocusNode.hasFocus) _stopKeyRepeat();
  }

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode(skipTraversal: true, canRequestFocus: true);
    _keyboardFocusNode.addListener(_handleFocusChange);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _requestFocusIfNeeded());
  }

  @override
  void didUpdateWidget(CalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _requestFocusIfNeeded());
  }

  void _requestFocusIfNeeded() {
    if (mounted && !_keyboardFocusNode.hasFocus) {
      _keyboardFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _keyboardFocusNode.removeListener(_handleFocusChange);
    _stopKeyRepeat();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  // ─── Keyboard ──────────────────────────────────────────────────────────────

  bool _isNavigationKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
  }

  KeyEventResult _handleCalendarKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (!_isNavigationKey(key)) return KeyEventResult.ignored;
    final cubit = context.read<CalendarCubit>();
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyDownEvent) {
      if (_currentPressedKey != key) {
        _executeNavigationAction(key, cubit);
        _currentPressedKey = key;
        _keyRepeatTimer?.cancel();
        _keyRepeatTimer = Timer(const Duration(milliseconds: 400), () {
          _keyRepeatTimer =
              Timer.periodic(const Duration(milliseconds: 80), (timer) {
            final pressedKey = _currentPressedKey;
            if (pressedKey != null &&
                mounted &&
                HardwareKeyboard.instance.logicalKeysPressed
                    .contains(pressedKey)) {
              _executeNavigationAction(pressedKey, cubit);
            } else {
              _stopKeyRepeat();
              timer.cancel();
            }
          });
        });
      }
    } else if (event is KeyUpEvent) {
      if (key == _currentPressedKey) _stopKeyRepeat();
    }
    return KeyEventResult.handled;
  }

  void _executeNavigationAction(LogicalKeyboardKey key, CalendarCubit cubit) {
    if (key == LogicalKeyboardKey.arrowRight) {
      cubit.navigateToPreviousDay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      cubit.navigateToNextDay();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      cubit.navigateToPreviousWeek();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      cubit.navigateToNextWeek();
    }
  }

  bool _isTextFieldFocused() {
    final w = FocusManager.instance.primaryFocus?.context?.widget;
    return w is TextField ||
        w is EditableText ||
        w.runtimeType.toString().contains('TextField');
  }

  SingleActivator _parseShortcut(String shortcut) {
    final parts = shortcut.toLowerCase().split('+');
    bool ctrl = false, shift = false, alt = false;
    LogicalKeyboardKey? key;
    for (final part in parts) {
      final t = part.trim();
      if (t == 'ctrl' || t == 'control') {
        ctrl = true;
      } else if (t == 'shift') {
        shift = true;
      } else if (t == 'alt') {
        alt = true;
      } else {
        key = _mapKeyString(t);
      }
    }
    return SingleActivator(key ?? LogicalKeyboardKey.keyA,
        control: ctrl, shift: shift, alt: alt);
  }

  LogicalKeyboardKey _mapKeyString(String s) {
    const map = {
      'a': LogicalKeyboardKey.keyA,
      'b': LogicalKeyboardKey.keyB,
      'c': LogicalKeyboardKey.keyC,
      'd': LogicalKeyboardKey.keyD,
      'e': LogicalKeyboardKey.keyE,
      'f': LogicalKeyboardKey.keyF,
      'g': LogicalKeyboardKey.keyG,
      'h': LogicalKeyboardKey.keyH,
      'i': LogicalKeyboardKey.keyI,
      'j': LogicalKeyboardKey.keyJ,
      'k': LogicalKeyboardKey.keyK,
      'l': LogicalKeyboardKey.keyL,
      'm': LogicalKeyboardKey.keyM,
      'n': LogicalKeyboardKey.keyN,
      'o': LogicalKeyboardKey.keyO,
      'p': LogicalKeyboardKey.keyP,
      'q': LogicalKeyboardKey.keyQ,
      'r': LogicalKeyboardKey.keyR,
      's': LogicalKeyboardKey.keyS,
      't': LogicalKeyboardKey.keyT,
      'u': LogicalKeyboardKey.keyU,
      'v': LogicalKeyboardKey.keyV,
      'w': LogicalKeyboardKey.keyW,
      'x': LogicalKeyboardKey.keyX,
      'y': LogicalKeyboardKey.keyY,
      'z': LogicalKeyboardKey.keyZ,
      '0': LogicalKeyboardKey.digit0,
      '1': LogicalKeyboardKey.digit1,
      '2': LogicalKeyboardKey.digit2,
      '3': LogicalKeyboardKey.digit3,
      '4': LogicalKeyboardKey.digit4,
      '5': LogicalKeyboardKey.digit5,
      '6': LogicalKeyboardKey.digit6,
      '7': LogicalKeyboardKey.digit7,
      '8': LogicalKeyboardKey.digit8,
      '9': LogicalKeyboardKey.digit9,
      'comma': LogicalKeyboardKey.comma,
      'arrowleft': LogicalKeyboardKey.arrowLeft,
      'arrowright': LogicalKeyboardKey.arrowRight,
      'arrowup': LogicalKeyboardKey.arrowUp,
      'arrowdown': LogicalKeyboardKey.arrowDown,
    };
    return map[s] ?? LogicalKeyboardKey.keyA;
  }

  void _navigateMonth(BuildContext context, {required bool forward}) {
    final cubit = context.read<CalendarCubit>();
    final current = cubit.state.selectedGregorianDate;
    final newDate = forward
        ? DateTime(current.year, current.month + 1, current.day)
        : DateTime(current.year, current.month - 1, current.day);
    cubit.jumpToDate(newDate);
  }

  void _navigateYear(BuildContext context, {required bool forward}) {
    final cubit = context.read<CalendarCubit>();
    final current = cubit.state.selectedGregorianDate;
    final newDate = forward
        ? DateTime(current.year + 1, current.month, current.day)
        : DateTime(current.year - 1, current.month, current.day);
    cubit.jumpToDate(newDate);
  }

  void _openSidePanelIfNeeded(BuildContext context, bool isMobile) {
    if (!isMobile) return;
    Scaffold.of(context).openEndDrawer();
  }

  void _toggleSidebar(BuildContext context, bool isMobile) {
    if (isMobile) {
      _openSidePanelIfNeeded(context, true);
      return;
    }
    setState(() => _isSidebarVisible = !_isSidebarVisible);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        final shortcuts = context.watch<SettingsBloc>().state.shortcuts;
        final navigateTabsShortcut =
            shortcuts['key-shortcut-calendar-navigate-times'] ?? 'ctrl+e';
        final todayShortcut =
            shortcuts['key-shortcut-calendar-today'] ?? 'ctrl+d';
        final jumpDateShortcut =
            shortcuts['key-shortcut-calendar-jump-date'] ?? 'ctrl+shift+d';
        final createEventShortcut =
            shortcuts['key-shortcut-calendar-create-event'] ?? 'ctrl+n';
        final toggleViewShortcut =
            shortcuts['key-shortcut-calendar-toggle-view'] ?? 'ctrl+shift+e';
        final printShortcut = shortcuts['key-shortcut-print'] ?? 'ctrl+p';
        final contextSettingsShortcut =
            shortcuts['key-shortcut-open-context-settings'] ??
                'ctrl+shift+comma';

        return CallbackShortcuts(
          bindings: {
            _parseShortcut(navigateTabsShortcut): () {
              if (_isTextFieldFocused()) return;
              setState(() {
                _sidePanelView = _sidePanelView == CalendarSidePanelView.times
                    ? CalendarSidePanelView.events
                    : CalendarSidePanelView.times;
              });
            },
            _parseShortcut(todayShortcut): () {
              if (_isTextFieldFocused()) return;
              context.read<CalendarCubit>().jumpToToday();
            },
            _parseShortcut(jumpDateShortcut): () {
              if (_isTextFieldFocused()) return;
              if (_isJumpToDateDialogOpen) {
                Navigator.of(context).pop();
                _isJumpToDateDialogOpen = false;
              } else {
                _showJumpToDateDialog(context);
              }
            },
            _parseShortcut(createEventShortcut): () {
              if (_isTextFieldFocused()) return;
              _showCreateEventDialog(context, state);
            },
            _parseShortcut(toggleViewShortcut): () {
              if (_isTextFieldFocused()) return;
              final cubit = context.read<CalendarCubit>();
              final next = switch (state.calendarView) {
                CalendarView.month => CalendarView.week,
                CalendarView.week => CalendarView.day,
                CalendarView.day => CalendarView.month,
              };
              cubit.changeCalendarView(next);
            },
            _parseShortcut(printShortcut): () {
              if (_isTextFieldFocused()) return;
              _printCalendar(context, state);
            },
            _parseShortcut(contextSettingsShortcut): () {
              if (_isTextFieldFocused()) return;
              setState(() => _sidePanelView = CalendarSidePanelView.settings);
            },
            const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
                () {
              if (_isTextFieldFocused()) return;
              _navigateMonth(context, forward: true);
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
                () {
              if (_isTextFieldFocused()) return;
              _navigateMonth(context, forward: false);
            },
            const SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
                () {
              if (_isTextFieldFocused()) return;
              _navigateYear(context, forward: true);
            },
            const SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
                () {
              if (_isTextFieldFocused()) return;
              _navigateYear(context, forward: false);
            },
          },
          child: Focus(
            focusNode: _keyboardFocusNode,
            autofocus: true,
            onKeyEvent: _handleCalendarKeyEvent,
            child: GestureDetector(
              onTap: () => _keyboardFocusNode.requestFocus(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile =
                      constraints.maxWidth < LayoutBreakpoints.compact;
                  return Scaffold(
                    backgroundColor: AppSurfaces.panelBackground(context),
                    appBar: _buildTopAppBar(context, state, isMobile),
                    endDrawer: isMobile
                        ? _buildSidePanelDrawer(context, state)
                        : null,
                    body: isMobile
                        ? _buildMobileLayout(context, state)
                        : _buildDesktopLayout(context, state),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Layouts ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildTopAppBar(
      BuildContext context, CalendarState state, bool isMobile) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: AppTokens.spaceMD,
      centerTitle: true,
      title: Text(
        getCurrentMonthYearText(state),
        textDirection: TextDirection.rtl,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      actions: _buildTopBarActions(context, state, isMobile),
    );
  }

  List<Widget> _buildTopBarActions(
      BuildContext context, CalendarState state, bool isMobile) {
    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'חודש קודם',
            onPressed: () => context.read<CalendarCubit>().previous(),
            icon: const Icon(FluentIcons.chevron_left_24_regular),
          ),
          IconButton(
            tooltip: 'חודש הבא',
            onPressed: () => context.read<CalendarCubit>().next(),
            icon: const Icon(FluentIcons.chevron_right_24_regular),
          ),
          const SizedBox(width: AppTokens.spaceXS),
          RecommendedActionButton(
            text: 'היום',
            onPressed: () => context.read<CalendarCubit>().jumpToToday(),
          ),
          const SizedBox(width: AppTokens.spaceXS),
          RecommendedActionButton(
            text: 'מעבר לתאריך',
            onPressed: () => _showJumpToDateDialog(context),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          AppSegmentedControl<CalendarView>(
            options: const [
              SegmentOption(value: CalendarView.day, label: 'יום'),
              SegmentOption(value: CalendarView.week, label: 'שבוע'),
              SegmentOption(value: CalendarView.month, label: 'חודש'),
            ],
            currentValue: state.calendarView,
            onChanged: (value) =>
                context.read<CalendarCubit>().changeCalendarView(value),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          SizedBox(
            height: 24,
            child: VerticalDivider(
              color: Theme.of(context).dividerColor,
              thickness: 1,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          IconButton(
            tooltip: 'הדפס',
            icon: const Icon(FluentIcons.print_24_regular),
            onPressed: () => _printCalendar(context, state),
          ),
          IconButton(
            tooltip: 'לוח צד',
            icon: const Icon(FluentIcons.panel_right_24_regular),
            onPressed: () => _toggleSidebar(context, isMobile),
          ),
        ],
      ),
    ];
  }

  Widget _buildDesktopLayout(BuildContext context, CalendarState state) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: _buildCalendar(context, state),
            ),
          ),
          if (_isSidebarVisible) ...[
            const SizedBox(width: AppTokens.spaceMD),
            Expanded(
              flex: 1,
              child: AppFloatingPanel(
                child: _buildSidePanel(context, state),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, CalendarState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: _buildCalendar(context, state),
    );
  }

  Widget _buildSidePanelDrawer(BuildContext context, CalendarState state) {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: cs.surfaceContainerHigh,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: _buildSidePanel(context, state),
        ),
      ),
    );
  }

  // ─── Calendar card ────────────────────────────────────────────────────────

  Widget _buildCalendar(BuildContext context, CalendarState state) {
    return AppFloatingPanel(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildCalendarGrid(context, state),
          ],
        ),
      ),
    );
  }

  // ─── Calendar grid ────────────────────────────────────────────────────────

  Widget _buildCalendarGrid(BuildContext context, CalendarState state) {
    switch (state.calendarView) {
      case CalendarView.month:
        return _buildMonthView(context, state);
      case CalendarView.week:
        return _buildWeekView(context, state);
      case CalendarView.day:
        return _buildDayView(context, state);
    }
  }

  Widget _buildDayNamesRow(BuildContext context) {
    return Row(
      children: hebrewDays
          .map((day) => Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildMonthView(BuildContext context, CalendarState state) {
    return Column(
      children: [
        _buildDayNamesRow(context),
        const SizedBox(height: 8),
        _buildCalendarDays(context, state),
      ],
    );
  }

  Widget _buildWeekView(BuildContext context, CalendarState state) {
    return Column(
      children: [
        _buildDayNamesRow(context),
        const SizedBox(height: 8),
        _buildWeekDays(context, state),
      ],
    );
  }

  Widget _buildDayView(BuildContext context, CalendarState state) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        border:
            Border.all(color: cs.primary.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hebrewDays[state.selectedGregorianDate.weekday % 7],
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatHebrewDay(state.selectedJewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(state.selectedJewishDate)}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.selectedGregorianDate.day} ${getGregorianMonthName(state.selectedGregorianDate.month)} ${state.selectedGregorianDate.year}',
                  style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Tooltip(
              message: 'צור אירוע',
              child: IconButton.filled(
                icon: const Icon(FluentIcons.add_24_regular, size: 16),
                onPressed: () => _showCreateEventDialog(context, state),
                style: IconButton.styleFrom(
                  minimumSize: const Size(24, 24),
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarDays(BuildContext context, CalendarState state) {
    return state.calendarType == CalendarType.gregorian
        ? _buildGregorianCalendarDays(context, state)
        : _buildHebrewCalendarDays(context, state);
  }

  Widget _buildHebrewCalendarDays(BuildContext context, CalendarState state) {
    final currentJewishDate = state.currentJewishDate;
    final daysInMonth = currentJewishDate.getDaysInJewishMonth();
    final firstDayOfMonth = JewishDate()
      ..setJewishDate(currentJewishDate.getJewishYear(),
          currentJewishDate.getJewishMonth(), 1);
    final startingWeekday = firstDayOfMonth.getGregorianCalendar().weekday % 7;

    List<Widget> dayWidgets = [];
    if (startingWeekday > 0) {
      final previousMonth = JewishDate()
        ..setJewishDate(currentJewishDate.getJewishYear(),
            currentJewishDate.getJewishMonth(), 1);
      previousMonth.back();
      final daysInPreviousMonth = previousMonth.getDaysInJewishMonth();
      for (int i = startingWeekday - 1; i >= 0; i--) {
        dayWidgets.add(_buildHebrewDayCell(
            context, state, daysInPreviousMonth - i,
            isFromOtherMonth: true, monthOffset: -1));
      }
    }
    for (int day = 1; day <= daysInMonth; day++) {
      dayWidgets.add(_buildHebrewDayCell(context, state, day));
    }
    final totalCells = ((dayWidgets.length / 7).ceil()) * 7;
    for (int day = 1; day <= totalCells - dayWidgets.length; day++) {
      dayWidgets.add(_buildHebrewDayCell(context, state, day,
          isFromOtherMonth: true, monthOffset: 1));
    }
    return Column(
      children: [
        for (int i = 0; i < dayWidgets.length; i += 7)
          Row(
            children: dayWidgets
                .sublist(
                    i, i + 7 > dayWidgets.length ? dayWidgets.length : i + 7)
                .map((w) => Expanded(child: w))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildGregorianCalendarDays(
      BuildContext context, CalendarState state) {
    final current = state.currentGregorianDate;
    final firstDayOfMonth = DateTime(current.year, current.month, 1);
    final daysInMonth = DateTime(current.year, current.month + 1, 0).day;
    final startingWeekday = firstDayOfMonth.weekday % 7;

    List<Widget> dayWidgets = [];
    if (startingWeekday > 0) {
      final daysInPreviousMonth = DateTime(current.year, current.month, 0).day;
      for (int i = startingWeekday - 1; i >= 0; i--) {
        dayWidgets.add(_buildGregorianDayCell(
            context, state, daysInPreviousMonth - i,
            isFromOtherMonth: true, monthOffset: -1));
      }
    }
    for (int day = 1; day <= daysInMonth; day++) {
      dayWidgets.add(_buildGregorianDayCell(context, state, day));
    }
    final totalCells = ((dayWidgets.length / 7).ceil()) * 7;
    for (int day = 1; day <= totalCells - dayWidgets.length; day++) {
      dayWidgets.add(_buildGregorianDayCell(context, state, day,
          isFromOtherMonth: true, monthOffset: 1));
    }
    return Column(
      children: [
        for (int i = 0; i < dayWidgets.length; i += 7)
          Row(
            children: dayWidgets
                .sublist(
                    i, i + 7 > dayWidgets.length ? dayWidgets.length : i + 7)
                .map((w) => Expanded(child: w))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildHebrewDayCell(BuildContext context, CalendarState state, int day,
      {bool isFromOtherMonth = false, int monthOffset = 0}) {
    final jewishDate = JewishDate()
      ..setJewishDate(state.currentJewishDate.getJewishYear(),
          state.currentJewishDate.getJewishMonth(), 1);
    if (isFromOtherMonth) {
      if (monthOffset < 0) {
        jewishDate.back();
        jewishDate.setJewishDate(
            jewishDate.getJewishYear(), jewishDate.getJewishMonth(), 1);
      } else if (monthOffset > 0) {
        final daysInMonth = jewishDate.getDaysInJewishMonth();
        jewishDate.setJewishDate(jewishDate.getJewishYear(),
            jewishDate.getJewishMonth(), daysInMonth);
        jewishDate.forward();
      }
      jewishDate.setJewishDate(
          jewishDate.getJewishYear(), jewishDate.getJewishMonth(), day);
    } else {
      jewishDate.setJewishDate(state.currentJewishDate.getJewishYear(),
          state.currentJewishDate.getJewishMonth(), day);
    }
    final gregorianDate = jewishDate.getGregorianCalendar();
    return buildDayCell(
      context,
      state,
      gregorianDate,
      jewishDate,
      isFromOtherMonth,
      () {
        if (isFromOtherMonth) {
          context.read<CalendarCubit>().jumpToDate(gregorianDate);
        } else {
          context.read<CalendarCubit>().selectDate(jewishDate, gregorianDate);
        }
      },
      () => _showCreateEventDialog(context, state, specificDate: gregorianDate),
    );
  }

  Widget _buildGregorianDayCell(
      BuildContext context, CalendarState state, int day,
      {bool isFromOtherMonth = false, int monthOffset = 0}) {
    final gregorianDate = DateTime(state.currentGregorianDate.year,
        state.currentGregorianDate.month + monthOffset, day);
    final jewishDate = JewishDate.fromDateTime(gregorianDate);
    return buildDayCell(
      context,
      state,
      gregorianDate,
      jewishDate,
      isFromOtherMonth,
      () {
        if (isFromOtherMonth) {
          context.read<CalendarCubit>().jumpToDate(gregorianDate);
        } else {
          context.read<CalendarCubit>().selectDate(jewishDate, gregorianDate);
        }
      },
      () => _showCreateEventDialog(context, state, specificDate: gregorianDate),
    );
  }

  Widget _buildWeekDays(BuildContext context, CalendarState state) {
    final selectedDate = state.selectedGregorianDate;
    final startOfWeek =
        selectedDate.subtract(Duration(days: selectedDate.weekday % 7));
    return Row(
      children: [
        for (int i = 0; i < 7; i++)
          Builder(builder: (context) {
            final dayDate = startOfWeek.add(Duration(days: i));
            final jewishDate = JewishDate.fromDateTime(dayDate);
            return Expanded(
              child: buildDayCell(
                context,
                state,
                dayDate,
                jewishDate,
                false,
                () => context
                    .read<CalendarCubit>()
                    .selectDate(jewishDate, dayDate),
                () => _showCreateEventDialog(
                    context, context.read<CalendarCubit>().state,
                    specificDate: dayDate),
              ),
            );
          }),
      ],
    );
  }

  // ─── Side panel ───────────────────────────────────────────────────────────

  Widget _buildSidePanel(BuildContext context, CalendarState state) {
    return CalendarSidePanel(
      state: state,
      activeView: _sidePanelView,
      onViewChanged: (view) => setState(() => _sidePanelView = view),
      buildTimesGrid: (ctx, st) => _buildTimesGrid(ctx, st),
      buildDafYomiButtons: (ctx, st) => _buildDafYomiButtons(ctx, st),
      buildCityDropdown: (ctx, st) => _buildCityDropdownWithSearch(ctx, st),
      buildEventsList: (ctx, st, isSearch) =>
          _buildEventsList(ctx, st, isSearch: isSearch),
      showCreateEventDialog: (ctx, st) => _showCreateEventDialog(ctx, st),
    );
  }

  // ─── Times grid ───────────────────────────────────────────────────────────

  Widget _buildTimesGrid(BuildContext context, CalendarState state) {
    final dailyTimes = state.dailyTimes;
    final jewishCalendar =
        JewishCalendar.fromDateTime(state.selectedGregorianDate);
    final List<Map<String, String?>> timesList = [
      {'id': 'alos', 'name': 'עלות השחר', 'time': dailyTimes['alos']},
      {
        'id': 'alos16point1Degrees',
        'name': "עלוה\"ש (72 דק') במע'",
        'time': dailyTimes['alos16point1Degrees']
      },
      {
        'id': 'alos19point8Degrees',
        'name': "עלוה\"ש (90 דק') במע'",
        'time': dailyTimes['alos19point8Degrees']
      },
      {'id': 'sunrise', 'name': 'זריחה', 'time': dailyTimes['sunrise']},
      {
        'id': 'sofZmanShmaMGA',
        'name': 'סוף זמן ק"ש - מג"א',
        'time': dailyTimes['sofZmanShmaMGA']
      },
      {
        'id': 'sofZmanShmaGRA',
        'name': 'סוף זמן ק"ש - גר"א',
        'time': dailyTimes['sofZmanShmaGRA']
      },
      {
        'id': 'sofZmanTfilaMGA',
        'name': 'סוף זמן תפילה - מג"א',
        'time': dailyTimes['sofZmanTfilaMGA']
      },
      {
        'id': 'sofZmanTfilaGRA',
        'name': 'סוף זמן תפילה - גר"א',
        'time': dailyTimes['sofZmanTfilaGRA']
      },
      {'id': 'chatzos', 'name': 'חצות היום', 'time': dailyTimes['chatzos']},
      {
        'id': 'chatzosLayla',
        'name': 'חצות הלילה',
        'time': dailyTimes['chatzosLayla']
      },
      {
        'id': 'minchaGedola',
        'name': 'מנחה גדולה',
        'time': dailyTimes['minchaGedola']
      },
      {
        'id': 'minchaKetana',
        'name': 'מנחה קטנה',
        'time': dailyTimes['minchaKetana']
      },
      {
        'id': 'plagHamincha',
        'name': 'פלג המנחה',
        'time': dailyTimes['plagHamincha']
      },
      {'id': 'sunset', 'name': 'שקיעה', 'time': dailyTimes['sunset']},
      {'id': 'tzais', 'name': 'צאת הכוכבים', 'time': dailyTimes['tzais']},
      {
        'id': 'sunsetRT',
        'name': 'צאת הכוכבים ר"ת',
        'time': dailyTimes['sunsetRT']
      },
    ];

    if (jewishCalendar.getYomTovIndex() == JewishCalendar.EREV_PESACH) {
      timesList.addAll([
        {
          'id': 'sofZmanAchilasChametzMGA',
          'name': 'סוף זמן אכילת חמץ - מג"א',
          'time': dailyTimes['sofZmanAchilasChametzMGA']
        },
        {
          'id': 'sofZmanAchilasChametzGRA',
          'name': 'סוף זמן אכילת חמץ - גר"א',
          'time': dailyTimes['sofZmanAchilasChametzGRA']
        },
        {
          'id': 'sofZmanBiurChametzMGA',
          'name': 'סוף זמן ביעור חמץ - מג"א',
          'time': dailyTimes['sofZmanBiurChametzMGA']
        },
        {
          'id': 'sofZmanBiurChametzGRA',
          'name': 'סוף זמן ביעור חמץ - גר"א',
          'time': dailyTimes['sofZmanBiurChametzGRA']
        },
      ]);
    }
    if (jewishCalendar.getDayOfWeek() == 6 || jewishCalendar.isErevYomTov()) {
      timesList.add({
        'id': 'candleLighting',
        'name': 'הדלקת נרות',
        'time': dailyTimes['candleLighting']
      });
    }
    final int yomTovIndex = jewishCalendar.getYomTovIndex();
    final bool isNotExitTimesDay =
        yomTovIndex == JewishCalendar.CHOL_HAMOED_SUCCOS ||
            yomTovIndex == JewishCalendar.CHOL_HAMOED_PESACH ||
            yomTovIndex == JewishCalendar.HOSHANA_RABBA ||
            yomTovIndex == JewishCalendar.CHANUKAH;
    if ((jewishCalendar.getDayOfWeek() == 7 || jewishCalendar.isYomTov()) &&
        !isNotExitTimesDay) {
      final String exitName, exitName2;
      if (jewishCalendar.getDayOfWeek() == 7 && !jewishCalendar.isYomTov()) {
        exitName = 'יציאת שבת';
        exitName2 = 'צאת השבת חזו"א';
      } else if (jewishCalendar.isYomTov()) {
        final holidayName = _getHolidayName(jewishCalendar);
        exitName = 'יציאת $holidayName';
        exitName2 = 'יציאת $holidayName חזו"א';
      } else {
        exitName = 'יציאת שבת';
        exitName2 = 'צאת השבת חזו"א';
      }
      timesList.addAll([
        {
          'id': 'shabbosExit1',
          'name': exitName,
          'time': dailyTimes['shabbosExit1']
        },
        {
          'id': 'shabbosExit2',
          'name': exitName2,
          'time': dailyTimes['shabbosExit2']
        },
      ]);
    }
    if (jewishCalendar.getDayOfOmer() != -1) {
      timesList.add({
        'id': 'omerCounting',
        'name': 'ספירת העומר',
        'time': dailyTimes['omerCounting']
      });
    }
    if (jewishCalendar.isTaanis() &&
        jewishCalendar.getYomTovIndex() != JewishCalendar.YOM_KIPPUR) {
      timesList.addAll([
        {
          'id': 'fastStart',
          'name': 'תחילת התענית',
          'time': dailyTimes['fastStart']
        },
        {'id': 'fastEnd', 'name': 'סיום התענית', 'time': dailyTimes['fastEnd']},
      ]);
    }
    for (final key in [
      'kidushLevanaEarliest',
      'kidushLevanaLatest',
      'tchilasKidushLevana',
      'sofZmanKidushLevana'
    ]) {
      if (dailyTimes[key] != null) {
        final name =
            key == 'kidushLevanaEarliest' || key == 'tchilasKidushLevana'
                ? 'תחילת זמן קידוש לבנה'
                : 'סוף זמן קידוש לבנה';
        timesList.add({'id': key, 'name': name, 'time': dailyTimes[key]});
      }
    }

    final filteredTimesList =
        timesList.where((t) => t['time'] != null).toList();
    final scheme = Theme.of(context).colorScheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: filteredTimesList.length,
      itemBuilder: (context, index) {
        final timeData = filteredTimesList[index];
        final timeId = timeData['id']!;
        final timeName = timeData['name']!;
        final timeLabel = timeData['time'] ?? '--:--';
        final existingAlert = state.zmanAlerts[timeId];
        final bool hasAlert = existingAlert != null;
        final isSpecialTime = _isSpecialTime(timeName);
        final bgColor = hasAlert
            ? scheme.errorContainer
            : isSpecialTime
                ? scheme.tertiaryContainer
                : scheme.surfaceContainerHighest;
        final border = hasAlert
            ? Border.all(color: scheme.error, width: 1)
            : isSpecialTime
                ? Border.all(color: scheme.tertiary, width: 1)
                : null;
        final titleColor = hasAlert
            ? scheme.onErrorContainer
            : isSpecialTime
                ? scheme.onTertiaryContainer
                : scheme.onSurfaceVariant;
        final timeColor = hasAlert
            ? scheme.onErrorContainer
            : isSpecialTime
                ? scheme.onTertiaryContainer
                : scheme.onSurface;

        return LayoutBuilder(builder: (context, itemConstraints) {
          final isCompact =
              itemConstraints.maxHeight < 44 || itemConstraints.maxWidth < 110;
          final titleFontSize = isCompact ? 10.0 : 12.0;
          final timeFontSize = isCompact ? 12.0 : 14.0;
          final pad = isCompact ? 4.0 : 8.0;
          final menuSize = isCompact ? 14.0 : 18.0;
          final menuIconSize = isCompact ? 12.0 : 16.0;

          return Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: isCompact
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        timeName,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w500,
                          color: titleColor,
                          height: isCompact ? 1.2 : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<ZmanMenuAction>(
                      tooltip: '',
                      padding: EdgeInsets.zero,
                      child: SizedBox.square(
                        dimension: menuSize,
                        child: Center(
                          child: Icon(
                            FluentIcons.more_vertical_24_regular,
                            color: titleColor,
                            size: menuIconSize,
                          ),
                        ),
                      ),
                      itemBuilder: (_) => [
                        PopupMenuItem<ZmanMenuAction>(
                          value: ZmanMenuAction.toggle,
                          child: Text(hasAlert
                              ? 'מופעלת התראה לזמן זה'
                              : 'הפעל התראה לזמן זה'),
                        ),
                      ],
                      onSelected: (_) async {
                        final cubit = context.read<CalendarCubit>();
                        if (timeLabel == '--:--') {
                          UiSnack.showError(
                              'לא ניתן להפעיל התראה לזמן לא זמין');
                          return;
                        }
                        final result = await showZmanAlertDialog(
                          context,
                          zmanName: timeName,
                          timeLabel: timeLabel,
                          initialMinutesBefore:
                              existingAlert?.minutesBefore ?? 60,
                          isEnabled: hasAlert,
                        );
                        if (result == null) return;
                        if (result.cancelAlert) {
                          await cubit.cancelZmanAlertPreference(timeId: timeId);
                          return;
                        }
                        await cubit.setZmanAlertPreference(
                          timeId: timeId,
                          displayName: timeName,
                          minutesBefore: result.minutesBefore,
                        );
                      },
                    ),
                  ],
                ),
                if (!isCompact) const SizedBox(height: 2),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: timeFontSize,
                    fontWeight: FontWeight.bold,
                    color: timeColor,
                    height: isCompact ? 1.0 : null,
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  bool _isSpecialTime(String timeName) {
    return timeName.contains('חמץ') ||
        timeName.contains('הדלקת נרות') ||
        timeName.contains('יציאת') ||
        timeName.contains('צאת השבת') ||
        timeName.contains('ספירת העומר') ||
        timeName.contains('תענית') ||
        timeName.contains('חנוכה') ||
        timeName.contains('קידוש לבנה');
  }

  String _getHolidayName(JewishCalendar jc) {
    switch (jc.getYomTovIndex()) {
      case JewishCalendar.ROSH_HASHANA:
        return 'ראש השנה';
      case JewishCalendar.YOM_KIPPUR:
        return 'יום כיפור';
      case JewishCalendar.SUCCOS:
        return 'חג הסוכות';
      case JewishCalendar.SHEMINI_ATZERES:
        return 'שמיני עצרת';
      case JewishCalendar.SIMCHAS_TORAH:
        return 'שמחת תורה';
      case JewishCalendar.PESACH:
        return 'חג הפסח';
      case JewishCalendar.SHAVUOS:
        return 'חג השבועות';
      default:
        return 'חג';
    }
  }

  Widget _buildDafYomiButtons(BuildContext context, CalendarState state) {
    final jewishCalendar =
        JewishCalendar.fromDateTime(state.selectedGregorianDate);
    String bavliTractate;
    int bavliDaf;
    try {
      final daf = YomiCalculator.getDafYomiBavli(jewishCalendar);
      bavliTractate = daf.getMasechta();
      bavliDaf = daf.getDaf();
    } catch (_) {
      bavliTractate = 'לא זמין';
      bavliDaf = 0;
    }
    final dafLabel = HebrewDateFormatter()
        .formatHebrewNumber(bavliDaf)
        .replaceAll('״', '')
        .replaceAll('׳', '');

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () =>
                openDafYomiBook(context, bavliTractate, ' $dafLabel.'),
            icon: const Icon(FluentIcons.book_24_regular),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('דף היומי בבלי',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text('$bavliTractate $dafLabel',
                    style: const TextStyle(fontSize: 10)),
              ],
            ),
            style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8)),
          ),
        ),
      ],
    );
  }

  Widget _buildCityDropdownWithSearch(
      BuildContext context, CalendarState state) {
    return NeutralActionButton(
      text: state.selectedCity,
      icon: FluentIcons.chevron_down_24_regular,
      onPressed: () =>
          setState(() => _sidePanelView = CalendarSidePanelView.settings),
    );
  }

  Widget _buildEventsList(BuildContext context, CalendarState state,
      {bool isSearch = false}) {
    final cubit = context.read<CalendarCubit>();
    final List<CustomEvent> events;
    if (state.eventSearchQuery.isNotEmpty) {
      events = cubit.getFilteredEvents(state.eventSearchQuery);
    } else if (state.showAllEvents) {
      events = List<CustomEvent>.from(state.events)
        ..sort((a, b) => a.baseGregorianDate.compareTo(b.baseGregorianDate));
    } else {
      events = cubit.eventsForDate(state.selectedGregorianDate);
    }

    if (events.isEmpty) {
      return Center(
        child: Text(state.eventSearchQuery.isNotEmpty
            ? 'לא נמצאו אירועים מתאימים'
            : state.showAllEvents
                ? 'אין אירועים במערכת'
                : 'אין אירועים ביום זה'),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppTokens.radiusMD),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(event.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        if (event.googleEventId != null &&
                            event.googleEventId!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(FluentIcons.arrow_sync_24_regular,
                                size: 14, color: scheme.primary),
                          ),
                      ],
                    ),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        truncateDescription(event.description),
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: event.eventTime != null
                                ? scheme.primary.withValues(alpha: 0.2)
                                : scheme.secondary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                event.eventTime != null
                                    ? FluentIcons.clock_24_filled
                                    : FluentIcons.calendar_day_24_filled,
                                size: 10,
                                color: event.eventTime != null
                                    ? scheme.primary
                                    : scheme.secondary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                event.eventTime != null
                                    ? '${event.eventTime!.hour.toString().padLeft(2, '0')}:${event.eventTime!.minute.toString().padLeft(2, '0')}'
                                    : 'כל היום',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: event.eventTime != null
                                      ? scheme.primary
                                      : scheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            formatEventDate(event.baseGregorianDate),
                            style: TextStyle(
                                fontSize: 10,
                                color: scheme.primary,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    if (event.recurring) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(FluentIcons.arrow_repeat_all_24_regular,
                              size: 12, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(getRecurrenceLabel(event.recurrenceType),
                              style: TextStyle(
                                  fontSize: 10, color: scheme.primary)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(FluentIcons.edit_24_regular, size: 20),
                    tooltip: 'ערוך אירוע',
                    onPressed: () => _showCreateEventDialog(context, state,
                        existingEvent: event),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.delete_24_regular, size: 20),
                    tooltip: 'מחק אירוע',
                    onPressed: () async {
                      final confirmed = await showConfirmationDialog(
                        context: context,
                        title: 'אישור מחיקה',
                        content:
                            'האם אתה בטוח שברצונך למחוק את האירוע "${event.title}"?',
                        confirmText: 'מחק',
                        isDangerous: true,
                      );
                      if (confirmed == true && context.mounted) {
                        context.read<CalendarCubit>().deleteEvent(event.id);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Dialogs ───────────────────────────────────────────────────────────────

  void _showJumpToDateDialog(BuildContext context) {
    DateTime selectedDate = DateTime.now();
    final dateController = TextEditingController();
    _isJumpToDateDialogOpen = true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppSurfaces.panelBackground(ctx),
          title: const Text('מעבר לתאריך'),
          content: SizedBox(
            width: 350,
            height: 450,
            child: Column(
              children: [
                RtlTextField(
                  controller: dateController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'הזן תאריך',
                    hintText: 'דוגמאות: 15/3/2025, כ״ה אדר תשפ״ה',
                    border: OutlineInputBorder(),
                    helperText: 'ניתן להזין תאריך לועזי (יום/חודש/שנה) או עברי',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (value) {
                    DateTime? dateToJump;
                    if (value.isNotEmpty) {
                      dateToJump = _parseInputDate(context, value);
                      if (dateToJump == null) {
                        UiSnack.showError('לא הצלחנו לפרש את התאריך.');
                        return;
                      }
                    } else {
                      dateToJump = selectedDate;
                    }
                    context.read<CalendarCubit>().jumpToDate(dateToJump);
                    Navigator.of(dialogContext).pop();
                    _isJumpToDateDialogOpen = false;
                  },
                ),
                const SizedBox(height: 20),
                const Divider(),
                const Text('או בחר בלוח השנה:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Expanded(
                  child: CalendarDatePicker(
                    initialDate: selectedDate,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                    onDateChanged: (date) {
                      setState(() {
                        selectedDate = date;
                        dateController.text =
                            '${date.day}/${date.month}/${date.year}';
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isJumpToDateDialogOpen = false;
              },
              child: const Text('ביטול'),
            ),
            RecommendedActionButton(
              text: 'פתח',
              onPressed: () {
                DateTime? dateToJump;
                if (dateController.text.isNotEmpty) {
                  dateToJump = _parseInputDate(context, dateController.text);
                  if (dateToJump == null) {
                    UiSnack.showError('לא הצלחנו לפרש את התאריך.');
                    return;
                  }
                } else {
                  dateToJump = selectedDate;
                }
                context.read<CalendarCubit>().jumpToDate(dateToJump);
                Navigator.of(dialogContext).pop();
                _isJumpToDateDialogOpen = false;
              },
            ),
          ],
        ),
      ),
    ).then((_) => _isJumpToDateDialogOpen = false);
  }

  DateTime? _parseInputDate(BuildContext context, String input) {
    final cleanInput = input.trim();
    final gregorianPattern = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$');
    final match = gregorianPattern.firstMatch(cleanInput);
    if (match != null) {
      try {
        final day = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final year = int.parse(match.group(3)!);
        if (year >= 1900 && year <= 2200) return DateTime(year, month, day);
      } catch (_) {}
    }
    try {
      final parts = cleanInput.split(RegExp(r'\s+'));
      if (parts.length < 2 || parts.length > 4) return null;
      final day = hebrewNumberToInt(parts[0]);
      String monthName;
      int yearPartIndex;
      if (parts.length >= 3 &&
          parts[1] == 'אדר' &&
          (parts[2] == 'א' ||
              parts[2] == 'א׳' ||
              parts[2] == 'ב' ||
              parts[2] == 'ב׳')) {
        monthName = '${parts[1]} ${parts[2]}';
        yearPartIndex = 3;
      } else {
        monthName = parts[1];
        yearPartIndex = 2;
      }
      final month = hebrewMonthToInt(monthName);
      final int year;
      if (parts.length > yearPartIndex) {
        year = hebrewYearToInt(parts[yearPartIndex]);
      } else {
        year = context
            .read<CalendarCubit>()
            .state
            .currentJewishDate
            .getJewishYear();
      }
      if (day > 0 && month > 0 && year > 5000) {
        final jewishDate = JewishDate()..setJewishDate(year, month, day);
        return jewishDate.getGregorianCalendar();
      }
    } catch (_) {}
    return null;
  }

  void _showCreateEventDialog(
    BuildContext context,
    CalendarState state, {
    CustomEvent? existingEvent,
    DateTime? specificDate,
  }) {
    final cubit = context.read<CalendarCubit>();
    final isEditMode = existingEvent != null;
    final titleController = TextEditingController(text: existingEvent?.title);
    final descriptionController =
        TextEditingController(text: existingEvent?.description);
    final yearsController = TextEditingController(
        text: existingEvent?.recurringYears?.toString() ?? '');
    bool isRecurring = (existingEvent?.recurrenceType ?? RecurrenceType.none) !=
        RecurrenceType.none;
    RecurrenceType selectedRecurrenceType = isRecurring
        ? existingEvent!.recurrenceType
        : RecurrenceType.annualHebrew;
    bool recurForever = existingEvent?.recurringYears == null;
    TimeOfDay? selectedTime = existingEvent?.eventTime;
    final displayedGregorianDate = existingEvent != null
        ? existingEvent.baseGregorianDate
        : (specificDate ?? state.selectedGregorianDate);
    final displayedJewishDate = JewishDate.fromDateTime(displayedGregorianDate);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppSurfaces.panelBackground(ctx),
          title: Text(isEditMode ? 'ערוך אירוע' : 'צור אירוע חדש'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RtlTextField(
                    controller: titleController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                        labelText: 'כותרת האירוע',
                        border: OutlineInputBorder()),
                    onSubmitted: (_) => _saveEvent(
                      context,
                      dialogContext,
                      cubit,
                      isEditMode,
                      existingEvent,
                      titleController,
                      descriptionController,
                      yearsController,
                      isRecurring,
                      recurForever,
                      selectedRecurrenceType,
                      displayedGregorianDate,
                      selectedTime,
                    ),
                  ),
                  const SizedBox(height: 16),
                  RtlTextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                        labelText: 'תיאור (אופציונלי)',
                        border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppTokens.radiusMD),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'תאריך לועזי: ${displayedGregorianDate.day}/${displayedGregorianDate.month}/${displayedGregorianDate.year}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'תאריך עברי: ${formatHebrewDay(displayedJewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(displayedJewishDate)} ${formatHebrewYear(displayedJewishDate.getJewishYear())}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('שעת האירוע (אופציונלי)'),
                    subtitle: Text(
                      selectedTime != null
                          ? 'שעה: ${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                          : 'לא נבחרה שעה',
                      textDirection: TextDirection.rtl,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selectedTime != null)
                          IconButton(
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                            onPressed: () =>
                                setState(() => selectedTime = null),
                            tooltip: 'נקה שעה',
                          ),
                        IconButton(
                          icon: const Icon(FluentIcons.clock_24_regular),
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
                              builder: (context, child) => Directionality(
                                textDirection: TextDirection.rtl,
                                child: child!,
                              ),
                            );
                            if (time != null) {
                              setState(() => selectedTime = time);
                            }
                          },
                          tooltip: 'בחר שעה',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('אירוע חוזר'),
                    value: isRecurring,
                    onChanged: (value) => setState(() => isRecurring = value),
                  ),
                  if (isRecurring) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          DropdownButtonFormField<RecurrenceType>(
                            initialValue: selectedRecurrenceType,
                            decoration: const InputDecoration(
                                labelText: 'חזור לפי',
                                border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem(
                                  value: RecurrenceType.weekly,
                                  child: Text('שבועי')),
                              DropdownMenuItem(
                                value: RecurrenceType.monthlyHebrew,
                                child: Text(
                                    'חודשי עברי (יום ${formatHebrewDay(displayedJewishDate.getJewishDayOfMonth())})'),
                              ),
                              DropdownMenuItem(
                                value: RecurrenceType.monthlyGregorian,
                                child: Text(
                                    'חודשי לועזי (יום ${displayedGregorianDate.day})'),
                              ),
                              DropdownMenuItem(
                                value: RecurrenceType.annualHebrew,
                                child: Text(
                                    'שנתי עברי (${formatHebrewDay(displayedJewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(displayedJewishDate)})'),
                              ),
                              DropdownMenuItem(
                                value: RecurrenceType.annualGregorian,
                                child: Text(
                                    'שנתי לועזי (${displayedGregorianDate.day}/${displayedGregorianDate.month})'),
                              ),
                            ],
                            onChanged: (value) => setState(() =>
                                selectedRecurrenceType =
                                    value ?? RecurrenceType.annualHebrew),
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            title: const Text('חזרה ללא הגבלה (תמיד)'),
                            value: recurForever,
                            onChanged: (value) {
                              setState(() {
                                recurForever = value ?? true;
                                if (recurForever) yearsController.clear();
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 8),
                          RtlTextField(
                            controller: yearsController,
                            keyboardType: TextInputType.number,
                            enabled: !recurForever,
                            decoration: InputDecoration(
                              labelText: 'חזור למשך (שנים)',
                              hintText: 'לדוגמה: 5',
                              border: const OutlineInputBorder(),
                              filled: recurForever,
                              fillColor: recurForever
                                  ? Theme.of(context)
                                      .disabledColor
                                      .withValues(alpha: 0.1)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            RecommendedActionButton(
              text: isEditMode ? 'שמור שינויים' : 'צור',
              onPressed: () => _saveEvent(
                context,
                dialogContext,
                cubit,
                isEditMode,
                existingEvent,
                titleController,
                descriptionController,
                yearsController,
                isRecurring,
                recurForever,
                selectedRecurrenceType,
                displayedGregorianDate,
                selectedTime,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveEvent(
    BuildContext context,
    BuildContext dialogContext,
    CalendarCubit cubit,
    bool isEditMode,
    CustomEvent? existingEvent,
    TextEditingController titleController,
    TextEditingController descriptionController,
    TextEditingController yearsController,
    bool isRecurring,
    bool recurForever,
    RecurrenceType selectedRecurrenceType,
    DateTime displayedGregorianDate,
    TimeOfDay? selectedTime,
  ) {
    if (titleController.text.isEmpty) {
      UiSnack.showError('יש למלא כותרת לאירוע.');
      return;
    }
    final int? recurringYears = (isRecurring && !recurForever)
        ? int.tryParse(yearsController.text.trim())
        : null;
    final finalRecurrenceType =
        isRecurring ? selectedRecurrenceType : RecurrenceType.none;

    if (isEditMode) {
      cubit.updateEvent(existingEvent!.copyWith(
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
        recurrenceType: finalRecurrenceType,
        recurringYears: recurringYears,
        eventTime: selectedTime,
      ));
    } else {
      cubit.addEvent(
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
        baseGregorianDate: displayedGregorianDate,
        recurrenceType: finalRecurrenceType,
        recurringYears: recurringYears,
        eventTime: selectedTime,
      );
    }
    Navigator.of(dialogContext).pop();
  }

  void _printCalendar(BuildContext context, CalendarState state) {
    int count = 1;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) {
          final (String periodName, String periodNamePlural, int maxCount) =
              switch (state.calendarView) {
            CalendarView.month => ('חודש', 'חודשים', 12),
            CalendarView.week => ('שבוע', 'שבועות', 52),
            CalendarView.day => ('יום', 'ימים', 365),
          };
          return AlertDialog(
            backgroundColor: AppSurfaces.panelBackground(context),
            title: const Text('הגדרות הדפסה'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('בחר כמה $periodNamePlural להדפיס:'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: count.toDouble(),
                          min: 1,
                          max: maxCount.toDouble(),
                          divisions: maxCount - 1,
                          label: count.toString(),
                          onChanged: (v) => setState(() => count = v.round()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: Text(
                          count == 1
                              ? '$count $periodName'
                              : '$count $periodNamePlural',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'טווח: ${count == 1 ? periodName : '$count $periodNamePlural'} החל מהתאריך הנוכחי',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            actions: [
              NeutralActionButton(
                text: 'ביטול',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              RecommendedActionButton(
                text: 'הדפס',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PrintingScreen(
                      data: Future.value(''),
                      bookId: 'calendar',
                      createPdfOverride: (format) => print_helper
                          .createCalendarPdf(state, format, count: count),
                    ),
                  ));
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
