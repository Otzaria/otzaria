import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_group.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// יצירה או עריכה של קבוצה, עם בחירה מרובה ושמירה לפני סגירה.
Future<void> showPluginGroupEditor(
  BuildContext context, {
  PluginGroup? group,
  List<String> initialPluginIds = const [],
}) async {
  final bloc = context.read<PluginSystemBloc>();
  final state = bloc.state;
  if (state is! PluginSystemLoaded || !state.groupsLoaded) return;
  await showDialogUntilTornDown<void>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (_) => PluginGroupEditor(
        group: group,
        plugins: state.plugins,
        groups: state.groups,
        initialPluginIds: initialPluginIds,
        onSave: (name, pluginIds) {
          final completion = Completer<void>();
          if (bloc.isClosed) return Future.error(StateError('Bloc closed'));
          bloc.add(
            group == null
                ? CreatePluginGroupRequested(
                    name: name,
                    pluginIds: pluginIds,
                    completion: completion,
                  )
                : UpdatePluginGroupRequested(
                    groupId: group.id,
                    name: name,
                    pluginIds: pluginIds,
                    expectedGroup: group,
                    completion: completion,
                  ),
          );
          return completion.future;
        },
      ),
    ),
  );
}

/// בורר יעד עם חלופה ליצירת קבוצה חדשה, גם ללא גרירה.
Future<void> showMovePluginToGroupDialog(
  BuildContext context,
  String pluginId,
) async {
  final bloc = context.read<PluginSystemBloc>();
  final state = bloc.state;
  if (state is! PluginSystemLoaded || !state.groupsLoaded) return;
  final current = state.groups.firstWhereOrNull(
    (group) => group.pluginIds.contains(pluginId),
  );
  final destination = await showSelectionDialog<_GroupDestination>(
    context: context,
    title: context.settingsText('העבר לקבוצה'),
    icon: FluentIcons.folder_24_regular,
    items: [
      SelectionItem(
        label: context.settingsText('קבוצה חדשה'),
        value: const _GroupDestination(create: true),
      ),
      if (current != null)
        SelectionItem(
          label: context.settingsText('ללא קבוצה'),
          value: const _GroupDestination(),
        ),
      for (final group in state.groups)
        if (group.id != current?.id)
          SelectionItem(
            label: group.name,
            value: _GroupDestination(groupId: group.id),
          ),
    ],
  );
  if (destination == null || !context.mounted || bloc.isClosed) return;
  if (destination.create) {
    await showPluginGroupEditor(context, initialPluginIds: [pluginId]);
    return;
  }
  bloc.add(
    MovePluginToGroupRequested(
      pluginId: pluginId,
      groupId: destination.groupId,
    ),
  );
}

class _GroupDestination {
  const _GroupDestination({this.groupId, this.create = false});

  final String? groupId;
  final bool create;
}

/// עורך קבוצות אישי; השינויים נשארים בטופס עד להצלחת השמירה.
class PluginGroupEditor extends StatefulWidget {
  const PluginGroupEditor({
    super.key,
    this.group,
    required this.plugins,
    required this.groups,
    this.initialPluginIds = const [],
    required this.onSave,
  });

  final PluginGroup? group;
  final List<InstalledPlugin> plugins;
  final List<PluginGroup> groups;
  final List<String> initialPluginIds;
  final Future<void> Function(String name, List<String> pluginIds) onSave;

  @override
  State<PluginGroupEditor> createState() => _PluginGroupEditorState();
}

