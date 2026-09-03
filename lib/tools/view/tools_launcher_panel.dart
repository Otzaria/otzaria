import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/view/plugin_actions.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';
import 'package:otzaria/plugins/utils/plugin_dev_tools_mode.dart';
import 'package:otzaria/plugins/view/widgets/plugin_drop_zone.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/tool_order.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/feedback/edge_scrollbar_behavior.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

const String kBuiltInToolsGroupLabel = 'כלים';
const String kPluginsGroupLabel = 'תוספים';

/// מנרמל טקסט להשוואת חיפוש: גרשיים, מקפים וניקוד אינם אמורים למנוע התאמה.
@visibleForTesting
String normalizeToolSearchText(String value) {
  return value
      .replaceAll(RegExp(r'[֑-ׇ]'), '')
      .replaceAll(RegExp(r'''["'`׳״\-–—]'''), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

/// מסנן רשומות לפי מחרוזת חיפוש, מול התווית ומול שם התוסף.
@visibleForTesting
List<ToolCatalogEntry> filterToolEntries(
  List<ToolCatalogEntry> entries,
  String query,
) {
  final normalized = normalizeToolSearchText(query);
  if (normalized.isEmpty) return entries;
  return entries.where((entry) {
    if (normalizeToolSearchText(entry.label).contains(normalized)) return true;
    final pluginName = entry.plugin?.name;
    return pluginName != null &&
        normalizeToolSearchText(pluginName).contains(normalized);
  }).toList();
}

typedef ToolGroup = ({String label, List<ToolCatalogEntry> entries});

/// מקבץ רשומות עוקבות לפי סוגן בלי לשנות את סדר הקטלוג.
///
/// הפיצול הוא גם לפי קבוצת המיון, ולא לפי התווית בלבד: כשכל הכלים המובנים
/// מוסתרים, שתי קבוצות התוספים (זו שהורשתה להקדים אותם וזו הרגילה) נהיות
/// עוקבות, וקבוצה מאוחדת הייתה מייצרת פעולות הזזה פעילות שאינן עושות דבר.
@visibleForTesting
List<ToolGroup> groupToolEntries(List<ToolCatalogEntry> entries) {
  final groups = <ToolGroup>[];
  int? lastPriority;
  for (final entry in entries) {
    final label = entry.isPlugin ? kPluginsGroupLabel : kBuiltInToolsGroupLabel;
    if (groups.isNotEmpty &&
        groups.last.label == label &&
        lastPriority == entry.sortGroupPriority) {
      groups.last.entries.add(entry);
    } else {
      groups.add((label: label, entries: [entry]));
    }
    lastPriority = entry.sortGroupPriority;
  }
  return groups;
}

/// סדר הקוביות כפי שהן מוצגות בפועל.
@visibleForTesting
List<ToolCatalogEntry> orderedToolEntries(List<ToolCatalogEntry> entries) => [
  for (final group in groupToolEntries(entries)) ...group.entries,
];

/// רוחב היעד לקובייה — ברוחב הפאנל שבברירת מחדל נכנסות ארבע קוביות בשורה.
@visibleForTesting
const double kToolTileTargetWidth = 88;

/// המרווח בקצה ימין שמפנה מקום לפס הגלילה, כדי שלא יעלה על הקוביות.
@visibleForTesting
const double kToolGridScrollbarGutter = 14;

/// מספר העמודות ברשת לרוחב נתון. הרוחב שמועבר הוא זה שנשאר לקוביות — כלומר
/// לאחר הפחתת [kToolGridScrollbarGutter].
@visibleForTesting
int toolGridColumns(double width) =>
    (width / kToolTileTargetWidth).floor().clamp(2, 5);

/// האינדקס המסומן הבא בניווט מקלדת. `-1` = אין סימון, והחץ הראשון מסמן את
/// הקובייה הראשונה.
@visibleForTesting
int nextHighlightIndex({
  required int current,
  required int delta,
  required int total,
}) {
  if (total <= 0) return 0;
  // ממצב "אין סימון" כל חץ מסמן את הקובייה הראשונה, ולא מדלג delta קוביות.
  if (current < 0) return 0;
  return (current + delta).clamp(0, total - 1);
}

/// האם שתי רשומות שייכות לאותה קבוצת תצוגה, כלומר האם מותר לסדר ביניהן.
///
/// כלי מובנה ותוסף אינם מתערבבים, וגם תוסף שהורשה להקדים את הכלים המובנים
/// יושב בקבוצה נפרדת מתוסף רגיל.
@visibleForTesting
bool canReorderBetween(ToolCatalogEntry source, ToolCatalogEntry target) =>
    source.toolId != target.toolId &&
    source.isPlugin == target.isPlugin &&
    source.sortGroupPriority == target.sortGroupPriority;

/// פעולה בתפריט הקובייה. מקור אמת אחד — נצרך גם בכפתור ⋯ וגם בבדיקות.
/// [onTap] ריק (`null`) = הפעולה מוצגת מעומעמת (למשל הזזה בקצה הקבוצה).
/// [children] הופך את הפעולה לתת-תפריט, ואז [onTap] אינו בשימוש.
@visibleForTesting
class ToolTileAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  /// מפריד מעל הפעולה — מפריד את הפעולות ההרסניות משאר התפריט.
  final bool dividerBefore;

  final List<ToolTileAction>? children;

  const ToolTileAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.dividerBefore = false,
    this.children,
  });
}

