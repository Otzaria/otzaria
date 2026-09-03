import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// Bloc for managing workspaces.
///
/// **Key architectural change:** This Bloc no longer holds a reference to TabsBloc.
/// Instead, the UI acts as a coordinator:
/// - When switching workspaces, the UI passes current tab data via events
/// - The UI listens to state changes and updates TabsBloc accordingly
///
/// This decoupling enables:
/// - Unit testing in isolation
/// - Clear data flow
/// - No circular dependencies
class WorkspaceBloc extends Bloc<WorkspaceEvent, WorkspaceState> {
  final WorkspaceRepository _repository;

  /// Callback function to notify when workspace tabs should be loaded.
  /// The UI should provide this to coordinate with TabsBloc.
  final FutureOr<void> Function(List<OpenedTab> tabs, int activeIndex)?
  onWorkspaceTabsChanged;

  List<OpenedTab> _cloneTabs(List<OpenedTab> tabs) {
    return tabs.map(OpenedTab.from).toList(growable: false);
  }

  WorkspaceBloc({
    required this._repository,
    this.onWorkspaceTabsChanged,
  }) : super(WorkspaceState.initial()) {
    on<LoadWorkspaces>(_onLoadWorkspaces, transformer: sequential());
    on<AddWorkspace>(_onAddWorkspace, transformer: sequential());
    on<RemoveWorkspace>(_onRemoveWorkspace, transformer: sequential());
    on<SwitchToWorkspace>(_onSwitchToWorkspace, transformer: sequential());
    on<RenameWorkspace>(_onRenameWorkspace, transformer: sequential());
    on<ClearWorkspaces>(_onClearWorkspaces, transformer: sequential());
    on<UpdateCurrentWorkspaceTabs>(
      _onUpdateCurrentWorkspaceTabs,
      transformer: sequential(),
    );
    on<MoveTabToWorkspace>(_onMoveTabToWorkspace, transformer: sequential());
  }

