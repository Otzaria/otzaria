import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/tool_page_factory.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/misc/exit_fullscreen_button.dart';

/// האם למקד את צומת התוכן של טאב כלי.
///
/// בתוסף לעולם לא: ה-WebView מגשר את פוקוס פלאטר לפוקוס הנייטיבי, וכל
/// `requestFocus` על צומת אב שלו מריץ `document.activeElement.blur()` ומוחק
/// את סמן הכתיבה מהשדה שהמשתמש מקליד בו. `contentHasFocus` כולל צאצאים.
@visibleForTesting
bool shouldRequestToolContentFocus({
  required bool isPlugin,
  required bool contentIsAttached,
  required bool contentHasFocus,
}) {
  if (isPlugin) return false;
  return contentIsAttached && !contentHasFocus;
}

/// מסך של כלי מובנה או תוסף, כחלונית בתוך מסך העיון.
///
/// מחזיק מפתחות פר-טאב (ולא פר-מסך כמו במסך הכלים הישן), כדי ששני טאבים של
/// אותו כלי מובנה לא יתנגשו.
class ToolTabScreen extends StatefulWidget {
  final ToolTab tab;

  const ToolTabScreen({super.key, required this.tab});

  @override
  State<ToolTabScreen> createState() => ToolTabScreenState();
}

class ToolTabScreenState extends State<ToolTabScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _calendarFocusRetryCount = 6;

  final GlobalKey<CalendarWidgetState> _calendarKey =
      GlobalKey<CalendarWidgetState>();
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  final FocusNode _contentFocusNode = FocusNode(skipTraversal: true);

  /// התוכן נבנה רק אחרי שהטאב הוצג בפועל. בלי זה, החלקה במובייל על-פני
  /// כרטיסיות הייתה בונה WebView לכל טאב תוסף בדרך.
  bool _activated = false;

  @override
  bool get wantKeepAlive => _activated;

  @override
  void initState() {
    super.initState();
    FocusRepository().registerTabContentFocusRequester(
      widget.tab,
      _requestContentFocus,
    );
  }

  @override
  void dispose() {
    FocusRepository().unregisterTabContentFocusRequester(widget.tab);
    _contentFocusNode.dispose();
    super.dispose();
  }

  // ─── Focus ───────────────────────────────────────────────────────────────

  void _requestContentFocus() {
    if (!mounted) return;
    if (widget.tab.toolId == 'builtin.calendar') {
      _requestCalendarFocus();
      return;
    }
    if (shouldRequestToolContentFocus(
      isPlugin: widget.tab.isPlugin,
      contentIsAttached: _contentFocusNode.enclosingScope != null,
      contentHasFocus: _contentFocusNode.hasFocus,
    )) {
      _contentFocusNode.requestFocus();
    }
  }

  void _requestCalendarFocus({
    int remainingAttempts = _calendarFocusRetryCount,
  }) {
    if (!mounted) return;
    final calendarState = _calendarKey.currentState;
    if (calendarState != null) {
      calendarState.requestKeyboardFocus();
      return;
    }
    if (remainingAttempts <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _requestCalendarFocus(remainingAttempts: remainingAttempts - 1);
        }
      });
    });
  }

  /// מאפס את לוח השנה לתאריך של היום. משמש את "הדף היומי" בספרייה, שממחזר
  /// טאב לוח-שנה קיים במקום לפתוח חדש.
  void resetToToday() {
    if (widget.tab.toolId != 'builtin.calendar') return;
    if (mounted) context.read<CalendarCubit>().jumpToToday();
    _requestCalendarFocus();
  }

  void closeTransientPanels() {
    if (widget.tab.toolId == 'builtin.calendar') {
      _calendarKey.currentState?.closeTransientPanels();
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  void _markActivated() {
    if (_activated) return;
    // ה-flag נקבע בתוך build; דוחים את ה-setState לפוסט-פריים.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activated) return;
      setState(() => _activated = true);
      updateKeepAlive();
    });
  }

  /// האם הטאב מוצג כרגע. `TickerMode` כבר משקף בדיוק את זה עבור טאב העיון
  /// הפעיל, ולכן אין צורך בערוץ נוסף.
  bool get _isVisible => TickerMode.valuesOf(context).enabled;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isVisible) _markActivated();
    if (!_activated) return const SizedBox.shrink();

    final settingsState = context.watch<SettingsBloc>().state;
    final pluginState = context.watch<PluginSystemBloc>().state;
    final lookup = lookupTool(
      widget.tab.toolId,
      hiddenBuiltInToolIds: settingsState.hiddenBuiltInToolIds,
      isOfflineMode: settingsState.isOfflineMode,
      pluginState: pluginState,
    );

    final Widget content = switch (lookup) {
      ToolAvailable(:final entry) => _buildToolContent(entry),
      ToolUnavailable(reason: ToolUnavailableReason.loading) => const Center(
        child: CircularProgressIndicator(),
      ),
      final ToolUnavailable unavailable => _buildUnavailable(unavailable),
    };

    return Stack(
      children: [
        Positioned.fill(
          child: Focus(
            focusNode: _contentFocusNode,
            child: ColoredBox(
              color: AppSurfaces.panelBackground(context),
              child: content,
            ),
          ),
        ),
        // במסך מלא אין שורת כותרת ואין סרגל ניווט; בלי הכפתור הזה אין דרך
        // לצאת מטאב כלי (בתוסף ה-Escape נבלע ב-WebView).
        if (settingsState.isFullscreen)
          const Positioned(top: 8, right: 8, child: ExitFullscreenButton()),
      ],
    );
  }

  Widget _buildToolContent(ToolCatalogEntry entry) {
    final plugin = entry.plugin;
    if (plugin != null) return buildPluginToolPage(plugin);
    return buildBuiltInToolPage(
          entry.toolId,
          calendarKey: _calendarKey,
          gematriaKey: _gematriaKey,
        ) ??
        _buildUnavailable(
          const ToolUnavailable(ToolUnavailableReason.notFound),
        );
  }

  Widget _buildUnavailable(ToolUnavailable unavailable) {
    final name = unavailable.name ?? widget.tab.title;
    final (message, subtitle) = switch (unavailable.reason) {
      ToolUnavailableReason.builtInHidden => (
        'הכלי "$name" מוסתר',
        'ניתן להציג אותו דרך הגדרות ← ניהול כלים',
      ),
      ToolUnavailableReason.pluginDisabled => (
        'התוסף "$name" מושבת',
        'ניתן להפעיל אותו דרך הגדרות ← ניהול כלים',
      ),
      ToolUnavailableReason.pluginHiddenFromTools => (
        'התוסף "$name" אינו מוצג בכלים',
        'ניתן להציג אותו דרך הגדרות ← ניהול כלים',
      ),
      ToolUnavailableReason.pluginRequiresInternet => (
        'התוסף "$name" דורש חיבור אינטרנט',
        'התוסף חסום כל עוד אוצריא במצב מנותק',
      ),
      _ => ('הכלי "$name" אינו זמין', 'ייתכן שהוסר מהתוכנה'),
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: ToolEmptyState(
            icon: FluentIcons.plug_disconnected_24_regular,
            message: message,
            subtitle: subtitle,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceXL),
          child: ActionButton.neutral(
            text: 'סגור כרטיסיה',
            onPressed: () =>
                context.read<TabsBloc>().add(RemoveTab(widget.tab)),
          ),
        ),
      ],
    );
  }
}