/// תוכן פאנל הכלים: חיפוש למעלה, ומתחתיו רשת קוביות מקובצת.
class ToolsLauncherPanel extends StatefulWidget {
  final ValueChanged<ToolCatalogEntry> onToolSelected;
  final VoidCallback onClose;

  /// `null` — לפי [PluginDevToolsMode.enabled] (debug או דגל `--dev-plugins`).
  final bool? showDevTools;

  const ToolsLauncherPanel({
    super.key,
    required this.onToolSelected,
    required this.onClose,
    this.showDevTools,
  });

  @override
  State<ToolsLauncherPanel> createState() => _ToolsLauncherPanelState();
}

class _ToolsLauncherPanelState extends State<ToolsLauncherPanel> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();
  late final FocusNode _searchFocusNode = FocusNode(
    onKeyEvent: _handleSearchFieldKey,
  );
  String _query = '';

  /// הקובייה המסומנת בניווט מקלדת, כאינדקס ברשימה המסוננת השטוחה.
  /// `-1` = אין סימון, כדי שלא ייראה כאילו הכלי הראשון נבחר.
  int _highlightedIndex = -1;
  List<ToolCatalogEntry> _keyboardEntries = const [];
  int _keyboardColumns = 2;

  /// הכלי שזז אחרון ומספר ההזזה — מריצים פעימת הדגשה על הקובייה שזזה.
  String? _movedToolId;
  int _moveNonce = 0;

  /// הסדר ששוגר וטרם חזר מה-bloc. בסיס לחישוב הזזה נוספת שמגיעה לפני שהמצב
  /// התיישר. `null` = אין שיגור באוויר.
  List<String>? _pendingBuiltInOrder;
  List<String>? _pendingPluginOrder;

  /// אזור הרשת כולו — קצוותיו הם אזורי גלילת הקצה בזמן גרירה.
  final GlobalKey _gridAreaKey = GlobalKey();

  /// מסמן אפס-גובה אחרי הקובייה האחרונה — הגבול שמתחתיו שחרור הוא "לסוף".
  final GlobalKey _gridEndKey = GlobalKey();

  /// גלילת הקצה בגרירה: הכיוון (1- למעלה, 1 למטה) והשעון שמניע אותה.
  double _autoScrollDirection = 0;
  Timer? _autoScrollTimer;

  /// הקובייה שמציגה קו "אחרי" כשהגרירה מרחפת בשטח הריק שמתחת לרשת.
  String? _endDropIndicatorId;

  @override
  void initState() {
    super.initState();
    // autofocus אינו עובד כאן: הפאנל נפתח בתוך FocusScope שכבר יש בו
    // focusedChild (מסך הקריאה), ואז בקשת ה-autofocus נזנחת.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _searchController.dispose();
    _gridScrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _installPlugin() async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !mounted) return;
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['otzplugin'],
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
    final path = result?.path;
    if (path == null || !mounted) return;
    context.read<PluginSystemBloc>().add(InstallPluginRequested(path));
  }

  Future<void> _loadDevPlugin() async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !mounted) return;
    final rootPath = await FilePicker.getDirectoryPath(
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
    if (rootPath == null || !mounted) return;
    context.read<PluginSystemBloc>().add(
      LoadDevelopmentPluginRequested(rootPath),
    );
  }

  Future<void> _loadLocalhostPlugin() async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !mounted) return;
    final bloc = context.read<PluginSystemBloc>();
    final url = await showInputDialog(
      context: context,
      title: 'טעינת תוסף מ-localhost',
      labelText: 'Base URL',
      hintText: 'http://localhost:3000',
      initialValue: 'http://localhost:3000',
      cancelText: 'ביטול',
      confirmText: 'טען',
    );
    if (url == null || url.isEmpty) return;
    bloc.add(LoadLocalhostPluginRequested(url));
  }

  void _moveHighlight(int delta, int total) {
    if (total == 0) return;
    setState(() {
      _highlightedIndex = nextHighlightIndex(
        current: _highlightedIndex,
        delta: delta,
        total: total,
      );
    });
  }

  void _activateHighlighted(List<ToolCatalogEntry> entries) {
    if (entries.isEmpty) return;
    widget.onToolSelected(
      entries[_highlightedIndex.clamp(0, entries.length - 1)],
    );
  }

  KeyEventResult _handleKey(
    KeyEvent event,
    List<ToolCatalogEntry> entries,
    int columns,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onClose();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveHighlight(columns, entries.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveHighlight(-columns, entries.length);
        return KeyEventResult.handled;
      // ב-RTL הקובייה הבאה נמצאת משמאל, ולכן החיצים מתהפכים ביחס ל-LTR.
      case LogicalKeyboardKey.arrowLeft:
        _moveHighlight(1, entries.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _moveHighlight(-1, entries.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _activateHighlighted(entries);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSearchFieldKey(FocusNode _, KeyEvent event) =>
      _handleKey(event, _keyboardEntries, _keyboardColumns);

  // ── סידור מחדש ──────────────────────────────────────────────────────────────

  /// סידור אפשרי רק ברשימה המלאה: בחיפוש הקוביות מסוננות, ו"השכן" על המסך
  /// אינו השכן האמיתי בסדר.
  bool get _isReorderEnabled => normalizeToolSearchText(_query).isEmpty;

  void _reorder({
    required ToolCatalogEntry source,
    required ToolCatalogEntry target,
    required bool placeAfter,
  }) {
    if (!canReorderBetween(source, target)) return;
    final pluginBloc = context.read<PluginSystemBloc>();
    final settingsBloc = context.read<SettingsBloc>();

    // שיגור מושהה לפריים הבא: הרשת נבנית בתוך LayoutBuilder, ושיגור בזמן
    // הבנייה מפיל את Flutter על הפעלה-מחדש של רכיבי Overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (source.isPlugin) {
        final pluginState = pluginBloc.state;
        if (pluginState is! PluginSystemLoaded) return;
        // הסדר ששוגר לפני רגע הוא הבסיס עד שה-bloc מתיישר, אחרת הזזה שנייה
        // מהירה מחושבת מהסדר הישן ומוחקת את הראשונה.
        final base =
            _pendingPluginOrder ??
            pluginState.plugins.map((plugin) => plugin.pluginId).toList();
        final ordered = reorderIdsAroundTarget(
          base,
          source.toolId,
          target.toolId,
          placeAfter: placeAfter,
        );
        _pendingPluginOrder = ordered;
        pluginBloc.add(ReorderPluginsRequested(ordered));
      } else {
        final ordered = reorderedBuiltInToolIds(
          _pendingBuiltInOrder ?? settingsBloc.state.builtInToolsOrder,
          source.toolId,
          target.toolId,
          placeAfter: placeAfter,
        );
        _pendingBuiltInOrder = ordered;
        settingsBloc.add(UpdateBuiltInToolsOrder(ordered));
      }
      setState(() {
        _movedToolId = source.toolId;
        _moveNonce++;
      });
    });
  }

  // ── שחרור בשטח הריק וגלילת קצה בגרירה ───────────────────────────────────────

  /// היעד לשחרור בשטח הריק: הקובייה האחרונה בקבוצה של [source], או `null`
  /// כשהמקור כבר אחרון ואין מה להזיז.
  ToolCatalogEntry? _endOfGroupTarget(ToolCatalogEntry source) {
    final last = _keyboardEntries.lastWhereOrNull(
      (entry) =>
          entry.isPlugin == source.isPlugin &&
          entry.sortGroupPriority == source.sortGroupPriority,
    );
    return (last == null || last.toolId == source.toolId) ? null : last;
  }

  /// האם הסמן מתחת לקובייה האחרונה — בשטח הריק של הרשת.
  bool _isBelowGridTiles(Offset globalPointer) {
    final box = _gridEndKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return globalPointer.dy >= box.localToGlobal(Offset.zero).dy;
  }

  bool _acceptEndOfGridDrop(DragTargetDetails<ToolCatalogEntry> details) {
    final target = _isReorderEnabled && _isBelowGridTiles(details.offset)
        ? _endOfGroupTarget(details.data)
        : null;
    _setEndDropIndicator(target?.toolId);
    return target != null;
  }

  void _dropAtEndOfGroup(ToolCatalogEntry source) {
    _onDragEnded();
    final target = _endOfGroupTarget(source);
    if (target == null) return;
    _reorder(source: source, target: target, placeAfter: true);
  }

  void _setEndDropIndicator(String? toolId) {
    if (toolId == _endDropIndicatorId) return;
    setState(() => _endDropIndicatorId = toolId);
  }

  void _onDragEnded() {
    _setEndDropIndicator(null);
    _stopDragAutoScroll();
  }

  /// מזניק או עוצר את גלילת הקצה לפי מיקום הסמן באזור הרשת.
  void _updateDragAutoScroll(Offset globalPointer) {
    final box = _gridAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _stopDragAutoScroll();
    final dy = box.globalToLocal(globalPointer).dy;
    var direction = 0.0;
    if (dy < _kGridAutoScrollEdge) {
      direction = -1;
    } else if (dy > box.size.height - _kGridAutoScrollEdge) {
      direction = 1;
    }
    if (direction == 0) return _stopDragAutoScroll();
    _autoScrollDirection = direction;
    _autoScrollTimer ??= Timer.periodic(
      _kGridAutoScrollTick,
      _onAutoScrollTick,
    );
  }

  void _onAutoScrollTick(Timer _) {
    if (!_gridScrollController.hasClients) return _stopDragAutoScroll();
    final position = _gridScrollController.position;
    final target =
        (position.pixels + _autoScrollDirection * _kGridAutoScrollStep).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if (target == position.pixels) return _stopDragAutoScroll();
    position.jumpTo(target);
  }

  void _stopDragAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = 0;
  }

  /// מנקה את הסדר הממתין ברגע שה-bloc התיישר עליו. חייב לקרות ב-build, כי שם
  /// מגיע ה-state המעודכן.
  void _clearSettledPendingOrders(
    SettingsState settingsState,
    PluginSystemState pluginState,
  ) {
    final pendingBuiltIn = _pendingBuiltInOrder;
    if (pendingBuiltIn != null &&
        const ListEquality<String>().equals(
          settingsState.builtInToolsOrder,
          pendingBuiltIn,
        )) {
      _pendingBuiltInOrder = null;
    }
    final pendingPlugins = _pendingPluginOrder;
    if (pendingPlugins != null && pluginState is PluginSystemLoaded) {
      final current = pluginState.plugins
          .map((plugin) => plugin.pluginId)
          .toList();
      // גם כשקבוצת התוספים עצמה השתנתה (התקנה, הסרה, כישלון בשמירה) הבסיס
      // הממתין אינו רלוונטי — אחרת הוא היה נשאר לנצח ומשגר סדר חסר מזהה.
      if (const ListEquality<String>().equals(current, pendingPlugins) ||
          !const SetEquality<String>().equals(
            current.toSet(),
            pendingPlugins.toSet(),
          )) {
        _pendingPluginOrder = null;
      }
    }
  }

  /// פעולות הקובייה, בסדר שבו הן מוצגות בתפריט ⋯.
  List<ToolTileAction> _tileActions(
    ToolCatalogEntry entry, {
    required VoidCallback? onMoveEarlier,
    required VoidCallback? onMoveLater,
    required VoidCallback? onMoveToStart,
    required VoidCallback? onMoveToEnd,
  }) {
    final plugin = entry.plugin;
    return [
      ToolTileAction(
        icon: FluentIcons.re_order_dots_vertical_24_regular,
        label: 'הזזה',
        onTap: null,
        children: [
          // RtlIcon בשורת התפריט מהפך את החץ, כך שיצביע לכיוון ההזזה בפועל.
          ToolTileAction(
            icon: FluentIcons.arrow_left_24_regular,
            label: 'הזז אחורה',
            onTap: onMoveEarlier,
          ),
          ToolTileAction(
            icon: FluentIcons.arrow_right_24_regular,
            label: 'הזז קדימה',
            onTap: onMoveLater,
          ),
          ToolTileAction(
            icon: FluentIcons.arrow_previous_24_regular,
            label: 'הזז לתחילה',
            onTap: onMoveToStart,
          ),
          ToolTileAction(
            icon: FluentIcons.arrow_next_24_regular,
            label: 'הזז לסוף',
            onTap: onMoveToEnd,
          ),
        ],
      ),
      if (plugin != null)
        ToolTileAction(
          icon: FluentIcons.shield_24_regular,
          label: 'ניהול הרשאות',
          onTap: () => showPluginSettingsDialog(context, plugin),
        ),
      ToolTileAction(
        icon: _isPinnedToNavRail(entry)
            ? FluentIcons.pin_off_24_regular
            : FluentIcons.pin_24_regular,
        label: _isPinnedToNavRail(entry)
            ? 'הסר מסרגל הניווט'
            : 'הצמד לסרגל הניווט',
        onTap: () => _togglePinToNavRail(entry),
      ),
      ToolTileAction(
        // תוסף מוצמד לסרגל הניווט נשאר בקטלוג גם כשהוא מוסתר, ולכן התווית
        // חייבת לשקף את מצבו בפועל — אחרת הלחיצה הבאה מחזירה אותו בשקט.
        icon: (plugin?.showInTools ?? true)
            ? FluentIcons.eye_off_24_regular
            : FluentIcons.eye_24_regular,
        label: (plugin?.showInTools ?? true) ? 'הסתר מהממשק' : 'הצג בממשק',
        onTap: () => _hideFromInterface(entry),
      ),
      if (plugin != null)
        ToolTileAction(
          icon: plugin.enabled
              ? FluentIcons.pause_circle_24_regular
              : FluentIcons.play_circle_24_regular,
          label: plugin.enabled ? 'השבת' : 'הפעל',
          onTap: () => togglePluginEnabled(context, plugin),
        ),
      if (plugin != null)
        ToolTileAction(
          icon: FluentIcons.delete_24_regular,
          label: 'מחק תוסף',
          isDestructive: true,
          dividerBefore: true,
          onTap: () => showDeletePluginDialog(context, plugin),
        ),
    ];
  }

  bool _isPinnedToNavRail(ToolCatalogEntry entry) =>
      entry.plugin?.pinnedToNavRail ??
      context.read<SettingsBloc>().state.builtInToolsPinnedToNavRail.contains(
        entry.toolId,
      );

  void _togglePinToNavRail(ToolCatalogEntry entry) {
    final plugin = entry.plugin;
    if (plugin != null) {
      togglePluginPinnedToNavRail(context, plugin);
      return;
    }
    final bloc = context.read<SettingsBloc>();
    final next = Set<String>.from(bloc.state.builtInToolsPinnedToNavRail);
    if (!next.add(entry.toolId)) next.remove(entry.toolId);
    bloc.add(UpdateBuiltInToolsPinnedToNavRail(next));
  }

  void _hideFromInterface(ToolCatalogEntry entry) {
    final plugin = entry.plugin;
    if (plugin != null) {
      togglePluginShowInTools(context, plugin);
      return;
    }
    final bloc = context.read<SettingsBloc>();
    final next = Set<String>.from(bloc.state.hiddenBuiltInToolIds)
      ..add(entry.toolId);
    bloc.add(UpdateHiddenBuiltInToolIds(next));
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsBloc>().state;
    final pluginState = context.watch<PluginSystemBloc>().state;
    final allEntries = buildToolCatalog(
      hiddenBuiltInToolIds: settingsState.hiddenBuiltInToolIds,
      isOfflineMode: settingsState.isOfflineMode,
      pluginState: pluginState,
      builtInToolsOrder: settingsState.builtInToolsOrder,
    );
    _clearSettledPendingOrders(settingsState, pluginState);
    final entries = orderedToolEntries(filterToolEntries(allEntries, _query));
    // הרשימה התקצרה (כלי הוסתר) — סימון שיצא מהטווח היה נשאר בלי חיווי, אבל
    // Enter היה פותח כלי אחר.
    if (_highlightedIndex >= entries.length) _highlightedIndex = -1;
    final openToolIds = _openToolIds(context.watch<TabsBloc>().state);
    _keyboardEntries = entries;

    return PluginDropZone(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: AppTokens.spaceSM),
          _buildSearchField(entries),
          const SizedBox(height: AppTokens.spaceMD),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: entries.isEmpty
                      ? _buildEmptyState(
                          settingsState.isOfflineMode,
                          allEntries,
                        )
                      : _buildGrid(
                          entries,
                          openToolIds,
                          bottomInset:
                              AppInputTokens.height(
                                settingsState.compactMenuMode,
                              ) +
                              AppTokens.spaceMD,
                        ),
                ),
                PositionedDirectional(
                  bottom: AppTokens.spaceSM,
                  start: kToolGridScrollbarGutter,
                  child: _PluginsToolbar(
                    showDevTools:
                        widget.showDevTools ?? PluginDevToolsMode.enabled,
                    onInstall: _installPlugin,
                    onLoadFolder: _loadDevPlugin,
                    onLoadLocalhost: _loadLocalhostPlugin,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Set<String> _openToolIds(TabsState state) => {
    for (final tab in state.tabs)
      for (final pane in leafPanes(tab))
        if (pane is ToolTab) pane.toolId,
  };

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'כלים ותוספים',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppTokens.fontXL,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
          tooltip: 'סגור',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  Widget _buildSearchField(List<ToolCatalogEntry> entries) {
    final field = OtzariaSearchField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      icon: OtzariaIcons.search_24_regular,
      hintText: 'חיפוש כלי או תוסף',
      onChanged: _onQueryChanged,
      onClear: () => _onQueryChanged(''),
      onSubmitted: (_) => _activateHighlighted(entries),
    );

    if (!(widget.showDevTools ?? PluginDevToolsMode.enabled)) return field;

    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: AppTokens.spaceXS),
        SquareIconButton.field(
          icon: FluentIcons.arrow_sync_24_regular,
          tooltip: 'רענן תוספים',
          onPressed: () =>
              context.read<PluginSystemBloc>().add(RefreshPlugins()),
        ),
      ],
    );
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      // בחיפוש התוצאה הראשונה מסומנת (Enter יפתח אותה); בלי חיפוש אין סימון.
      _highlightedIndex = normalizeToolSearchText(value).isEmpty ? -1 : 0;
    });
  }

  Widget _buildEmptyState(bool isOfflineMode, List<ToolCatalogEntry> all) {
    final message = _query.trim().isNotEmpty
        ? 'לא נמצאו כלים התואמים לחיפוש'
        : (isOfflineMode
              ? 'אין כלים זמינים במצב מנותק'
              : 'לא נמצאו כלים זמינים');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLG),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildGrid(
    List<ToolCatalogEntry> entries,
    Set<String> openToolIds, {
    required double bottomInset,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = toolGridColumns(
          constraints.maxWidth - kToolGridScrollbarGutter,
        );
        _keyboardColumns = columns;
        final groups = groupToolEntries(entries);
        final theme = Theme.of(context);
        return Focus(
          autofocus: false,
          onKeyEvent: (_, event) => _handleKey(event, entries, columns),
          // היעד מאחורי הרשת כולה: קולט שחרור בשטח הריק שמתחת לקוביות, ומזין
          // את גלילת הקצה בכל מקום שאין בו קובייה קולטת.
          child: DragTarget<ToolCatalogEntry>(
            key: _gridAreaKey,
            onWillAcceptWithDetails: _acceptEndOfGridDrop,
            onMove: (details) => _updateDragAutoScroll(details.offset),
            onLeave: (_) => _onDragEnded(),
            onAcceptWithDetails: (details) => _dropAtEndOfGroup(details.data),
            builder: (context, _, _) => ScrollConfiguration(
              behavior: const EdgeScrollbarBehavior.right(),
              child: CustomScrollView(
                controller: _gridScrollController,
                slivers: _buildGridSlivers(
                  groups: groups,
                  columns: columns,
                  openToolIds: openToolIds,
                  bottomInset: bottomInset,
                  theme: theme,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildGridSlivers({
    required List<ToolGroup> groups,
    required int columns,
    required Set<String> openToolIds,
    required double bottomInset,
    required ThemeData theme,
  }) {
    final slivers = <Widget>[];
    var runningIndex = 0;
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final isNewLabel = i == 0 || group.label != groups[i - 1].label;
      if (i > 0 && isNewLabel) {
        slivers.add(
          const SliverPadding(
            padding: EdgeInsets.only(
              top: AppTokens.spaceMD,
              right: kToolGridScrollbarGutter,
              bottom: AppTokens.spaceSM,
            ),
            sliver: SliverToBoxAdapter(child: Divider(height: 1)),
          ),
        );
      }
      if (isNewLabel) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.only(
              top: AppTokens.spaceSM,
              right: kToolGridScrollbarGutter,
              bottom: AppTokens.spaceSM,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                group.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }
      final groupStartIndex = runningIndex;
      runningIndex += group.entries.length;
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.only(right: kToolGridScrollbarGutter),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppTokens.spaceSM,
              crossAxisSpacing: AppTokens.spaceSM,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildTile(
                group: group.entries,
                indexInGroup: index,
                flatIndex: groupStartIndex + index,
                openToolIds: openToolIds,
              ),
              childCount: group.entries.length,
            ),
          ),
        ),
      );
    }
    slivers.add(
      SliverPadding(
        padding: EdgeInsets.only(
          right: kToolGridScrollbarGutter,
          bottom: bottomInset,
        ),
        sliver: SliverToBoxAdapter(
          child: Column(
            children: [
              SizedBox(key: _gridEndKey, height: 0),
              const SizedBox(height: AppTokens.spaceMD),
            ],
          ),
        ),
      ),
    );
    return slivers;
  }

  Widget _buildTile({
    required List<ToolCatalogEntry> group,
    required int indexInGroup,
    required int flatIndex,
    required Set<String> openToolIds,
  }) {
    final entry = group[indexInGroup];
    final canReorder = _isReorderEnabled;
    final isFirst = indexInGroup == 0;
    final isLast = indexInGroup == group.length - 1;
    VoidCallback? moveTo(
      int targetIndex, {
      required bool enabled,
      required bool placeAfter,
    }) => enabled
        ? () => _reorder(
            source: entry,
            target: group[targetIndex],
            placeAfter: placeAfter,
          )
        : null;

    return _ReorderableToolTile(
      key: ValueKey(entry.toolId),
      entry: entry,
      canDrag: canReorder,
      showEndIndicator: entry.toolId == _endDropIndicatorId,
      onDragOver: _updateDragAutoScroll,
      onDragEnded: _onDragEnded,
      onAcceptSource: (source, {required placeAfter}) =>
          _reorder(source: source, target: entry, placeAfter: placeAfter),
      tile: ToolTile(
        entry: entry,
        isOpen: openToolIds.contains(entry.toolId),
        isHighlighted: flatIndex == _highlightedIndex,
        movePulse: entry.toolId == _movedToolId ? _moveNonce : 0,
        // בלי זה הפוקוס נשאר על מסלול התפריט שנסגר, ומקשי הפאנל (Escape,
        // חצים, Enter) מפסיקים לעבוד עד לחיצה על שדה החיפוש.
        onMenuClosed: () => _searchFocusNode.requestFocus(),
        actions: _tileActions(
          entry,
          onMoveEarlier: moveTo(
            indexInGroup - 1,
            enabled: canReorder && !isFirst,
            placeAfter: false,
          ),
          onMoveLater: moveTo(
            indexInGroup + 1,
            enabled: canReorder && !isLast,
            placeAfter: true,
          ),
          onMoveToStart: moveTo(
            0,
            enabled: canReorder && !isFirst,
            placeAfter: false,
          ),
          onMoveToEnd: moveTo(
            group.length - 1,
            enabled: canReorder && !isLast,
            placeAfter: true,
          ),
        ),
        onTap: () => widget.onToolSelected(entry),
      ),
    );
  }
}

/// סרגל צף לפעולות התוספים, בתחתית תחילת החלונית — באותו עיצוב של סרגל
/// התצוגה המקדימה בספריה.
class _PluginsToolbar extends StatelessWidget {
  final bool showDevTools;
  final VoidCallback onInstall;
  final VoidCallback onLoadFolder;
  final VoidCallback onLoadLocalhost;

  const _PluginsToolbar({
    required this.showDevTools,
    required this.onInstall,
    required this.onLoadFolder,
    required this.onLoadLocalhost,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      shape: AppTokens.roundedShape,
      elevation: AppTokens.elevation1,
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SquareIconButton.toolbar(
            icon: FluentIcons.add_24_regular,
            tooltip: 'התקן תוסף חדש',
            onPressed: onInstall,
          ),
          if (showDevTools) ...[
            SquareIconButton.toolbar(
              icon: FluentIcons.folder_add_24_regular,
              tooltip: 'טען תיקיית תוסף',
              onPressed: onLoadFolder,
            ),
            SquareIconButton.toolbar(
              icon: FluentIcons.globe_add_24_regular,
              tooltip: 'טען תוסף מ-localhost',
              onPressed: onLoadLocalhost,
            ),
          ],
        ],
      ),
    );
  }
}

