import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/plugins/view/plugin_actions.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';
import 'package:otzaria/widgets/misc/animated_pin_button.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

const String _networkAccessPermission = 'network.access';
const String _networkLocalhostPermission = 'network.localhost';

/// הרשאות הרשת שפעולת ה-bulk "גישה לרשת" מעניקה/מבטלת לפי הצהרת התוסף.
const List<String> _networkPermissions = [
  _networkAccessPermission,
  _networkLocalhostPermission,
];

/// פאנל ניהול כלים (מובנים + תוספים) במסך "הגדרות › כלים".
///
/// מבנה:
/// - כלים מובנים — שורה מתקפלת; לכל שורה הסתרה/הצגה והצמדה לסרגל הניווט.
/// - תוספים מותקנים — בחירה מרובה עם סרגל פעולות (הסתרה, הצמדה, השבתה, הרשאות, מחיקה).
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
        'בעלייה',
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

  /// האם מצב הבחירה הרב-שורתית פעיל.
  bool _isSelectionMode = false;

  /// מפתחות גלובליים לעטיפות האנימציה — מאפשרים לקרוא ל-playAnimation ישירות.
  final Map<String, GlobalKey<_AnimatedPluginMoveWrapperState>>
  _moveWrapperKeys = {};

  /// מצב פתיחה/סגירה של אזור הכלים המובנים — סגור כברירת מחדל.
  bool _builtInExpanded = false;

  // הרחבה אוטומטית בניווט מחיפוש לכלים המובנים.
  late final ValueListenable<bool> _builtInFlash;

  @override
  void initState() {
    super.initState();
    final registry = SettingsSearchRegistry.instance;
    _builtInFlash = registry.flashNotifierFor(_builtInCardId);
    _builtInFlash.addListener(_onBuiltInFlash);
  }

  @override
  void dispose() {
    _builtInFlash.removeListener(_onBuiltInFlash);
    super.dispose();
  }

  void _onBuiltInFlash() {
    if (_builtInFlash.value && !_builtInExpanded && mounted) {
      setState(() => _builtInExpanded = true);
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

  void _enterSelectionMode() {
    setState(() => _isSelectionMode = true);
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
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
            _pruneStaleSelection(plugins);
            return LayoutBuilder(
              builder: (context, constraints) {
                final rowMaxWidth = constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SettingsCard(
                      cardId: _builtInCardId,
                      title: 'כלים מובנים',
                      children: [
                        ExpandableSection(
                          icon: FluentIcons.apps_24_regular,
                          title: 'רשימת הכלים',
                          subtitle:
                              'הסתר כלים מהממשק או הצמד אותם לסרגל הניווט הראשי.',
                          isExpanded: _builtInExpanded,
                          onTap: () => setState(
                            () => _builtInExpanded = !_builtInExpanded,
                          ),
                          children: _builtInToolRows(settingsState),
                        ),
                      ],
                    ),
                    if (plugins.isNotEmpty) ...[
                      kSettingsCardSpacing,
                      SettingsCard(
                        cardId: _pluginsCardId,
                        title: 'תוספים מותקנים',
                        children: [
                          // כותרת + סרגל פעולות כילד אחד כדי ש-divider יופיע רק בין הכותרת לשורות.
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SettingsActionTile.text(
                                icon: FluentIcons.puzzle_piece_24_regular,
                                title: 'רשימת התוספים',
                                subtitle: _isSelectionMode
                                    ? '${_selectedIds.length} נבחרו'
                                    : 'נהל את התוספים שלך: השבתה, הסתרה, הצמדה, הרשאות ומחיקה. גרור לשינוי סדר.',
                                // LayoutBuilder + Tooltip(OverlayPortal) reactivation
                                // during drag reorder crashes here.
                                responsiveActions: false,
                                actions: _isSelectionMode
                                    ? [
                                        ActionButton.ghost(
                                          icon: FluentIcons
                                              .checkbox_checked_24_regular,
                                          text: 'בחר הכל',
                                          onPressed:
                                              _selectedIds.length ==
                                                  plugins.length
                                              ? null
                                              : () =>
                                                    _selectAllPlugins(plugins),
                                        ),
                                        ActionButton.neutral(
                                          icon: FluentIcons
                                              .dismiss_circle_24_regular,
                                          text: 'ביטול',
                                          onPressed: _exitSelectionMode,
                                        ),
                                      ]
                                    : [
                                        ActionButton.neutral(
                                          icon: FluentIcons
                                              .multiselect_rtl_24_regular,
                                          text: 'בחירה',
                                          onPressed: _enterSelectionMode,
                                        ),
                                      ],
                              ),
                              AnimatedSize(
                                duration: AppTokens.animNormal,
                                curve: Curves.easeInOut,
                                child: _isSelectionMode
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Builder(
                                            builder: (ctx) =>
                                                AppCard.sectionDivider(ctx),
                                          ),
                                          _ActionBar(
                                            selectedIds: _selectedIds.toSet(),
                                            plugins: plugins,
                                          ),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                          ..._pluginRows(plugins, rowMaxWidth),
                        ],
                      ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  List<Widget> _builtInToolRows(SettingsState state) {
    return [
      for (final meta in kBuiltInToolsCatalog)
        _BuiltInToolRow(
          meta: meta,
          hidden: state.hiddenBuiltInToolIds.contains(meta.toolId),
          pinnedToNavRail: state.builtInToolsPinnedToNavRail.contains(
            meta.toolId,
          ),
          onToggleHide: () => _toggleBuiltInHide(meta.toolId, state),
          onTogglePin: () => _toggleBuiltInPin(meta.toolId, state),
        ),
    ];
  }

  List<Widget> _pluginRows(List<InstalledPlugin> plugins, double rowMaxWidth) {
    return [
      for (int i = 0; i < plugins.length; i++)
        _AnimatedPluginMoveWrapper(
          key: _moveWrapperKeys.putIfAbsent(
            plugins[i].pluginId,
            () => GlobalKey(),
          ),
          child: _DraggableSettingsPluginRow(
            plugin: plugins[i],
            rowMaxWidth: rowMaxWidth,
            isSelectionMode: _isSelectionMode,
            selected: _selectedIds.contains(plugins[i].pluginId),
            onSelectChanged: (v) => _toggleSelection(plugins[i].pluginId, v),
            isFirst: i == 0,
            isLast: i == plugins.length - 1,
            onMoveUp: i == 0 ? null : () => _handleMove(plugins, i, i - 1),
            onMoveDown: i == plugins.length - 1
                ? null
                : () => _handleMove(plugins, i, i + 1),
            onAcceptSource: (sourceId) => _handleReorder(
              context: context,
              allPlugins: plugins,
              sourcePluginId: sourceId,
              targetPluginId: plugins[i].pluginId,
            ),
            onToggleHide: () => togglePluginShowInTools(context, plugins[i]),
            onTogglePinNavRail: () =>
                togglePluginPinnedToNavRail(context, plugins[i]),
            onToggleEnabled: () => togglePluginEnabled(context, plugins[i]),
            onToggleNetworkAccess: () =>
                togglePluginNetworkAccess(context, plugins[i]),
            onToggleRunOnStartup: () =>
                togglePluginRunOnStartup(context, plugins[i]),
            onDelete: () => showDeletePluginDialog(context, plugins[i]),
          ),
        ),
    ];
  }

  void _handleMove(List<InstalledPlugin> plugins, int from, int to) {
    final movedId = plugins[from].pluginId;
    final movedUp = to < from;
    final reordered = List.of(plugins);
    final item = reordered.removeAt(from);
    reordered.insert(to, item);
    final ids = reordered.map((p) => p.pluginId).toList();
    // Defer dispatch so the BlocBuilder rebuilds during the normal build phase
    // of the next frame, not inside a LayoutBuilder's _rebuildWithConstraints.
    // Without deferral, GlobalKey reactivation of rows with Tooltip/OverlayPortal
    // happens during the LayoutBuilder's buildScope → Flutter rendering crash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PluginSystemBloc>().add(ReorderPluginsRequested(ids));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _moveWrapperKeys[movedId]?.currentState?.playAnimation(
          movedUp: movedUp,
        );
      });
    });
  }

  void _handleReorder({
    required BuildContext context,
    required List<InstalledPlugin> allPlugins,
    required String sourcePluginId,
    required String targetPluginId,
  }) {
    final ids = reorderedPluginIds(allPlugins, sourcePluginId, targetPluginId);
    // Same deferral as _handleMove: prevents LayoutBuilder + BlocBuilder
    // dirty collision that causes OverlayPortal reactivation crash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      this.context.read<PluginSystemBloc>().add(ReorderPluginsRequested(ids));
    });
  }

  /// מנקה מזהי תוספים נבחרים שאינם רלוונטיים עוד (תוסף שהוסר). חייב לקרות
  /// בתוך build כי הנתונים מגיעים מ-BlocBuilder.
  void _pruneStaleSelection(List<InstalledPlugin> plugins) {
    if (_selectedIds.isEmpty) return;
    // plugins ריק = מצב טעינה; אל נקה את הבחירה בינתיים, כי ה-IDs עדיין תקינים.
    if (plugins.isEmpty) return;
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

  const _ActionBar({
    required this.selectedIds,
    required this.plugins,
  });

  Iterable<InstalledPlugin> get _selectedPlugins =>
      plugins.where((p) => selectedIds.contains(p.pluginId));

  /// האם כל התוספים שנבחרו כבר מוסתרים ממסך הכלים?
  bool get _allSelectedHiddenFromTools {
    final selected = _selectedPlugins;
    return selected.isNotEmpty && selected.every((p) => !p.showInTools);
  }

  /// האם כל התוספים שנבחרו כבר מוצמדים ל-nav rail?
  bool get _allSelectedArePinnedToNav {
    final selected = _selectedPlugins;
    return selected.isNotEmpty && selected.every((p) => p.pinnedToNavRail);
  }

  bool get _allSelectedPluginsEnabled =>
      _selectedPlugins.every((p) => p.enabled);

  bool get _allSelectedHaveNetworkAccess {
    final eligible = _selectedPlugins
        .where((p) => p.manifest.permissions.contains(_networkAccessPermission))
        .toList();
    return eligible.isNotEmpty && eligible.every((p) => p.networkAccessGranted);
  }

  bool get _anySelectedHasNetworkPermission => _selectedPlugins.any(
    (p) => p.manifest.permissions.contains(_networkAccessPermission),
  );

  bool get _allSelectedHaveStartupEnabled {
    final eligible = _selectedPlugins
        .where(
          (p) => p.manifest.permissions.contains(pluginRunOnStartupPermission),
        )
        .toList();
    return eligible.isNotEmpty && eligible.every((p) => p.runOnStartupGranted);
  }

  bool get _anySelectedHasStartupPermission => _selectedPlugins.any(
    (p) => p.manifest.permissions.contains(pluginRunOnStartupPermission),
  );

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedIds.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionButton.neutral(
              icon: _allSelectedHiddenFromTools
                  ? FluentIcons.eye_24_regular
                  : FluentIcons.eye_off_24_regular,
              text: _allSelectedHiddenFromTools ? 'הצג' : 'הסתר',
              onPressed: hasSelection
                  ? () => _onToggleShowInTools(context)
                  : null,
            ),
            ActionButton.neutral(
              icon: _allSelectedArePinnedToNav
                  ? FluentIcons.pin_24_filled
                  : FluentIcons.pin_24_regular,
              text: _allSelectedArePinnedToNav ? 'הסר מניווט' : 'הצמד לניווט',
              onPressed: hasSelection
                  ? () => _onTogglePinNavRail(context)
                  : null,
            ),
            ActionButton.neutral(
              icon: _allSelectedPluginsEnabled
                  ? FluentIcons.pause_circle_24_regular
                  : FluentIcons.play_circle_24_regular,
              text: _allSelectedPluginsEnabled ? 'השבת' : 'הפעל',
              onPressed: hasSelection ? () => _onToggleEnabled(context) : null,
            ),
            ActionButton.neutral(
              icon: _allSelectedHaveNetworkAccess
                  ? FluentIcons.globe_prohibited_24_regular
                  : FluentIcons.globe_24_regular,
              text: _allSelectedHaveNetworkAccess ? 'דחיה מהרשת' : 'גישה לרשת',
              onPressed: hasSelection && _anySelectedHasNetworkPermission
                  ? () => _setNetworkAccess(
                      context,
                      granted: !_allSelectedHaveNetworkAccess,
                    )
                  : null,
            ),
            ActionButton.neutral(
              icon: _allSelectedHaveStartupEnabled
                  ? FluentIcons.power_24_filled
                  : FluentIcons.power_24_regular,
              text: _allSelectedHaveStartupEnabled
                  ? 'טעינה רגילה'
                  : 'טעינה בעליה',
              onPressed: hasSelection && _anySelectedHasStartupPermission
                  ? () => _setRunOnStartup(
                      context,
                      granted: !_allSelectedHaveStartupEnabled,
                    )
                  : null,
            ),
            ActionButton.ghost(
              icon: FluentIcons.delete_24_regular,
              text: 'מחק',
              onPressed: hasSelection ? () => _onDelete(context) : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _onToggleShowInTools(BuildContext context) {
    final shouldShow = _allSelectedHiddenFromTools;
    final bloc = context.read<PluginSystemBloc>();
    for (final p in _selectedPlugins) {
      bloc.add(
        SetPluginShowInToolsRequested(
          pluginId: p.pluginId,
          showInTools: shouldShow,
        ),
      );
    }
    UiSnack.show(
      shouldShow
          ? SettingsMessages.pluginsShownInTools
          : SettingsMessages.pluginsHiddenFromTools,
    );
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
    final bloc = context.read<PluginSystemBloc>();
    var updated = false;
    for (final p in _selectedPlugins) {
      for (final permission in _networkPermissions) {
        if (!p.manifest.permissions.contains(permission)) continue;
        bloc.add(
          SetPluginPermissionRequested(
            pluginId: p.pluginId,
            permission: permission,
            granted: granted,
          ),
        );
        updated = true;
      }
    }
    if (!updated) {
      UiSnack.showError(SettingsMessages.noSelectedPluginUsesNetwork);
      return;
    }
    UiSnack.show(
      granted
          ? SettingsMessages.networkAccessGranted
          : SettingsMessages.networkAccessRevoked,
    );
  }

  void _setRunOnStartup(BuildContext context, {required bool granted}) {
    final eligible = _selectedPlugins
        .where(
          (p) => p.manifest.permissions.contains(pluginRunOnStartupPermission),
        )
        .toList();
    if (eligible.isEmpty) {
      UiSnack.showError(SettingsMessages.noSelectedPluginSupportsStartup);
      return;
    }
    final bloc = context.read<PluginSystemBloc>();
    for (final p in eligible) {
      bloc.add(
        SetPluginPermissionRequested(
          pluginId: p.pluginId,
          permission: pluginRunOnStartupPermission,
          granted: granted,
        ),
      );
    }
    UiSnack.show(
      granted
          ? SettingsMessages.runOnStartupEnabled
          : SettingsMessages.runOnStartupDisabled,
    );
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
      subtitle: 'פעולה זו אינה הפיכה! נתוני התוסף יימחקו.',
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
    UiSnack.show(SettingsMessages.pluginsMarkedForDeletion);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// שורות הטבלה
// ──────────────────────────────────────────────────────────────────────────────

/// כפתור אייקון דו-מצבי — כשהמצב *כבוי* (לא נבחר) מקבל רקע [offBackgroundColor]
/// (ברירת מחדל cs.surfaceContainerHighest), כדי להבליט שהאפשרות מושבתת (למשל:
/// מוסתר, ללא גישה לרשת). ל"טעינה בעלייה" כבויה מועבר cs.errorContainer.
Widget _toggleIconButton(
  BuildContext context, {
  required String tooltip,
  required bool isSelected,
  required IconData icon,
  required IconData selectedIcon,
  required VoidCallback onPressed,
  Color? offBackgroundColor,
  Color? offForegroundColor,
}) {
  final cs = Theme.of(context).colorScheme;
  return IconButton(
    tooltip: tooltip,
    isSelected: isSelected,
    icon: Icon(icon),
    selectedIcon: Icon(selectedIcon),
    style: IconButton.styleFrom(
      backgroundColor: isSelected
          ? null
          : (offBackgroundColor ?? cs.surfaceContainerHighest),
      foregroundColor: isSelected
          ? null
          : (offForegroundColor ?? cs.onSurfaceVariant),
    ),
    onPressed: onPressed,
  );
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
    // SettingsActionTile uses LayoutBuilder internally, which conflicts with
    // Tooltip's OverlayPortal when elements re-activate during layout. Use
    // ListTile directly for all cases.
    return ListTile(
      hoverColor: Colors.transparent,
      leading: meta.imageIcon != null
          ? ImageIcon(AssetImage(meta.imageIcon!), size: 24)
          : RtlIcon(meta.icon!),
      title: Text(meta.label, style: AppTextStyles.settingTitle),
      trailing: _buildTrailing(context),
    );
  }

  Row _buildTrailing(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _toggleIconButton(
        context,
        tooltip: hidden ? 'הצג בממשק' : 'הסתר מהממשק',
        isSelected: !hidden,
        icon: FluentIcons.eye_off_24_regular,
        selectedIcon: FluentIcons.eye_24_regular,
        onPressed: onToggleHide,
      ),
      AnimatedPinButton(
        tooltip: pinnedToNavRail ? 'הסר מסרגל הניווט' : 'הצמד לסרגל הניווט',
        isPinned: pinnedToNavRail,
        onPressed: onTogglePin,
      ),
    ],
  );
}

class _DraggableSettingsPluginRow extends StatelessWidget {
  final InstalledPlugin plugin;
  final double rowMaxWidth;
  final bool isSelectionMode;
  final bool selected;
  final ValueChanged<bool?> onSelectChanged;
  final ValueChanged<String> onAcceptSource;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onToggleHide;
  final VoidCallback onTogglePinNavRail;
  final VoidCallback onToggleEnabled;
  final VoidCallback onToggleNetworkAccess;
  final VoidCallback onToggleRunOnStartup;
  final VoidCallback onDelete;

  const _DraggableSettingsPluginRow({
    required this.plugin,
    required this.rowMaxWidth,
    required this.isSelectionMode,
    required this.selected,
    required this.onSelectChanged,
    required this.onAcceptSource,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleHide,
    required this.onTogglePinNavRail,
    required this.onToggleEnabled,
    required this.onToggleNetworkAccess,
    required this.onToggleRunOnStartup,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != plugin.pluginId,
      onAcceptWithDetails: (details) => onAcceptSource(details.data),
      builder: (context, candidateData, _) {
        final isHovering = candidateData.isNotEmpty;
        final cs = Theme.of(context).colorScheme;
        final row = _PluginRow(
          plugin: plugin,
          rowMaxWidth: rowMaxWidth,
          isSelectionMode: isSelectionMode,
          selected: selected,
          onSelectChanged: onSelectChanged,
          isFirst: isFirst,
          isLast: isLast,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onToggleHide: onToggleHide,
          onTogglePinNavRail: onTogglePinNavRail,
          onToggleEnabled: onToggleEnabled,
          onToggleNetworkAccess: onToggleNetworkAccess,
          onToggleRunOnStartup: onToggleRunOnStartup,
          onDelete: onDelete,
        );
        // גרירה מכל מקום בכרטיס פעילה תמיד מחוץ למצב בחירה (גם לתוסף מושבת) —
        // כפתורי הפעולה שבתוך הכרטיס תופסים לחיצה קצרה משלהם דרך ה-gesture arena.
        final draggableRow = isSelectionMode
            ? row
            : Draggable<String>(
                data: plugin.pluginId,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: _SettingsDragFeedback(plugin: plugin),
                child: row,
              );
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
            child: draggableRow,
          ),
        );
      },
    );
  }
}

