// ignore_for_file: unused_element, unused_element_parameter

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/printing/printing_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/widgets/floating_panel.dart';
import 'package:otzaria/widgets/inputs/segmented_button_tile.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_day_cell.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_event_dialog.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_print_dialog.dart';
import 'package:otzaria/tools/calendar/utils/calendar_date_parser.dart';
import 'package:otzaria/tools/calendar/utils/calendar_month_navigation.dart';
import 'package:otzaria/tools/calendar/view/widgets/jump_to_date_dialog.dart';
import 'package:otzaria/tools/calendar/view/panels/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/view/panels/widgets/calendar_events_panel.dart';
import 'package:otzaria/tools/calendar/view/panels/widgets/calendar_settings_panel.dart';
import 'package:otzaria/tools/calendar/view/panels/widgets/calendar_times_panel.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_main_panel.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_top_bar.dart';
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
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  Timer? _keyRepeatTimer;
  LogicalKeyboardKey? _currentPressedKey;
  bool _isJumpToDateDialogOpen = false;
  bool _isCreateEventDialogOpen = false;
  bool _isPrintDialogOpen = false;
  bool _isSidebarVisible = true;
  bool _isSearchMode = false;
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
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode(skipTraversal: true, canRequestFocus: true);
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

  /// מבקש מחדש את הפוקוס של לוח השנה אחרי מעבר מטאב אחר.
  void requestKeyboardFocus() {
    _requestFocusIfNeeded();
  }

  @override
  void dispose() {
    _keyboardFocusNode.removeListener(_handleFocusChange);
    _stopKeyRepeat();
    _keyboardFocusNode.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
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
    final newDate = shiftGregorianMonthPreservingDay(
      cubit.state.selectedGregorianDate,
      forward: forward,
    );
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

  Future<void> _openCalendarCalculationPage(BuildContext context) async {
    await showSingleActionDialog(
      context: context,
      title: 'אודות חישובי הלוח',
      content:
          'חישובי הלוח בתוכנה זו מיוסדים על דרכו של הרב ישראל דוד הרפנס, כפי שנתבארה בספרו ישראל והזמנים ובשאר ספריו העוסקים בענייני זמני הלכה. מטרת הדברים איננה להציג חישוב עצמאי חדש, אלא ליישם בצורה מסודרת, מדויקת ובהירה את כללי חשבון הלוח העברי על פי הביאור והסידור שנתפרשו בספריו.\n\nהרב הרפנס, מו"ץ בהתאחדות הרבנים ורב קהילת ישראל והזמנים, נודע במיוחד בבירור סוגיות הזמן בהלכה, וספרו ישראל והזמנים נזכר בקובץ זה כספר היסוד שעל פיו נבנתה תשתית החישוב שבתוכנה. לצד ספר זה, חיבר הרב גם ספרים נוספים בענייני הלכה וזמנים.',
      confirmText: 'הבנתי',
    );
  }

  void _toggleCalendarSettingsPanel() {
    setState(() {
      _sidePanelView = _sidePanelView == CalendarSidePanelView.settings
          ? CalendarSidePanelView.times
          : CalendarSidePanelView.settings;
    });
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
              _togglePrintCalendar(context, state);
            },
            _parseShortcut(contextSettingsShortcut): () {
              if (_isTextFieldFocused()) return;
              _toggleCalendarSettingsPanel();
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
                  if (_searchController.text != state.eventSearchQuery) {
                    _searchController.text = state.eventSearchQuery;
                  }
                  return Scaffold(
                    backgroundColor: Colors.transparent,
                    appBar: CalendarTopBar(
                      state: state,
                      isSearchMode: _isSearchMode,
                      searchController: _searchController,
                      searchFocusNode: _searchFocusNode,
                      onSearchChanged: (value) => context
                          .read<CalendarCubit>()
                          .setEventSearchQuery(value),
                      onToggleSearch: () {
                        setState(() => _isSearchMode = !_isSearchMode);
                        if (_isSearchMode) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _searchFocusNode.requestFocus();
                          });
                        } else {
                          _searchFocusNode.unfocus();
                        }
                      },
                      onJumpToToday: () =>
                          context.read<CalendarCubit>().jumpToToday(),
                      onPreviousPeriod: () =>
                          context.read<CalendarCubit>().previous(),
                      onNextPeriod: () => context.read<CalendarCubit>().next(),
                      onViewChanged: (value) => context
                          .read<CalendarCubit>()
                          .changeCalendarView(value),
                      onSidePanelViewChanged: (value) {
                        setState(() => _sidePanelView = value);
                      },
                      activeSidePanelView: _sidePanelView,
                      onPrint: () => _togglePrintCalendar(context, state),
                      onToggleSidebar: () => _toggleSidebar(context, isMobile),
                      parseInputDate: (input) =>
                          parseCalendarInputDate(context, input),
                      onJumpToDateSelected: (date) {
                        context.read<CalendarCubit>().jumpToDate(date);
                        setState(() => _isSearchMode = false);
                      },
                    ),
                    endDrawer:
                        isMobile ? _buildSidePanelDrawer(context, state) : null,
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
            onPressed: () => _togglePrintCalendar(context, state),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: _buildCalendar(context, state),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isSidebarVisible
                ? Padding(
                    padding: const EdgeInsets.only(right: AppTokens.spaceMD),
                    child: SizedBox(
                      width: 360,
                      child: FloatingPanel(
                        child: _buildSidePanel(context, state),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
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
    return CalendarMainPanel(
      state: state,
      onCreateEvent: ({existingEvent, specificDate}) => _showCreateEventDialog(
        context,
        state,
        existingEvent: existingEvent,
        specificDate: specificDate,
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
      timesPanel: CalendarTimesPanel(
        state: state,
        onOpenCalendarCalculationPage: _openCalendarCalculationPage,
      ),
      eventsPanel: CalendarEventsPanel(
        state: state,
        onCreateEvent: ({existingEvent, specificDate}) =>
            _showCreateEventDialog(
          context,
          state,
          existingEvent: existingEvent,
          specificDate: specificDate,
        ),
      ),
      settingsPanel: const CalendarSettingsPanel(),
    );
  }

  // ─── Dialogs ───────────────────────────────────────────────────────────────

  void _showJumpToDateDialog(BuildContext context) {
    _isJumpToDateDialogOpen = true;
    showJumpToDateDialog(
      context: context,
      parseInputDate: (input) => parseCalendarInputDate(context, input),
    ).then((selectedDate) {
      if (selectedDate != null && context.mounted) {
        context.read<CalendarCubit>().jumpToDate(selectedDate);
      }
      _isJumpToDateDialogOpen = false;
    });
  }

  void _showCreateEventDialog(
    BuildContext context,
    CalendarState state, {
    CustomEvent? existingEvent,
    DateTime? specificDate,
  }) {
    if (_isCreateEventDialogOpen) {
      Navigator.of(context).pop();
      _isCreateEventDialogOpen = false;
      return;
    }

    _isCreateEventDialogOpen = true;
    showCalendarEventDialog(
      context: context,
      state: state,
      existingEvent: existingEvent,
      specificDate: specificDate,
    ).then((result) {
      _isCreateEventDialogOpen = false;
      if (result == null || !context.mounted) {
        return;
      }

      final cubit = context.read<CalendarCubit>();
      final displayedGregorianDate = existingEvent != null
          ? existingEvent.baseGregorianDate
          : (specificDate ?? state.selectedGregorianDate);

      if (existingEvent != null) {
        cubit.updateEvent(existingEvent.copyWith(
          title: result.title,
          description: result.description,
          recurrenceType: result.recurrenceType,
          recurringYears: result.recurringYears,
          eventTime: result.eventTime,
        ));
      } else {
        cubit.addEvent(
          title: result.title,
          description: result.description,
          baseGregorianDate: displayedGregorianDate,
          recurrenceType: result.recurrenceType,
          recurringYears: result.recurringYears,
          eventTime: result.eventTime,
        );
      }
    });
  }

  void _togglePrintCalendar(BuildContext context, CalendarState state) {
    if (_isPrintDialogOpen) {
      Navigator.of(context).pop();
      _isPrintDialogOpen = false;
      return;
    }

    _isPrintDialogOpen = true;
    showCalendarPrintDialog(
      context: context,
      calendarView: state.calendarView,
    ).then((count) {
      _isPrintDialogOpen = false;
      if (count == null || !context.mounted) {
        return;
      }

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PrintingScreen(
          data: Future.value(''),
          bookId: 'calendar',
          createPdfOverride: (format) =>
              print_helper.createCalendarPdf(state, format, count: count),
        ),
      ));
    });
  }
}
