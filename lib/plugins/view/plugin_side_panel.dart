import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/plugins/view/plugin_actions.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

class PluginSidePanel extends StatelessWidget {
  final Function(InstalledPlugin)? onPluginSelected;
  final bool showDevTools;
  final VoidCallback? onClose;

  const PluginSidePanel({
    super.key,
    this.onPluginSelected,
    this.showDevTools = kDebugMode,
    this.onClose,
  });

  Future<void> _installPlugin(BuildContext context) async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !context.mounted) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['otzplugin'],
      lockParentWindow: true,
    );
    if (result != null && result.files.single.path != null) {
      if (context.mounted) {
        context.read<PluginSystemBloc>().add(
          InstallPluginRequested(result.files.single.path!),
        );
      }
    }
  }

  Future<void> _loadDevPlugin(BuildContext context) async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !context.mounted) return;

    final rootPath = await FilePicker.getDirectoryPath(lockParentWindow: true);
    if (rootPath != null) {
      if (context.mounted) {
        context.read<PluginSystemBloc>().add(
          LoadDevelopmentPluginRequested(rootPath),
        );
      }
    }
  }

  Future<void> _loadLocalhostPlugin(BuildContext context) async {
    final verified = await verifySaferModePassword(context);
    if (!verified || !context.mounted) return;

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
    if (url != null && url.isNotEmpty) {
      bloc.add(LoadLocalhostPluginRequested(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              if (onClose != null)
                IconButton(
                  icon: Icon(FluentIcons.dismiss_24_regular),
                  tooltip: 'סגור',
                  onPressed: onClose,
                  iconSize: 20,
                ),
              const Expanded(
                child: Text(
                  'תוספים',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              IconButton(
                icon: Icon(FluentIcons.add_24_regular),
                tooltip: 'התקן תוסף חדש',
                onPressed: () => _installPlugin(context),
              ),
              if (showDevTools)
                IconButton(
                  icon: Icon(FluentIcons.folder_add_24_regular),
                  tooltip: 'טען תיקיית תוסף',
                  onPressed: () => _loadDevPlugin(context),
                ),
              if (showDevTools)
                IconButton(
                  icon: Icon(FluentIcons.globe_add_24_regular),
                  tooltip: 'טען תוסף מ-localhost',
                  onPressed: () => _loadLocalhostPlugin(context),
                ),
              if (showDevTools)
                IconButton(
                  icon: Icon(FluentIcons.arrow_sync_24_regular),
                  tooltip: 'רענן תוספים',
                  onPressed: () =>
                      context.read<PluginSystemBloc>().add(RefreshPlugins()),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: BlocBuilder<PluginSystemBloc, PluginSystemState>(
            builder: (context, state) {
              if (state is PluginSystemLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is PluginSystemError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'שגיאה: ${state.message}',
                    ),
                  ),
                );
              }
              if (state is PluginSystemLoaded) {
                final isOfflineMode = context.select<SettingsBloc, bool>(
                  (b) => b.state.isOfflineMode,
                );
                final plugins = state.activePlugins.filterForOfflineMode(
                  isOfflineMode,
                );
                if (plugins.isEmpty) {
                  return Center(
                    child: Text(
                      isOfflineMode && state.plugins.isNotEmpty
                          ? 'כל התוספים המותקנים דורשים אינטרנט\nוהוסתרו במצב מנותק'
                          : 'לא הותקנו תוספים',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: plugins.length,
                  itemBuilder: (context, index) {
                    final plugin = plugins[index];
                    return _DraggablePluginRow(
                      key: ValueKey(plugin.pluginId),
                      plugin: plugin,
                      onAcceptSource: (sourceId) =>
                          context.read<PluginSystemBloc>().add(
                            ReorderPluginsRequested(
                              reorderedPluginIds(
                                state.plugins,
                                sourceId,
                                plugin.pluginId,
                              ),
                            ),
                          ),
                      onPluginSelected: onPluginSelected,
                    );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}

/// שורת תוסף בודדת עם תמיכה בגרירה: כל השורה היא [DragTarget] שמקבל id
/// של תוסף אחר, וה-handle בצד הוא [Draggable] שמתחיל גרירה.
class _DraggablePluginRow extends StatelessWidget {
  final InstalledPlugin plugin;
  final ValueChanged<String> onAcceptSource;
  final Function(InstalledPlugin)? onPluginSelected;

  const _DraggablePluginRow({
    super.key,
    required this.plugin,
    required this.onAcceptSource,
    required this.onPluginSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != plugin.pluginId,
      onAcceptWithDetails: (details) => onAcceptSource(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        final cs = Theme.of(context).colorScheme;
        return Container(
          decoration: isHovering
              ? BoxDecoration(
                  color: AppSurfaces.dragTargetHighlight(cs),
                  border: Border(top: BorderSide(color: cs.primary, width: 2)),
                )
              : null,
          child: Material(
            color: Colors.transparent,
            child: _PluginListTile(
              plugin: plugin,
              onPluginSelected: onPluginSelected,
            ),
          ),
        );
      },
    );
  }
}

class _PluginListTile extends StatelessWidget {
  final InstalledPlugin plugin;
  final Function(InstalledPlugin)? onPluginSelected;

  const _PluginListTile({
    required this.plugin,
    required this.onPluginSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            fluentIconFromName(plugin.manifest.toolTabIconName) ??
                FluentIcons.puzzle_piece_24_regular,
          ),
          if (plugin.isDevelopment)
            Positioned(
              right: -8,
              top: -8,
              child: Tooltip(
                message: 'תוסף פיתוח המוטען מתיקייה מקומית',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiary,
                    borderRadius: AppTokens.borderRadiusAll,
                  ),
                  child: Text(
                    'DEV',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onTertiary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(plugin.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(plugin.version),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PluginActionsMenu(plugin: plugin),
          Draggable<String>(
            data: plugin.pluginId,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _DragFeedback(plugin: plugin),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: 'גרור ושחרר לסידור מחדש',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Icon(FluentIcons.re_order_dots_vertical_24_regular),
                ),
              ),
            ),
          ),
        ],
      ),
      onTap: () {
        if (onPluginSelected != null) {
          onPluginSelected!(plugin);
        }
      },
    );
  }
}

class _PluginActionsMenu extends StatelessWidget {
  final InstalledPlugin plugin;

  const _PluginActionsMenu({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppPopupMenuButton<VoidCallback>(
      tooltip: 'פעולות',
      onSelected: (action) => action(),
      itemBuilder: (context) {
        final metrics =
            Theme.of(context).extension<AppMenuMetrics>() ??
            AppMenuMetrics.create(compactMenus: false);
        return [
          _menuItem(
            context,
            metrics,
            AppMenuEntry<VoidCallback>(
              value: () => showPluginSettingsDialog(context, plugin),
              icon: FluentIcons.shield_24_regular,
              label: 'ניהול הרשאות',
            ),
          ),
          _menuItem(
            context,
            metrics,
            AppMenuEntry<VoidCallback>(
              value: () => togglePluginPinnedToNavRail(context, plugin),
              icon: plugin.pinnedToNavRail
                  ? FluentIcons.pin_24_filled
                  : FluentIcons.pin_24_regular,
              label: plugin.pinnedToNavRail
                  ? 'הסר מסרגל הניווט'
                  : 'הצמד לסרגל הניווט',
            ),
          ),
          _menuItem(
            context,
            metrics,
            AppMenuEntry<VoidCallback>(
              value: () => togglePluginShowInTools(context, plugin),
              icon: plugin.showInTools
                  ? FluentIcons.eye_off_24_regular
                  : FluentIcons.eye_24_regular,
              label: plugin.showInTools ? 'הסתר מהממשק' : 'הצג בממשק',
            ),
          ),
          _menuItem(
            context,
            metrics,
            AppMenuEntry<VoidCallback>(
              value: () => togglePluginEnabled(context, plugin),
              icon: plugin.enabled
                  ? FluentIcons.pause_circle_24_regular
                  : FluentIcons.play_circle_24_regular,
              label: plugin.enabled ? 'השבת' : 'הפעל',
            ),
          ),
          const PopupMenuDivider(),
          _menuItem(
            context,
            metrics,
            AppMenuEntry<VoidCallback>(
              value: () => showDeletePluginDialog(context, plugin),
              icon: FluentIcons.delete_24_regular,
              label: 'מחק תוסף',
              isDestructive: true,
            ),
          ),
        ];
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'פעולות',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(
              FluentIcons.chevron_down_24_regular,
              size: 16,
              color: cs.primary,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuEntry<VoidCallback> _menuItem(
    BuildContext context,
    AppMenuMetrics metrics,
    AppMenuEntry<VoidCallback> entry,
  ) {
    return buildAppPopupMenuItem<VoidCallback>(
      context,
      entry,
      metrics,
      null,
    );
  }
}

/// ה-widget שצף מתחת לסמן בזמן גרירה. מוצג מעל Overlay של ה-Navigator
/// (לא OverlayPortal) ולכן ללא חשש לקונפליקט עם LayoutBuilders.
class _DragFeedback extends StatelessWidget {
  final InstalledPlugin plugin;

  const _DragFeedback({required this.plugin});

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
            Icon(
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