class _PluginRow extends StatefulWidget {
  final InstalledPlugin plugin;
  final double rowMaxWidth;
  final bool isSelectionMode;
  final bool selected;
  final ValueChanged<bool?> onSelectChanged;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onToggleHide;
  final VoidCallback onTogglePinNavRail;
  final VoidCallback onToggleEnabled;
  final VoidCallback onToggleNetworkAccess;
  final VoidCallback onToggleRunOnStartup;
  final VoidCallback onDelete;

  const _PluginRow({
    required this.plugin,
    required this.rowMaxWidth,
    required this.isSelectionMode,
    required this.selected,
    required this.onSelectChanged,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleHide,
    required this.onTogglePinNavRail,
    required this.onToggleEnabled,
    required this.onToggleNetworkAccess,
    required this.onToggleRunOnStartup,
    required this.onDelete,
  });

  @override
  State<_PluginRow> createState() => _PluginRowState();
}

class _PluginRowState extends State<_PluginRow> {
  static const double _rowHeight = 72;
  static const double _iconSlot = 44;
  // רוחב שמור לפריט (סמל, כותרת מינימלית, ריפודים) לפני אזור הפעולות.
  static const double _reservedWidth = 190;

  bool _isHovering = false;
  final GlobalKey<AppContextMenuRegionState> _menuKey = GlobalKey();

