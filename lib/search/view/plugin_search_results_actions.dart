import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/search_dialog_query.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

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
            if (!context.mounted) return;
            final currentState = tab.searchBloc.state;
            if (!actionsFor(registry, currentState).any(
              (action) => action.$1 == pluginId && action.$2.id == itemId,
            )) {
              return;
            }
            final payload = {
              'itemId': itemId,
              'request': _request(currentState),
            };
            if (launcher != null) {
              launcher!(pluginId, payload);
            } else {
              launchPluginSearch(context, pluginId, payload);
            }
          }

          switch (layout) {
            case PluginSearchResultsActionsLayout.bar:
              if (actions.isEmpty) return const SizedBox.shrink();
              if (iconOnly) {
                return _NarrowBarActions(actions: actions, onOpen: open);
              }
              // tonal כמו בוררי המיון והאיחוד שלידו: כפתור שקוף נבלע בסרגל.
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSM,
                    vertical: AppTokens.spaceXS,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (index, (pluginId, item))
                          in actions.indexed) ...[
                        if (index > 0) const SizedBox(width: AppTokens.spaceSM),
                        ActionButton.neutral(
                          text: item.resultsAction!,
                          icon: _iconOf(item),
                          onPressed: () => open(pluginId, item.id),
                        ),
                      ],
                    ],
                  ),
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
                        icon: _iconOf(item),
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

/// אייקון כפתור הפעולה: מה שהתוסף הצהיר עליו (`resultsActionIcon`), ובלעדיו
/// או עם שם שאינו מוכר, "פתח".
IconData _iconOf(PluginSearchDialogItem item) =>
    pluginIconFromName(item.resultsActionIcon) ?? FluentIcons.open_24_regular;

/// גודל כפתורי האייקון בסרגל החיפוש, כמו בוררי המיון והאיחוד: נמוך מגובה
/// הסרגל בצפיפות מצומצמת.
const BoxConstraints _iconOnlyConstraints = BoxConstraints.tightFor(
  width: 36,
  height: 36,
);

/// הפעולות בסרגל צר: כפתור אייקון tonal אחד לפעולה בודדת, ותפריט אחד
/// (באותו מראה) כשיש כמה: אייקונים זהים בלי תווית אי אפשר להבדיל.
class _NarrowBarActions extends StatelessWidget {
  const _NarrowBarActions({required this.actions, required this.onOpen});

  final List<(String, PluginSearchDialogItem)> actions;
  final void Function(String pluginId, String itemId) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const padding = EdgeInsets.symmetric(
      horizontal: AppTokens.spaceSM,
      vertical: AppTokens.spaceXS,
    );
    if (actions.length > 1) {
      return Padding(
        padding: padding,
        child: AppPopupMenuButton<(String, String)>(
          tooltip: 'המשך בתוסף',
          icon: const Icon(FluentIcons.open_24_regular, size: AppTokens.iconMD),
          highlighted: true,
          constraints: _iconOnlyConstraints,
          entries: [
            for (final (pluginId, item) in actions)
              AppMenuEntry(
                value: (pluginId, item.id),
                label: item.resultsAction!,
                icon: _iconOf(item),
              ),
          ],
          onSelected: (action) => onOpen(action.$1, action.$2),
        ),
      );
    }
    final (pluginId, item) = actions.single;
    return Padding(
      padding: padding,
      child: IconButton(
        tooltip: item.resultsAction,
        onPressed: () => onOpen(pluginId, item.id),
        constraints: _iconOnlyConstraints,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
          shape: AppTokens.roundedShape,
        ),
        icon: Icon(_iconOf(item), size: AppTokens.iconMD),
      ),
    );
  }
}
