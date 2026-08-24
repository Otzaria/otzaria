import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/services/plugin_update_check_service.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';

/// האם להציג צ'יפ עדכון: קיים עדכון שגרסתו גבוהה ממש מהמותקנת.
/// ההשוואה כאן (ולא בזמן הבדיקה) מעלימה את הצ'יפ מעצמו אחרי עדכון מוצלח,
/// ברגע שגרסת התוסף ב-`PluginSystemLoaded` מתעדכנת.
@visibleForTesting
bool shouldShowUpdateChip(PluginUpdateInfo? update, String installedVersion) {
  if (update == null) return false;
  try {
    return PluginVersionUtils.compareCoreVersions(
          update.version,
          installedVersion,
        ) >
        0;
  } on PluginVersionFormatException {
    return false;
  }
}

/// צ'יפ "עדכון זמין" בבעלות התוכנה, מוצג מעל ה-WebView של טאב תוסף.
/// לחיצה מזרימה את מסלול ההתקנה הרגיל — דיאלוג ההרשאות ייפתח במצב עדכון.
/// התוסף עצמו אינו מודע לצ'יפ ואינו יכול להפעיל או להסתיר אותו.
class PluginUpdateChip extends StatelessWidget {
  final InstalledPlugin plugin;

  const PluginUpdateChip({super.key, required this.plugin});

  @override
  Widget build(BuildContext context) {
    final update = context.watch<PluginUpdatesCubit>().state.updateFor(
      plugin.pluginId,
    );
    if (!shouldShowUpdateChip(update, plugin.version)) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.read<PluginSystemBloc>().add(
              InstallRemotePluginRequested(update!.downloadUrl),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.arrow_sync_24_regular,
                    size: 16,
                    color: cs.onPrimaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'עדכון זמין',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'הסתר',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              FluentIcons.dismiss_24_regular,
              color: cs.onPrimaryContainer,
            ),
            onPressed: () =>
                context.read<PluginUpdatesCubit>().dismiss(plugin.pluginId),
          ),
        ],
      ),
    );
  }
}
