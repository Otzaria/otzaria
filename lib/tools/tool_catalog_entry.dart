import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

/// רשומת תצוגה מאוחדת לכלי מובנה ולתוסף.
///
/// מחליפה את `ToolDescriptor` שהיה במסך הכלים: כאן אין `buildPage`, כי העמוד
/// נבנה על-ידי `ToolTabScreen` בתוך טאב העיון.
class ToolCatalogEntry {
  final String toolId;
  final String label;
  final int order;

  /// אייקון Fluent. `null` רק כאשר [imageIcon] קיים.
  final IconData? icon;
  final IconData? iconFilled;

  /// נכס תמונה, לכלים שמשתמשים בלוגו במקום באייקון (כמו "שמור וזכור").
  final String? imageIcon;

  final InstalledPlugin? plugin;

  const ToolCatalogEntry({
    required this.toolId,
    required this.label,
    required this.order,
    this.icon,
    this.iconFilled,
    this.imageIcon,
    this.plugin,
  });

  bool get isPlugin => plugin != null;
  bool get isDevelopment => plugin?.isDevelopment ?? false;

  factory ToolCatalogEntry.fromBuiltIn(BuiltInToolMeta meta) =>
      ToolCatalogEntry(
        toolId: meta.toolId,
        label: meta.label,
        order: meta.order,
        icon: meta.icon,
        iconFilled: meta.iconFilled,
        imageIcon: meta.imageIcon,
      );

  factory ToolCatalogEntry.fromPlugin(InstalledPlugin plugin) {
    final icon =
        fluentIconFromName(plugin.manifest.toolTabIconName) ??
        FluentIcons.puzzle_piece_24_regular;
    return ToolCatalogEntry(
      toolId: plugin.pluginId,
      label: plugin.manifest.toolTabTitle,
      order: plugin.effectiveToolTabOrder,
      icon: icon,
      iconFilled: icon,
      plugin: plugin,
    );
  }

  /// קבוצת המיון: כלים מובנים לפני תוספים, למעט תוסף שהמשתמש אישר לו
  /// להקדים אותם.
  int get sortGroupPriority {
    if (plugin == null) return 1;
    return plugin!.allowsOrderBeforeBuiltIns ? 0 : 2;
  }
}

/// ממיין רשומות במיון *יציב*: כלים מובנים לפני תוספים (למעט תוסף שאושר
/// להקדים אותם), ובתוך כל קבוצה לפי [ToolCatalogEntry.order] עולה.
///
/// `List.sort` הרגיל אינו יציב והיה משבש בין הרצות את הסדר של רשומות
/// שחולקות אותו `order` — סדר שכבר נקבע דטרמיניסטית ב-repository.
@visibleForTesting
void sortToolEntriesStably(List<ToolCatalogEntry> entries) {
  insertionSort(
    entries,
    compare: (a, b) {
      final byKind = a.sortGroupPriority.compareTo(b.sortGroupPriority);
      if (byKind != 0) return byKind;
      return a.order.compareTo(b.order);
    },
  );
}

/// אייקון קטן לשורת הכרטיסיות. מחזיר `null` כשאין מה להציג.
///
/// [pluginState] אופציונלי: בלעדיו תוסף מקבל את אייקון ברירת המחדל במקום את
/// האייקון שהצהיר עליו במניפסט.
Widget? buildToolTabLeadingIcon(
  String toolId, {
  required Color color,
  double size = 14,
  PluginSystemState? pluginState,
}) {
  final builtIn = kBuiltInToolsCatalog.firstWhereOrNull(
    (meta) => meta.toolId == toolId,
  );
  if (builtIn != null) {
    if (builtIn.imageIcon != null) {
      return ImageIcon(
        AssetImage(builtIn.imageIcon!),
        size: size,
        color: color,
      );
    }
    return Icon(builtIn.icon, size: size, color: color);
  }

  IconData? icon;
  if (pluginState is PluginSystemLoaded) {
    final plugin = pluginState.plugins.firstWhereOrNull(
      (p) => p.pluginId == toolId,
    );
    if (plugin != null) {
      icon = fluentIconFromName(plugin.manifest.toolTabIconName);
    }
  }
  return Icon(
    icon ?? FluentIcons.puzzle_piece_24_regular,
    size: size,
    color: color,
  );
}