class _PluginGroupEditorState extends State<PluginGroupEditor> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  final _search = TextEditingController();
  final _nameFocus = FocusNode();
  final _dirty = ValueNotifier(false);
  late final _initialIds = List<String>.of(
    widget.group?.pluginIds ?? widget.initialPluginIds,
  );
  late final _selected = _initialIds.toSet();
  late final _plugins = widget.plugins.where((p) => p.hasToolPage).toList();
  late final _groupNames = {
    for (final group in widget.groups)
      for (final id in group.pluginIds) id: group.name,
  };
  String? _nameError;
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    _nameFocus.dispose();
    _dirty.dispose();
    super.dispose();
  }

  void _updateDirty() {
    _dirty.value =
        _name.text != (widget.group?.name ?? '') ||
        !const SetEquality<String>().equals(_selected, _initialIds.toSet());
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final nameError = name.isEmpty
        ? context.settingsText('הזן שם לקבוצה')
        : widget.groups.any(
            (group) =>
                group.id != widget.group?.id &&
                group.name.toLowerCase() == name.toLowerCase(),
          )
        ? context.settingsText('כבר קיימת קבוצה בשם זה')
        : null;
    if (nameError != null) {
      setState(() => _nameError = nameError);
      _nameFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
      _saveError = null;
    });
    final ids = <String>{
      for (final id in _initialIds)
        if (_selected.contains(id)) id,
      for (final plugin in _plugins)
        if (_selected.contains(plugin.pluginId)) plugin.pluginId,
    }.toList();
    try {
      await widget.onSave(name, ids);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error is PluginGroupChanged
            ? context.settingsText(
                'הקבוצה השתנתה בחלון אחר. סגור ופתח את העריכה מחדש.',
              )
            : error is PluginGroupNameInUse
            ? context.settingsText('כבר קיימת קבוצה בשם זה')
            : context.settingsText(PluginMessages.pluginGroupSaveFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final plugins = _plugins
        .where(
          (plugin) =>
              plugin.name.toLowerCase().contains(query) ||
              plugin.manifest.toolTabTitle.toLowerCase().contains(query),
        )
        .toList();
    return AppDialogFrame(
      title: context.settingsText(
        widget.group == null ? 'קבוצה חדשה' : 'עריכת קבוצה',
      ),
      icon: FluentIcons.folder_24_regular,
      size: AppDialogSize.large,
      height: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightFactor,
      closeEnabled: !_saving,
      isDirty: _dirty,
      confirmDiscard: confirmDiscardChanges,
      handleEnterKey: false,
      actions: [
        ActionButton.neutral(
          text: context.settingsText('ביטול'),
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
        ),
        ActionButton.recommended(
          text: context.settingsText('שמור'),
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RtlTextField(
            key: const ValueKey('plugin-group-name'),
            controller: _name,
            focusNode: _nameFocus,
            autofocus: true,
            enabled: !_saving,
            inputFormatters: [
              LengthLimitingTextInputFormatter(PluginGroup.maxNameLength),
            ],
            decoration: InputDecoration(
              labelText: context.settingsText('שם הקבוצה'),
              hintText: context.settingsText('למשל: חזרות, כתיבה או עיון'),
              errorText: _nameError,
            ),
            onChanged: (_) {
              _updateDirty();
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: AppTokens.spaceMD),
          Text(
            context.settingsText('בחר את התוספים שיופיעו בקבוצה'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppTokens.spaceSM),
          OtzariaSearchField(
            key: const ValueKey('plugin-group-search'),
            controller: _search,
            hintText: context.settingsText('חיפוש תוסף'),
            onChanged: (_) => setState(() {}),
            onClear: () => setState(() {}),
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MetaChip(
              icon: FluentIcons.puzzle_piece_24_regular,
              label: context.settingsText(
                'נבחרו {count} תוספים',
                args: {'count': _selected.length},
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Expanded(
            child: plugins.isEmpty
                ? OtzariaEmptyState(
                    icon: FluentIcons.puzzle_piece_24_regular,
                    title: context.settingsText(
                      query.isEmpty ? 'אין תוספים לבחירה' : 'לא נמצאו תוספים',
                    ),
                  )
                : ListView.builder(
                    itemCount: plugins.length,
                    itemBuilder: (context, index) {
                      final plugin = plugins[index];
                      final groupName = _groupNames[plugin.pluginId];
                      final details = [
                        if (groupName != null)
                          context.settingsText(
                            'בקבוצה: {name}',
                            args: {'name': groupName},
                          ),
                        if (!plugin.savedEnabled) context.settingsText('מושבת'),
                        if (!plugin.showInTools)
                          context.settingsText('מוסתר מלוח הכלים'),
                      ];
                      return CheckboxListTile(
                        key: ValueKey('group-member-${plugin.pluginId}'),
                        value: _selected.contains(plugin.pluginId),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(plugin.manifest.toolTabTitle),
                        subtitle: details.isEmpty
                            ? null
                            : Text(details.join(' · ')),
                        secondary: Icon(
                          pluginIconFromName(plugin.manifest.toolTabIconName) ??
                              FluentIcons.puzzle_piece_24_regular,
                          size: AppTokens.iconMD,
                        ),
                        onChanged: _saving
                            ? null
                            : (selected) => setState(() {
                                if (selected == true) {
                                  _selected.add(plugin.pluginId);
                                } else {
                                  _selected.remove(plugin.pluginId);
                                }
                                _updateDirty();
                              }),
                      );
                    },
                  ),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: AppTokens.spaceSM),
            AppInfoBanner(
              tone: AppInfoBannerTone.error,
              message: _saveError!,
            ),
          ],
        ],
      ),
    );
  }
}