  void _setHovering(bool value) {
    if (_isHovering != value) setState(() => _isHovering = value);
  }

  _StatusBadges _statusBadges(
    InstalledPlugin plugin, {
    required bool disabled,
  }) {
    return _StatusBadges(
      version: plugin.version,
      disabled: disabled,
      hidden: !plugin.showInTools,
      pinnedToNavRail: plugin.pinnedToNavRail,
      networkDeclared: plugin.networkAccessGranted,
      networkRevoked:
          plugin.manifest.networkEnabled && !plugin.networkAccessGranted,
    );
  }

  /// כל פעולות השורה בסדר התצוגה — מקור אמת אחד. מרונדרות גם ככפתורי אייקון
  /// (בריחוף) וגם כפריטי תפריט (בכפתור ⋯ ובלחיצה ימנית).
  List<_RowAction> _actions(BuildContext context) {
    final plugin = widget.plugin;
    final cs = Theme.of(context).colorScheme;
    if (!plugin.enabled) {
      return [
        _RowAction(
          icon: FluentIcons.play_circle_24_regular,
          label: 'הפעל',
          fixedBg: cs.errorContainer,
          fixedFg: cs.onErrorContainer,
          onTap: widget.onToggleEnabled,
        ),
        _RowAction(
          icon: FluentIcons.delete_24_regular,
          label: 'מחק תוסף',
          isDestructive: true,
          onTap: widget.onDelete,
        ),
      ];
    }
    return [
      if (plugin.manifest.permissions.contains(pluginNetworkAccessPermission))
        _RowAction(
          icon: FluentIcons.globe_prohibited_24_regular,
          selectedIcon: FluentIcons.globe_24_regular,
          selected: plugin.networkAccessGranted,
          label: plugin.networkAccessGranted
              ? 'חסימת גישה לרשת'
              : 'אישור גישה לרשת',
          onTap: widget.onToggleNetworkAccess,
        ),
      if (plugin.manifest.permissions.contains(pluginRunOnStartupPermission))
        _RowAction(
          icon: FluentIcons.power_24_regular,
          selectedIcon: FluentIcons.power_24_filled,
          selected: plugin.runOnStartupGranted,
          offBg: cs.errorContainer,
          offFg: cs.onErrorContainer,
          label: plugin.runOnStartupGranted
              ? 'ביטול טעינה בעלייה'
              : 'הפעלת טעינה בעלייה',
          onTap: widget.onToggleRunOnStartup,
        ),
      _RowAction(
        icon: FluentIcons.shield_24_regular,
        label: 'ניהול הרשאות',
        onTap: () => showPluginSettingsDialog(context, plugin),
      ),
      _RowAction(
        icon: plugin.pinnedToNavRail
            ? FluentIcons.pin_24_filled
            : FluentIcons.pin_24_regular,
        isPin: true,
        selected: plugin.pinnedToNavRail,
        label: plugin.pinnedToNavRail
            ? 'הסר מסרגל הניווט'
            : 'הצמד לסרגל הניווט',
        onTap: widget.onTogglePinNavRail,
      ),
      _RowAction(
        icon: FluentIcons.eye_off_24_regular,
        selectedIcon: FluentIcons.eye_24_regular,
        selected: plugin.showInTools,
        label: plugin.showInTools ? 'הסתר מהממשק' : 'הצג בממשק',
        onTap: widget.onToggleHide,
      ),
      _RowAction(
        icon: FluentIcons.pause_circle_24_regular,
        label: 'השבת',
        onTap: widget.onToggleEnabled,
      ),
      _RowAction(
        icon: FluentIcons.delete_24_regular,
        label: 'מחק תוסף',
        isDestructive: true,
        onTap: widget.onDelete,
      ),
    ];
  }