/// עוטף קובייה ביכולת גרירה לסידור מחדש: גוררים קובייה, וקו ההוספה מראה בין
/// אילו קוביות היא תיפול — לפי חצי הקובייה שהסמן נמצא בו, כמו סידור לשוניות
/// בדפדפן. במגע הגרירה מתחילה בלחיצה ארוכה, כדי לא לחטוף את הגלילה.
class _ReorderableToolTile extends StatefulWidget {
  final ToolCatalogEntry entry;
  final ToolTile tile;
  final bool canDrag;

  /// קו "אחרי" כפוי — כשגרירה מרחפת בשטח הריק והקובייה היא סוף קבוצת היעד.
  final bool showEndIndicator;
  final void Function(ToolCatalogEntry source, {required bool placeAfter})
  onAcceptSource;

  /// תזוזת גרירה מעל הקובייה — מזינה את גלילת הקצה של הרשת.
  final ValueChanged<Offset> onDragOver;

  /// הגרירה עזבה את הקובייה או הסתיימה — עוצרת את גלילת הקצה.
  final VoidCallback onDragEnded;

  const _ReorderableToolTile({
    super.key,
    required this.entry,
    required this.tile,
    required this.canDrag,
    required this.showEndIndicator,
    required this.onDragOver,
    required this.onDragEnded,
    required this.onAcceptSource,
  });

