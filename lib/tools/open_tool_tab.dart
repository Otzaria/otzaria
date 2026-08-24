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
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';

/// פותח כלי ככרטיסיה במסך העיון.
///
/// כלי שכבר פתוח ממוקד (dedupeKey); מופע נוסף נפתח דרך
/// [openNewToolTabInstance].
void openToolTab(BuildContext context, ToolCatalogEntry entry) {
  context.read<TabsBloc>().add(
    OpenOrFocusTab(ToolTab(toolId: entry.toolId, title: entry.label)),
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

/// פותח מופע נוסף של הכלי בטאב חדש גם כשכבר פתוח טאב שלו.
/// נקודת כניסה עתידית (Ctrl+לחיצה / "פתח בטאב חדש") — אין עדיין UI שקורא לה.
void openNewToolTabInstance(BuildContext context, ToolCatalogEntry entry) {
  context.read<TabsBloc>().add(OpenOrFocusTab(newToolTabInstance(entry)));
  context.read<NavigationBloc>().add(
    const NavigateToScreen(Screen.reading),
  );
}

/// פותח כלי לפי מזהה בלבד — לקישורים עמוקים, קיצורי מקלדת ופריטים מוצמדים
/// לסרגל הניווט.
///
/// כשמערכת התוספים עדיין נטענת הכרטיסיה נפתחת אופטימיסטית עם כותרת גיבוי;
/// `ToolTabScreen` מציג טעינה עד שהמצב האמיתי ידוע. בכל סיבת אי-זמינות אחרת
/// מוצגת הודעה מפורשת במקום שתיקה.
void openToolTabById(BuildContext context, String toolId) {
  final settingsState = context.read<SettingsBloc>().state;
  final result = lookupTool(
    toolId,
    hiddenBuiltInToolIds: settingsState.hiddenBuiltInToolIds,
    isOfflineMode: settingsState.isOfflineMode,
    pluginState: context.read<PluginSystemBloc>().state,
  );

  switch (result) {
    case ToolAvailable(:final entry):
      openToolTab(context, entry);
    case ToolUnavailable(reason: ToolUnavailableReason.loading):
      context.read<TabsBloc>().add(
        OpenOrFocusTab(
          ToolTab(toolId: toolId, title: ToolTab.fallbackTitleFor(toolId)),
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
    ToolUnavailableReason.pluginHiddenFromTools =>
      ToolsMessages.pluginNotShownInTools(name ?? toolId),
    ToolUnavailableReason.pluginRequiresInternet =>
      ToolsMessages.pluginRequiresInternet(name ?? toolId),
    _ => ToolsMessages.toolNotFound(toolId),
  };
}
