import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';
import 'package:otzaria/tools/measurement_converter/measurement_converter_screen.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';
import 'package:otzaria/tools/acronyms_dictionary/acronyms_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/widgets/navigation/keyboard_navigator.dart';
import 'package:otzaria/widgets/misc/exit_fullscreen_button.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/view/plugin_side_panel.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';

/// בדיקה האם שני סטים מכילים את אותם הערכים. שימושי ב-`listenWhen`.
bool _setEquals(Set<String> a, Set<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

/// מזהה הכלי שפעיל כרגע ב-ToolsScreen, או `null` אם המסך לא מוצג.
/// משמש את ה-MainWindowScreen כדי להדגיש את התוסף שבחרת בסרגל הניווט/הבר
/// כשנבחרה לשונית של תוסף-מוצמד-לסרגל.
final ValueNotifier<String?> activeToolIdNotifier = ValueNotifier<String?>(
  null,
);

/// מעדכן את [activeToolIdNotifier] באופן בטוח גם בזמן פאזת build:
/// אם נקרא מתוך build/layout של פריים (למשל מ-`initState` של מסך שמורכב
/// בתוך עץ הורה שבונה את עצמו כרגע), העדכון נדחה ל-`addPostFrameCallback`
/// כדי למנוע `setState during build` אצל `ValueListenableBuilder`-ים שכבר
/// מורכבים בעץ (סרגל הניווט הראשי ב-`MainWindowScreen`).
///
/// [isMounted] מאפשר לקורא לבטל את העדכון אם הוא נפטר בינתיים.
@visibleForTesting
void setActiveToolIdSafely(String? id, {bool Function()? isMounted}) {
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.persistentCallbacks) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isMounted?.call() ?? true) activeToolIdNotifier.value = id;
    });
  } else {
    activeToolIdNotifier.value = id;
  }
}

/// מחשב את התוסף ה-transient לאחר טעינת רשימת תוספים מעודכנת: מחזיר את
/// גרסתו העדכנית, או null אם הוסר מהתצוגה או הפך חסום במצב מנותק
/// (למשל כשהוענקה לו הרשאת רשת בזמן אמת).
@visibleForTesting
InstalledPlugin? resolveTransientAfterPluginsLoaded(
  InstalledPlugin? transient,
  List<InstalledPlugin> plugins, {
  required bool isOfflineMode,
}) {
  if (transient == null) return null;
  final updated = plugins.firstWhere(
    (p) => p.pluginId == transient.pluginId,
    orElse: () => transient,
  );
  if (!updated.showInTools && !updated.pinnedToNavRail) return null;
  if (isOfflineMode && updated.blockedInOfflineMode) return null;
  return updated;
}

/// האם להסתיר את סרגל הלשוניות העליון של מסך הכלים.
///
/// מוסתר במסך מלא, וכן כשמוצג תוסף שהוצמד לסרגל הניווט הראשי — לתוסף כזה
/// אין לשונית בכלל, ולכן הסרגל רק גוזל מקום.
@visibleForTesting
bool shouldHideToolsTabBar({
  required bool isImmersive,
  required String? hiddenNavRailPluginId,
  required String? selectedToolId,
}) {
  if (isImmersive) return true;
  return hiddenNavRailPluginId != null &&
      hiddenNavRailPluginId == selectedToolId;
}

/// האם על ה-restorer של מסך הכלים להחזיר פוקוס לצומת התוכן.
///
/// [contentHasFocus] כולל צאצאים. כשהפוקוס כבר בתוך הכלי — למשל בשדה קלט
/// ב-WebView של תוסף — requestFocus היה גוזל אותו לצומת האב, וה-WebView היה
/// מריץ `document.activeElement.blur()` ומאבד את סמן הכתיבה.
@visibleForTesting
bool shouldRestoreToolsContentFocus({
  required bool contentIsAttached,
  required bool contentHasFocus,
}) {
  return contentIsAttached && !contentHasFocus;
}

/// שם התוסף שיוצג ככותרת מסך הכלים במקום "כלים", או null לכותרת הרגילה.
///
/// רק לתוסף שאין לו לשונית בכלים (מוצמד לסרגל הניווט או `showInTools=false`)
/// — עבורו הכותרת היא הרמז היחיד לזהותו; לתוסף עם לשונית השם מופיע בלשונית.
String? resolveToolsTitlePluginName({
  required String? activeToolId,
  required List<InstalledPlugin> plugins,
}) {
  if (activeToolId == null) return null;
  for (final plugin in plugins) {
    if (plugin.pluginId != activeToolId) continue;
    if (plugin.pinnedToNavRail || !plugin.showInTools) return plugin.name;
    return null;
  }
  return null;
}

/// ממיין רשימת [ToolDescriptor] במיון *יציב*.
///
/// כברירת מחדל, כלים מובנים ([BuiltInToolDescriptor]) מופיעים לפני תוספים
/// ([PluginToolDescriptor]) — גם אם לתוסף יש `order` נמוך יותר.
///
/// חריג מפורש: תוסף שהצהיר במניפסט על
/// `allowOrderBeforeBuiltIns=true` רשאי להתחרות מול הכלים המובנים ולהופיע
/// לפניהם. בתוך כל קבוצה המיון הוא לפי [ToolDescriptor.order] עולה.
///
/// כש-N כלים חולקים את אותו `order` (למשל כמה תוספים בברירת המחדל 900
/// מהמניפסט), הסדר היחסי ביניהם נשמר כפי שהגיע ברשימת הקלט — סדר שכבר נקבע
/// דטרמיניסטית ב-repository (order → installedAt → pluginId). `List.sort`
/// הרגיל אינו יציב והיה משבש את הסדר הזה בין הרצות.
@visibleForTesting
void sortToolDescriptorsStably(List<ToolDescriptor> descriptors) {
  insertionSort(
    descriptors,
    compare: (a, b) {
      final byKind = a.sortGroupPriority.compareTo(b.sortGroupPriority);
      if (byKind != 0) return byKind;
      return a.order.compareTo(b.order);
    },
  );
}