  @override
  State<_ReorderableToolTile> createState() => _ReorderableToolTileState();
}

class _ReorderableToolTileState extends State<_ReorderableToolTile> {
  /// `true` = הקובייה הנגררת תיפול *אחרי* הקובייה הזאת בסדר.
  bool _placeAfter = false;

  bool get _isTouch => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  /// בכיוון RTL "לפני" הוא הצד הימני של הקובייה, ולכן סמן בחצי הימני מציב
  /// לפניה וסמן בחצי השמאלי מציב אחריה.
  void _updateSide(ToolCatalogEntry source, Offset globalPointer) {
    // Flutter מדווח על תזוזה גם ליעדים שנדחו, כולל הקובייה הנגררת עצמה.
    if (!canReorderBetween(source, widget.entry)) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(globalPointer);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final inLeadingHalf = local.dx < box.size.width / 2;
    final placeAfter = isRtl ? inLeadingHalf : !inLeadingHalf;
    if (placeAfter != _placeAfter) setState(() => _placeAfter = placeAfter);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<ToolCatalogEntry>(
      onWillAcceptWithDetails: (details) =>
          widget.canDrag && canReorderBetween(details.data, widget.entry),
      onMove: (details) {
        _updateSide(details.data, details.offset);
        widget.onDragOver(details.offset);
      },
      onLeave: (_) => widget.onDragEnded(),
      onAcceptWithDetails: (details) =>
          widget.onAcceptSource(details.data, placeAfter: _placeAfter),
      builder: (context, candidates, _) {
        final tile = _DropInsertionIndicator(
          placeAfter: widget.showEndIndicator
              ? true
              : (candidates.isEmpty ? null : _placeAfter),
          child: widget.tile,
        );
        if (!widget.canDrag) return tile;

        final feedback = _ToolDragFeedback(entry: widget.entry);
        final placeholder = Opacity(opacity: 0.35, child: widget.tile);
        return _isTouch
            ? LongPressDraggable<ToolCatalogEntry>(
                data: widget.entry,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: feedback,
                childWhenDragging: placeholder,
                onDragEnd: (_) => widget.onDragEnded(),
                child: tile,
              )
            : _SlopDraggable<ToolCatalogEntry>(
                data: widget.entry,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: feedback,
                childWhenDragging: placeholder,
                onDragEnd: (_) => widget.onDragEnded(),
                child: tile,
              );
      },
    );
  }
}