  Future<void> _onLoadWorkspaces(
    LoadWorkspaces event,
    Emitter<WorkspaceState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final (workspaces, activeId) = _repository.loadWorkspaces();

      List<Workspace> finalWorkspaces = List.from(workspaces);
      String? finalActiveId = activeId;

      // Create default workspace if none exist
      if (finalWorkspaces.isEmpty) {
        final defaultWorkspace = Workspace(
          name: "שולחן עבודה 1",
          tabs: [],
          activeTabIndex: 0,
        );
        finalWorkspaces.add(defaultWorkspace);
        finalActiveId = defaultWorkspace.id;
        await _repository.saveWorkspaces(finalWorkspaces, finalActiveId);
      }

      // Ensure the active ID exists in the list
      if (finalActiveId != null &&
          !finalWorkspaces.any((w) => w.id == finalActiveId)) {
        finalActiveId = finalWorkspaces.first.id;
      }

      emit(
        state.copyWith(
          workspaces: finalWorkspaces,
          activeWorkspaceId: finalActiveId,
          isLoading: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Failed to load workspaces: $e',
        ),
      );
    }
  }

  Future<void> _onAddWorkspace(
    AddWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    try {
      final newWorkspace = Workspace(
        name: event.name,
        tabs: _cloneTabs(event.tabs),
        activeTabIndex: event.currentTabIndex,
      );

      final updatedWorkspaces = [...state.workspaces, newWorkspace];

      await _repository.saveWorkspaces(
        updatedWorkspaces,
        state.activeWorkspaceId,
      );

      emit(state.copyWith(workspaces: updatedWorkspaces));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to add workspace: $e'));
    }
  }

  Future<void> _onRemoveWorkspace(
    RemoveWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    try {
      // Can't remove the active workspace
      if (state.activeWorkspaceId == event.workspaceId) {
        emit(state.copyWith(error: 'לא ניתן למחוק שולחן עבודה פעיל'));
        return;
      }

      final updatedWorkspaces = state.workspaces
          .where((w) => w.id != event.workspaceId)
          .toList();

      await _repository.saveWorkspaces(
        updatedWorkspaces,
        state.activeWorkspaceId,
      );

      emit(state.copyWith(workspaces: updatedWorkspaces));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to remove workspace: $e'));
    }
  }

  Future<void> _onSwitchToWorkspace(
    SwitchToWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    try {
      // 1. Save current tabs to the currently active workspace
      final currentId = state.activeWorkspaceId;
      List<Workspace> updatedWorkspaces = state.workspaces.map((w) {
        if (w.id == currentId) {
          return w.copyWith(
            tabs: _cloneTabs(event.currentTabsToSave),
            activeTabIndex: event.currentTabIndexToSave,
          );
        }
        return w;
      }).toList();

      // 2. Get the target workspace
      final targetWorkspace = updatedWorkspaces.firstWhere(
        (w) => w.id == event.targetWorkspaceId,
      );

      // 3. Notify UI to update TabsBloc before exposing the new workspace.
      if (onWorkspaceTabsChanged != null) {
        int newCurrentTab = 0;
        if (targetWorkspace.tabs.isNotEmpty) {
          newCurrentTab =
              targetWorkspace.activeTabIndex < targetWorkspace.tabs.length
              ? targetWorkspace.activeTabIndex
              : 0;
        }
        await onWorkspaceTabsChanged!(
          _cloneTabs(targetWorkspace.tabs),
          newCurrentTab,
        );
      }

      // 4. Emit new state (UI updates immediately, not blocked by disk I/O)
      emit(
        state.copyWith(
          workspaces: updatedWorkspaces,
          activeWorkspaceId: event.targetWorkspaceId,
        ),
      );

      // 5. Save to repository
      await _repository.saveWorkspaces(
        updatedWorkspaces,
        event.targetWorkspaceId,
      );
    } catch (e) {
      emit(state.copyWith(error: 'Failed to switch workspace: $e'));
    }
  }

  Future<void> _onRenameWorkspace(
    RenameWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    try {
      final updatedWorkspaces = state.workspaces.map((w) {
        if (w.id == event.workspaceId) {
          return w.copyWith(name: event.newName);
        }
        return w;
      }).toList();

      await _repository.saveWorkspaces(
        updatedWorkspaces,
        state.activeWorkspaceId,
      );

      emit(state.copyWith(workspaces: updatedWorkspaces));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to rename workspace: $e'));
    }
  }

  Future<void> _onClearWorkspaces(
    ClearWorkspaces event,
    Emitter<WorkspaceState> emit,
  ) async {
    try {
      final defaultWorkspace = Workspace(
        name: "ברירת מחדל",
        tabs: _cloneTabs(event.currentTabs),
        activeTabIndex: event.currentTabIndex,
      );

      await _repository.saveWorkspaces([defaultWorkspace], defaultWorkspace.id);

      emit(
        state.copyWith(
          workspaces: [defaultWorkspace],
          activeWorkspaceId: defaultWorkspace.id,
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: 'Failed to clear workspaces: $e'));
    }
  }

  Future<void> _onUpdateCurrentWorkspaceTabs(
    UpdateCurrentWorkspaceTabs event,
    Emitter<WorkspaceState> emit,
  ) async {
    try {
      final currentId = state.activeWorkspaceId;
      if (currentId == null) return;

      final updatedWorkspaces = state.workspaces.map((w) {
        if (w.id == currentId) {
          return w.copyWith(
            tabs: _cloneTabs(event.tabs),
            activeTabIndex: event.activeTabIndex,
          );
        }
        return w;
      }).toList();

      await _repository.saveWorkspaces(updatedWorkspaces, currentId);
      emit(state.copyWith(workspaces: updatedWorkspaces));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to update workspace tabs: $e'));
    }
  }

  Future<void> _onMoveTabToWorkspace(
    MoveTabToWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    try {
      final currentId = state.activeWorkspaceId;
      if (currentId == null) return;

      // מעדכן את שני שולחנות העבודה:
      // 1. מסיר את הטאב משולחן העבודה הנוכחי
      // 2. מוסיף את הטאב לשולחן העבודה היעד
      final updatedWorkspaces = state.workspaces.map((w) {
        if (w.id == currentId) {
          // מסיר את הטאב משולחן העבודה הנוכחי
          return w.copyWith(
            tabs: _cloneTabs(event.currentTabs),
            activeTabIndex: event.currentTabIndex,
          );
        } else if (w.id == event.targetWorkspaceId) {
          // מוסיף את הטאב לשולחן העבודה היעד
          return w.copyWith(
            tabs: [..._cloneTabs(w.tabs), OpenedTab.from(event.tab)],
          );
        }
        return w;
      }).toList();

      await _repository.saveWorkspaces(updatedWorkspaces, currentId);
      emit(state.copyWith(workspaces: updatedWorkspaces));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to move tab to workspace: $e'));
    }
  }
}