typedef MobileToolGroupDef = ({String label, List<String> toolIds});
typedef MobileToolGroup = ({String label, List<ToolDescriptor> tools});

/// בונה את קבוצות התצוגה של תפריט המובייל מתוך הסדר שכבר חושב ב-descriptors.
///
/// כך תוספים שמורשים להופיע לפני כלים מובנים נשארים במקומם גם במובייל.
/// אם תוסף "חותך" קבוצה מובנית, אותה כותרת יכולה להופיע יותר מפעם אחת —
/// זה מכוון, כדי לא לשבור את הסדר האפקטיבי של הכלים.
@visibleForTesting
List<MobileToolGroup> buildMobileToolGroups(
  List<ToolDescriptor> descriptors, {
  required List<MobileToolGroupDef> groupDefs,
}) {
  final labelByToolId = <String, String>{
    for (final group in groupDefs)
      for (final toolId in group.toolIds) toolId: group.label,
  };

  final groups = <MobileToolGroup>[];
  for (final descriptor in descriptors) {
    final label = labelByToolId[descriptor.toolId] ?? 'תוספים';
    if (groups.isNotEmpty && groups.last.label == label) {
      groups.last.tools.add(descriptor);
      continue;
    }
    groups.add((label: label, tools: [descriptor]));
  }
  return groups;
}

abstract class ToolDescriptor {
  final String toolId;
  final String label;
  final int order;
  const ToolDescriptor({
    required this.toolId,
    required this.label,
    required this.order,
  });
  int get sortGroupPriority => 2;
  Widget buildTab(BuildContext context);
  Widget buildPage(BuildContext context);
  TopNavItem buildTopNavItem({
    required bool isSelected,
    required VoidCallback onTap,
    Key? key,
  });
  SidebarNavItem buildSidebarNavItem({
    required bool isSelected,
    required VoidCallback onTap,
    Key? key,
  });
}

class BuiltInToolDescriptor extends ToolDescriptor {
  final IconData? icon;
  final IconData? iconFilled;
  final String? imageIcon;
  final Widget Function() pageBuilder;

  const BuiltInToolDescriptor({
    required super.toolId,
    required super.label,
    required super.order,
    this.icon,
    this.iconFilled,
    this.imageIcon,
    required this.pageBuilder,
  });

  @override
  int get sortGroupPriority => 1;

  @override
  Widget buildTab(BuildContext context) {
    if (imageIcon != null) {
      return SizedBox(
        width: 100,
        child: Tab(
          text: label,
          icon: ImageIcon(AssetImage(imageIcon!), size: 20),
        ),
      );
    }
    return SizedBox(
      width: 100,
      child: Tab(text: label, icon: RtlIcon(icon!, size: 20)),
    );
  }

  @override
  Widget buildPage(BuildContext context) => pageBuilder();

