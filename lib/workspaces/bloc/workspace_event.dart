import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/tab.dart';

typedef WorkspaceTabs = ({
  List<OpenedTab> tabs,
  int activeTabIndex,
  String? activePane,
});

String _captureTabs(List<OpenedTab> tabs) =>
    jsonEncode(tabs.map((tab) => tab.toJson()).toList(growable: false));

List<OpenedTab> _restoreTabs(String snapshot) => (jsonDecode(snapshot) as List)
    .map(
      (json) => OpenedTab.fromJson(
        OpenedTab.withNewRuntimeIdentity(json as Map<String, dynamic>),
      ),
    )
    .toList(growable: false);

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
/// ה-UI נשאר מקור האמת; הכרטיסיות נקראות רק כשמגיע תורו של המעבר.
class SwitchToWorkspace extends WorkspaceEvent {
  final String? sourceWorkspaceId;

  /// The ID of the workspace to switch to
  final String targetWorkspaceId;

  final WorkspaceTabs Function() readCurrentTabs;

  /// נקרא בסיום: האם נפתחו כרטיסיות, או null אם המעבר לא הצליח.
  final void Function(bool? hasTabs)? onCompleted;

  const SwitchToWorkspace({
    required this.sourceWorkspaceId,
    required this.targetWorkspaceId,
    required this.readCurrentTabs,
    this.onCompleted,
  });

  @override
  List<Object?> get props => [
    sourceWorkspaceId,
    targetWorkspaceId,
    readCurrentTabs,
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
  final String? sourceWorkspaceId;
  final String _tabsSnapshot;
  final int activeTabIndex;

  /// צד החלונית הפעילה — ראו [Workspace.activePane].
  final String? activePane;
  final void Function(bool saved)? onCompleted;

  UpdateCurrentWorkspaceTabs({
    required this.sourceWorkspaceId,
    required List<OpenedTab> tabs,
    required this.activeTabIndex,
    this.activePane,
    this.onCompleted,
  }) : _tabsSnapshot = _captureTabs(tabs);

  // אין תלות בטאב החי: מעבר קודם בתור יכול כבר לשחרר את מצב התוסף שלו.
  List<OpenedTab> restoreTabs() => _restoreTabs(_tabsSnapshot);

  @override
  List<Object?> get props => [
    sourceWorkspaceId,
    _tabsSnapshot,
    activeTabIndex,
    activePane,
    onCompleted,
  ];
}

/// מעביר כרטיסיות — אחת או בחירה מרובה — מהשולחן הנוכחי לשולחן אחר.
class MoveTabsToWorkspace extends WorkspaceEvent {
  final String? sourceWorkspaceId;
  final List<OpenedTab> tabs;
  final String targetWorkspaceId;
  final WorkspaceTabs Function() readCurrentTabs;

  /// נקרא רק אחרי שמירה; ההסרה החיה מסתיימת לפני האירוע הבא בתור.
  final FutureOr<void> Function()? onTabsMoved;
  final void Function(bool moved)? onCompleted;

  const MoveTabsToWorkspace({
    required this.sourceWorkspaceId,
    required this.tabs,
    required this.targetWorkspaceId,
    required this.readCurrentTabs,
    this.onTabsMoved,
    this.onCompleted,
  });

  @override
  List<Object?> get props => [
    sourceWorkspaceId,
    tabs,
    targetWorkspaceId,
    readCurrentTabs,
    onTabsMoved,
    onCompleted,
  ];
}

/// מקבע או משחרר שולחן עבודה — ראו [Workspace.isPinned].
///
/// בקיבוע השולחן הפעיל, הכרטיסיות מוקפאות לפני שהאירוע ממתין בתור.
class SetWorkspacePinned extends WorkspaceEvent {
  final String workspaceId;
  final bool isPinned;
  final String? _tabsSnapshot;
  final int tabIndexToSave;
  final String? activePaneToSave;
  final void Function(bool saved)? onCompleted;

  SetWorkspacePinned({
    required this.workspaceId,
    required this.isPinned,
    List<OpenedTab>? tabsToSave,
    this.tabIndexToSave = 0,
    this.activePaneToSave,
    this.onCompleted,
  }) : _tabsSnapshot = tabsToSave == null ? null : _captureTabs(tabsToSave);

  List<OpenedTab>? restoreTabsToSave() =>
      _tabsSnapshot == null ? null : _restoreTabs(_tabsSnapshot);

  @override
  List<Object?> get props => [
    workspaceId,
    isPinned,
    _tabsSnapshot,
    tabIndexToSave,
    activePaneToSave,
    onCompleted,
  ];
}
