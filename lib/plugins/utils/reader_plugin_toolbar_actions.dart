import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/utils/plugin_toolbar_actions.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// The plugin toolbar buttons of a reader screen. [pluginContext] tells the
/// plugins which reader asks, such as `reader-text` or `reader-pdf`.
List<ActionButtonData> buildReaderPluginActions(
  BuildContext context, {
  required OpenedTab tab,
  required String pluginContext,
}) {
  final records = PluginToolbarRegistry.instance.getAll();
  if (records.isEmpty) return const [];
  return buildPluginToolbarActions(
    records: records,
    context: pluginContext,
    compact: context.read<SettingsBloc>().state.compactMenuMode,
    locationPayload: () async =>
        (await resolveReaderLocation(tab))?.toJson() ?? const {},
    hostActionDispatcher: context
        .read<PluginSystemBloc>()
        .declarativeHost
        ?.dispatchAction,
  );
}

/// The plugin entries of a reader screen's overflow menu, with their order.
List<(int, ActionButtonData)> buildReaderPluginOverflowActions(
  BuildContext context, {
  required OpenedTab tab,
  required String pluginContext,
}) {
  final records = PluginToolbarRegistry.instance.getAll();
  if (records.isEmpty) return const [];
  return buildOrderedPluginOverflowActions(
    records: records,
    context: pluginContext,
    compact: context.read<SettingsBloc>().state.compactMenuMode,
    locationPayload: () async =>
        (await resolveReaderLocation(tab))?.toJson() ?? const {},
    hostActionDispatcher: context
        .read<PluginSystemBloc>()
        .declarativeHost
        ?.dispatchAction,
  );
}
