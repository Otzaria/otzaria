import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/view/widgets/plugin_update_chip.dart';
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
/// WebView של תוסף מאבד את סמן הכתיבה אם צומת האב מקבל פוקוס.
@visibleForTesting
bool shouldRequestToolContentFocus({
  required bool isPlugin,
  required bool contentIsAttached,
  required bool contentHasFocus,
}) {
  if (isPlugin) return false;
  return contentIsAttached && !contentHasFocus;
}

/// מייצב את תוצאת [lookupTool] מול מצבי ביניים של רישום התוספים.
///
/// `PluginSystemBloc` אינו נמצא ב-`PluginSystemLoaded` לאורך כל חייו: טעינה
/// מחדש של הרישום (אחרי התקנה, הצמדה, סידור מחדש) ודיאלוג ההרשאות של התקנה
/// מעבירים אותו במצבים אחרים, ובהם `lookupTool` מחזיר `loading` — כלומר
/// "עדיין לא ידוע", לא "אינו זמין". החלפת הכלי בספינר באותם רגעים מוציאה את
/// `PluginTabPage` מהעץ, הורסת את ה-WebView של התוסף וגורמת לו להיטען מאפס.
/// לכן כל עוד ידוע כלי קודם — ממשיכים להציג אותו.
@visibleForTesting
ToolLookupResult resolveToolLookup(
  ToolLookupResult lookup,
  ToolCatalogEntry? lastEntry,
) {
  if (lastEntry != null &&
      lookup is ToolUnavailable &&
      lookup.reason == ToolUnavailableReason.loading) {
    return ToolAvailable(lastEntry);
  }
  return lookup;
}

/// מסך של כלי מובנה או תוסף בתוך מסך העיון.
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

  /// התוכן נבנה רק כשהטאב מוצג, כדי לא ליצור WebView מראש.
  bool _activated = false;

  /// הכלי שהוצג לאחרונה — ראה [resolveToolLookup].
  ToolCatalogEntry? _lastEntry;

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

  void _requestContentFocus() {
    if (!mounted) return;
    if (widget.tab.toolId == 'builtin.calendar') {
      _requestCalendarFocus();
      return;
    }
    if (widget.tab.isPlugin) {
      // פוקוס ה-WebView חי מחוץ לעץ של Flutter, ולכן נדרשת העברה נייטיבית.
      unawaited(
        PluginRuntimeDispatcher.instance.requestKeyboardFocus(
          widget.tab.toolId,
          instanceId: widget.tab.instanceId,
        ),
      );
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

  /// מאפס את לוח השנה לתאריך של היום.
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

  void _markActivated() {
    if (_activated) return;
    // עדכון מצב מתוך build נדחה לסוף הפריים.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activated) return;
      setState(() => _activated = true);
      updateKeepAlive();
    });
  }

  /// האם הטאב מוצג כרגע.
  bool get _isVisible => TickerMode.valuesOf(context).enabled;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isVisible) _markActivated();
    if (!_activated) return const SizedBox.shrink();

    final settingsState = context.watch<SettingsBloc>().state;
    final pluginState = context.watch<PluginSystemBloc>().state;
    final lookup = resolveToolLookup(
      lookupTool(
        widget.tab.toolId,
        hiddenBuiltInToolIds: settingsState.hiddenBuiltInToolIds,
        isOfflineMode: settingsState.isOfflineMode,
        pluginState: pluginState,
      ),
      _lastEntry,
    );

    final Widget content = switch (lookup) {
      ToolAvailable(:final entry) => _buildToolContent(_lastEntry = entry),
      // ספינר רק בטעינה הראשונה — אחריה resolveToolLookup מחזיר את הכלי הקודם.
      ToolUnavailable(reason: ToolUnavailableReason.loading) => const Center(
        child: CircularProgressIndicator(),
      ),
      final ToolUnavailable unavailable => _buildUnavailable(unavailable),
    };

    final plugin = lookup is ToolAvailable ? lookup.entry.plugin : null;
    if (plugin != null) _requestUpdateCheck(pluginState);

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
        // WebView עלול לבלוע Escape במסך מלא.
        if (settingsState.isFullscreen)
          const Positioned(top: 8, right: 8, child: ExitFullscreenButton()),
        if (plugin != null)
          PositionedDirectional(
            bottom: 16,
            start: 16,
            child: PluginUpdateChip(plugin: plugin),
          ),
      ],
    );
  }

  /// בדיקת עדכונים עצלה בפתיחת טאב תוסף — הקוביט מתלכד וממטמן, כך שפתיחת
  /// כמה טאבים גוררת לכל היותר קריאת רשת אחת לחלון זמן.
  void _requestUpdateCheck(PluginSystemState pluginState) {
    if (pluginState is! PluginSystemLoaded) return;
    final cubit = context.read<PluginUpdatesCubit>();
    final plugins = pluginState.plugins;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cubit.ensureChecked(plugins);
    });
  }

  Widget _buildToolContent(ToolCatalogEntry entry) {
    final plugin = entry.plugin;
    if (plugin != null) {
      return buildPluginToolPage(plugin, instanceId: widget.tab.instanceId);
    }
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
    // הכלי אינו זמין (הוסר/הושבת/הוסתר) — אין למה לחזור בטעינה הבאה.
    _lastEntry = null;
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