  Widget _iconButton(BuildContext context, _RowAction a) {
    if (a.isPin) {
      return AnimatedPinButton(
        isPinned: a.selected,
        tooltip: a.label,
        onPressed: a.onTap,
      );
    }
    if (a.selectedIcon != null) {
      return _toggleIconButton(
        context,
        tooltip: a.label,
        isSelected: a.selected,
        icon: a.icon,
        selectedIcon: a.selectedIcon!,
        offBackgroundColor: a.offBg,
        offForegroundColor: a.offFg,
        onPressed: a.onTap,
      );
    }
    return IconButton(
      tooltip: a.label,
      icon: Icon(a.icon),
      style: a.fixedBg != null
          ? IconButton.styleFrom(
              backgroundColor: a.fixedBg,
              foregroundColor: a.fixedFg,
            )
          : null,
      onPressed: a.onTap,
    );
  }

  List<AppContextMenuEntry> _menuEntries(BuildContext context) {
    final actions = _actions(context);
    return [
      for (int i = 0; i < actions.length; i++) ...[
        if (actions[i].isDestructive && i > 0)
          const AppContextMenuEntry.divider(),
        AppContextMenuEntry(
          label: actions[i].label,
          icon: actions[i].displayIcon,
          isDestructive: actions[i].isDestructive,
          onTap: actions[i].onTap,
        ),
      ],
    ];
  }

