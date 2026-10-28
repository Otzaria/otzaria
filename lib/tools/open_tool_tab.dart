import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/tool_query.dart';

/// פותח כלי ככרטיסיה במסך העיון.
///
/// כלי שכבר פתוח ממוקד (dedupeKey) ומקבל את [query]; מופע נוסף נפתח דרך
/// [openNewToolTabInstance].
void openToolTab(
  BuildContext context,
  ToolCatalogEntry entry, {
  ToolQuery? query,
}) {
  context.read<TabsBloc>().add(
    OpenOrFocusTab(
      ToolTab(toolId: entry.toolId, title: entry.label, query: query),
    ),
  );
  context.read<NavigationBloc>().add(
    const NavigateToScreen(Screen.reading),
  );
}

/// בונה טאב של מופע נוסף לכלי — בלי dedupeKey, כך שפתיחתו לא תמקד טאב קיים.
ToolTab newToolTabInstance(ToolCatalogEntry entry) => ToolTab(
  toolId: entry.toolId,
  title: entry.label,
  allowMultipleInstances: true,
);

/// תקרת הכרטיסיות הפתוחות של אותו תוסף (כולל הראשונה). כל מופע הוא WebView
/// נפרד, וקריאה חוזרת של תוסף ל-`plugin.openSelf` עם `newTab` לא תוכל להציף
/// את המסך.
const int kMaxPluginToolInstances = 10;

/// מספר הכרטיסיות הפתוחות של הכלי [toolId], כולל חלוניות מפוצלות.
int openToolInstanceCount(Iterable<OpenedTab> tabs, String toolId) => tabs
    .expand(leafPanes)
    .whereType<ToolTab>()
    .where((tab) => tab.toolId == toolId)
    .length;

/// האם אפשר לפתוח מופע נוסף של [toolId], לפי הכרטיסיות הפתוחות ו-[pending]
/// פתיחות שנשלחו ועדיין אינן ב-state.
bool hasRoomForPluginInstance(
  Iterable<OpenedTab> tabs,
  String toolId, {
  int pending = 0,
}) => openToolInstanceCount(tabs, toolId) + pending < kMaxPluginToolInstances;

/// פותח מופע נוסף של תוסף מותקן בכרטיסיה חדשה — הנתיב של `plugin.openSelf`
/// עם `newTab: true`.
///
/// מחזיר את מזהה המופע שנפתח, או `null` כשהפתיחה נדחתה: הכלי אינו זמין, או
/// שכבר פתוחות [kMaxPluginToolInstances] כרטיסיות שלו (בשני המקרים מוצגת הודעה).
/// כשרשימת התוספים עדיין נטענת הכרטיסיה נפתחת עם כותרת גיבוי, כמו ב-
/// [openToolTabById].
String? openPluginToolInstanceById(BuildContext context, String pluginId) {
  final settingsState = context.read<SettingsBloc>().state;
  final result = lookupTool(
    pluginId,
    hiddenBuiltInToolIds: settingsState.hiddenBuiltInToolIds,
    isOfflineMode: settingsState.isOfflineMode,
    pluginState: context.read<PluginSystemBloc>().state,
  );
  final ToolTab tab;
  switch (result) {
    case ToolAvailable(:final entry):
      tab = newToolTabInstance(entry);
    case ToolUnavailable(reason: ToolUnavailableReason.loading):
      tab = ToolTab(
        toolId: pluginId,
        title: ToolTab.fallbackTitleFor(pluginId),
        allowMultipleInstances: true,
      );
    case ToolUnavailable(:final reason, :final name):
      UiSnack.showError(toolUnavailableMessage(reason, name, pluginId));
      return null;
  }
  final tabsBloc = context.read<TabsBloc>();
  final reserved = _reservedInstanceIds(tabsBloc, pluginId);
  reserved.removeAll(_toolInstanceIds(tabsBloc.state.tabs));
  if (!hasRoomForPluginInstance(
    tabsBloc.state.tabs,
    pluginId,
    pending: reserved.length,
  )) {
    tab.dispose();
    UiSnack.showError(
      ToolsMessages.pluginInstanceLimitReached(
        tab.title,
        kMaxPluginToolInstances,
      ),
    );
    return null;
  }
  final instanceId = _dispatchInstanceTab(context, tab);
  reserved.add(instanceId);
  unawaited(
    tabsBloc.stream
        .firstWhere(
          (state) => _toolInstanceIds(state.tabs).contains(instanceId),
        )
        .timeout(_reservationTimeout)
        .then<void>((_) {}, onError: (_) {})
        .whenComplete(() => reserved.remove(instanceId)),
  );
  return instanceId;
}

