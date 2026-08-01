import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

/// טאב של כלי מובנה או של תוסף, המוצג בתוך מסך העיון ככל טאב אחר.
///
/// המצב החי (בלוקים, מפתחות, WebView) שייך ל-`State` של המסך ולא למודל —
/// שלא כמו [TextBookTab] שמחזיק `bloc` משלו. לכן אין כאן `dispose`.
class ToolTab extends OpenedTab {
  /// מזהה הכלי: `builtin.*` לכלי מובנה, או `pluginId` לתוסף.
  final String toolId;

  ToolTab({
    required this.toolId,
    required String title,
    super.isPinned,
  }) : super(title, dedupeKey: dedupeKeyFor(toolId));

  /// רק תוסף מוגבל למופע WebView יחיד; כלים מובנים מתנהגים כמו ספרים וניתנים
  /// לפתיחה ולשכפול במספר כרטיסיות.
  static String? dedupeKeyFor(String toolId) =>
      isBuiltInToolId(toolId) ? null : 'tool:$toolId';

  static bool isBuiltInToolId(String toolId) =>
      kBuiltInToolsCatalog.any((meta) => meta.toolId == toolId);

  bool get isBuiltIn => isBuiltInToolId(toolId);

  bool get isPlugin => !isBuiltIn;

  /// כותרת גיבוי לפתיחה לפי מזהה בלבד (deep link / קיצור מקלדת), לפני
  /// ש-`PluginSystemBloc` נטען ושם הכלי האמיתי ידוע.
  static String fallbackTitleFor(String toolId) {
    for (final meta in kBuiltInToolsCatalog) {
      if (meta.toolId == toolId) return meta.label;
    }
    return 'כלי';
  }

  @override
  OpenedTab clone() =>
      ToolTab(toolId: toolId, title: title, isPinned: isPinned);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ToolTab',
    'toolId': toolId,
    'title': title,
    'isPinned': isPinned,
  };

  /// מזהי התוספים שמוצגים בטאב [tab] — כולל חלוניות בתוך טאב מפוצל.
  ///
  /// מזין את `PluginRuntimeDispatcher.setVisiblePluginTabs`: תוסף שאינו כאן
  /// מושהה כדי לא לצרוך CPU/RAM ברקע.
  static Set<String> visiblePluginIdsOf(OpenedTab? tab) {
    if (tab == null) return const {};
    return {
      for (final pane in leafPanes(tab))
        if (pane is ToolTab && pane.isPlugin) pane.toolId,
    };
  }

  factory ToolTab.fromJson(Map<String, dynamic> json) {
    final toolId = json['toolId'] as String? ?? '';
    final title = json['title'] as String?;
    return ToolTab(
      toolId: toolId,
      title: title == null || title.isEmpty ? fallbackTitleFor(toolId) : title,
      isPinned: json['isPinned'] == true,
    );
  }
}
