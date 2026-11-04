import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
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
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

class WorkspaceSwitcherDialog extends StatefulWidget {
  const WorkspaceSwitcherDialog({super.key});

  @override
  State<WorkspaceSwitcherDialog> createState() =>
      _WorkspaceSwitcherDialogState();
}

class _WorkspaceSwitcherDialogState extends State<WorkspaceSwitcherDialog> {
  /// הרוחב המזערי של אריח: ב־720 של דיאלוג גדול נכנסות 3 עמודות.
  static const double _minTileWidth = 200;

  /// הריבוע שסביב ה־+ באריח "שולחן עבודה חדש".
  static const double _newTileIconBox = 100;

  bool _switchPending = false;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    context.read<WorkspaceBloc>().add(LoadWorkspaces());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// בלי ניקוד ובלי הבדל אותיות גדולות, כמו בשאר שדות הסינון.
  static String _normalize(String text) =>
      removeVolwels(text).toLowerCase().trim();

  @override
  Widget build(BuildContext context) {
    return AppDialogFrame(
      title: 'שולחנות עבודה',
      icon: OtzariaIcons.lectern_24_regular,
      size: AppDialogSize.large,
      // גובה קבוע, כדי ששדה החיפוש לא יזוז בזמן ההקלדה (§3.1).
      height: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightFactor,
      child: BlocBuilder<WorkspaceBloc, WorkspaceState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const LoadingIndicator();
          }

          if (state.error != null) {
            return OtzariaErrorState(
              title: 'לא ניתן לטעון את שולחנות העבודה',
              details: state.error,
            );
          }

          final liveTabs = context.select(
            (TabsBloc bloc) => bloc.state.tabs,
          );
          final query = _normalize(_query);
          final workspaces = query.isEmpty
              ? state.workspaces
              : state.workspaces
                    .where((w) => _normalize(w.name).contains(query))
                    .toList();
          final grid = LayoutBuilder(
            builder: (context, constraints) {
              // מספר עמודות לפי הרוחב הזמין; במסך צר יורד ל-1-2 עמודות
              final crossAxisCount = (constraints.maxWidth / _minTileWidth)
                  .floor()
                  .clamp(1, 3);
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: AppTokens.spaceMD,
                  mainAxisSpacing: AppTokens.spaceMD,
                  childAspectRatio: 1.2,
                ),
                // אריח "חדש" תמיד בסוף, גם כשהחיפוש לא מצא דבר.
                itemCount: workspaces.length + 1,
                // אריח לפי מזהה השולחן: כשהסינון משתנה, מצב העריכה של השם
                // עובר עם השולחן למקומו החדש, ולא נשאר באינדקס של שולחן אחר.
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<String>) return null;
                  final index = workspaces.indexWhere(
                    (w) => w.id == key.value,
                  );
                  return index < 0 ? null : index;
                },
                itemBuilder: (context, index) {
                  if (index == workspaces.length) {
                    // "New Workspace" tile
                    return _buildNewWorkspaceTile(context);
                  } else {
                    // Workspace tile
                    final workspace = workspaces[index];
                    final isActive = state.activeWorkspaceId == workspace.id;
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
          // שדה החיפוש תמיד, כמו בתוספים, בהגדרות ובהיסטוריה (#2841).
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OtzariaSearchField(
                controller: _search,
                hintText: 'חיפוש שולחן עבודה',
                onChanged: (value) => setState(() => _query = value),
                onClear: () => setState(() => _query = ''),
              ),
              const SizedBox(height: AppTokens.spaceSM),
              if (workspaces.isEmpty)
                const OtzariaEmptyState(
                  isCompact: true,
                  icon: OtzariaIcons.search_24_regular,
                  title: 'לא נמצאו שולחנות עבודה',
                ),
              Expanded(child: grid),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNewWorkspaceTile(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, tabsState) {
        return AppCard(
          margin: const EdgeInsets.all(4),
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
                width: _newTileIconBox,
                height: _newTileIconBox,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: Icon(
                  FluentIcons.add_24_regular,
                  size: AppTokens.iconXL,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    // הפעיל: מסגרת הבחירה, ורק אזור התצוגה המקדימה בצבע "נבחר" (q9 שאלה 7).
    return AppCard(
      key: ValueKey<String>(workspace.id),
      margin: const EdgeInsets.all(4),
      active: isActive,
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
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppSurfaces.selectedRow(cs)
                        : cs.surfaceContainerHighest,
                    borderRadius: AppTokens.borderRadiusAll,
                  ),
                  child: _buildWorkspacePreview(context, tabs, isActive),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: _WorkspaceNameField(
                  workspace: workspace,
                  // הפעיל לא נמחק: הכפתור מושבת, במקום הודעת שגיאה.
                  onDelete: isActive
                      ? null
                      : () => _deleteWorkspace(context, workspace),
                ),
              ),
            ],
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive && workspace.isPinned)
                  IconButton(
                    tooltip: 'שמור את הספרים הפתוחים כעת בשולחן המקובע',
                    icon: const Icon(
                      FluentIcons.save_24_regular,
                      size: AppTokens.iconSM,
                    ),
                    onPressed: () => _saveSnapshot(context),
                  ),
                IconButton(
                  tooltip: workspace.isPinned
                      ? 'בטל קיבוע'
                      : 'קבע: בכל כניסה ייפתחו רק הספרים שנשמרו',
                  isSelected: workspace.isPinned,
                  icon: const Icon(
                    FluentIcons.pin_24_regular,
                    size: AppTokens.iconSM,
                  ),
                  selectedIcon: const Icon(
                    FluentIcons.pin_24_filled,
                    size: AppTokens.iconSM,
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

  Future<void> _deleteWorkspace(
    BuildContext context,
    Workspace workspace,
  ) async {
    final workspaceBloc = context.read<WorkspaceBloc>();
    final confirmed = await showWarningDialog(
      context: context,
      title: 'למחוק את שולחן העבודה?',
      content: 'שולחן העבודה "${workspace.name}" והכרטיסיות שנשמרו בו יימחקו.',
      confirmText: 'מחק',
    );
    if (confirmed != true) return;
    workspaceBloc.add(RemoveWorkspace(workspace.id));
    UiSnack.show(NotesMessages.workspaceDeleted);
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

  Widget _buildWorkspacePreview(
    BuildContext context,
    List<OpenedTab> tabs,
    bool isActive,
  ) {
    final cs = Theme.of(context).colorScheme;
    final color = isActive ? AppSurfaces.onSelectedRow(cs) : cs.primary;
    final preview = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(OtzariaIcons.lectern_24_filled, size: 44, color: color),
        if (tabs.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            tabs.length == 1 ? 'כרטיסייה אחת' : '${tabs.length} כרטיסיות',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ],
    );
    return Center(
      // שמות הכרטיסיות נשארים זמינים בריחוף, כמו שהיו בריבועים שהוחלפו.
      child: tabs.isEmpty
          ? preview
          : Tooltip(
              message: tabs.map((tab) => tab.title).join('\n'),
              child: preview,
            ),
    );
  }
}

/// מצב העריכה נשמר ב-State כדי שפתיחת המקלדת לא תסגור את שדה הקלט.
class _WorkspaceNameField extends StatefulWidget {
  const _WorkspaceNameField({required this.workspace, required this.onDelete});

  final Workspace workspace;

  /// null = מושבת (השולחן הפעיל).
  final VoidCallback? onDelete;

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
    // הפוקוס חוזר לכרטיס השולחן שמכיל את השדה, כך ש-Enter נוסף פותח אותו.
    Focus.maybeOf(context, createDependency: false)?.requestFocus();
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
                isDense: true,
              ),
              onSubmitted: (_) => _commitRenameAndClose(),
            ),
          ),
          const SizedBox(width: 6),
          AppIconButton(
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
        AppIconButton(
          tooltip: 'שנה שם',
          icon: const Icon(FluentIcons.edit_24_regular),
          onPressed: _startEditing,
        ),
        AppIconButton(
          // המושבת (השולחן הפעיל) אומר למה (q10 שאלה 24).
          tooltip: widget.onDelete == null
              ? NotesMessages.cannotDeleteActiveWorkspace
              : 'מחק שולחן עבודה',
          icon: const Icon(FluentIcons.delete_24_regular),
          onPressed: widget.onDelete,
        ),
      ],
    );
  }
}
