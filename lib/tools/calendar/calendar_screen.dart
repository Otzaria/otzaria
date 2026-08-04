// lib/tools/calendar/calendar_screen.dart

import 'dart:async';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/shortcuts/key_map.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart'
    show kMainPanelMinWidth, kSideBySideMinWidth;
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_event_dialog.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_print_dialog.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_navigation_helpers.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_events_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_settings_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_times_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_main_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_top_bar.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_helpers.dart'
    as print_helper;
import 'package:otzaria/widgets/widgets_exports.dart';

export 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';

class CalendarWidget extends StatefulWidget {
  const CalendarWidget({super.key});

  @override
  State<CalendarWidget> createState() => CalendarWidgetState();
}

class CalendarWidgetState extends State<CalendarWidget> {
  late final FocusNode _keyboardFocusNode;
  Timer? _keyRepeatTimer;
  LogicalKeyboardKey? _currentPressedKey;
  bool _isJumpToDateSearchOpen = false;
  bool _isCreateEventDialogOpen = false;
  bool _isPrintDialogOpen = false;
  bool _isSidebarVisible = false;
  bool _isSidebarExplicitlyClosed = false;
  bool _isSidebarAutoHiddenForNarrow = false;
  bool? _lastHasRoomForSideBySide;
  bool _isSettingsPanelOpen = false;
  double _sidePanelWidth = 360;
  CalendarSidePanelView _sidePanelView = CalendarSidePanelView.times;

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode(skipTraversal: true, canRequestFocus: true);
    _keyboardFocusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestFocusIfNeeded(),
    );
  }

  @override
  void didUpdateWidget(CalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestFocusIfNeeded(),
    );
  }

  void _onFocusChange() {
    if (!_keyboardFocusNode.hasFocus) _stopKeyRepeat();
  }

  void _requestFocusIfNeeded() {
    if (!mounted || !_keyboardFocusNode.canRequestFocus) return;
    if (!_keyboardFocusNode.hasFocus) {
      _keyboardFocusNode.requestFocus();
    }
  }

  void requestKeyboardFocus() => _requestFocusIfNeeded();

  void closeTransientPanels() {
    if (!_isSettingsPanelOpen && !_isJumpToDateSearchOpen) return;
    setState(() {
      _isSettingsPanelOpen = false;
      _isJumpToDateSearchOpen = false;
    });
  }

  @override
  void deactivate() {
    if (_isSettingsPanelOpen) {
      _isSettingsPanelOpen = false;
    }
    super.deactivate();
  }

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
          _keyRepeatTimer = Timer.periodic(const Duration(milliseconds: 80), (
            timer,
          ) {
            final pressedKey = _currentPressedKey;
            if (pressedKey != null &&
                mounted &&
                HardwareKeyboard.instance.logicalKeysPressed.contains(
                  pressedKey,
                )) {
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

  /// ממיר מחרוזת קיצור (כגון 'ctrl+shift+f') ל-[ShortcutActivator].
  ///
  /// מחזיר [SingleActivator] עם modifiers מתאימים.
  /// אם המחרוזת אינה ניתנת לניתוח, מחזיר `null` ולא קושר קיצור שגוי.
  ShortcutActivator? _shortcutActivator(
    Map<String, String> shortcuts,
    String key,
    String fallback,
  ) {
    final configuredShortcut = shortcuts[key];
    final configuredActivator = configuredShortcut == null
        ? null
        : _activatorFromShortcut(configuredShortcut);
    if (configuredShortcut != null && configuredActivator == null) {
      debugPrint('Invalid shortcut for $key: $configuredShortcut');
    }

    final fallbackActivator = _activatorFromShortcut(fallback);
    if (fallbackActivator == null) {
      debugPrint('Invalid fallback shortcut for $key: $fallback');
    }

    return configuredActivator ?? fallbackActivator;
  }

  static const _modifiers = {'ctrl', 'control', 'shift', 'alt', 'meta'};

  ShortcutActivator? _activatorFromShortcut(String shortcut) {
    final parts = shortcut.toLowerCase().split('+');
    final hasCtrl = parts.contains('ctrl') || parts.contains('control');
    final hasShift = parts.contains('shift');
    final hasAlt = parts.contains('alt');
    final hasMeta = parts.contains('meta');

    final mainKeyName = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKeyName == null) return null;

    LogicalKeyboardKey? logicalKey;
    if (mainKeyName.length == 1) {
      // אות יחידה a–z
      final code = mainKeyName.codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        logicalKey = LogicalKeyboardKey(0x00000061 + (code - 97));
      }
    }
    logicalKey ??= KeyMap.keyFor(mainKeyName);
    if (logicalKey == null) return null;

    return SingleActivator(
      logicalKey,
      control: hasCtrl,
      shift: hasShift,
      alt: hasAlt,
      meta: hasMeta,
    );
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
    cubit.jumpToDate(
      DateTime(current.year + (forward ? 1 : -1), current.month, current.day),
    );
  }

  void _toggleSidebar(BuildContext context, bool isMobile) {
    setState(() {
      final nextVisible = !_isSidebarVisible;
      _isSidebarVisible = nextVisible;
      _isSidebarExplicitlyClosed = !nextVisible;
      if (nextVisible) {
        _isSidebarAutoHiddenForNarrow = false;
      }
    });
  }

  void _toggleTimesPanel() {
    setState(() {
      if (_sidePanelView == CalendarSidePanelView.times && _isSidebarVisible) {
        _isSidebarVisible = false;
        _isSidebarExplicitlyClosed = true;
        return;
      }
      _sidePanelView = CalendarSidePanelView.times;
      _isSidebarVisible = true;
      _isSidebarExplicitlyClosed = false;
      _isSidebarAutoHiddenForNarrow = false;
    });
  }

  void _toggleEventsPanel() {
    setState(() {
      if (_sidePanelView == CalendarSidePanelView.events && _isSidebarVisible) {
        _isSidebarVisible = false;
        _isSidebarExplicitlyClosed = true;
        return;
      }
      _sidePanelView = CalendarSidePanelView.events;
      _isSidebarVisible = true;
      _isSidebarExplicitlyClosed = false;
      _isSidebarAutoHiddenForNarrow = false;
    });
  }

  void _toggleSettingsPanel() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowForOverlay = screenWidth < kSideBySideMinWidth;

    setState(() {
      final nextOpen = !_isSettingsPanelOpen;
      _isSettingsPanelOpen = nextOpen;

      if (nextOpen && isNarrowForOverlay && _isSidebarVisible) {
        _isSidebarVisible = false;
        _isSidebarAutoHiddenForNarrow = true;
      }
    });
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        final shortcuts = context.watch<SettingsBloc>().state.shortcuts;
        final bindings = <ShortcutActivator, VoidCallback>{};

        void registerShortcut(
          String settingsKey,
          String fallback,
          VoidCallback callback,
        ) {
          final activator = _shortcutActivator(
            shortcuts,
            settingsKey,
            fallback,
          );
          if (activator != null) {
            bindings[activator] = callback;
          }
        }

        registerShortcut(
          'key-shortcut-calendar-toggle-times',
          'ctrl+t',
          () {
            if (_isTextFieldFocused()) return;
            _toggleTimesPanel();
          },
        );
        registerShortcut(
          'key-shortcut-calendar-toggle-events',
          'ctrl+e',
          () {
            if (_isTextFieldFocused()) return;
            _toggleEventsPanel();
          },
        );
        registerShortcut(
          'key-shortcut-calendar-today',
          'ctrl+d',
          () {
            if (_isTextFieldFocused()) return;
            context.read<CalendarCubit>().jumpToToday();
          },
        );
        registerShortcut(
          'key-shortcut-search-current-window',
          'ctrl+f',
          () {
            if (_isTextFieldFocused()) return;
            _toggleJumpToDateSearch();
          },
        );
        registerShortcut(
          'key-shortcut-calendar-create-event',
          'ctrl+shift+n',
          () {
            if (_isTextFieldFocused()) return;
            _showCreateEventDialog(context, state);
          },
        );
        registerShortcut(
          'key-shortcut-calendar-toggle-view',
          'ctrl+shift+e',
          () {
            if (_isTextFieldFocused()) return;
            final cubit = context.read<CalendarCubit>();
            cubit.changeCalendarView(switch (state.calendarView) {
              CalendarView.month => CalendarView.week,
              CalendarView.week => CalendarView.month,
              CalendarView.day => CalendarView.month,
            });
          },
        );
        registerShortcut('key-shortcut-print', 'ctrl+p', () {
          if (_isTextFieldFocused()) return;
          _togglePrintCalendar(context, state);
        });
        registerShortcut(
          'key-shortcut-open-context-settings',
          'ctrl+shift+comma',
          _toggleSettingsPanel,
        );

        bindings[const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
        )] = () {
          if (_isTextFieldFocused()) return;
          _navigateMonth(context, forward: true);
        };
        bindings[const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
        )] = () {
          if (_isTextFieldFocused()) return;
          _navigateMonth(context, forward: false);
        };
        bindings[const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          control: true,
        )] = () {
          if (_isTextFieldFocused()) return;
          _navigateYear(context, forward: true);
        };
        bindings[const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
        )] = () {
          if (_isTextFieldFocused()) return;
          _navigateYear(context, forward: false);
        };

        return CallbackShortcuts(
          bindings: bindings,
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
                  final hasRoomForSideBySide =
                      constraints.maxWidth >= kSideBySideMinWidth;
                  _syncSidebarVisibilityForWidth(
                    hasRoomForSideBySide,
                    isMobile: isMobile,
                  );
                  return Scaffold(
                    backgroundColor: Colors.transparent,
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
                          activeSidePanelView: _sidePanelView,
                          isSidePanelVisible: _isSidebarVisible,
                          isSettingsPanelOpen: _isSettingsPanelOpen,
                          onToggleTimesPanel: _toggleTimesPanel,
                          onToggleEventsPanel: _toggleEventsPanel,
                          onToggleSettingsPanel: _toggleSettingsPanel,
                          onPrint: () => _togglePrintCalendar(context, state),
                          onToggleSidebar: () =>
                              _toggleSidebar(context, isMobile),
                          isJumpToDateSearchOpen: _isJumpToDateSearchOpen,
                          onToggleJumpToDateSearch: _toggleJumpToDateSearch,
                          onCloseJumpToDateSearch: _closeJumpToDateSearch,
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
    return Stack(
      children: [
        // תוכן ראשי + חלונית צד
        AdaptiveSidePane(
          isOpen: _isSidebarVisible,
          alignment: AlignmentDirectional.centerStart, // שמאל בעברית (RTL)
          mainContent: CalendarMainPanel(
            state: state,
            onCreateEvent: ({existingEvent, specificDate}) =>
                _showCreateEventDialog(
                  context,
                  state,
                  existingEvent: existingEvent,
                  specificDate: specificDate,
                ),
          ),
          paneContent: _buildSidePanel(context, state),
          paneWidth: _sidePanelWidth,
          minMainContentWidth: kMainPanelMinWidth,
          onClose: _handleSidebarClosedByUser,
          autoHandleResponsiveVisibility: false,
          isResizable: true,
          minPaneWidth: 280,
          maxPaneWidth: 520,
          onPaneWidthChanged: (nextWidth) {
            _sidePanelWidth = nextWidth;
          },
          widePaneBuilder: (context, paneContent, paneWidth) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: paneContent,
          ),
          narrowPaneBuilder: (context, paneContent) => Material(
            color: AppSurfaces.solidPanelBackground(context),
            child: SafeArea(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 8),
                    child: paneContent,
                  ),
                  PositionedDirectional(
                    top: 4,
                    start: 4,
                    child: BarButton.icon(
                      tooltip: 'סגור חלונית',
                      icon: FluentIcons.dismiss_24_regular,
                      onPressed: _handleSidebarClosedByUser,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // פאנל הגדרות overlay
        ContextOverlayPanel(
          isOpen: _isSettingsPanelOpen,
          onClose: _toggleSettingsPanel,
          width: 400,
          title: 'הגדרות',
          child: const Expanded(
            child: CalendarSettingsPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, CalendarState state) {
    // במסך צר אין מקום לפריסה זה-לצד-זה (kSideBySideMinWidth=840), אז במקום
    // להחביא את חלונית הצד מאחורי טוגל מוצגים אותה מתחת ללוח. חלוקה 3:2 —
    // הלוח (חלוקת התצוגה הראשית) מקבל את רוב המקום והזמנים/אירועים מתחת.
    // המשתמש עדיין יכול לכווץ את החלק התחתון דרך כפתור ה-toggle בסרגל העליון.
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              flex: 3,
              child: CalendarMainPanel(
                state: state,
                onCreateEvent: ({existingEvent, specificDate}) =>
                    _showCreateEventDialog(
                      context,
                      state,
                      existingEvent: existingEvent,
                      specificDate: specificDate,
                    ),
              ),
            ),
            if (_isSidebarVisible) ...[
              Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: _buildSidePanel(context, state),
                ),
              ),
            ],
          ],
        ),
        ContextOverlayPanel(
          isOpen: _isSettingsPanelOpen,
          onClose: _toggleSettingsPanel,
          width: 400,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      'הגדרות',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: CalendarSettingsPanel(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _syncSidebarVisibilityForWidth(
    bool hasRoomForSideBySide, {
    required bool isMobile,
  }) {
    final previousHasRoomForSideBySide = _lastHasRoomForSideBySide;
    _lastHasRoomForSideBySide = hasRoomForSideBySide;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // במסך מוביילי הפריסה מוערמת — לוח למעלה וזמנים למטה — כך ששתי
      // החלוניות נראות יחד ואין צורך לחבא את חלונית הצד. דילוג על מנגנון
      // ה-auto-hide המיועד לטווח ה-medium (600-840) שבו חלונית הצד הופכת
      // ל-overlay.
      if (isMobile) {
        if (!_isSidebarVisible &&
            !_isSidebarExplicitlyClosed &&
            (_isSidebarAutoHiddenForNarrow ||
                previousHasRoomForSideBySide == null)) {
          setState(() {
            _isSidebarVisible = true;
            _isSidebarAutoHiddenForNarrow = false;
          });
        }
        return;
      }

      if (previousHasRoomForSideBySide == null) {
        if (hasRoomForSideBySide &&
            !_isSidebarVisible &&
            !_isSidebarExplicitlyClosed) {
          setState(() {
            _isSidebarVisible = true;
            _isSidebarAutoHiddenForNarrow = false;
          });
        }
        return;
      }

      if (previousHasRoomForSideBySide == true &&
          !hasRoomForSideBySide &&
          _isSidebarVisible &&
          !_isSidebarAutoHiddenForNarrow) {
        setState(() {
          _isSidebarVisible = false;
          _isSidebarAutoHiddenForNarrow = true;
        });
        return;
      }

      if (previousHasRoomForSideBySide == false &&
          hasRoomForSideBySide &&
          !_isSidebarVisible &&
          !_isSidebarExplicitlyClosed) {
        setState(() {
          _isSidebarVisible = true;
          _isSidebarAutoHiddenForNarrow = false;
        });
        return;
      }

      if (hasRoomForSideBySide && _isSidebarAutoHiddenForNarrow) {
        setState(() {
          _isSidebarAutoHiddenForNarrow = false;
        });
      }
    });
  }

  void _handleSidebarClosedByUser() {
    setState(() {
      _isSidebarVisible = false;
      _isSidebarExplicitlyClosed = true;
      _isSidebarAutoHiddenForNarrow = false;
    });
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
            _showCreateEventDialog(
              context,
              state,
              existingEvent: existingEvent,
              specificDate: specificDate,
            ),
      ),
    );
  }

  // ─── Dialogs ─────────────────────────────────────────────────────────────────

  void _toggleJumpToDateSearch() {
    setState(() => _isJumpToDateSearchOpen = !_isJumpToDateSearchOpen);
  }

  void _closeJumpToDateSearch() {
    setState(() => _isJumpToDateSearchOpen = false);
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
      if (existingEvent != null) {
        final jd = JewishDate.fromDateTime(result.selectedDate);
        cubit.updateEvent(
          existingEvent.copyWith(
            title: result.title,
            description: result.description,
            baseGregorianDate: result.selectedDate,
            baseJewishYear: jd.getJewishYear(),
            baseJewishMonth: jd.getJewishMonth(),
            baseJewishDay: jd.getJewishDayOfMonth(),
            recurrenceType: result.recurrenceType,
            recurringYears: result.recurringYears,
            eventTime: () => result.eventTime,
            endTime: () => result.endTime,
            endGregorianDate: () => result.endGregorianDate,
            colorIndex: () => result.colorIndex,
            notificationMinutes: result.notificationMinutes,
          ),
        );
      } else {
        cubit.addEvent(
          title: result.title,
          description: result.description,
          baseGregorianDate: result.selectedDate,
          recurrenceType: result.recurrenceType,
          recurringYears: result.recurringYears,
          eventTime: result.eventTime,
          endTime: result.endTime,
          endGregorianDate: result.endGregorianDate,
          colorIndex: result.colorIndex,
          notificationMinutes: result.notificationMinutes,
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
      closeShortcut: _shortcutActivator(
        context.read<SettingsBloc>().state.shortcuts,
        'key-shortcut-print',
        'ctrl+p',
      ),
    ).then((count) {
      _isPrintDialogOpen = false;
      if (count == null || !context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PrintingScreen(
          data: Future.value(''),
          bookId: 'calendar',
          createPdfOverride: (format) =>
              print_helper.createCalendarPdf(state, format, count: count),
        ),
      );
    });
  }

  Future<void> _openCalendarCalculationPage(BuildContext context) async {
    await showSingleActionDialog(
      context: context,
      title: 'אודות חישובי הלוח',
      content:
          'חישובי הלוח בתוכנה זו מיוסדים על דרכו של הרב ישראל דוד הרפנס, כפי שנתבארה בספרו ישראל והזמנים ובשאר ספריו העוסקים בענייני זמני הלכה. מטרת הדברים איננה להציג חישוב עצמאי חדש, אלא ליישם בצורה מסודרת, מדויקת ובהירה את כללי חשבון הלוח העברי על פי הביאור והסידור שנתפרשו בספריו.\n\n'
          'הרב הרפנס, מו"ץ בהתאחדות הרבנים ורב קהילת ישראל והזמנים, נודע במיוחד בבירור סוגיות הזמן בהלכה, וספרו ישראל והזמנים הוא ספר היסוד שעל פיו נבנתה תשתית החישוב שבתוכנה. לצד ספר זה, חיבר הרב גם ספרים נוספים בענייני הלכה שונים.\n\n'
          'אין בהבאת זמנים אלו משום נקיטת צד באופן החישוב, והם הובאו רק משום הקלות לשלבם בתוכנה.',
      confirmText: 'הבנתי',
    );
  }
}
