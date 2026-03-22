// lib/tools/calendar/view/calendar_screen.dart
//
// **שינויים:**
// • CalendarTopBar עבר מ-appBar ל-body Column (כמו LibraryBrowser)
//   → מאפשר שימוש ב-AppTopBar ללא PreferredSizeWidget
// • Layout דסקטופ: Row עם Expanded — ללא SingleChildScrollView
//   → הלוח ממלא את כל הגובה
// • Layout מובייל: נשמר SingleChildScrollView
// • CalendarView.day ו-.week מציגות את לוח החודש (ב-CalendarMainPanel)

// ignore_for_file: unused_element

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/printing/printing_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/widgets/floating_panel.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
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
  Timer? _keyRepeatTimer;
  LogicalKeyboardKey? _currentPressedKey;
  bool _isJumpToDateDialogOpen = false;
  bool _isCreateEventDialogOpen = false;
  bool _isPrintDialogOpen = false;
  bool _isSidebarVisible = true;
  CalendarSidePanelView _sidePanelView = CalendarSidePanelView.times;

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode(skipTraversal: true, canRequestFocus: true);
    _keyboardFocusNode.addListener(_onFocusChange);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _requestFocusIfNeeded());
  }

  @override
  void didUpdateWidget(CalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _requestFocusIfNeeded());
  }

  void _onFocusChange() {
    if (!_keyboardFocusNode.hasFocus) _stopKeyRepeat();
  }

  void _requestFocusIfNeeded() {
    if (!mounted) return;
    requestFocusIfNeeded(_keyboardFocusNode);
  }

  void requestKeyboardFocus() => _requestFocusIfNeeded();

  @override
  void dispose() {
    _keyboardFocusNode.removeListener(_onFocusChange);
    _stopKeyRepeat();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  // ─── Keyboard ───────────────────────────────────────────────────────────────

  void _stopKeyRepeat() {
    _keyRepeatTimer?.cancel();
    _keyRepeatTimer = null;
    _currentPressedKey = null;
  }

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
        forward: forward);
    cubit.jumpToDate(newDate);
  }

  void _navigateYear(BuildContext context, {required bool forward}) {
    final cubit = context.read<CalendarCubit>();
    final current = cubit.state.selectedGregorianDate;
    cubit.jumpToDate(DateTime(
        current.year + (forward ? 1 : -1), current.month, current.day));
  }

  void _toggleSidebar(BuildContext context, bool isMobile) {
    if (isMobile) {
      Scaffold.of(context).openEndDrawer();
      return;
    }
    setState(() => _isSidebarVisible = !_isSidebarVisible);
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        final shortcuts = context.watch<SettingsBloc>().state.shortcuts;

        return CallbackShortcuts(
          bindings: {
            _parseShortcut(shortcuts['key-shortcut-calendar-navigate-times'] ??
                'ctrl+e'): () {
              if (_isTextFieldFocused()) return;
              setState(() {
                _sidePanelView = _sidePanelView == CalendarSidePanelView.times
                    ? CalendarSidePanelView.events
                    : CalendarSidePanelView.times;
              });
            },
            _parseShortcut(
                shortcuts['key-shortcut-calendar-today'] ?? 'ctrl+d'): () {
              if (_isTextFieldFocused()) return;
              context.read<CalendarCubit>().jumpToToday();
            },
            _parseShortcut(shortcuts['key-shortcut-calendar-jump-date'] ??
                'ctrl+shift+d'): () {
              if (_isTextFieldFocused()) return;
              if (_isJumpToDateDialogOpen) {
                Navigator.of(context).pop();
                _isJumpToDateDialogOpen = false;
              } else {
                _showJumpToDateDialog(context);
              }
            },
            _parseShortcut(shortcuts['key-shortcut-calendar-create-event'] ??
                'ctrl+n'): () {
              if (_isTextFieldFocused()) return;
              _showCreateEventDialog(context, state);
            },
            _parseShortcut(shortcuts['key-shortcut-calendar-toggle-view'] ??
                'ctrl+shift+e'): () {
              if (_isTextFieldFocused()) return;
              final cubit = context.read<CalendarCubit>();
              cubit.changeCalendarView(switch (state.calendarView) {
                CalendarView.month => CalendarView.week,
                CalendarView.week => CalendarView.day,
                CalendarView.day => CalendarView.month,
              });
            },
            _parseShortcut(shortcuts['key-shortcut-print'] ?? 'ctrl+p'): () {
              if (_isTextFieldFocused()) return;
              _togglePrintCalendar(context, state);
            },
            _parseShortcut(shortcuts['key-shortcut-open-context-settings'] ??
                'ctrl+shift+comma'): () {
              if (_isTextFieldFocused()) return;
              setState(() {
                _sidePanelView =
                    _sidePanelView == CalendarSidePanelView.settings
                        ? CalendarSidePanelView.times
                        : CalendarSidePanelView.settings;
              });
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
                    backgroundColor: Colors.transparent,
                    endDrawer:
                        isMobile ? _buildSidePanelDrawer(context, state) : null,
                    // ── גוף: Topbar + תוכן ──────────────────────────────
                    body: Column(
                      children: [
                        // סרגל עליון חדש (לא appBar)
                        CalendarTopBar(
                          state: state,
                          onJumpToToday: () =>
                              context.read<CalendarCubit>().jumpToToday(),
                          onPreviousPeriod: () =>
                              context.read<CalendarCubit>().previous(),
                          onNextPeriod: () =>
                              context.read<CalendarCubit>().next(),
                          onViewChanged: (v) => context
                              .read<CalendarCubit>()
                              .changeCalendarView(v),
                          onSidePanelViewChanged: (v) =>
                              setState(() => _sidePanelView = v),
                          activeSidePanelView: _sidePanelView,
                          onPrint: () => _togglePrintCalendar(context, state),
                          onToggleSidebar: () =>
                              _toggleSidebar(context, isMobile),
                          parseInputDate: (input) =>
                              parseCalendarInputDate(context, input),
                          onJumpToDateSelected: (date) {
                            context.read<CalendarCubit>().jumpToDate(date);
                          },
                        ),
                        // תוכן
                        Expanded(
                          child: isMobile
                              ? _buildMobileLayout(context, state)
                              : _buildDesktopLayout(context, state),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Layouts ────────────────────────────────────────────────────────────────

  Widget _buildDesktopLayout(BuildContext context, CalendarState state) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── לוח חודש מלא (Expanded) ────────────────────────────────────
          Expanded(
            child: CalendarMainPanel(
              state: state,
              onCreateEvent: ({existingEvent, specificDate}) =>
                  _showCreateEventDialog(context, state,
                      existingEvent: existingEvent, specificDate: specificDate),
            ),
          ),
          // ── לוח צד (AnimatedSize) ────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isSidebarVisible
                ? Padding(
                    padding: const EdgeInsets.only(right: AppTokens.spaceMD),
                    child: SizedBox(
                      width: 340,
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
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: CalendarMainPanel(
          state: state,
          onCreateEvent: ({existingEvent, specificDate}) =>
              _showCreateEventDialog(context, state,
                  existingEvent: existingEvent, specificDate: specificDate),
        ),
      ),
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

  Widget _buildSidePanel(BuildContext context, CalendarState state) {
    return CalendarSidePanel(
      state: state,
      activeView: _sidePanelView,
      onViewChanged: (v) => setState(() => _sidePanelView = v),
      timesPanel: CalendarTimesPanel(
        state: state,
        onOpenCalendarCalculationPage: _openCalendarCalculationPage,
      ),
      eventsPanel: CalendarEventsPanel(
        state: state,
        onCreateEvent: ({existingEvent, specificDate}) =>
            _showCreateEventDialog(context, state,
                existingEvent: existingEvent, specificDate: specificDate),
      ),
      settingsPanel: const CalendarSettingsPanel(),
    );
  }

  // ─── Dialogs ─────────────────────────────────────────────────────────────────

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
      if (result == null || !context.mounted) return;
      final cubit = context.read<CalendarCubit>();
      final displayedDate = existingEvent != null
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
          baseGregorianDate: displayedDate,
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
      if (count == null || !context.mounted) return;
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

  Future<void> _openCalendarCalculationPage(BuildContext context) async {
    await showSingleActionDialog(
      context: context,
      title: 'אודות חישובי הלוח',
      content:
          'חישובי הלוח בתוכנה זו מיוסדים על דרכו של הרב ישראל דוד הרפנס...',
      confirmText: 'הבנתי',
    );
  }
}
