import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

const String _networkAccessPermission = 'network.access';

/// פאנל ניהול כלים (מובנים + תוספים) במסך "הגדרות › כלים".
///
/// מבנה:
/// - שני אזורים מתקפלים (סגורים כברירת מחדל, נפתחים בלחיצה על חץ): "כלים
///   מובנים" ו"תוספים מותקנים".
/// - **כלים מובנים** — לכל שורה שני לחצני פעולה ישירים: הסתרה/הצגה מהממשק
///   והצמדה/הסרה מסרגל הניווט הראשי. אין בחירה מרובה.
/// - **תוספים** — בחירה מרובה עם סרגל פעולות. כאשר נבחר תוסף, סרגל הפעולות
///   מוצמד לראש המסך בגלילה כל עוד אזור התוספים גלוי (PinnedHeaderSliver בתוך
///   SliverMainAxisGroup), ונעלם רק כשגוללים מעבר לכל אזור התוספים.
///
/// הפאנל מחזיר **sliver** ולכן חייב להיות מוצב בתוך CustomScrollView.
class ToolsManagementPanel extends StatefulWidget {
  const ToolsManagementPanel({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'tools.management.hide',
      title: 'הסתרת כלים',
      subtitle: 'הסתר כלים מובנים או תוספים מהממשק',
      tab: SettingsTab.tools,
      cardId: 'tools.management',
      keywords: ['הסתר', 'הסתרה', 'הסתרת', 'הצג', 'מוסתר', 'כלים', 'תוספים'],
    ),
    SettingsSearchEntry(
      id: 'tools.management.pin_nav_rail',
      title: 'הצמדה לסרגל הניווט',
      subtitle: 'הצמד כלים או תוספים לסרגל הניווט הראשי',
      tab: SettingsTab.tools,
      cardId: 'tools.management',
      keywords: ['הצמד', 'הצמדה', 'ניווט', 'סרגל', 'nav rail'],
    ),
    SettingsSearchEntry(
      id: 'tools.management.plugins',
      title: 'ניהול תוספים',
      subtitle: 'השבתה, הפעלה, מחיקה והרשאות לתוספים',
      tab: SettingsTab.tools,
      cardId: 'tools.plugins',
      keywords: [
        'תוסף',
        'תוספים',
        'מחק',
        'מחיקה',
        'השבת',
        'השבתה',
        'הפעל',
        'הרשאות',
        'רשת',
        'אינטרנט',
        'טעינה אוטומטית',
        'בעלייה'
      ],
    ),
  ];

  @override
  State<ToolsManagementPanel> createState() => _ToolsManagementPanelState();
}

/// מזהי העוגנים של שני האזורים — משמשים גם לחיפוש (SettingsAnchor + searchEntries)
/// וגם להרחבה אוטומטית בניווט מחיפוש.
const String _builtInCardId = 'tools.management';
const String _pluginsCardId = 'tools.plugins';

class _ToolsManagementPanelState extends State<ToolsManagementPanel> {
  /// מזהי התוספים שנבחרו כרגע (בחירה מרובה — תוספים בלבד).
  final Set<String> _selectedIds = <String>{};

  /// מצב פתיחה/סגירה של האזורים המתקפלים — סגורים כברירת מחדל.
  bool _builtInExpanded = false;
  bool _pluginsExpanded = false;

  // הרחבה אוטומטית בניווט מחיפוש: כשמסך ההגדרות מבזיק על עוגן של אזור, נפתח
  // אותו כדי שהמשתמש יראה את הבקרה שחיפש (ולא כותרת של אזור סגור).
  late final ValueListenable<bool> _builtInFlash;
  late final ValueListenable<bool> _pluginsFlash;

