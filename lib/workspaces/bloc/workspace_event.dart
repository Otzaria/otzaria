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

  const SwitchToWorkspace({
    required this.targetWorkspaceId,
    required this.currentTabsToSave,
    required this.currentTabIndexToSave,
  });

  @override
  List<Object?> get props =>
      [targetWorkspaceId, currentTabsToSave, currentTabIndexToSave];
}

/// Event to rename a workspace by its ID.
class RenameWorkspace extends WorkspaceEvent {
  final String workspaceId;
  final String newName;

  const RenameWorkspace({required this.workspaceId, required this.newName});

  @override
  List<Object?> get props => [workspaceId, newName];
}

/// Event to clear all workspaces and create a default one.
///
/// Carries the current tabs data to preserve them in the new default workspace.
class ClearWorkspaces extends WorkspaceEvent {
  final List<OpenedTab> currentTabs;
  final int currentTabIndex;

  const ClearWorkspaces({
    required this.currentTabs,
    required this.currentTabIndex,
  });

  @override
  List<Object?> get props => [currentTabs, currentTabIndex];
}

/// Event to update the current workspace with new tab data.
///
/// Used for auto-save or explicit save operations.
class UpdateCurrentWorkspaceTabs extends WorkspaceEvent {
  final List<OpenedTab> tabs;
  final int activeTabIndex;

  const UpdateCurrentWorkspaceTabs({
    required this.tabs,
    required this.activeTabIndex,
  });

  @override
  List<Object?> get props => [tabs, activeTabIndex];
}

/// Event to move a tab from current workspace to another workspace.
class MoveTabToWorkspace extends WorkspaceEvent {
  final OpenedTab tab;
  final String targetWorkspaceId;
  final List<OpenedTab> currentTabs;
  final int currentTabIndex;

  const MoveTabToWorkspace({
    required this.tab,
    required this.targetWorkspaceId,
    required this.currentTabs,
    required this.currentTabIndex,
  });

  @override
  List<Object?> get props =>
      [tab, targetWorkspaceId, currentTabs, currentTabIndex];
}
