import 'dart:math';

import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';
import 'package:otzaria/tools/tool_query.dart';

/// תקרת מופעי WebView של תוסף בחלון, כולל המופע הראשי.
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

/// טאב של כלי מובנה או תוסף, המוצג במסך העיון ככל טאב אחר.
class ToolTab extends OpenedTab {
  /// מזהה הכלי: `builtin.*` לכלי מובנה, או `pluginId` לתוסף.
  final String toolId;

  /// מזהה ריצה ייחודי של מופע הטאב. [clone] מייצר מזהה חדש.
  final String instanceId;

  /// טאב שנפתח כמופע נוסף מוותר על dedupeKey, כדי שפתיחה רגילה
  /// של אותו כלי לא תמקד אותו במקום לפתוח חדש.
  final bool allowMultipleInstances;

  /// בקשות חיפוש שממתינות למסך הכלי. אינן נשמרות עם הטאב.
  final ToolQueryInbox queryInbox = ToolQueryInbox();

  ToolTab({
    required this.toolId,
    required String title,
    super.isPinned,
    String? instanceId,
    this.allowMultipleInstances = false,
    ToolQuery? query,
  }) : instanceId = instanceId ?? newInstanceId(),
       super(
         title,
         dedupeKey: allowMultipleInstances ? null : dedupeKeyFor(toolId),
       ) {
    if (query != null) queryInbox.post(query);
  }

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

  PluginInstanceKey get _pluginKey =>
      (pluginId: toolId, instanceId: instanceId);

  @override
  void dispose() {
    PluginRestoreStateStore.instance.remove(_pluginKey);
    queryInbox.dispose();
    super.dispose();
  }

  @override
  OpenedTab clone({bool? allowMultipleInstances}) {
    final copy = ToolTab(
      toolId: toolId,
      title: title,
      isPinned: isPinned,
      allowMultipleInstances:
          allowMultipleInstances ?? this.allowMultipleInstances,
    );
    // שולחנות עבודה עוברים דרך clone — בלי ההעתקה המצב אובד במזהה החדש.
    final restoreState = PluginRestoreStateStore.instance.jsonOf(_pluginKey);
    if (restoreState != null) {
      PluginRestoreStateStore.instance.seed(copy._pluginKey, restoreState);
    }
    return copy;
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ToolTab',
    'toolId': toolId,
    'title': title,
    'isPinned': isPinned,
    'instanceId': instanceId,
    'allowMultipleInstances': allowMultipleInstances,
    // מצב השחזור של התוסף (plugin.setRestoreState) עובר עם הטאב לסשן
    // ולסביבות העבודה.
    'pluginRestoreState': ?PluginRestoreStateStore.instance.jsonOf(_pluginKey),
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
    final tab = ToolTab(
      toolId: toolId,
      title: title == null || title.isEmpty ? fallbackTitleFor(toolId) : title,
      isPinned: json['isPinned'] == true,
      // JSON ישן (גיבוי/סביבת עבודה) בלי השדה — נוצר מזהה טרי.
      instanceId: json['instanceId'] as String?,
      allowMultipleInstances: json['allowMultipleInstances'] == true,
    );
    final restoreState = json['pluginRestoreState'];
    if (restoreState is String) {
      PluginRestoreStateStore.instance.seed(tab._pluginKey, restoreState);
    }
    return tab;
  }
}
