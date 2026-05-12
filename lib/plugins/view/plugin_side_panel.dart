import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';

class PluginSidePanel extends StatelessWidget {
  final Function(InstalledPlugin)? onPluginSelected;
  final bool showDevTools;
  
  const PluginSidePanel({
    super.key, 
    this.onPluginSelected,
    this.showDevTools = kDebugMode,
  });

  Future<void> _installPlugin(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['otzplugin'],
    );
    if (result != null && result.files.single.path != null) {
      if (context.mounted) {
        context.read<PluginSystemBloc>().add(InstallPluginRequested(result.files.single.path!));
      }
    }
  }

  Future<void> _loadDevPlugin(BuildContext context) async {
    final rootPath = await FilePicker.getDirectoryPath();
    if (rootPath != null) {
      if (context.mounted) {
        context.read<PluginSystemBloc>().add(LoadDevelopmentPluginRequested(rootPath));
      }
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
                const Expanded(
                  child: Text(
                    'תוספים',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.add_24_regular),
                  tooltip: 'התקן תוסף חדש',
                  onPressed: () => _installPlugin(context),
                ),
                if (showDevTools)
                  IconButton(
                    icon: const Icon(FluentIcons.folder_add_24_regular),
                    tooltip: 'טען תיקיית תוסף',
                    onPressed: () => _loadDevPlugin(context),
                  ),
                if (showDevTools)
                  IconButton(
                    icon: const Icon(FluentIcons.arrow_sync_24_regular),
                    tooltip: 'רענן תוספים',
                    onPressed: () => context.read<PluginSystemBloc>().add(RefreshPlugins()),
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
                      child: Text('שגיאה: ${state.message}'),
                    ),
                  );
                }
                if (state is PluginSystemLoaded) {
                  final isOfflineMode = context
                      .select<SettingsBloc, bool>((b) => b.state.isOfflineMode);
                  final plugins = state.plugins.filterForOfflineMode(isOfflineMode);
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
                      return ListTile(
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(FluentIcons.puzzle_piece_24_regular),
                            if (plugin.isDevelopment)
                              Positioned(
                                right: -8,
                                top: -8,
                                child: Tooltip(
                                  message: 'תוסף פיתוח המוטען מתיקייה מקומית',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.tertiary,
                                      borderRadius: BorderRadius.circular(4),
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
                            IconButton(
                              icon: const Icon(FluentIcons.settings_24_regular),
                              tooltip: 'הגדרות תוסף',
                              onPressed: () async {
                                final result = await showDialog<bool>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => BlocProvider<PluginSystemBloc>.value(
                                    value: context.read<PluginSystemBloc>(),
                                    child: PluginSettingsScreen(plugin: plugin),
                                  ),
                                );
                                if (result == true && onPluginSelected != null) {
                                  if (context.mounted) {
                                    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.more));
                                    onPluginSelected!(plugin);
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                plugin.pinned
                                    ? FluentIcons.pin_24_filled
                                    : FluentIcons.pin_24_regular,
                              ),
                              tooltip: plugin.pinned ? 'בטל הצמדה' : 'הצמד לסרגל',
                              onPressed: () {
                                if (plugin.pinned) {
                                  context.read<PluginSystemBloc>().add(UnpinPluginRequested(plugin.pluginId));
                                } else {
                                  context.read<PluginSystemBloc>().add(PinPluginRequested(plugin.pluginId));
                                }
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          if (onPluginSelected != null) {
                            onPluginSelected!(plugin);
                          }
                        },
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