  Widget _moreButton() => IconButton(
    tooltip: 'עוד פעולות',
    icon: const Icon(FluentIcons.more_horizontal_24_regular),
    onPressed: _openMenu,
  );

  /// פותח את תפריט הפעולות בקצה השורה (מיקום כפתור ⋯) — משמש גם ללחיצה על ⋯
  /// וגם ללחיצה ימנית על הכרטיס.
  void _openMenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final local = Offset(isRtl ? 0 : box.size.width, box.size.height / 2);
    _menuKey.currentState?.openMenuAt(box.localToGlobal(local));
  }

  /// אזור הפעולות של תוסף פעיל. מצב רגיל: כפתור ⋯ בלבד. בריחוף: האייקונים
  /// שנכנסים ברוחב הזמין לפי הסדר, ואם חלקם לא נכנסים — כפתור ⋯ לשאר.
  Widget _enabledTrailing(BuildContext context) {
    if (!_isHovering) return _moreButton();
    final actions = _actions(context);
    final available = widget.rowMaxWidth - _reservedWidth;
    final capacity = (available / _iconSlot).floor().clamp(0, actions.length);
    if (capacity >= actions.length) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final a in actions) _iconButton(context, a)],
      );
    }
    final visibleCount = (capacity - 1).clamp(0, actions.length);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in actions.take(visibleCount)) _iconButton(context, a),
        _moreButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final icon =
        fluentIconFromName(plugin.manifest.toolTabIconName) ??
        FluentIcons.puzzle_piece_24_regular;
    final disabled = !widget.isSelectionMode && !plugin.enabled;
    final showDragHint = !widget.isSelectionMode && _isHovering;

    final tile = SizedBox(
      height: _rowHeight,
      child: ListTile(
        hoverColor: widget.isSelectionMode ? Colors.transparent : null,
        leading: widget.isSelectionMode
            ? SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: widget.selected,
                  onChanged: widget.onSelectChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            : showDragHint
            ? const Tooltip(
                message: 'גרור ושחרר לשינוי סדר',
                child: Icon(FluentIcons.re_order_dots_vertical_24_regular),
              )
            : RtlIcon(icon),
        title: Text(plugin.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: widget.isSelectionMode
            ? _statusBadges(plugin, disabled: !plugin.enabled)
            : disabled || _isHovering
            ? Text('v${plugin.version}', style: AppTextStyles.settingSubtitle)
            : _statusBadges(plugin, disabled: false),
        trailing: widget.isSelectionMode
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ActionButton.ghost(
                    icon: FluentIcons.arrow_up_24_regular,
                    text: 'הזז למעלה',
                    onPressed: widget.isFirst ? null : widget.onMoveUp,
                  ),
                  const SizedBox(width: 8),
                  ActionButton.ghost(
                    icon: FluentIcons.arrow_down_24_regular,
                    text: 'הזז למטה',
                    onPressed: widget.isLast ? null : widget.onMoveDown,
                  ),
                ],
              )
            : disabled
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in _actions(context)) _iconButton(context, a),
                ],
              )
            : _enabledTrailing(context),
        onTap: widget.isSelectionMode
            ? () => widget.onSelectChanged(!widget.selected)
            : () => showPluginSettingsDialog(context, plugin),
      ),
    );

    final hoverable = MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: tile,
    );

    if (widget.isSelectionMode) return hoverable;
    // התפריט נפתח מכפתור ⋯ שבקצה השורה — בלחיצה עליו וגם בלחיצה ימנית על הכרטיס.
    return Stack(
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (event.buttons == kSecondaryButton) _openMenu();
          },
          child: hoverable,
        ),
        // מארח בלבד את מנגנון התפריט; הפתיחה מתבצעת ידנית דרך _openMenu.
        AppContextMenuRegion(
          key: _menuKey,
          menuBuilder: (_, _) => _menuEntries(context),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// תיאור פעולה בשורת תוסף. משמש מקור אמת יחיד — מרונדר גם ככפתור אייקון וגם
/// כפריט תפריט. [selectedIcon] הופך את הפעולה לטוגל דו-מצבי.
class _RowAction {
  final IconData icon;
  final IconData? selectedIcon;
  final bool selected;
  final Color? offBg;
  final Color? offFg;
  final Color? fixedBg;
  final Color? fixedFg;
  final bool isPin;
  final bool isDestructive;
  final String label;
  final VoidCallback onTap;

  const _RowAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selectedIcon,
    this.selected = false,
    this.offBg,
    this.offFg,
    this.fixedBg,
    this.fixedFg,
    this.isPin = false,
    this.isDestructive = false,
  });

  IconData get displayIcon =>
      selectedIcon != null && selected ? selectedIcon! : icon;
}

