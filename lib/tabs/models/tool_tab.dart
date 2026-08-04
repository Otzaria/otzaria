import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

/// טאב של כלי מובנה או תוסף, המוצג במסך העיון ככל טאב אחר.
class ToolTab extends OpenedTab {
  /// מזהה הכלי: `builtin.*` לכלי מובנה, או `pluginId` לתוסף.
  final String toolId;

  ToolTab({
    required this.toolId,
    required String title,
    super.isPinned,
  }) : super(title, dedupeKey: dedupeKeyFor(toolId));

  /// רק תוסף מוגבל למופע WebView יחיד.
  static String? dedupeKeyFor(String toolId) =>
      isBuiltInToolId(toolId) ? null : 'tool:$toolId';

  static bool isBuiltInToolId(String toolId) =>
      kBuiltInToolsCatalog.any((meta) => meta.toolId == toolId);

  bool get isBuiltIn => isBuiltInToolId(toolId);

  bool get isPlugin => !isBuiltIn;

  /// כותרת גיבוי לפתיחה לפי מזהה לפני טעינת שם התוסף.
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

  /// מזהי התוספים המוצגים בטאב [tab], כולל חלוניות מפוצלות.
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