/// כמה זמן פתיחה שנשלחה נספרת בתקרה, אם היא עדיין לא הגיעה ל-state.
const Duration _reservationTimeout = Duration(seconds: 30);

/// פתיחות שנשלחו ל-[TabsBloc] ועדיין אינן ב-state. בלעדיהן שתי קריאות
/// רצופות היו רואות אותו מספר כרטיסיות ועוקפות את התקרה.
final _instanceReservations = Expando<Map<String, Set<String>>>();

Set<String> _reservedInstanceIds(TabsBloc bloc, String pluginId) =>
    (_instanceReservations[bloc] ??= {}).putIfAbsent(pluginId, () => {});

Set<String> _toolInstanceIds(Iterable<OpenedTab> tabs) => {
  for (final tab in tabs.expand(leafPanes).whereType<ToolTab>()) tab.instanceId,
};

/// פותח מופע נוסף של הכלי בטאב חדש גם כשכבר פתוח טאב שלו, ומחזיר את מזהה
/// המופע שנפתח.
///
/// הקורא כיום: [openPluginToolInstanceById] (`plugin.openSelf` עם `newTab`).
/// נקודת כניסה אפשרית נוספת: Ctrl+לחיצה / "פתח בטאב חדש".
String openNewToolTabInstance(BuildContext context, ToolCatalogEntry entry) =>
    _dispatchInstanceTab(context, newToolTabInstance(entry));

String _dispatchInstanceTab(BuildContext context, ToolTab tab) {
  // המופע החדש נפתח מתוך התוסף, ולכן הוא נכנס מיד אחרי הטאב הנוכחי ולא בסוף
  // השורה.
  context.read<TabsBloc>().add(OpenOrFocusTab(tab, insertAdjacent: true));
  context.read<NavigationBloc>().add(
    const NavigateToScreen(Screen.reading),
  );
  return tab.instanceId;
}

/// פותח כלי לפי מזהה בלבד — לקישורים עמוקים, קיצורי מקלדת ופריטים מוצמדים
/// לסרגל הניווט.
///
/// כשמערכת התוספים עדיין נטענת הכרטיסיה נפתחת אופטימיסטית עם כותרת גיבוי;
/// `ToolTabScreen` מציג טעינה עד שהמצב האמיתי ידוע. בכל סיבת אי-זמינות אחרת
/// מוצגת הודעה מפורשת במקום שתיקה.
void openToolTabById(
  BuildContext context,
  String toolId, {
  ToolQuery? query,
}) {
  final settingsState = context.read<SettingsBloc>().state;
  final result = lookupTool(
    toolId,
    hiddenBuiltInToolIds: settingsState.hiddenBuiltInToolIds,
    isOfflineMode: settingsState.isOfflineMode,
    pluginState: context.read<PluginSystemBloc>().state,
  );

  switch (result) {
    case ToolAvailable(:final entry):
      openToolTab(context, entry, query: query);
    case ToolUnavailable(reason: ToolUnavailableReason.loading):
      context.read<TabsBloc>().add(
        OpenOrFocusTab(
          ToolTab(
            toolId: toolId,
            title: ToolTab.fallbackTitleFor(toolId),
            query: query,
          ),
        ),
      );
      context.read<NavigationBloc>().add(
        const NavigateToScreen(Screen.reading),
      );
    case ToolUnavailable(:final reason, :final name):
      UiSnack.showError(toolUnavailableMessage(reason, name, toolId));
  }
}

/// הכרטיסיות הפתוחות של תוספים שכבר אינם מותקנים.
///
/// מחיקת תוסף חייבת לסגור את הכרטיסיה שלו — אחרת נשארת כרטיסיה עם "הכלי אינו
/// זמין" שהמשתמש צריך לסגור ידנית. תוסף מושבת או מוסתר מהכלים אינו נכלל כאן:
/// הוא עדיין מותקן והמשתמש יכול להחזירו מההגדרות, ולכן ההודעה בכרטיסיה היא
/// המשוב הנכון.
List<ToolTab> orphanedPluginToolTabs(
  List<OpenedTab> tabs,
  Iterable<String> installedPluginIds,
) {
  final installed = installedPluginIds.toSet();
  return tabs
      .whereType<ToolTab>()
      .where((tab) => tab.isPlugin && !installed.contains(tab.toolId))
      .toList();
}

