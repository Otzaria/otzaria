import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// Base class for all workspace events.
abstract class WorkspaceEvent extends Equatable {
  const WorkspaceEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load workspaces from storage.
class LoadWorkspaces extends WorkspaceEvent {}

/// Event to add a new workspace.
class AddWorkspace extends WorkspaceEvent {
  final String name;
  final List<OpenedTab> tabs;
  final int currentTabIndex;

  const AddWorkspace({
    required this.name,
    required this.tabs,
    required this.currentTabIndex,
  });

  @override
  List<Object?> get props => [name, tabs, currentTabIndex];
}

/// Event to remove a workspace by its ID.
class RemoveWorkspace extends WorkspaceEvent {
  final String workspaceId;

  const RemoveWorkspace(this.workspaceId);

  @override
  List<Object?> get props => [workspaceId];
}

/// Event to switch to a different workspace.
///
/// This event carries the current tabs data to save before switching,
/// ensuring the UI is the source of truth (not another Bloc).
class SwitchToWorkspace extends WorkspaceEvent {
  /// The ID of the workspace to switch to
  final String targetWorkspaceId;

  /// Current tabs to save in the active workspace before switching
  final List<OpenedTab> currentTabsToSave;

  /// Current tab index to save
  final int currentTabIndexToSave;

  /// צד החלונית הפעילה לשמירה — ראו [Workspace.activePane].
  final String? currentActivePaneToSave;

  /// נקרא בסיום: האם נפתחו כרטיסיות, או null אם המעבר לא הצליח.
  final void Function(bool? hasTabs)? onCompleted;

  const SwitchToWorkspace({
    required this.targetWorkspaceId,
    required this.currentTabsToSave,
    required this.currentTabIndexToSave,
    this.currentActivePaneToSave,
    this.onCompleted,
  });

  @override
  List<Object?> get props => [
    targetWorkspaceId,
    currentTabsToSave,
    currentTabIndexToSave,
    currentActivePaneToSave,
    onCompleted,
  ];
}

/// Event to rename a workspace by its ID.
class RenameWorkspace extends WorkspaceEvent {
  final String workspaceId;
  final String newName;

  const RenameWorkspace({required this.workspaceId, required this.newName});

  @override
  List<Object?> get props => [workspaceId, newName];
}

/// Event to update the current workspace with new tab data.
///
/// Used for auto-save or explicit save operations.
class UpdateCurrentWorkspaceTabs extends WorkspaceEvent {
  final List<OpenedTab> tabs;
  final int activeTabIndex;

  /// צד החלונית הפעילה — ראו [Workspace.activePane].
  final String? activePane;

  const UpdateCurrentWorkspaceTabs({
    required this.tabs,
    required this.activeTabIndex,
    this.activePane,
  });

  @override
  List<Object?> get props => [tabs, activeTabIndex, activePane];
}

/// מעביר כרטיסיות — אחת או בחירה מרובה — מהשולחן הנוכחי לשולחן אחר.
class MoveTabsToWorkspace extends WorkspaceEvent {
  final List<OpenedTab> tabs;
  final String targetWorkspaceId;
  final List<OpenedTab> currentTabs;
  final int currentTabIndex;

  /// צד החלונית הפעילה בשולחן העבודה שממנו הטאבים יוצאים.
  final String? currentActivePane;

  const MoveTabsToWorkspace({
    required this.tabs,
    required this.targetWorkspaceId,
    required this.currentTabs,
    required this.currentTabIndex,
    this.currentActivePane,
  });

  @override
  List<Object?> get props => [
    tabs,
    targetWorkspaceId,
    currentTabs,
    currentTabIndex,
    currentActivePane,
  ];
}

/// מקבע או משחרר שולחן עבודה — ראו [Workspace.isPinned].
///
/// בקיבוע השולחן הפעיל, [tabsToSave] הם הכרטיסיות החיות שיהפכו לתמונה הקבועה.
class SetWorkspacePinned extends WorkspaceEvent {
  final String workspaceId;
  final bool isPinned;
  final List<OpenedTab>? tabsToSave;
  final int tabIndexToSave;
  final String? activePaneToSave;

  const SetWorkspacePinned({
    required this.workspaceId,
    required this.isPinned,
    this.tabsToSave,
    this.tabIndexToSave = 0,
    this.activePaneToSave,
  });

  @override
  List<Object?> get props => [
    workspaceId,
    isPinned,
    tabsToSave,
    tabIndexToSave,
    activePaneToSave,
  ];
}
