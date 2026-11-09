import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';

class PluginDevErrorView extends StatelessWidget {
  final InstalledPlugin plugin;
  final String errorMessage;

  const PluginDevErrorView({
    super.key,
    required this.plugin,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OtzariaErrorState(
      icon: FluentIcons.warning_24_filled,
      title: 'שגיאה בטעינת תוסף פיתוח',
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'נתיב: ${plugin.resolvedRootPath}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: AppTokens.spaceMD),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTokens.spaceMD),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Text(
                errorMessage,
                style: TextStyle(color: cs.onErrorContainer),
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
      ),
      actions: [
        ActionButton.recommended(
          text: 'נסה קריאה מחדש',
          onPressed: () {
            context.read<PluginSystemBloc>().add(
              ReloadDevelopmentPluginRequested(plugin.pluginId),
            );
          },
        ),
        ActionButton.neutral(
          text: 'הגדרות תוסף',
          onPressed: () async {
            final result = await showDialog<bool>(
              context: context,
              builder: (_) => BlocProvider<PluginSystemBloc>.value(
                value: context.read<PluginSystemBloc>(),
                child: PluginSettingsScreen(plugin: plugin),
              ),
            );
            if (result == true && context.mounted) {
              ToolsLauncherController.instance.open();
            }
          },
        ),
      ],
    );
  }
}
