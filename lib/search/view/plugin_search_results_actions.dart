import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/search_dialog_query.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

/// היכן מוצגים כפתורי `resultsAction`.
enum PluginSearchResultsActionsLayout {
  /// כפתורים בסרגל העליון של טאב החיפוש.
  bar,

  /// כפתורים בגוף המסך: במצב "אין תוצאות" ואחרי התוצאה האחרונה.
  inline,
}

/// כפתורי תוספים לאחר סיום חיפוש, גם בלי תוצאות.
/// לחיצה מוסרת `search.requested` עם הגדרות אותו חיפוש.
class PluginSearchResultsActions extends StatelessWidget {
  const PluginSearchResultsActions({
    super.key,
    required this.tab,
    this.layout = PluginSearchResultsActionsLayout.bar,
    this.iconOnly = false,
    this.leading = const [],
    this.padding = EdgeInsets.zero,
    this.registry,
    this.launcher,
  });

  final SearchingTab tab;

  final PluginSearchResultsActionsLayout layout;

  /// בסרגל שאין בו מקום — אייקון בלבד, והכותרת ב-tooltip.
  final bool iconOnly;

  /// ב-[PluginSearchResultsActionsLayout.inline]: ווידג'טים שמוצגים באותה
  /// שורה לפני כפתורי התוספים (למשל "ערוך חיפוש"), ונשארים גם כשאין תוסף.
  final List<Widget> leading;

  /// ריווח סביב כפתורי התוספים; נוסף רק כשיש כפתור להציג.
  final EdgeInsetsGeometry padding;

  /// ברירת המחדל: [PluginSearchDialogRegistry.instance] (לבדיקות).
  final PluginSearchDialogRegistry? registry;

  /// ברירת המחדל: [launchPluginSearch] (לבדיקות).
  final PluginSearchSubmitLauncher? launcher;

  /// האם יש כפתור להציג כרגע ב-[state]. מקור אמת יחיד לווידג'ט ולסרגל
  /// העליון, שאינו מוסיף פריט (ורווח) כשהווידג'ט ריק.
  static bool hasActions(
    PluginSearchDialogRegistry registry,
    SearchState state,
  ) => actionsFor(registry, state).isNotEmpty;

  /// השורות שמצהירות `resultsAction` ורלוונטיות למצב החיפוש. ריק כל עוד
  /// החיפוש לא הסתיים, ובמצבים שבהם גוף המסך מציג הודעה במקום תוצאות
  /// (שגיאה, "לא נבחרו קטגוריות", מגבלת אפשרויות).
  static List<(String, PluginSearchDialogItem)> actionsFor(
    PluginSearchDialogRegistry registry,
    SearchState state,
  ) {
    if (state.searchQuery.isEmpty ||
        state.errorMessage != null ||
        state.hasNoSelectedFacets ||
        (state.results.isEmpty && state.resultsTruncated)) {
      return const [];
    }
    // טעינת המשך (תוצאות כבר מוצגות, בלי ספירה) אינה מסתירה את הכפתור:
    // אחרת הוא היה מהבהב ומזיז את הסרגל בכל עמוד שנטען.
    if (state.isLoading && (state.isCounting || state.results.isEmpty)) {
      return const [];
    }
    final mode = state.configuration.searchMode;
    return registry
        .getAll()
        .where(
          (record) =>
              record.$2.resultsAction != null && record.$2.isVisibleIn(mode),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final registry = this.registry ?? PluginSearchDialogRegistry.instance;
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) => BlocBuilder<SearchBloc, SearchState>(
        bloc: tab.searchBloc,
        builder: (context, state) {
          final actions = actionsFor(registry, state);
          void open(String pluginId, String itemId) {
            final payload = {'itemId': itemId, 'request': _request(state)};
            if (launcher != null) {
              launcher!(pluginId, payload);
            } else {
              launchPluginSearch(context, pluginId, payload);
            }
          }

          switch (layout) {
            case PluginSearchResultsActionsLayout.bar:
              if (actions.isEmpty) return const SizedBox.shrink();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (pluginId, item) in actions)
                      BarButton.icon(
                        icon: FluentIcons.open_24_regular,
                        label: iconOnly ? null : item.resultsAction,
                        tooltip: item.resultsAction!,
                        onPressed: () => open(pluginId, item.id),
                      ),
                  ],
                ),
              );
            case PluginSearchResultsActionsLayout.inline:
              if (actions.isEmpty && leading.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: actions.isEmpty ? EdgeInsets.zero : padding,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ...leading,
                    for (final (pluginId, item) in actions)
                      ActionButton.neutral(
                        text: item.resultsAction!,
                        icon: FluentIcons.open_24_regular,
                        onPressed: () => open(pluginId, item.id),
                      ),
                  ],
                ),
              );
          }
        },
      ),
    );
  }

  Map<String, dynamic> _request(SearchState state) {
    final configuration = state.configuration;
    final (positive, negative) = tab.normalizedSearchParameters(
      state.searchQuery,
      state.negativeQuery,
    );
    return pluginSearchRequest(
      query: state.searchQuery,
      negativeQuery: state.negativeQuery,
      mode: configuration.searchMode,
      distance: configuration.distance,
      proximityScope: configuration.proximityScope,
      facets: state.searchScopeFacets,
      configuration: configuration,
      normalizedParameters: positive,
      normalizedNegativeParameters: negative,
    );
  }
}