/// תגיות סטטוס לשורת תוסף. כל התגיות באותו צבע (cs.surfaceContainerHighest),
/// למעט "מושבת" ו"מנותק מהרשת" שמודגשות ב-cs.errorContainer.
class _StatusBadges extends StatelessWidget {
  final String? version;
  final bool disabled;
  final bool hidden;
  final bool pinnedToNavRail;
  final bool networkDeclared;
  final bool networkRevoked;

  const _StatusBadges({
    this.version,
    this.disabled = false,
    this.hidden = false,
    this.pinnedToNavRail = false,
    this.networkDeclared = false,
    this.networkRevoked = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <Widget>[];
    if (version != null) {
      chips.add(Text('v$version', style: AppTextStyles.settingSubtitle));
    }
    if (disabled) {
      chips.add(
        _badge(
          context,
          'מושבת',
          cs.errorContainer,
          cs.onErrorContainer,
          FluentIcons.pause_circle_24_regular,
        ),
      );
    }
    if (hidden) {
      chips.add(
        _badge(
          context,
          'מוסתר',
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
          FluentIcons.eye_off_24_regular,
        ),
      );
    }
    if (pinnedToNavRail) {
      chips.add(
        _badge(
          context,
          'בסרגל ניווט',
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
          FluentIcons.pin_24_regular,
        ),
      );
    }
    if (networkDeclared) {
      chips.add(
        _badge(
          context,
          'משתמש ברשת',
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
          FluentIcons.globe_24_regular,
        ),
      );
    }
    if (networkRevoked) {
      chips.add(
        _badge(
          context,
          'מנותק מהרשת',
          cs.errorContainer,
          cs.onErrorContainer,
          FluentIcons.globe_prohibited_24_regular,
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            chips[i],
            if (i < chips.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _badge(
    BuildContext context,
    String tooltip,
    Color bg,
    Color fg,
    IconData icon,
  ) {
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

class _AnimatedPluginMoveWrapper extends StatefulWidget {
  final Widget child;

  const _AnimatedPluginMoveWrapper({
    super.key,
    required this.child,
  });

  @override
  State<_AnimatedPluginMoveWrapper> createState() =>
      _AnimatedPluginMoveWrapperState();
}

class _AnimatedPluginMoveWrapperState extends State<_AnimatedPluginMoveWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _progress;
  bool _movedUp = true;

  void playAnimation({required bool movedUp}) {
    _movedUp = movedUp;
    _ctrl.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
      value: 1.0,
    );
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slideSign = _movedUp ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value;
        final slideY = slideSign * 0.25 * (1.0 - t);
        final shadowAlpha = 0.28 * (1.0 - t);
        final bgAlpha = 0.10 * (1.0 - t);
        return FractionalTranslation(
          translation: Offset(0, slideY),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: bgAlpha),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: shadowAlpha),
                  blurRadius: 8.0 * (1.0 - t),
                  offset: Offset(0, 4.0 * (1.0 - t)),
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
            RtlIcon(
              fluentIconFromName(plugin.manifest.toolTabIconName) ??
                  FluentIcons.puzzle_piece_24_regular,
            ),
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