/// כמו [orphanedPluginToolTabs], לפי מצב מערכת התוספים.
///
/// כל עוד הרשימה עדיין נטענת מוחזרת רשימה ריקה: באותו רגע אין דרך לדעת מה
/// מותקן, וסגירה הייתה מוחקת כרטיסיות תקינות — למשל בעלייה, כשהכרטיסיות
/// משוחזרות לפני שרישום התוספים נקרא.
List<ToolTab> orphanedPluginToolTabsForState(
  List<OpenedTab> tabs,
  PluginSystemState pluginState,
) {
  if (pluginState is! PluginSystemLoaded) return const [];
  return orphanedPluginToolTabs(
    tabs,
    pluginState.plugins.map((p) => p.pluginId),
  );
}

/// סוגר כרטיסיות של תוספים שהוסרו.
///
/// נקרא משני כיוונים: כשרשימת התוספים משתנה (הסרה — שיכולה להגיע מחלונית
/// התוספים, ממסך ההגדרות או מניהול הכלים), וכשרשימת הכרטיסיות מתחלפת (מעבר
/// בין סביבות עבודה ושחזור בעלייה) — כי כרטיסיה של תוסף שהוסר יכולה לצוץ
/// מסביבת עבודה שלא הייתה פעילה בזמן המחיקה.
void closeUninstalledPluginTabs(BuildContext context) {
  final tabsBloc = context.read<TabsBloc>();
  final orphaned = orphanedPluginToolTabsForState(
    tabsBloc.state.tabs,
    context.read<PluginSystemBloc>().state,
  );
  for (final tab in orphaned) {
    tabsBloc.add(RemoveTab(tab));
  }
}

/// טאבי תוסף שעדיין נושאים את כותרת הגיבוי, ממופים לשם האמיתי של התוסף.
/// טאב שנפתח בזמן שרישום התוספים נטען מקבל "כלי" ונשמר כך עם סביבת העבודה.
Map<ToolTab, String> pluginTabsWithFallbackTitle(
  List<OpenedTab> tabs,
  PluginSystemState pluginState,
) {
  if (pluginState is! PluginSystemLoaded) return const {};
  final titles = {
    for (final plugin in pluginState.plugins)
      plugin.pluginId: ToolCatalogEntry.fromPlugin(plugin).label,
  };
  return {
    for (final tab in tabs.expand(leafPanes).whereType<ToolTab>())
      if (tab.isPlugin &&
          tab.title == ToolTab.fallbackTitleFor(tab.toolId) &&
          titles[tab.toolId] != null)
        tab: titles[tab.toolId]!,
  };
}

/// מחליף את כותרת הגיבוי של טאבי תוסף בשם התוסף.
void retitleFallbackPluginTabs(BuildContext context) {
  final tabsBloc = context.read<TabsBloc>();
  pluginTabsWithFallbackTitle(
    tabsBloc.state.tabs,
    context.read<PluginSystemBloc>().state,
  ).forEach((tab, title) => tabsBloc.add(RenameTab(tab, title)));
}

/// הודעת השגיאה המתאימה לסיבת אי-הזמינות.
String toolUnavailableMessage(
  ToolUnavailableReason reason,
  String? name,
  String toolId,
) {
  return switch (reason) {
    ToolUnavailableReason.builtInHidden => ToolsMessages.builtInToolHidden(
      name ?? toolId,
    ),
    ToolUnavailableReason.pluginDisabled => LibraryMessages.pluginDisabled(
      name ?? toolId,
    ),
    ToolUnavailableReason.pluginRequiresInternet =>
      ToolsMessages.pluginRequiresInternet(name ?? toolId),
    ToolUnavailableReason.pluginHeadless => ToolsMessages.pluginIsHeadless(
      name ?? toolId,
    ),
    _ => ToolsMessages.toolNotFound(toolId),
  };
}
