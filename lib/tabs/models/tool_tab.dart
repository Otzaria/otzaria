import 'dart:math';

import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

/// טאב של כלי מובנה או תוסף, המוצג במסך העיון ככל טאב אחר.
class ToolTab extends OpenedTab {
  /// מזהה הכלי: `builtin.*` לכלי מובנה, או `pluginId` לתוסף.
  final String toolId;

  /// מזהה ריצה ייחודי של מופע הטאב. [clone] מייצר מזהה חדש.
  final String instanceId;

  /// טאב שנפתח כמופע נוסף מוותר על dedupeKey, כדי שפתיחה רגילה
  /// של אותו כלי לא תמקד אותו במקום לפתוח חדש.
  final bool allowMultipleInstances;

  ToolTab({
    required this.toolId,
    required String title,
    super.isPinned,
    String? instanceId,
    this.allowMultipleInstances = false,
  }) : instanceId = instanceId ?? newInstanceId(),
       super(
         title,
         dedupeKey: allowMultipleInstances ? null : dedupeKeyFor(toolId),
       );

  static int _instanceCounter = 0;
  static final Random _instanceRandom = Random();

  /// מזהה מופע חדש — ייחודי בתוך ההפעלה (מונה) וגם בין הפעלות (זמן + אקראי).
  static String newInstanceId() =>
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${_instanceCounter++}-${_instanceRandom.nextInt(0xffffff)}';

  /// מפתח מיקוד — פתיחה רגילה ממקדת את הטאב הקיים במקום לפתוח חדש.
  static String dedupeKeyFor(String toolId) => 'tool:$toolId';

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
  OpenedTab clone() => ToolTab(
    toolId: toolId,
    title: title,
    isPinned: isPinned,
    allowMultipleInstances: allowMultipleInstances,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ToolTab',
    'toolId': toolId,
    'title': title,
    'isPinned': isPinned,
    'instanceId': instanceId,
    'allowMultipleInstances': allowMultipleInstances,
  };

  /// מפתחות מופעי התוספים המוצגים בטאב [tab], כולל חלוניות מפוצלות.
  static Set<PluginInstanceKey> visiblePluginInstancesOf(OpenedTab? tab) {
    if (tab == null) return const {};
    return {
      for (final pane in leafPanes(tab))
        if (pane is ToolTab && pane.isPlugin)
          (pluginId: pane.toolId, instanceId: pane.instanceId),
    };
  }

  factory ToolTab.fromJson(Map<String, dynamic> json) {
    final toolId = json['toolId'] as String? ?? '';
    final title = json['title'] as String?;
    return ToolTab(
      toolId: toolId,
      title: title == null || title.isEmpty ? fallbackTitleFor(toolId) : title,
      isPinned: json['isPinned'] == true,
      // JSON ישן (גיבוי/סביבת עבודה) בלי השדה — נוצר מזהה טרי.
      instanceId: json['instanceId'] as String?,
      allowMultipleInstances: json['allowMultipleInstances'] == true,
    );
  }
}
