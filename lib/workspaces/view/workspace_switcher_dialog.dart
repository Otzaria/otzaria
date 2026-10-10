import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class WorkspaceSwitcherDialog extends StatefulWidget {
  const WorkspaceSwitcherDialog({super.key});

  @override
  State<WorkspaceSwitcherDialog> createState() =>
      _WorkspaceSwitcherDialogState();
}

class _WorkspaceSwitcherDialogState extends State<WorkspaceSwitcherDialog> {
  final TextEditingController _textFieldController = TextEditingController();
  bool _switchPending = false;

  @override
  void initState() {
    super.initState();
    _textFieldController.text = getHebrewTimeStamp();
    context.read<WorkspaceBloc>().add(LoadWorkspaces());
  }

  @override
  void dispose() {
    _textFieldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'שולחנות עבודה',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<WorkspaceBloc, WorkspaceState>(
                builder: (context, state) {
                  if (state.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state.error != null) {
                    return Center(
                      child: Text(
                        'שגיאה: ${state.error}',
                      ),
                    );
                  }

                  final liveTabs = context.select(
                    (TabsBloc bloc) => bloc.state.tabs,
                  );
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      // מספר עמודות לפי הרוחב הזמין; במסך צר יורד ל-1-2 עמודות
                      final crossAxisCount = (constraints.maxWidth / 200)
                          .floor()
                          .clamp(1, 3);
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: state.workspaces.length + 1,
                        itemBuilder: (context, index) {
                          if (index == state.workspaces.length) {
                            // "New Workspace" tile
                            return _buildNewWorkspaceTile(context);
                          } else {
                            // Workspace tile
                            final workspace = state.workspaces[index];
                            final isActive =
                                state.activeWorkspaceId == workspace.id;
                            return _buildWorkspaceTile(
                              context,
                              workspace,
                              state.tabsOf(workspace, liveTabs),
                              isActive,
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewWorkspaceTile(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, tabsState) {
        return Card(
          child: InkWell(
            onTap: () {
              final workspaceBloc = context.read<WorkspaceBloc>();
              final newWorkspaceName = uniqueWorkspaceName(
                workspaceBloc.state.workspaces,
              );
              workspaceBloc.add(
                AddWorkspace(
                  name: newWorkspaceName,
                  tabs: const [],
                  currentTabIndex: 0,
                ),
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: AppTokens.borderRadiusAll,
                  ),
                  child: const Icon(
                    FluentIcons.add_24_regular,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'שולחן עבודה חדש',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceTile(
    BuildContext context,
    Workspace workspace,
    List<OpenedTab> tabs,
    bool isActive,
  ) {
    return Card(
      child: Stack(
        children: [
          InkWell(
            onTap: () async {
              if (_switchPending) return;
              _switchPending = true;
              // הכרטיסיות נשמרות לשולחן, אך מצב ה-JS של תוסף אינו נשמר איתן.
              final tabsBloc = context.read<TabsBloc>();
              final workspaceBloc = context.read<WorkspaceBloc>();
              final navigationBloc = context.read<NavigationBloc>();
              final navigator = Navigator.of(context);
              final route = ModalRoute.of(context);
              if (!await confirmCloseTabs(context, tabsBloc.state.tabs)) {
                _switchPending = false;
                return;
              }
              if (!context.mounted || route?.isCurrent != true) return;
              final tabsState = tabsBloc.state;
              workspaceBloc.add(
                SwitchToWorkspace(
                  targetWorkspaceId: workspace.id,
                  currentTabsToSave: tabsState.tabs,
                  currentTabIndexToSave: tabsState.currentTabIndex,
                  // החלונית הפעילה נשמרת כצד: שולחן עבודה משכפל את
                  // הטאבים, וזהות האובייקט אובדת ממילא.
                  currentActivePaneToSave: tabsState.activePaneSide,
                  onCompleted: (hasTabs) {
                    _switchPending = false;
                    if (hasTabs == null ||
                        !context.mounted ||
                        route?.isCurrent != true) {
                      return;
                    }
                    navigationBloc.add(
                      NavigateToScreen(
                        hasTabs ? Screen.reading : Screen.library,
                      ),
                    );
                    navigator.pop();
                  },
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isActive
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.5)
                          : Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                    child: _buildWorkspacePreview(tabs),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _WorkspaceNameField(workspace: workspace),
                ),
              ],
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 16),
              onPressed: () {
                // Remove the workspace
                if (isActive) {
                  UiSnack.showError(NotesMessages.cannotDeleteActiveWorkspace);
                  return;
                }
                context.read<WorkspaceBloc>().add(
                  RemoveWorkspace(workspace.id),
                );
                UiSnack.show(NotesMessages.workspaceDeleted);
              },
            ),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive && workspace.isPinned)
                  IconButton(
                    tooltip: 'שמור את הספרים הפתוחים כעת בשולחן המקובע',
                    icon: const Icon(FluentIcons.save_24_regular, size: 16),
                    onPressed: () => _saveSnapshot(context),
                  ),
                IconButton(
                  tooltip: workspace.isPinned
                      ? 'בטל קיבוע'
                      : 'קבע: בכל כניסה ייפתחו רק הספרים שנשמרו',
                  isSelected: workspace.isPinned,
                  icon: const Icon(FluentIcons.pin_24_regular, size: 16),
                  selectedIcon: const Icon(
                    FluentIcons.pin_24_filled,
                    size: 16,
                  ),
                  onPressed: () => _togglePinned(context, workspace, isActive),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _togglePinned(BuildContext context, Workspace workspace, bool isActive) {
    final pin = !workspace.isPinned;
    // בקיבוע השולחן הפעיל, התמונה הקבועה היא מה שפתוח כעת ולא השמירה הקודמת.
    final tabsState = pin && isActive ? context.read<TabsBloc>().state : null;
    context.read<WorkspaceBloc>().add(
      SetWorkspacePinned(
        workspaceId: workspace.id,
        isPinned: pin,
        tabsToSave: tabsState?.tabs,
        tabIndexToSave: tabsState?.currentTabIndex ?? 0,
        activePaneToSave: tabsState?.activePaneSide,
      ),
    );
    UiSnack.show(
      pin ? NotesMessages.workspacePinned : NotesMessages.workspaceUnpinned,
    );
  }

  void _saveSnapshot(BuildContext context) {
    final tabsState = context.read<TabsBloc>().state;
    context.read<WorkspaceBloc>().add(
      UpdateCurrentWorkspaceTabs(
        tabs: tabsState.tabs,
        activeTabIndex: tabsState.currentTabIndex,
        activePane: tabsState.activePaneSide,
      ),
    );
    UiSnack.show(NotesMessages.workspaceSnapshotSaved);
  }

  Widget _buildWorkspacePreview(List<OpenedTab> tabs) {
    return Center(
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: tabs.map((tab) {
          return Tooltip(
            message: tab.title,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: AppTokens.borderRadiusAll,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// מצב העריכה נשמר ב-State כדי שפתיחת המקלדת לא תסגור את שדה הקלט.
class _WorkspaceNameField extends StatefulWidget {
  const _WorkspaceNameField({required this.workspace});

  final Workspace workspace;

  @override
  State<_WorkspaceNameField> createState() => _WorkspaceNameFieldState();
}

class _WorkspaceNameFieldState extends State<_WorkspaceNameField> {
  final TextEditingController _controller = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    final name = widget.workspace.name;
    _controller.text = name;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: name.length),
    );
    setState(() => _isEditing = true);
  }

  void _commitRenameAndClose() {
    final newName = _controller.text.trim();
    if (newName.isNotEmpty && newName != widget.workspace.name) {
      context.read<WorkspaceBloc>().add(
        RenameWorkspace(
          workspaceId: widget.workspace.id,
          newName: newName,
        ),
      );
    }
    setState(() => _isEditing = false);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: RtlTextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _commitRenameAndClose(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'שמור',
            icon: const Icon(FluentIcons.checkmark_24_regular),
            onPressed: _commitRenameAndClose,
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.workspace.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(FluentIcons.edit_24_regular),
          onPressed: _startEditing,
        ),
      ],
    );
  }
}