/// למה כלי אינו זמין לפתיחה. משמש גם להודעת השגיאה בפתיחה וגם למסך
/// שמוצג בטאב של כלי שנעלם.
enum ToolUnavailableReason {
  /// עדיין לא ידוע — `PluginSystemBloc` טרם סיים לטעון.
  loading,
  notFound,
  builtInHidden,
  pluginDisabled,
  pluginHiddenFromTools,
  pluginRequiresInternet,
}

/// תוצאת חיפוש כלי לפי מזהה: הרשומה עצמה, או הסיבה שאינה זמינה.
sealed class ToolLookupResult {
  const ToolLookupResult();
}

class ToolAvailable extends ToolLookupResult {
  final ToolCatalogEntry entry;
  const ToolAvailable(this.entry);
}

class ToolUnavailable extends ToolLookupResult {
  final ToolUnavailableReason reason;

  /// שם הכלי לתצוגה בהודעה, כשהוא ידוע.
  final String? name;
  const ToolUnavailable(this.reason, {this.name});
}

/// הכלים שמוצגים במשגר: כלים מובנים שאינם מוסתרים, ותוספים מופעלים
/// שאינם מוסתרים מהממשק ואינם חסומים במצב מנותק.
///
/// תוסף שהוצמד לסרגל הניווט מופיע כאן גם כן — בשונה מסרגל הלשוניות הישן,
/// ברשת הזו הופעה כפולה אינה מפריעה והשמטתו רק הייתה מסתירה אותו מהחיפוש.
List<ToolCatalogEntry> buildToolCatalog({
  required Set<String> hiddenBuiltInToolIds,
  required bool isOfflineMode,
  required PluginSystemState pluginState,
}) {
  final entries = <ToolCatalogEntry>[
    for (final meta in kBuiltInToolsCatalog)
      if (!hiddenBuiltInToolIds.contains(meta.toolId))
        ToolCatalogEntry.fromBuiltIn(meta),
  ];

  if (pluginState is PluginSystemLoaded) {
    for (final plugin in pluginState.plugins) {
      if (!plugin.enabled) continue;
      if (!plugin.showInTools && !plugin.pinnedToNavRail) continue;
      if (isOfflineMode && plugin.blockedInOfflineMode) continue;
      entries.add(ToolCatalogEntry.fromPlugin(plugin));
    }
  }

  sortToolEntriesStably(entries);
  return entries;
}

/// מאתר כלי לפי מזהה ומחזיר את הסיבה המדויקת כשאינו זמין.
///
/// אינו מסתמך על [buildToolCatalog] בכוונה: הוא צריך להבחין בין "לא קיים"
/// ל"קיים אך מוסתר/מושבת/חסום", כדי שפתיחה מקישור עמוק או מקיצור מקלדת
/// תסביר למשתמש מה קרה במקום לשתוק.
ToolLookupResult lookupTool(
  String toolId, {
  required Set<String> hiddenBuiltInToolIds,
  required bool isOfflineMode,
  required PluginSystemState pluginState,
}) {
  final builtIn = kBuiltInToolsCatalog.firstWhereOrNull(
    (meta) => meta.toolId == toolId,
  );
  if (builtIn != null) {
    if (hiddenBuiltInToolIds.contains(toolId)) {
      return ToolUnavailable(
        ToolUnavailableReason.builtInHidden,
        name: builtIn.label,
      );
    }
    return ToolAvailable(ToolCatalogEntry.fromBuiltIn(builtIn));
  }

  if (pluginState is! PluginSystemLoaded) {
    return const ToolUnavailable(ToolUnavailableReason.loading);
  }

  final plugin = pluginState.plugins.firstWhereOrNull(
    (p) => p.pluginId == toolId,
  );
  if (plugin == null) {
    return const ToolUnavailable(ToolUnavailableReason.notFound);
  }
  if (!plugin.enabled) {
    return ToolUnavailable(
      ToolUnavailableReason.pluginDisabled,
      name: plugin.name,
    );
  }
  if (!plugin.showInTools && !plugin.pinnedToNavRail) {
    return ToolUnavailable(
      ToolUnavailableReason.pluginHiddenFromTools,
      name: plugin.name,
    );
  }
  if (isOfflineMode && plugin.blockedInOfflineMode) {
    return ToolUnavailable(
      ToolUnavailableReason.pluginRequiresInternet,
      name: plugin.name,
    );
  }
  return ToolAvailable(ToolCatalogEntry.fromPlugin(plugin));
}
