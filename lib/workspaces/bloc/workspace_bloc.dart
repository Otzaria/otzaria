import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/window_role.dart';
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
  ///
  /// [activePane] הוא צד החלונית הפעילה בטאב שב-[activeIndex]
  /// (`'right'`/`'left'`), או `null` כשהטאב אינו מפוצל.
  final FutureOr<void> Function(
    List<OpenedTab> tabs,
    int activeIndex,
    String? activePane,
  )?
  onWorkspaceTabsChanged;

  List<OpenedTab> _cloneTabs(List<OpenedTab> tabs) {
    return tabs.map(OpenedTab.from).toList(growable: false);
  }

  /// חלון אחר שינה את רשימת השולחנות — העותק שבזיכרון התיישן.
  ///
  /// ⚠️ בלי המנוי הרשימה כאן נשארה כפי שנטענה: שולחן שנוסף בחלון אחר לא
  /// הופיע בתפריט, ושולחן שנמחק שם עוד הוצג ולחיצה עליו זרקה.
  StreamSubscription<void>? _remoteChanges;

  WorkspaceBloc({
    required this._repository,
    this.onWorkspaceTabsChanged,
  }) : super(WorkspaceState.initial()) {
    _remoteChanges = _repository.remoteChanges.listen((_) {
      if (!isClosed) add(LoadWorkspaces());
    });
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

  @override
  Future<void> close() {
    _remoteChanges?.cancel();
    return super.close();
  }

  Future<void> _onLoadWorkspaces(
    LoadWorkspaces event,
    Emitter<WorkspaceState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final (workspaces, activeId) = await _repository.loadWorkspaces();

      List<Workspace> finalWorkspaces = List.from(workspaces);
      String? finalActiveId = activeId;

      // Create default workspace if none exist
      if (finalWorkspaces.isEmpty) {
        final defaultWorkspace = Workspace(
          name: "שולחן עבודה 1",
          tabs: [],
          activeTabIndex: 0,
        );
        // ⚠️ נוצר רק אם הרשימה עדיין ריקה אצל הבעלים. בלי התנאי, חלון
        // שני שנפתח בזמן שהראשון עוד טוען היה מוסיף "שולחן עבודה 1" שני.
        finalWorkspaces = await _repository.mutateWorkspaces(
          (current) => current.isEmpty ? [defaultWorkspace] : current,
        );
        // ⚠️ חלון משני מתחיל **בלי** שולחן פעיל — ראו
        // [WorkspaceRepository.loadWorkspaces]. במרוץ עם הבעלים ה-`mutate`
        // מחזיר את השולחנות **שלו**, וקיבוע כאן היה נועל את שני החלונות על
        // אותו שולחן — ואז כל החלפה דורסת את ה-stash של השני.
        if (!WindowRole.isSecondary) {
          finalActiveId = finalWorkspaces.first.id;
          await _repository.saveActiveWorkspaceId(finalActiveId);
        }
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
          clearActiveWorkspaceId: finalActiveId == null,
          isLoading: false,
          clearError: true,
        ),
      );
    } catch (e) {
      UiSnack.showError(NotesMessages.workspacesLoadFailed);
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
        activePane: event.activePane,
      );

      final saved = await _repository.mutateWorkspaces(
        (current) => [...current, newWorkspace],
      );

      emit(state.copyWith(workspaces: saved, clearError: true));
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed);
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
        UiSnack.showError(NotesMessages.cannotDeleteActiveWorkspace);
        emit(
          state.copyWith(error: NotesMessages.cannotDeleteActiveWorkspace),
        );
        return;
      }

      final saved = await _repository.mutateWorkspaces(
        (current) => current.where((w) => w.id != event.workspaceId).toList(),
      );

      emit(state.copyWith(workspaces: saved, clearError: true));
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed);
      emit(state.copyWith(error: 'Failed to remove workspace: $e'));
    }
  }

  Future<void> _onSwitchToWorkspace(
    SwitchToWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    // 1. Save current tabs to the currently active workspace
    final currentId = state.activeWorkspaceId;
    List<Workspace> stash(List<Workspace> current) => current.map((w) {
      if (w.id == currentId) {
        return w.withTabs(
          tabs: _cloneTabs(event.currentTabsToSave),
          activeTabIndex: event.currentTabIndexToSave,
          activePane: event.currentActivePaneToSave,
        );
      }
      return w;
    }).toList();

    // ⚠️ **השמירה קודמת לחשיפה.** החלפת הכרטיסיות החיות משחררת את הכרטיסיות
    // של השולחן הנעזב, ולכן כשל שמירה אחריה מוחק אותן לצמיתות.
    final List<Workspace> saved;
    try {
      saved = await _repository.mutateWorkspaces(stash);
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSwitchFailed);
      emit(state.copyWith(error: 'Failed to switch workspace: $e'));
      return;
    }

    try {
      // 2. Get the target workspace, from the authoritative list.
      //
      // ⚠️ `firstWhereOrNull`: השולחן יכול להיעלם בין בניית התפריט
      // לבחירה, אם חלון אחר מחק אותו. `firstWhere` זרק `StateError`.
      final targetWorkspace = saved.firstWhereOrNull(
        (w) => w.id == event.targetWorkspaceId,
      );
      if (targetWorkspace == null) {
        UiSnack.showError(LibraryMessages.workspaceNoLongerExists);
        emit(state.copyWith(workspaces: saved, clearError: true));
        return;
      }

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
          // הצד תקף רק כשהאינדקס שנשמר הוא זה שנפתח בפועל; אחרת הוא
          // מתייחס לטאב אחר לגמרי.
          newCurrentTab == targetWorkspace.activeTabIndex
              ? targetWorkspace.activePane
              : null,
        );
      }

      await _repository.saveActiveWorkspaceId(event.targetWorkspaceId);
      emit(
        state.copyWith(
          workspaces: saved,
          activeWorkspaceId: event.targetWorkspaceId,
          clearError: true,
        ),
      );
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSwitchFailed);
      emit(
        state.copyWith(
          workspaces: saved,
          error: 'Failed to switch workspace: $e',
        ),
      );
    }
  }

  Future<void> _onRenameWorkspace(
    RenameWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    try {
      final saved = await _repository.mutateWorkspaces(
        (current) => current
            .map(
              (w) => w.id == event.workspaceId
                  ? w.copyWith(name: event.newName)
                  : w,
            )
            .toList(),
      );

      emit(state.copyWith(workspaces: saved, clearError: true));
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed);
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
        activePane: event.activePane,
      );

      // "מחק את כל השולחנות" פירושו הכול, גם מה שחלון אחר הוסיף.
      final saved = await _repository.mutateWorkspaces(
        (_) => [defaultWorkspace],
      );
      await _repository.saveActiveWorkspaceId(defaultWorkspace.id);

      emit(
        state.copyWith(
          workspaces: saved,
          activeWorkspaceId: defaultWorkspace.id,
          clearError: true,
        ),
      );
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed);
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

      final saved = await _repository.mutateWorkspaces(
        (current) => current.map((w) {
          if (w.id == currentId) {
            return w.withTabs(
              tabs: _cloneTabs(event.tabs),
              activeTabIndex: event.activeTabIndex,
              activePane: event.activePane,
            );
          }
          return w;
        }).toList(),
      );
      emit(state.copyWith(workspaces: saved, clearError: true));
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed);
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
      final saved = await _repository.mutateWorkspaces(
        (current) => current.map((w) {
          if (w.id == currentId) {
            // מסיר את הטאב משולחן העבודה הנוכחי
            return w.withTabs(
              tabs: _cloneTabs(event.currentTabs),
              activeTabIndex: event.currentTabIndex,
              activePane: event.currentActivePane,
            );
          } else if (w.id == event.targetWorkspaceId) {
            // מוסיף את הטאב לשולחן העבודה היעד
            return w.copyWith(
              tabs: [..._cloneTabs(w.tabs), OpenedTab.from(event.tab)],
            );
          }
          return w;
        }).toList(),
      );
      emit(state.copyWith(workspaces: saved, clearError: true));
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed);
      emit(state.copyWith(error: 'Failed to move tab to workspace: $e'));
    }
  }
}