/// מרחק התזוזה שממנו לחיצה נחשבת גרירה.
///
/// ה-`Draggable` הרגיל תופס את המחווה כבר בפיקסל אחד בעכבר, ואז לחיצה שבה
/// היד רעדה קלות אינה מגיעה ללחצן שבקובייה — הכלי לא נפתח והתפריט לא נפתח.
const double _kToolDragSlop = 12;

/// עומק אזור הקצה שגרירה בתוכו גוללת את הרשת, כמו ברצועת הכרטיסיות.
const double _kGridAutoScrollEdge = 40;

/// קצב גלילת הקצה — פיקסלים לכל פעימה (פעימה לכל פריים בקירוב).
const double _kGridAutoScrollStep = 8;

const Duration _kGridAutoScrollTick = Duration(milliseconds: 16);

/// מזהה גרירה מיידי עם סף תזוזה גדול מברירת המחדל. תומך במצביע מדויק בלבד:
/// במגע הגרירה מתחילה בלחיצה ארוכה, כדי לא לחטוף את הגלילה.
class _SlopMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  _SlopMultiDragGestureRecognizer({super.debugOwner})
    : super(
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      );

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _SlopPointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'tool tile drag';
}

class _SlopPointerState extends MultiDragPointerState {
  _SlopPointerState(super.initialPosition, super.kind, super.gestureSettings);