  @override
  TopNavItem buildTopNavItem({
    required bool isSelected,
    required VoidCallback onTap,
    Key? key,
  }) {
    return TopNavItem(
      key: key,
      icon: icon,
      iconFilled: iconFilled,
      imageAsset: imageIcon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  @override
  SidebarNavItem buildSidebarNavItem({
    required bool isSelected,
    required VoidCallback onTap,
    Key? key,
  }) {
    return SidebarNavItem(
      key: key,
      icon: icon,
      iconFilled: iconFilled,
      imageAsset: imageIcon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }
}

class PluginToolDescriptor extends ToolDescriptor {
  final InstalledPlugin plugin;
  PluginToolDescriptor({required this.plugin})
    : super(
        toolId: plugin.pluginId,
        label: plugin.manifest.toolTabTitle,
        order: plugin.effectiveToolTabOrder,
      );

  @override
  int get sortGroupPriority => plugin.allowsOrderBeforeBuiltIns ? 0 : 2;

  @override
  Widget buildTab(BuildContext context) {
    final iconData = fluentIconFromName(plugin.manifest.toolTabIconName);
    return SizedBox(
      width: 100,
      child: Tab(
        text: label,
        icon: iconData != null ? RtlIcon(iconData, size: 20) : null,
      ),
    );
  }

  @override
  Widget buildPage(BuildContext context) => PluginTabPage(
    // ה-key כולל גם את `version` ו-`updatedAt` כדי שעדכון של התוסף יאלץ
    // יצירה מחדש של ה-State. ל-PluginTabPage יש לוגיקה ב-initState
    // שתלויה ב-plugin (resolvedRootPath, bridge, adapter) — בלי הרחבת
    // ה-key Flutter היה משתמש שוב ב-State הישן עם הנתיב הישן.
    key: ValueKey(
      'plugin-tab-${plugin.pluginId}-${plugin.version}-'
      '${plugin.updatedAt.millisecondsSinceEpoch}',
    ),
    plugin: plugin,
  );

  IconData get _pluginIcon =>
      fluentIconFromName(plugin.manifest.toolTabIconName) ??
      FluentIcons.puzzle_piece_24_regular;

  @override
  TopNavItem buildTopNavItem({
    required bool isSelected,
    required VoidCallback onTap,
    Key? key,
  }) {
    final icon = _pluginIcon;
    return TopNavItem(
      key: key,
      icon: icon,
      iconFilled: icon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  @override
  SidebarNavItem buildSidebarNavItem({
    required bool isSelected,
    required VoidCallback onTap,
    Key? key,
  }) {
    final icon = _pluginIcon;
    return SidebarNavItem(
      key: key,
      icon: icon,
      iconFilled: icon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }
}

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  ToolsScreenState createState() => ToolsScreenState();
}

class ToolsScreenState extends State<ToolsScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _calendarFocusRetryCount = 6;

  final GlobalKey<CalendarWidgetState> _calendarKey =
      GlobalKey<CalendarWidgetState>();
  final GlobalKey<GematriaSearchScreenState> _gematriaKey =
      GlobalKey<GematriaSearchScreenState>();
  final FocusNode _contentFocusNode = FocusNode(skipTraversal: true);
  final ScrollController _contentScrollController = ScrollController();

  List<ToolDescriptor> _descriptors = [];
  List<Widget> _pages = [];
  String? _selectedToolId;
  bool _isPanelOpen = false;
  bool _showMobileMenu = true;
  InstalledPlugin? _transientPlugin;
  bool _didInitFromBloc = false;

  // תוסף מוסתר-מכלים שנפתח מניווט ראשי — חי כ-transient אך tab שלו מוסתר.
  InstalledPlugin? _hiddenNavRailPlugin;

  /// toolId-ים שכבר הוצגו פעם אחת לפחות. בדסקטופ ה-IndexedStack בונה את
  /// הילדים שלו עצלן: רק כלים שמופיעים פה נבנים בפועל, השאר נשארים
  /// SizedBox.shrink(). זה מונע יצירה מקבילית של כל ה-WebViews של תוספים
  /// כשהמשתמש נכנס למסך "כלים", ומקטין את החשיפה לבאגים native של
  /// flutter_inappwebview_windows בעת אתחול מרובה.
  final Set<String> _activatedToolIds = {};
  // מונע rebuild מרובה של הטאבים כאשר הזהות המלאה של הלשוניות לא השתנתה
  String _lastDescriptorsSignature = '';

  // גלילת שורת הטאבים בדסקטופ
  final ScrollController _tabScrollController = ScrollController();
  bool _canTabScrollLeft = false;
  bool _canTabScrollRight = false;

  // בקשת פתיחה ממתינה לכלי שעדיין אין לו descriptor (בעיקר תוספים שטרם
  // נטענו מ-PluginSystemBloc). תיפתח באוטומט ב-_applyTabState הבא, או
  // תיכשל עם UiSnack לאחר timeout.
  String? _pendingToolIdToOpen;
  Timer? _pendingToolTimeoutTimer;
  static const Duration _pendingToolTimeout = Duration(seconds: 5);

  static const List<MobileToolGroupDef> _mobileGroupDefs = [
    (label: 'לוח שנה', toolIds: <String>['builtin.calendar']),
    (
      label: 'תורה שלמדתי',
      toolIds: <String>['builtin.shamor_zachor', 'builtin.notes'],
    ),
    (
      label: 'דקדוקי סופרים',
      toolIds: <String>[
        'builtin.measurements',
        'builtin.gematria',
        'builtin.aramaic_dictionary',
        'builtin.acronyms_dictionary',
      ],
    ),
  ];

  // ─── Focus management ────────────────────────────────────────────────────────

  String _descriptorSignature(List<ToolDescriptor> descriptors) {
    return descriptors
        .map((d) {
          if (d is PluginToolDescriptor) {
            return '${d.toolId}|${d.label}|${d.order}|${d.plugin.pinned}|${d.plugin.manifest.toolTabIconName}|${d.plugin.updatedAt.millisecondsSinceEpoch}';
          }
          return '${d.toolId}|${d.label}|${d.order}';
        })
        .join('::');
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

  /// מעדכן את ה-screen restorer של מסך הכלים.
  ///
  /// הקריטריון הוא מה מחובר לעץ הפוקוס בפועל, לא _showMobileMenu:
  /// - בdesktop, _contentFocusNode תמיד בעץ גם כש-_showMobileMenu==true
  /// - בmobile menu, _contentFocusNode לא מחובר → canRestore=false טבעית
  void _registerMoreRestorer() {
    FocusRepository().setScreenRestorer(
      restore: () {
        if (!mounted) return;
        if (_selectedToolId == 'builtin.calendar') {
          _requestCalendarFocus();
        } else if (shouldRestoreToolsContentFocus(
          contentIsAttached: _contentFocusNode.enclosingScope != null,
          contentHasFocus: _contentFocusNode.hasFocus,
        )) {
          _contentFocusNode.requestFocus();
        }
      },
      canRestore: () {
        if (!mounted) return false;
        if (_selectedToolId == 'builtin.calendar') {
          return _calendarKey.currentState != null;
        }
        return _contentFocusNode.enclosingScope != null;
      },
    );
  }

  void requestActiveTabFocus() {
    // עדכון restorer מיידי לפי מצב נוכחי, לפני כל addPostFrameCallback
    _registerMoreRestorer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // אין unfocus גלובלי — זה עלול להשאיר את האפליקציה ללא פוקוס כלל
      // אם ה-requestFocus שאחריו נכשל (למשל בזמן resize ב-Windows).
      if (_selectedToolId == 'builtin.calendar') {
        _requestCalendarFocus();
      } else if (_contentFocusNode.enclosingScope != null &&
          !_contentFocusNode.hasFocus) {
        _contentFocusNode.requestFocus();
      }
    });
  }

  // ─── Tab / descriptor management ────────────────────────────────────────────

  /// בונה את כל הכלים המובנים, ללא סינון. רשימה זו מהווה את המקור הסמכותי
  /// לזיהוי כלים מובנים תקפים גם עבור מסך הגדרות הניהול.
  List<BuiltInToolDescriptor> _buildAllBuiltInDescriptors() {
    // מזהה → בונה עמוד. שאר המטא-דאטה (תווית, סדר, אייקונים) מגיע מהמקור
    // הסמכותי היחיד [kBuiltInToolsCatalog]. ה-pageBuilder תלוי במצב המסך
    // (מפתחות, מופעי widgets) ולכן נשאר כאן.
    final pageBuilders = <String, Widget Function()>{
      'builtin.calendar': () => BlocBuilder<CalendarCubit, CalendarState>(
        builder: (context, _) => CalendarWidget(key: _calendarKey),
      ),
      'builtin.shamor_zachor': () => ShamorZachorWidget(onTitleChanged: (_) {}),
      'builtin.measurements': () => const MeasurementConverterScreen(),
      'builtin.notes': () => const PersonalNotesManagerScreen(),
      'builtin.gematria': () => GematriaSearchScreen(key: _gematriaKey),
      'builtin.aramaic_dictionary': () => const AramaicDictionaryScreen(),
      'builtin.acronyms_dictionary': () => const AcronymsDictionaryScreen(),
    };
    return [
      for (final meta in kBuiltInToolsCatalog)
        BuiltInToolDescriptor(
          toolId: meta.toolId,
          label: meta.label,
          order: meta.order,
          icon: meta.icon,
          iconFilled: meta.iconFilled,
          imageIcon: meta.imageIcon,
          pageBuilder: pageBuilders[meta.toolId]!,
        ),
    ];
  }

  List<ToolDescriptor> _buildBaseDescriptors() {
    final hiddenIds = context.read<SettingsBloc>().state.hiddenBuiltInToolIds;
    return _buildAllBuiltInDescriptors()
        .where((d) => !hiddenIds.contains(d.toolId))
        .toList();
  }

  void _closeTransientPanelsForToolId(String? toolId) {
    if (toolId == 'builtin.calendar') {
      _calendarKey.currentState?.closeTransientPanels();
    }
  }

  void closeTransientPanels() {
    _closeTransientPanelsForToolId(_selectedToolId);
  }

  void _setSelectedToolId(String? id) {
    _selectedToolId = id;
    if (id != null) {
      // מסמנים את הכלי כ"הופעל" כדי שה-IndexedStack בדסקטופ יבנה אותו
      // ויחזיק אותו בחיים מכאן והלאה.
      _activatedToolIds.add(id);
    }
    setActiveToolIdSafely(id, isMounted: () => mounted);
    // מדווח ל-dispatcher רק מזהה תוסף אמיתי (או null לכלי מובנה), כדי שישהה
    // את התוסף שעזבנו ויחדש את הנכנס. כלי מובנה => null => רק השהיית הקודם.
    final isPlugin =
        id != null &&
        (_transientPlugin?.pluginId == id ||
            _descriptors.any(
              (d) => d.toolId == id && d is PluginToolDescriptor,
            ));
    PluginRuntimeDispatcher.instance.setSelectedToolPlugin(
      isPlugin ? id : null,
    );
  }

  void _changeTab(int index) {
    if (index < 0 || index >= _descriptors.length) return;
    final toolId = _descriptors[index].toolId;
    if (_selectedToolId == toolId && !_showMobileMenu) {
      requestActiveTabFocus();
      return;
    }
    _closeTransientPanelsForToolId(_selectedToolId);
    setState(() {
      _setSelectedToolId(toolId);
      _showMobileMenu = false;
    });
    requestActiveTabFocus();
  }

  /// פותח את פאנל ניהול התוספים — משמש ל-deep link `otzaria://open/sdk`.
  void openPluginPanel() {
    setState(() => _isPanelOpen = true);
  }

  void openPluginTransiently(InstalledPlugin plugin) {
    final isOfflineMode = context.read<SettingsBloc>().state.isOfflineMode;
    if (isOfflineMode && plugin.blockedInOfflineMode) {
      UiSnack.showError(ToolsMessages.pluginRequiresInternet(plugin.name));
      return;
    }
    // תוסף שהוצמד לסרגל הניווט כבר מקבל שם מקום משלו, ולכן גם הוא (כמו
    // תוסף עם showInTools=false) נפתח כ-transient "מוסתר" ולא כלשונית
    // רגילה — למניעת הצגה כפולה בכלים.
    if (!plugin.showInTools || plugin.pinnedToNavRail) {
      setState(() {
        _hiddenNavRailPlugin = plugin;
        _transientPlugin = plugin;
        _showMobileMenu = false;
        _setSelectedToolId(plugin.pluginId);
      });
      final blocState = context.read<PluginSystemBloc>().state;
      if (blocState is PluginSystemLoaded) {
        _rebuildTabs(
          blocState.pinnedPlugins.filterForOfflineMode(isOfflineMode),
          transient: _transientPlugin,
        );
      }
      return;
    }
    // פתיחת תוסף רגיל — מנקה hidden state ישן (כולל transient ו-descriptor) אם יש
    clearHiddenNavRailPlugin();
    if (plugin.pinned) {
      // לתוסף שמוצמד-ללשוניות ומוצג בכלים יש descriptor רגיל. מנתבים דרך
      // requestOpenTool כדי לקבל את מנגנון ה-pending/timeout במקרה שה-bloc
      // עדיין לא טען את הרשימה ברגע הלחיצה.
      requestOpenTool(plugin.pluginId);
      return;
    }
    // לתוסף שלא מוצמד ללשוניות — מצב transient (מחושב כאן ולא מחכה ל-bloc)
    setState(() {
      _transientPlugin = plugin;
      _showMobileMenu = false;
      _setSelectedToolId(plugin.pluginId);
    });
    final blocState = context.read<PluginSystemBloc>().state;
    if (blocState is PluginSystemLoaded) {
      _rebuildTabs(
        blocState.pinnedPlugins.filterForOfflineMode(isOfflineMode),
        transient: _transientPlugin,
      );
    }
  }

  bool get hasHiddenNavRailPlugin => _hiddenNavRailPlugin != null;
  String? get hiddenNavRailPluginId => _hiddenNavRailPlugin?.pluginId;

  /// מנקה את התוסף המוסתר הפעיל. מחזיר true אם היה תוסף שנוקה.
  bool clearHiddenNavRailPlugin() {
    if (_hiddenNavRailPlugin == null) return false;
    _hiddenNavRailPlugin = null;
    _transientPlugin = null;
    final blocState = context.read<PluginSystemBloc>().state;
    if (blocState is PluginSystemLoaded) {
      final isOfflineMode = context.read<SettingsBloc>().state.isOfflineMode;
      _rebuildTabs(
        blocState.pinnedPlugins.filterForOfflineMode(isOfflineMode),
        transient: null,
      );
    }
    return true;
  }

  void _applyTabState(
    List<InstalledPlugin> pinnedPlugins, {
    InstalledPlugin? transient,
    required bool notify,
  }) {
    final newDescriptors = <ToolDescriptor>[
      ..._buildBaseDescriptors(),
      ...pinnedPlugins.map((p) => PluginToolDescriptor(plugin: p)),
    ];
    if (transient != null) {
      if (!pinnedPlugins.any((p) => p.pluginId == transient.pluginId)) {
        newDescriptors.add(PluginToolDescriptor(plugin: transient));
      }
    }

    sortToolDescriptorsStably(newDescriptors);
    final newSignature = _descriptorSignature(newDescriptors);
    if (newSignature == _lastDescriptorsSignature && _pages.isNotEmpty) {
      return;
    }
    _lastDescriptorsSignature = newSignature;

    if (newDescriptors.isEmpty) {
      void applyEmpty() {
        _descriptors = [];
        _pages = [];
        _setSelectedToolId(null);
      }

      if (notify) {
        setState(applyEmpty);
      } else {
        applyEmpty();
      }
      return;
    }

    String newToolId = _selectedToolId ?? newDescriptors.first.toolId;
    if (!newDescriptors.any((d) => d.toolId == newToolId)) {
      newToolId = newDescriptors.first.toolId;
    }

    void applyState() {
      // re-use של widgets קיימים לפי toolId+updatedAt — כשמשתמש מסדר מחדש
      // תוספים (drag-and-drop) הסדר משתנה אבל אותם תוספים נמצאים. בנייה
      // מחדש של PluginTabPage גורמת ל-IndexedStack לבצע dispose ל-WebView
      // של תוסף שלא בתצוגה, וזה גורם לקריסה ב-flutter_inappwebview_windows.
      // הצמדת updatedAt למפתח מבטיחה שעדכון תוסף *כן* יבנה widget חדש.
      String reuseKey(ToolDescriptor d) {
        if (d is PluginToolDescriptor) {
          return '${d.toolId}|${d.plugin.updatedAt.microsecondsSinceEpoch}';
        }
        return d.toolId;
      }

      final oldPagesByKey = <String, Widget>{};
      for (var i = 0; i < _descriptors.length && i < _pages.length; i++) {
        oldPagesByKey[reuseKey(_descriptors[i])] = _pages[i];
      }
      _descriptors = newDescriptors;
      _pages = newDescriptors.map((t) {
        final existing = oldPagesByKey[reuseKey(t)];
        return existing ?? t.buildPage(context);
      }).toList();
      _setSelectedToolId(newToolId);
    }

    if (notify) {
      setState(applyState);
    } else {
      applyState();
    }

    _flushPendingToolIfReady();
  }

  void _rebuildTabs(
    List<InstalledPlugin> pinnedPlugins, {
    InstalledPlugin? transient,
  }) {
    if (!mounted) return;
    _applyTabState(pinnedPlugins, transient: transient, notify: true);
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────────

  void _onTabScrollMetrics(ScrollMetrics metrics) {
    final canLeft = metrics.pixels > metrics.minScrollExtent + 0.5;
    final canRight = metrics.pixels < metrics.maxScrollExtent - 0.5;
    if (_canTabScrollLeft != canLeft || _canTabScrollRight != canRight) {
      setState(() {
        _canTabScrollLeft = canLeft;
        _canTabScrollRight = canRight;
      });
    }
  }

  void _updateTabScrollState() {
    if (!mounted || !_tabScrollController.hasClients) return;
    final pos = _tabScrollController.position;
    if (!pos.hasContentDimensions) return;
    _onTabScrollMetrics(pos);
  }

  void _tabScrollBy(double delta) {
    if (!_tabScrollController.hasClients) return;
    final pos = _tabScrollController.position;
    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _tabScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  void initState() {
    super.initState();
    FocusRepository().registerMoreScreenFocusRequester(requestActiveTabFocus);
    _applyTabState([], notify: false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateTabScrollState(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitFromBloc) {
      _didInitFromBloc = true;
      final state = context.read<PluginSystemBloc>().state;
      if (state is PluginSystemLoaded) {
        final isOfflineMode = context.read<SettingsBloc>().state.isOfflineMode;
        _applyTabState(
          state.pinnedPlugins.filterForOfflineMode(isOfflineMode),
          notify: false,
        );
      }
    }
  }

  void resetToCalendar() {
    // _showMobileMenu חייב להתאפס גם כשהכלי כבר הוא לוח השנה, אחרת במסך צר
    // המשתמש שהיה בתפריט "כלים" וחזר ללוח שנה ימשיך לראות את התפריט.
    if (_selectedToolId != 'builtin.calendar' || _showMobileMenu) {
      setState(() {
        _setSelectedToolId('builtin.calendar');
        _showMobileMenu = false;
      });
    }
    _requestCalendarFocus();
  }

  /// פותח לשונית כלי לפי מזהה. אם ה-descriptor עדיין לא נטען (תוסף שעוד לא
  /// הגיע מ-PluginSystemBloc), הבקשה נכנסת לתור ותתבצע אוטומטית בעת הרענון
  /// הבא של ה-descriptors. אם תוך 5 שניות עדיין לא נמצא — מוצגת שגיאה.
  ///
  /// משמש גם את ה-Guided Tour וגם את ה-deep links (`otzaria://open/tool/...`).
  void requestOpenTool(String toolId) {
    final index = _descriptors.indexWhere((d) => d.toolId == toolId);
    if (index != -1) {
      _clearPendingTool();
      _changeTab(index);
      return;
    }

    // ה-descriptor לא נמצא בלשוניות הנוכחיות. בודקים אם מדובר בכלי קיים
    // שסונן מהתצוגה — כדי להחזיר שגיאה תיאורית במקום "הכלי לא נמצא" המטעה.

    // בדיקה: כלי מובנה מוסתר
    final settingsState = context.read<SettingsBloc>().state;
    final allBuiltIns = _buildAllBuiltInDescriptors();
    final hiddenBuiltIn = allBuiltIns.cast<BuiltInToolDescriptor?>().firstWhere(
      (d) => d?.toolId == toolId,
      orElse: () => null,
    );
    if (hiddenBuiltIn != null &&
        settingsState.hiddenBuiltInToolIds.contains(toolId)) {
      _clearPendingTool();
      UiSnack.showError(ToolsMessages.builtInToolHidden(hiddenBuiltIn.label));
      return;
    }

    // בדיקה: תוסף שאינו מוצג בכלים או שדורש אינטרנט במצב מנותק
    final isOfflineMode = settingsState.isOfflineMode;
    final blocState = context.read<PluginSystemBloc>().state;
    if (blocState is PluginSystemLoaded) {
      InstalledPlugin? matchedPlugin;
      for (final p in blocState.plugins) {
        if (p.pluginId == toolId) {
          matchedPlugin = p;
          break;
        }
      }
      if (matchedPlugin != null) {
        if (!matchedPlugin.showInTools && !matchedPlugin.pinnedToNavRail) {
          _clearPendingTool();
          UiSnack.showError(
            ToolsMessages.pluginNotShownInTools(matchedPlugin.name),
          );
          return;
        }
        if (isOfflineMode && matchedPlugin.blockedInOfflineMode) {
          _clearPendingTool();
          UiSnack.showError(
            ToolsMessages.pluginRequiresInternet(matchedPlugin.name),
          );
          return;
        }
      }
    }

    // ה-descriptor עדיין לא קיים — קורה בעיקר עם תוספים לפני ש-PluginSystemLoaded
    // הגיע. ממתינים ל-_applyTabState הבא כדי לפתוח, ומוסיפים timeout עם פידבק
    // למקרה שהכלי לא מתקיים בפועל.
    _pendingToolIdToOpen = toolId;
    _pendingToolTimeoutTimer?.cancel();
    _pendingToolTimeoutTimer = Timer(_pendingToolTimeout, () {
      if (!mounted) return;
      if (_pendingToolIdToOpen == toolId) {
        _pendingToolIdToOpen = null;
        _pendingToolTimeoutTimer = null;
        UiSnack.showError(ToolsMessages.toolNotFound(toolId));
      }
    });
  }

  void _clearPendingTool() {
    _pendingToolIdToOpen = null;
    _pendingToolTimeoutTimer?.cancel();
    _pendingToolTimeoutTimer = null;
  }

  void _flushPendingToolIfReady() {
    final pendingId = _pendingToolIdToOpen;
    if (pendingId == null) return;
    final index = _descriptors.indexWhere((d) => d.toolId == pendingId);
    if (index == -1) return;
    _clearPendingTool();
    // _applyTabState רץ בתוך setState; דוחים את החלפת הטאב לפריים הבא כדי לא
    // לקנן setState נוספת.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < _descriptors.length &&
          _descriptors[index].toolId == pendingId) {
        _changeTab(index);
      } else {
        // הסדר השתנה בין הקריאות — נחפש שוב לפי id.
        final freshIndex = _descriptors.indexWhere(
          (d) => d.toolId == pendingId,
        );
        if (freshIndex != -1) _changeTab(freshIndex);
      }
    });
  }

  @override
  void dispose() {
    FocusRepository().unregisterMoreScreenFocusRequester(requestActiveTabFocus);
    _pendingToolTimeoutTimer?.cancel();
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
    _tabScrollController.dispose();
    activeToolIdNotifier.value = null;
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // ─── UI builders ─────────────────────────────────────────────────────────────

  Widget _buildMobileMenu(Color bgColor) {
    final cs = Theme.of(context).colorScheme;
    // תוסף מוסתר-מכלים אינו מוצג בתפריט המובייל (כמו בסרגל הלשוניות בדסקטופ)
    final visibleDescriptors = _hiddenNavRailPlugin == null
        ? _descriptors
        : _descriptors
              .where((d) => d.toolId != _hiddenNavRailPlugin!.pluginId)
              .toList();
    final groupedDescriptors = buildMobileToolGroups(
      visibleDescriptors,
      groupDefs: _mobileGroupDefs,
    );

    Widget buildIcon(ToolDescriptor descriptor) {
      if (descriptor is BuiltInToolDescriptor) {
        if (descriptor.imageIcon != null) {
          return ImageIcon(
            AssetImage(descriptor.imageIcon!),
            size: 22,
            color: cs.primary,
          );
        }
        return RtlIcon(descriptor.icon!, color: cs.primary);
      }
      if (descriptor is PluginToolDescriptor) {
        return RtlIcon(descriptor._pluginIcon, color: cs.primary);
      }
      return Icon(FluentIcons.puzzle_piece_24_regular, color: cs.primary);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('כלים'),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.puzzle_piece_24_regular),
            tooltip: 'תוספים',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (modalContext) => SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: PluginSidePanel(
                  onPluginSelected: (plugin) {
                    Navigator.of(context).pop();
                    openPluginTransiently(plugin);
                  },
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final group in groupedDescriptors) ...[
            SettingsCard(
              title: group.label,
              children: [
                for (final descriptor in group.tools)
                  ListTile(
                    leading: buildIcon(descriptor),
                    title: Text(descriptor.label),
                    trailing: const RtlIcon(
                      FluentIcons.chevron_left_24_regular,
                    ),
                    onTap: () {
                      final index = _descriptors.indexOf(descriptor);
                      if (index != -1) _changeTab(index);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSM),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileContent(Color bgColor) {
    final currentIndex = _descriptors.indexWhere(
      (d) => d.toolId == _selectedToolId,
    );
    final safeIndex = currentIndex.clamp(
      0,
      _descriptors.isEmpty ? 0 : _descriptors.length - 1,
    );

    return KeyboardNavigator(
      currentTabIndex: safeIndex,
      totalTabs: _descriptors.length,
      onTabChange: _changeTab,
      onBack: () => setState(() => _showMobileMenu = true),
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            _descriptors.isEmpty ? '' : _descriptors[safeIndex].label,
          ),
          leading: Tooltip(
            message: 'חזור (Esc)',
            child: IconButton(
              icon: const RtlIcon(FluentIcons.arrow_right_24_regular),
              onPressed: () => setState(() => _showMobileMenu = true),
            ),
          ),
        ),
        body: Focus(
          focusNode: _contentFocusNode,
          child: ColoredBox(
            color: bgColor,
            child: _pages.isEmpty ? const SizedBox() : _pages[safeIndex],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(Color bgColor, {required bool isImmersive}) {
    final currentIndex = _descriptors.indexWhere(
      (d) => d.toolId == _selectedToolId,
    );
    final safeIndex = currentIndex.clamp(
      0,
      _descriptors.isEmpty ? 0 : _descriptors.length - 1,
    );

    return KeyboardNavigator(
      currentTabIndex: safeIndex,
      totalTabs: _descriptors.length,
      onTabChange: _changeTab,
      onBack: null,
      child: ColoredBox(
        color: bgColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      _contentScrollController.hasClients) {
                    final newOffset =
                        _contentScrollController.offset + event.scrollDelta.dy;
                    _contentScrollController.jumpTo(
                      newOffset.clamp(
                        0.0,
                        _contentScrollController.position.maxScrollExtent,
                      ),
                    );
                  }
                },
                child: Column(
                  children: [
                    if (!shouldHideToolsTabBar(
                      isImmersive: isImmersive,
                      hiddenNavRailPluginId: _hiddenNavRailPlugin?.pluginId,
                      selectedToolId: _selectedToolId,
                    ))
                      ColoredBox(
                        color: bgColor,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.spaceXS,
                          ),
                          child: Row(
                            children: [
                              // חץ ימני – מוצג כשיש תוכן נסתר בצד ימין
                              SizedBox(
                                width: 36,
                                height: 40,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: _canTabScrollLeft ? 1.0 : 0.0,
                                  child: IgnorePointer(
                                    ignoring: !_canTabScrollLeft,
                                    child: IconButton(
                                      icon: const RtlIcon(
                                        FluentIcons.chevron_right_24_regular,
                                      ),
                                      iconSize: 18,
                                      onPressed: () => _tabScrollBy(-150),
                                      tooltip: 'גלול ימינה',
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: NotificationListener<ScrollMetricsNotification>(
                                  onNotification: (n) {
                                    if (n.metrics.axis == Axis.horizontal) {
                                      _onTabScrollMetrics(n.metrics);
                                    }
                                    return false;
                                  },
                                  child: NotificationListener<ScrollNotification>(
                                    onNotification: (n) {
                                      if (n.metrics.axis == Axis.horizontal) {
                                        _onTabScrollMetrics(n.metrics);
                                      }
                                      return false;
                                    },
                                    child: Center(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        controller: _tabScrollController,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (
                                              int index = 0;
                                              index < _descriptors.length;
                                              index++
                                            ) ...[
                                              // תוסף מוסתר-מכלים: לא מציג tab
                                              if (_descriptors[index].toolId !=
                                                  _hiddenNavRailPlugin
                                                      ?.pluginId) ...[
                                                _descriptors[index]
                                                    .buildTopNavItem(
                                                      isSelected:
                                                          _selectedToolId ==
                                                          _descriptors[index]
                                                              .toolId,
                                                      onTap: () =>
                                                          _changeTab(index),
                                                    ),
                                                if (index <
                                                    _descriptors.length - 1)
                                                  const SizedBox(
                                                    width: AppTokens.spaceXS,
                                                  ),
                                              ],
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // חץ שמאלי – מוצג כשיש תוכן נסתר בצד שמאל
                              SizedBox(
                                width: 36,
                                height: 40,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: _canTabScrollRight ? 1.0 : 0.0,
                                  child: IgnorePointer(
                                    ignoring: !_canTabScrollRight,
                                    child: IconButton(
                                      icon: const RtlIcon(
                                        FluentIcons.chevron_left_24_regular,
                                      ),
                                      iconSize: 18,
                                      onPressed: () => _tabScrollBy(150),
                                      tooltip: 'גלול שמאלה',
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                              // כפתור תוספים מוצמד לשמאל חזותי (סוף Row ב-RTL)
                              IconButton(
                                icon: const Icon(
                                  FluentIcons.puzzle_piece_24_regular,
                                ),
                                onPressed: () => setState(
                                  () => _isPanelOpen = !_isPanelOpen,
                                ),
                                tooltip: 'תוספים',
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          ClipRect(
                            child: PrimaryScrollController(
                              controller: _contentScrollController,
                              child: Focus(
                                focusNode: _contentFocusNode,
                                child: ColoredBox(
                                  color: bgColor,
                                  child: _pages.isEmpty
                                      ? const SizedBox()
                                      : IndexedStack(
                                          sizing: StackFit.expand,
                                          index: safeIndex,
                                          // בנייה עצלנית: רק כלים שכבר נבחרו
                                          // פעם אחת מוצגים כ-widget אמיתי.
                                          // אחרים נשארים SizedBox.shrink() —
                                          // החיסכון העיקרי: לא יוצרים WebView
                                          // לכל תוסף בכניסה למסך "כלים".
                                          children: List<Widget>.generate(
                                            _pages.length,
                                            (i) =>
                                                _activatedToolIds.contains(
                                                  _descriptors[i].toolId,
                                                )
                                                ? _pages[i]
                                                : const SizedBox.shrink(),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                          // לתוספים אין AppTopBar שמארח את לחצן היציאה ממסך
                          // מלא, לכן רק אצלם מוצג לחצן צף.
                          if (isImmersive &&
                              _descriptors.isNotEmpty &&
                              _descriptors[safeIndex] is PluginToolDescriptor)
                            const Positioned(
                              top: 8,
                              right: 8,
                              child: ExitFullscreenButton(),
                            ),
                          ContextOverlayPanel(
                            isOpen: _isPanelOpen,
                            onClose: () => setState(() => _isPanelOpen = false),
                            width: 400,
                            child: PluginSidePanel(
                              onPluginSelected: (plugin) {
                                openPluginTransiently(plugin);
                              },
                              onClose: () =>
                                  setState(() => _isPanelOpen = false),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bgColor = AppSurfaces.panelBackground(context);
    // מסך מלא מותר רק בעיון/כלים; מסך הכלים נראה רק כשהמסך הוא Screen.more,
    // ולכן די לבדוק את דגל מסך-מלא כדי לדעת שאנו במצב אימרסיבי בכלים.
    final isImmersive = context.select(
      (SettingsBloc b) => b.state.isFullscreen,
    );

    return MultiBlocListener(
      listeners: [
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (prev, curr) =>
              prev.isOfflineMode != curr.isOfflineMode ||
              !_setEquals(prev.hiddenBuiltInToolIds, curr.hiddenBuiltInToolIds),
          listener: (context, settingsState) {
            final blocState = context.read<PluginSystemBloc>().state;
            if (blocState is! PluginSystemLoaded) return;
            // אם התוסף ה-transient דורש אינטרנט ועברנו למצב מנותק — נסגור אותו.
            if (settingsState.isOfflineMode &&
                _transientPlugin != null &&
                _transientPlugin!.blockedInOfflineMode) {
              _transientPlugin = null;
            }
            _rebuildTabs(
              blocState.pinnedPlugins.filterForOfflineMode(
                settingsState.isOfflineMode,
              ),
              transient: _transientPlugin,
            );
          },
        ),
        BlocListener<PluginSystemBloc, PluginSystemState>(
          listener: (context, state) {
            if (state is PluginSystemLoaded) {
              final isOfflineMode = context
                  .read<SettingsBloc>()
                  .state
                  .isOfflineMode;
              _transientPlugin = resolveTransientAfterPluginsLoaded(
                _transientPlugin,
                state.plugins,
                isOfflineMode: isOfflineMode,
              );
              // עדכון מידע תוסף מוסתר פעיל (אם הותקן מחדש / השתנה)
              if (_hiddenNavRailPlugin != null) {
                final updated = state.plugins.firstWhere(
                  (p) => p.pluginId == _hiddenNavRailPlugin!.pluginId,
                  orElse: () => _hiddenNavRailPlugin!,
                );
                if (!updated.enabled || !updated.pinnedToNavRail) {
                  // התוסף הושבת או הוסר מ-NavRail — סגור
                  _hiddenNavRailPlugin = null;
                  _transientPlugin = null;
                } else {
                  _hiddenNavRailPlugin = updated;
                }
              }
              _rebuildTabs(
                state.pinnedPlugins.filterForOfflineMode(isOfflineMode),
                transient: _transientPlugin,
              );
            }
            // טיפול ב-PluginSystemOverwriteRequired עבר ל-main_window_screen.dart
            // כדי לעבוד גם כשפותחים קובץ ‎.otzplugin ממסך אחר.
          },
        ),
      ],
      child: Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: bgColor,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < LayoutBreakpoints.compact;
            final content = isMobile
                ? (_showMobileMenu
                      ? _buildMobileMenu(bgColor)
                      : _buildMobileContent(bgColor))
                : _buildDesktop(bgColor, isImmersive: isImmersive);

            // החזרת content ישירות — ללא AnimatedSwitcher וללא KeyedSubtree.
            // AnimatedSwitcher עם key משתנה גורם ל-Flutter לשמיד ולהקים
            // מחדש את כל ה-subtree (כולל FocusNodes) בכל מעבר mobile↔desktop,
            // וזו שורש הקריסות ואיבודי הפוקוס ב-Windows בזמן resize.
            return content;
          },
        ),
      ),
    );
  }
}