  bool get _anySelected => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final registry = SettingsSearchRegistry.instance;
    _builtInFlash = registry.flashNotifierFor(_builtInCardId);
    _pluginsFlash = registry.flashNotifierFor(_pluginsCardId);
    _builtInFlash.addListener(_onBuiltInFlash);
    _pluginsFlash.addListener(_onPluginsFlash);
  }

  @override
  void dispose() {
    _builtInFlash.removeListener(_onBuiltInFlash);
    _pluginsFlash.removeListener(_onPluginsFlash);
    super.dispose();
  }

  void _onBuiltInFlash() {
    if (_builtInFlash.value && !_builtInExpanded && mounted) {
      setState(() => _builtInExpanded = true);
    }
  }

  void _onPluginsFlash() {
    if (_pluginsFlash.value && !_pluginsExpanded && mounted) {
      setState(() => _pluginsExpanded = true);
    }
  }

  void _toggleSelection(String id, bool? value) {
    setState(() {
      if (value == true) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  void _selectAllPlugins(List<InstalledPlugin> plugins) {
    setState(() => _selectedIds.addAll(plugins.map((p) => p.pluginId)));
  }

  // ── פעולות כלי מובנה (לחצן בשורה) ───────────────────────────────────────────

  void _toggleBuiltInHide(String toolId, SettingsState state) {
    final next = Set<String>.from(state.hiddenBuiltInToolIds);
    if (!next.add(toolId)) next.remove(toolId);
    context.read<SettingsBloc>().add(UpdateHiddenBuiltInToolIds(next));
  }

  void _toggleBuiltInPin(String toolId, SettingsState state) {
    final next = Set<String>.from(state.builtInToolsPinnedToNavRail);
    if (!next.add(toolId)) next.remove(toolId);
    context.read<SettingsBloc>().add(UpdateBuiltInToolsPinnedToNavRail(next));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PluginSystemBloc, PluginSystemState>(
      builder: (context, pluginState) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final plugins = pluginState is PluginSystemLoaded
                ? pluginState.plugins
                : const <InstalledPlugin>[];
            // ניקוי מזהי תוספים נבחרים שהוסרו:
            _pruneStaleSelection(plugins);
            return SliverMainAxisGroup(
              slivers: [
                // אזור הכלים המובנים — ללא סרגל פעולות מוצמד.
                ..._collapsibleSectionSlivers(
                  cardId: _builtInCardId,
                  title: 'כלים מובנים',
                  subtitle: 'הסתר כלים מהממשק או הצמד אותם לסרגל הניווט הראשי.',
                  summaryLabel: 'רשימת הכלים',
                  summaryIcon: FluentIcons.apps_24_regular,
                  expanded: _builtInExpanded,
                  onToggle: () =>
                      setState(() => _builtInExpanded = !_builtInExpanded),
                  children: _builtInToolRows(settingsState),
                ),
                if (plugins.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  // קבוצת סליברים נפרדת לאזור התוספים — מאפשרת לסרגל הפעולות
                  // (PinnedHeaderSliver) להיות מוצמד לראש המסך *אחרי* הכותרת,
                  // כל עוד אזור התוספים גלוי, ולהיעלם כשגוללים מעבר אליו.
                  SliverMainAxisGroup(
                    slivers: _collapsibleSectionSlivers(
                      cardId: _pluginsCardId,
                      title: 'תוספים מותקנים',
                      subtitle:
                          'נהל את התוספים שלך: השבתה, הסתרה, הצמדה, הרשאות ומחיקה. גרור לשינוי סדר.',
                      summaryLabel: 'רשימת התוספים',
                      summaryIcon: FluentIcons.puzzle_piece_24_regular,
                      expanded: _pluginsExpanded,
                      onToggle: () => setState(() {
                        _pluginsExpanded = !_pluginsExpanded;
                        // בסגירה — נקה בחירה כדי שלא יישאר סרגל פעולות תלוי באוויר.
                        if (!_pluginsExpanded) _selectedIds.clear();
                      }),
                      pinnedBar: (_pluginsExpanded && _anySelected)
                          ? _ActionBar(
                              selectedIds: _selectedIds.toSet(),
                              plugins: plugins,
                              onClear: _clearSelection,
                            )
                          : null,
                      children: _pluginRows(plugins),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// בונה את הסליברים של אזור מתקפל, בסדר: כותרת → (סרגל מוצמד אופציונלי) → גוף.
  ///
  /// [pinnedBar] — אם ניתן, מוצמד לראש המסך *אחרי הכותרת* (PinnedHeaderSliver).
  /// כדי שההצמדה תהיה מוגבלת לאזור זה בלבד, יש למקם את הסליברים בתוך
  /// SliverMainAxisGroup ייעודי.
  List<Widget> _collapsibleSectionSlivers({
    required String cardId,
    required String title,
    String? subtitle,
    required String summaryLabel,
    required IconData summaryIcon,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
    Widget? pinnedBar,
  }) {
    return [
      // כותרת-קטגוריה (גוללת רגיל, מעל הסרגל המוצמד).
      SliverToBoxAdapter(
        child: ToolPanelWrapper(
          child: SettingsAnchor(
            cardId: cardId,
            child: SettingsCardHeader(title: title, subtitle: subtitle),
          ),
        ),
      ),
      if (pinnedBar != null)
        PinnedHeaderSliver(
          child: ColoredBox(
            color: AppSurfaces.panelBackground(context),
            child: ToolPanelWrapper(child: pinnedBar),
          ),
        ),
      // גוף הכרטיס — שורת פתיחה/סגירה ומתחתיה הפריטים כשפתוח.
      SliverToBoxAdapter(
        child: ToolPanelWrapper(
          child: SettingsCardBody(
            children: [
              _sectionToggleRow(
                label: summaryLabel,
                icon: summaryIcon,
                expanded: expanded,
                onToggle: onToggle,
              ),
              if (expanded) ...children,
            ],
          ),
        ),
      ),
    ];
  }

  /// שורת פתיחה/סגירה (תווית + חץ) בראש גוף הכרטיס.
  Widget _sectionToggleRow({
    required String label,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Icon(
        expanded
            ? FluentIcons.chevron_up_24_regular
            : FluentIcons.chevron_down_24_regular,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onToggle,
    );
  }

  List<Widget> _builtInToolRows(SettingsState state) {
    return [
      for (final meta in kBuiltInToolsCatalog)
        _BuiltInToolRow(
          meta: meta,
          hidden: state.hiddenBuiltInToolIds.contains(meta.toolId),
          pinnedToNavRail:
              state.builtInToolsPinnedToNavRail.contains(meta.toolId),
          onToggleHide: () => _toggleBuiltInHide(meta.toolId, state),
          onTogglePin: () => _toggleBuiltInPin(meta.toolId, state),
        ),
    ];
  }

  List<Widget> _pluginRows(List<InstalledPlugin> plugins) {
    return [
      _SelectAllRow(
        allSelected: plugins.every((p) => _selectedIds.contains(p.pluginId)),
        anySelected: plugins.any((p) => _selectedIds.contains(p.pluginId)),
        onChanged: (selectAll) =>
            selectAll ? _selectAllPlugins(plugins) : _clearSelection(),
      ),
      for (final plugin in plugins)
        _DraggableSettingsPluginRow(
          key: ValueKey(plugin.pluginId),
          plugin: plugin,
          selected: _selectedIds.contains(plugin.pluginId),
          onSelectChanged: (v) => _toggleSelection(plugin.pluginId, v),
          onAcceptSource: (sourceId) => _handleReorder(
            context: context,
            allPlugins: plugins,
            sourcePluginId: sourceId,
            targetPluginId: plugin.pluginId,
          ),
        ),
    ];
  }

  void _handleReorder({
    required BuildContext context,
    required List<InstalledPlugin> allPlugins,
    required String sourcePluginId,
    required String targetPluginId,
  }) {
    final sourceIdx =
        allPlugins.indexWhere((p) => p.pluginId == sourcePluginId);
    final targetIdx =
        allPlugins.indexWhere((p) => p.pluginId == targetPluginId);
    if (sourceIdx < 0 || targetIdx < 0) return;
    final reordered = List.of(allPlugins);
    final src = reordered.removeAt(sourceIdx);
    reordered.insert(targetIdx, src);
    context.read<PluginSystemBloc>().add(
          ReorderPluginsRequested(reordered.map((p) => p.pluginId).toList()),
        );
  }

  /// מנקה מזהי תוספים נבחרים שאינם רלוונטיים עוד (תוסף שהוסר). חייב לקרות
  /// בתוך build כי הנתונים מגיעים מ-BlocBuilder.
  void _pruneStaleSelection(List<InstalledPlugin> plugins) {
    if (_selectedIds.isEmpty) return;
    final validIds = <String>{for (final p in plugins) p.pluginId};
    final stale = _selectedIds.difference(validIds);
    if (stale.isNotEmpty) {
      // setState אסורה ב-build; מזיזים את ההסרה לאחר ה-frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedIds.removeAll(stale));
      });
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// סרגל הפעולות (תוספים בלבד)
// ──────────────────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final Set<String> selectedIds;
  final List<InstalledPlugin> plugins;
  final VoidCallback onClear;

  const _ActionBar({
    required this.selectedIds,
    required this.plugins,
    required this.onClear,
  });

  Iterable<InstalledPlugin> get _selectedPlugins =>
      plugins.where((p) => selectedIds.contains(p.pluginId));

  /// האם כל התוספים שנבחרו כבר מוסתרים?
  bool get _allSelectedAreHidden {
    final selected = _selectedPlugins;
    return selected.isNotEmpty && selected.every((p) => p.hiddenFromTools);
  }

  /// האם כל התוספים שנבחרו כבר מוצמדים ל-nav rail?
  bool get _allSelectedArePinnedToNav {
    final selected = _selectedPlugins;
    return selected.isNotEmpty && selected.every((p) => p.pinnedToNavRail);
  }

  bool get _allSelectedPluginsEnabled =>
      _selectedPlugins.every((p) => p.enabled);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = selectedIds.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cs.surfaceContainerHigh,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '$count נבחרו',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(FluentIcons.dismiss_circle_24_regular),
                label: const Text('נקה בחירה'),
              ),
              _ActionChip(
                icon: _allSelectedAreHidden
                    ? FluentIcons.eye_24_regular
                    : FluentIcons.eye_off_24_regular,
                label: _allSelectedAreHidden ? 'הצג' : 'הסתר',
                onPressed: () => _onToggleHide(context),
              ),
              _ActionChip(
                icon: _allSelectedArePinnedToNav
                    ? FluentIcons.pin_off_24_regular
                    : FluentIcons.pin_24_regular,
                label: _allSelectedArePinnedToNav
                    ? 'הסר מסרגל הניווט'
                    : 'הצמד לסרגל הניווט',
                onPressed: () => _onTogglePinNavRail(context),
              ),
              _ActionChip(
                icon: _allSelectedPluginsEnabled
                    ? FluentIcons.pause_circle_24_regular
                    : FluentIcons.play_circle_24_regular,
                label: _allSelectedPluginsEnabled ? 'השבת' : 'הפעל',
                onPressed: () => _onToggleEnabled(context),
              ),
              _PermissionMenu(
                icon: FluentIcons.globe_24_regular,
                label: 'גישה לרשת',
                onGrant: () => _setNetworkAccess(context, granted: true),
                onRevoke: () => _setNetworkAccess(context, granted: false),
              ),
              _PermissionMenu(
                icon: FluentIcons.power_24_regular,
                label: 'טעינה אוטומטית בעלייה',
                onGrant: () => _setRunOnStartup(context, granted: true),
                onRevoke: () => _setRunOnStartup(context, granted: false),
              ),
              _ActionChip(
                icon: FluentIcons.delete_24_regular,
                label: 'מחק',
                danger: true,
                onPressed: () => _onDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _onToggleHide(BuildContext context) {
    final shouldHide = !_allSelectedAreHidden;
    final bloc = context.read<PluginSystemBloc>();
    for (final p in _selectedPlugins) {
      bloc.add(SetPluginHiddenRequested(
        pluginId: p.pluginId,
        hidden: shouldHide,
      ));
    }
    UiSnack.show(shouldHide ? 'התוספים הוסתרו' : 'התוספים יוצגו');
  }

  void _onTogglePinNavRail(BuildContext context) {
    final shouldPin = !_allSelectedArePinnedToNav;
    final bloc = context.read<PluginSystemBloc>();
    for (final p in _selectedPlugins) {
      if (shouldPin) {
        bloc.add(PinPluginToNavRailRequested(p.pluginId));
      } else {
        bloc.add(UnpinPluginFromNavRailRequested(p.pluginId));
      }
    }
  }

  void _onToggleEnabled(BuildContext context) {
    final shouldEnable = !_allSelectedPluginsEnabled;
    final bloc = context.read<PluginSystemBloc>();
    for (final p in _selectedPlugins) {
      if (shouldEnable) {
        bloc.add(EnablePluginRequested(p.pluginId));
      } else {
        bloc.add(DisablePluginRequested(p.pluginId));
      }
    }
  }

  void _setNetworkAccess(BuildContext context, {required bool granted}) {
    final eligible = _selectedPlugins
        .where((p) => p.manifest.permissions.contains(_networkAccessPermission))
        .toList();
    if (eligible.isEmpty) {
      UiSnack.showError('אף תוסף נבחר לא מצהיר על שימוש ברשת — אין מה לעדכן');
      return;
    }
    final bloc = context.read<PluginSystemBloc>();
    for (final p in eligible) {
      bloc.add(SetPluginPermissionRequested(
        pluginId: p.pluginId,
        permission: _networkAccessPermission,
        granted: granted,
      ));
    }
    UiSnack.show(granted
        ? 'גישה לרשת הוענקה לתוספים הנבחרים'
        : 'גישה לרשת בוטלה לתוספים הנבחרים');
  }

  void _setRunOnStartup(BuildContext context, {required bool granted}) {
    final eligible = _selectedPlugins
        .where((p) =>
            p.manifest.permissions.contains(pluginRunOnStartupPermission))
        .toList();
    if (eligible.isEmpty) {
      UiSnack.showError('אף תוסף נבחר לא תומך בטעינה אוטומטית בעלייה');
      return;
    }
    final bloc = context.read<PluginSystemBloc>();
    for (final p in eligible) {
      bloc.add(SetPluginPermissionRequested(
        pluginId: p.pluginId,
        permission: pluginRunOnStartupPermission,
        granted: granted,
      ));
    }
    UiSnack.show(granted
        ? 'טעינה אוטומטית בעלייה הופעלה לתוספים הנבחרים'
        : 'טעינה אוטומטית בעלייה בוטלה לתוספים הנבחרים');
  }

  Future<void> _onDelete(BuildContext context) async {
    final plugins = _selectedPlugins.toList();
    if (plugins.isEmpty) return;
    final names = plugins.map((p) => p.name).join('\n• ');
    // קוראים ל-bloc *לפני* ה-await כדי לא להחזיק BuildContext חוצה גבולות async
    final bloc = context.read<PluginSystemBloc>();
    final confirmed = await showWarningDialog(
      context: context,
      title: 'מחיקת תוספים',
      content: 'האם למחוק ${plugins.length} תוסף(ים)?\n\n• $names',
      subtitle: 'פעולה זו אינה הפיכה. נתוני התוסף יימחקו.',
      confirmText: 'מחק',
    );
    if (confirmed != true) return;
    for (final p in plugins) {
      if (p.isDevelopment) {
        bloc.add(DetachDevelopmentPluginRequested(p.pluginId));
      } else {
        bloc.add(UninstallPluginRequested(p.pluginId));
      }
    }
    UiSnack.show('התוספים סומנו למחיקה');
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = danger ? cs.error : null;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: fg),
      label: Text(
        label,
        style: fg != null ? TextStyle(color: fg) : null,
      ),
    );
  }
}

/// פעולה דו-כיוונית מפורשת — תפריט נפתח עם "הענק" ו"בטל".
///
/// משמשת לפעולות שאי אפשר לקבוע "מצב נוכחי" ממידע ה-state (כי ההרשאה
/// נשמרת ב-permission grant table הנפרד, לא ב-`InstalledPlugin`).
/// במקום לנחש כיוון או להחזיק מצב a-synchronous, נציע למשתמש שתי
/// בחירות מפורשות.
class _PermissionMenu extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;

  const _PermissionMenu({
    required this.icon,
    required this.label,
    required this.onGrant,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: label,
      onSelected: (grant) => grant ? onGrant() : onRevoke(),
      itemBuilder: (_) => const [
        PopupMenuItem<bool>(
          value: true,
          child: ListTile(
            leading: Icon(FluentIcons.checkmark_24_regular),
            title: Text('הענק'),
            dense: true,
          ),
        ),
        PopupMenuItem<bool>(
          value: false,
          child: ListTile(
            leading: Icon(FluentIcons.dismiss_24_regular),
            title: Text('בטל'),
            dense: true,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 4),
            Text(label),
            const SizedBox(width: 2),
            const Icon(FluentIcons.chevron_down_24_regular, size: 16),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// שורות הטבלה
// ──────────────────────────────────────────────────────────────────────────────

/// שורת "בחר הכל" בראש רשימת התוספים — תיבת בחירה (tristate) שמסמנת/מנקה את כל
/// התוספים. גלויה תמיד כשהאזור פתוח, גם כשאין בחירה.
class _SelectAllRow extends StatelessWidget {
  final bool allSelected;
  final bool anySelected;
  final ValueChanged<bool> onChanged;

  const _SelectAllRow({
    required this.allSelected,
    required this.anySelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // tristate: הכל מסומן → true, חלק → null, ללא → false.
    final bool? value = allSelected ? true : (anySelected ? null : false);
    void toggle() => onChanged(!allSelected);
    return ListTile(
      hoverColor: Colors.transparent,
      leading: Checkbox(
        tristate: true,
        value: value,
        onChanged: (_) => toggle(),
      ),
      title: const Text('בחר הכל'),
      onTap: toggle,
    );
  }
}

/// שורת כלי מובנה — ללא תיבת סימון; שני לחצני פעולה ישירים בצד.
class _BuiltInToolRow extends StatelessWidget {
  final BuiltInToolMeta meta;
  final bool hidden;
  final bool pinnedToNavRail;
  final VoidCallback onToggleHide;
  final VoidCallback onTogglePin;

  const _BuiltInToolRow({
    required this.meta,
    required this.hidden,
    required this.pinnedToNavRail,
    required this.onToggleHide,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final Widget? toolIcon = meta.icon != null
        ? Icon(meta.icon)
        : (meta.imageIcon != null
            ? ImageIcon(AssetImage(meta.imageIcon!), size: 24)
            : null);
    return ListTile(
      hoverColor: Colors.transparent,
      leading: toolIcon,
      title: _RowTitle(
        label: meta.label,
        badges: _StatusBadges(
          hidden: hidden,
          pinnedToNavRail: pinnedToNavRail,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: hidden ? 'הצג בממשק' : 'הסתר מהממשק',
            isSelected: hidden,
            icon: const Icon(FluentIcons.eye_off_24_regular),
            selectedIcon: const Icon(FluentIcons.eye_24_regular),
            onPressed: onToggleHide,
          ),
          IconButton(
            tooltip: pinnedToNavRail ? 'הסר מסרגל הניווט' : 'הצמד לסרגל הניווט',
            isSelected: pinnedToNavRail,
            icon: const Icon(FluentIcons.pin_24_regular),
            selectedIcon: const Icon(FluentIcons.pin_off_24_regular),
            onPressed: onTogglePin,
          ),
        ],
      ),
    );
  }
}

class _DraggableSettingsPluginRow extends StatelessWidget {
  final InstalledPlugin plugin;
  final bool selected;
  final ValueChanged<bool?> onSelectChanged;
  final ValueChanged<String> onAcceptSource;

  const _DraggableSettingsPluginRow({
    super.key,
    required this.plugin,
    required this.selected,
    required this.onSelectChanged,
    required this.onAcceptSource,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != plugin.pluginId,
      onAcceptWithDetails: (details) => onAcceptSource(details.data),
      builder: (context, candidateData, _) {
        final isHovering = candidateData.isNotEmpty;
        final cs = Theme.of(context).colorScheme;
        return Container(
          decoration: isHovering
              ? BoxDecoration(
                  color: AppSurfaces.dragTargetHighlight(cs),
                  border: Border(
                    top: BorderSide(color: cs.primary, width: 2),
                  ),
                )
              : null,
          child: Material(
            color: Colors.transparent,
            child: _PluginRow(
              plugin: plugin,
              selected: selected,
              onSelectChanged: onSelectChanged,
              dragHandle: Draggable<String>(
                data: plugin.pluginId,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: _SettingsDragFeedback(plugin: plugin),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Tooltip(
                    message: 'גרור ושחרר לשינוי סדר',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Icon(
                        FluentIcons.re_order_dots_vertical_24_regular,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PluginRow extends StatelessWidget {
  final InstalledPlugin plugin;
  final bool selected;
  final ValueChanged<bool?> onSelectChanged;
  final Widget? dragHandle;

  const _PluginRow({
    required this.plugin,
    required this.selected,
    required this.onSelectChanged,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final icon = fluentIconFromName(plugin.manifest.toolTabIconName) ??
        FluentIcons.puzzle_piece_24_regular;
    return ListTile(
      hoverColor: Colors.transparent,
      leading: Checkbox(value: selected, onChanged: onSelectChanged),
      title: _RowTitle(
        label: '${plugin.name}  •  v${plugin.version}',
        badges: _StatusBadges(
          hidden: plugin.hiddenFromTools,
          pinnedToNavRail: plugin.pinnedToNavRail,
          disabled: !plugin.enabled,
          networkDeclared: plugin.manifest.networkEnabled,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          if (dragHandle != null) dragHandle!,
        ],
      ),
      onTap: () => onSelectChanged(!selected),
    );
  }
}

class _SettingsDragFeedback extends StatelessWidget {
  final InstalledPlugin plugin;

  const _SettingsDragFeedback({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
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
            Icon(fluentIconFromName(plugin.manifest.toolTabIconName) ??
                FluentIcons.puzzle_piece_24_regular),
            const SizedBox(width: 8),
            Text(
              plugin.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// כותרת שורה: שם הכלי/התוסף ולצדו תגיות הסטטוס (אייקונים בלבד). התגיות מוצגות
/// רק כשרוחב השורה מאפשר, אחרת השם מקבל את כל המקום.
class _RowTitle extends StatelessWidget {
  final String label;
  final _StatusBadges badges;

  const _RowTitle({required this.label, required this.badges});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showBadges = badges.hasAny && constraints.maxWidth > 220;
        return Row(
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            if (showBadges) ...[
              const SizedBox(width: 8),
              badges,
            ],
          ],
        );
      },
    );
  }
}

/// תגיות סטטוס לשורת כלי/תוסף — אייקונים בלבד; ההסבר מופיע ב-tooltip בריחוף.
class _StatusBadges extends StatelessWidget {
  final bool hidden;
  final bool pinnedToNavRail;
  final bool disabled;
  final bool networkDeclared;

  const _StatusBadges({
    this.hidden = false,
    this.pinnedToNavRail = false,
    this.disabled = false,
    this.networkDeclared = false,
  });

  bool get hasAny => hidden || pinnedToNavRail || disabled || networkDeclared;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badges = <Widget>[];
    if (disabled) {
      badges.add(_badge(context, 'מושבת', cs.errorContainer,
          cs.onErrorContainer, FluentIcons.pause_circle_24_regular));
    }
    if (hidden) {
      badges.add(_badge(context, 'מוסתר', cs.surfaceContainerHighest,
          cs.onSurfaceVariant, FluentIcons.eye_off_24_regular));
    }
    if (pinnedToNavRail) {
      badges.add(_badge(context, 'בסרגל ניווט', cs.primaryContainer,
          cs.onPrimaryContainer, FluentIcons.pin_24_regular));
    }
    if (networkDeclared) {
      badges.add(_badge(context, 'משתמש ברשת', cs.tertiaryContainer,
          cs.onTertiaryContainer, FluentIcons.globe_24_regular));
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < badges.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          badges[i],
        ],
      ],
    );
  }

  Widget _badge(
      BuildContext context, String tooltip, Color bg, Color fg, IconData icon) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: RtlIcon(icon, size: 14, color: fg),
      ),
    );
  }
}