  @override
  void checkForResolutionAfterMove() {
    if ((pendingDelta?.distance ?? 0) > _kToolDragSlop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}

class _SlopDraggable<T extends Object> extends Draggable<T> {
  const _SlopDraggable({
    required super.child,
    required super.feedback,
    super.data,
    super.dragAnchorStrategy,
    super.childWhenDragging,
    super.onDragEnd,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _SlopMultiDragGestureRecognizer(debugOwner: this)..onStart = onStart;
}

/// מפתח קו ההוספה שמוצג בגרירה, בצד שאליו הקובייה תיפול.
@visibleForTesting
const Key kToolDropIndicatorKey = Key('tool-drop-indicator');

/// קו ההוספה בקצה הקובייה. [placeAfter] ריק = הגרירה אינה מעל הקובייה הזאת.
class _DropInsertionIndicator extends StatelessWidget {
  static const double lineWidth = 3;

  final bool? placeAfter;
  final Widget child;

  const _DropInsertionIndicator({
    required this.placeAfter,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final side = placeAfter;
    if (side == null) return child;
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          top: 2,
          bottom: 2,
          start: side ? null : 0,
          end: side ? 0 : null,
          child: Container(
            key: kToolDropIndicatorKey,
            width: lineWidth,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(lineWidth),
            ),
          ),
        ),
      ],
    );
  }
}

/// מה שצף מתחת לסמן בזמן גרירת קובייה.
class _ToolDragFeedback extends StatelessWidget {
  final ToolCatalogEntry entry;

  const _ToolDragFeedback({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: AppTokens.borderRadiusAll,
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            entry.imageIcon != null
                ? ImageIcon(AssetImage(entry.imageIcon!), size: 18)
                : Icon(entry.icon, size: 18),
            const SizedBox(width: 8),
            Text(
              entry.label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// קובייה בודדת ברשת הכלים.
class ToolTile extends StatelessWidget {
  static const double maxIconSize = 36;
  static const double minIconSize = 20;
  static const double menuButtonSize = 24;
  static const double menuIconSize = 13;

  /// התווית קטנה ובשתי שורות, כדי שרוב הקובייה תישאר לאייקון.
  static const double labelFontSize = 11;
  static const double labelLineHeight = 1.2;
  static const double labelBlockHeight = labelFontSize * labelLineHeight * 2;

  /// גודל האייקון לגובה הפנוי בקובייה: כל מה שנשאר אחרי שתי שורות התווית.
  /// כך פאנל מצומצם מקטין את האייקון במקום לחתוך את הכתב.
  static double iconSizeFor(double availableHeight) {
    if (!availableHeight.isFinite) return maxIconSize;
    return (availableHeight - AppTokens.spaceXS - labelBlockHeight).clamp(
      minIconSize,
      maxIconSize,
    );
  }

  final ToolCatalogEntry entry;
  final bool isOpen;
  final bool isHighlighted;
  final VoidCallback onTap;

  /// פעולות תפריט ⋯. ריק = הקובייה מוצגת בלי כפתור פעולות.
  final List<ToolTileAction> actions;

  /// מזהה פעימת ההזזה: כל שינוי מריץ אנימציית הדגשה קצרה. 0 = ללא פעימה.
  final int movePulse;

  /// נקרא כשתפריט הפעולות נסגר — הפאנל מחזיר לעצמו את הפוקוס למקלדת.
  final VoidCallback? onMenuClosed;

  const ToolTile({
    super.key,
    required this.entry,
    required this.isOpen,
    required this.isHighlighted,
    required this.onTap,
    this.actions = const [],
    this.movePulse = 0,
    this.onMenuClosed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _MovePulse(
      nonce: movePulse,
      child: AppCard(
        onTap: onTap,
        selected: isHighlighted,
        child: Stack(
          children: [
            // האייקון והכותרת ממורכזים כגוש אחד.
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceXS),
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildIcon(cs, iconSizeFor(constraints.maxHeight)),
                      const SizedBox(height: AppTokens.spaceXS),
                      Flexible(
                        child: Text(
                          entry.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: labelFontSize,
                            height: labelLineHeight,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (actions.isNotEmpty)
              PositionedDirectional(
                top: 0,
                end: 0,
                child: _buildMenuButton(cs),
              ),
            if (entry.isDevelopment)
              PositionedDirectional(
                bottom: 2,
                start: 4,
                child: _Badge(label: 'DEV', color: cs.tertiary),
              ),
            if (isOpen)
              PositionedDirectional(
                top: 4,
                start: 4,
                child: Icon(
                  FluentIcons.checkmark_circle_16_filled,
                  size: 12,
                  color: cs.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(ColorScheme cs) {
    return SizedBox(
      width: menuButtonSize,
      height: menuButtonSize,
      child: AppPopupMenuButton<VoidCallback>(
        tooltip: 'אפשרויות נוספות',
        icon: Icon(
          FluentIcons.more_vertical_24_regular,
          size: menuIconSize,
          color: cs.secondary,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: menuButtonSize,
          minHeight: menuButtonSize,
        ),
        onSelected: (action) => action(),
        onMenuClosed: onMenuClosed,
        itemBuilder: (context) {
          final metrics =
              Theme.of(context).extension<AppMenuMetrics>() ??
              AppMenuMetrics.create(compactMenus: false);
          return [
            for (final action in actions) ...[
              if (action.dividerBefore) const PopupMenuDivider(),
              _menuItem(context, metrics, action),
            ],
          ];
        },
      ),
    );
  }

  PopupMenuEntry<VoidCallback> _menuItem(
    BuildContext context,
    AppMenuMetrics metrics,
    ToolTileAction action,
  ) {
    final children = action.children;
    // תת-תפריט שכל פעולותיו מושבתות מרונדר כשורה מעומעמת רגילה: שורת תת-תפריט
    // נפתחת בלחיצה על ה-InkWell הפנימי שלה גם כשהפריט מושבת.
    if (children != null && children.any((child) => child.onTap != null)) {
      return buildAppSubmenuPopupMenuItem<VoidCallback>(
        context: context,
        metrics: metrics,
        label: action.label,
        icon: action.icon,
        menuChildren: [
          for (final child in children) _menuItem(context, metrics, child),
        ],
        onSelected: (selected) => selected(),
      );
    }
    return buildAppPopupMenuItem<VoidCallback>(
      context,
      AppMenuEntry<VoidCallback>(
        value: action.onTap ?? () {},
        label: action.label,
        icon: action.icon,
        enabled: action.onTap != null,
        isDestructive: action.isDestructive,
      ),
      metrics,
      null,
    );
  }

  Widget _buildIcon(ColorScheme cs, double iconSize) {
    if (entry.imageIcon != null) {
      return ImageIcon(
        AssetImage(entry.imageIcon!),
        size: iconSize,
        color: cs.primary,
      );
    }
    return Icon(entry.icon, size: iconSize, color: cs.primary);
  }
}

/// פעימת הדגשה קצרה על קובייה שזזה — מראה למשתמש לאן היא נחתה.
class _MovePulse extends StatefulWidget {
  final int nonce;
  final Widget child;

  const _MovePulse({required this.nonce, required this.child});

  @override
  State<_MovePulse> createState() => _MovePulseState();
}

class _MovePulseState extends State<_MovePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 320),
    vsync: this,
    value: 1.0,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void didUpdateWidget(covariant _MovePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nonce != oldWidget.nonce && widget.nonce != 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _progress,
      // מבנה העץ קבוע גם במנוחה: החלפת מבנה בתחילת הפעימה ובסופה הייתה בונה
      // את הקובייה מחדש ומאפסת את מצב הריחוף שלה.
      builder: (context, child) {
        final remaining = 1.0 - _progress.value;
        return Transform.scale(
          scale: 1.0 - 0.06 * remaining,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppTokens.borderRadiusAll,
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.35 * remaining),
                  blurRadius: 12 * remaining,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onTertiary,
        ),
      ),
    );
  }
}
