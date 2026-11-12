import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// מנהל שולחנות עבודה; ה-UI מוסר את הכרטיסיות החיות ומחליף אותן בעת מעבר.
class WorkspaceBloc extends Bloc<WorkspaceEvent, WorkspaceState> {
  final WorkspaceRepository _repository;
  final AppWindowKeys _windowKeys;
  int _pendingTabChanges = 0;

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

  @override
  void add(WorkspaceEvent event) {
    final changesTabs =
        event is SwitchToWorkspace || event is MoveTabsToWorkspace;
    if (!changesTabs || isClosed) {
      super.add(event);
      return;
    }
    // גם פעולה שממתינה מאחורי I/O אחר מונעת צילום של הטאבים שלפני השינוי.
    _pendingTabChanges++;
    // ignore: invalid_use_of_visible_for_testing_member
    super.emit(state.copyWith(isChangingTabs: true));
    try {
      super.add(event);
    } catch (_) {
      _pendingTabChanges--;
      // ignore: invalid_use_of_visible_for_testing_member
      super.emit(state.copyWith(isChangingTabs: _pendingTabChanges > 0));
      rethrow;
    }
  }

  void _finishTabChange(Emitter<WorkspaceState> emit) {
    _pendingTabChanges--;
    emit(state.copyWith(isChangingTabs: _pendingTabChanges > 0));
  }

  /// חלון אחר שינה את רשימת השולחנות — העותק שבזיכרון התיישן.
  ///
  /// ⚠️ בלי המנוי הרשימה כאן נשארה כפי שנטענה: שולחן שנוסף בחלון אחר לא
  /// הופיע בתפריט, ושולחן שנמחק שם עוד הוצג ולחיצה עליו זרקה.
  StreamSubscription<void>? _remoteChanges;

  /// האם חלון מוצג אחר עומד על השולחן; null — חלון יחיד, בלי אזהרה.
  final bool Function(String workspaceId)? isOpenInOtherWindow;

  WorkspaceBloc({
    required this._repository,
    this.onWorkspaceTabsChanged,
    this.isOpenInOtherWindow,
    AppWindowKeys? windowKeys,
  }) : _windowKeys = windowKeys ?? AppWindowKeys.current,
       super(WorkspaceState.initial()) {
    _remoteChanges = _repository.remoteChanges.listen((_) {
      if (!isClosed) add(LoadWorkspaces());
    });
    // sequential חל על on יחיד; כל סוגי האירועים חולקים תור כדי שטעינה
    // שמסתיימת מאוחר לא תדרוס כתיבה שכבר הסתיימה.
    on<WorkspaceEvent>((event, emit) async {
      if (event is LoadWorkspaces) {
        await _onLoadWorkspaces(event, emit);
      } else if (event is AddWorkspace) {
        await _onAddWorkspace(event, emit);
      } else if (event is RemoveWorkspace) {
        await _onRemoveWorkspace(event, emit);
      } else if (event is SwitchToWorkspace) {
        await _onSwitchToWorkspace(event, emit);
      } else if (event is RenameWorkspace) {
        await _onRenameWorkspace(event, emit);
      } else if (event is UpdateCurrentWorkspaceTabs) {
        await _onUpdateCurrentWorkspaceTabs(event, emit);
      } else if (event is MoveTabsToWorkspace) {
        await _onMoveTabsToWorkspace(event, emit);
      } else if (event is SetWorkspacePinned) {
        await _onSetWorkspacePinned(event, emit);
      }
    }, transformer: sequential());
  }

  /// שולחן שחלון אחר עומד עליו: שני חלונות דורסים זה לזה את ה-stash, ולכן
  /// מזהירים — אבל לא חוסמים; זו בחירה של המשתמש.
  void _warnIfOpenElsewhere(String workspaceId) {
    final check = isOpenInOtherWindow;
    if (check != null && check(workspaceId)) {
      UiSnack.show(
        WindowMessages.workspaceOpenInOtherWindow,
        window: _windowKeys,
      );
    }
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
        // ⚠️ במרוץ עם חלון אחר ה-`mutate` מחזיר את השולחנות **שלו**; לכן
        // הראשון נבחר רק אם השולחן שנוצר כאן הוא זה שברשימה.
        if (finalWorkspaces.first.id == defaultWorkspace.id) {
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
      UiSnack.showError(
        NotesMessages.workspacesLoadFailed,
        window: _windowKeys,
      );
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

      final saved = await _repository.mutateWorkspaces(
        (current) => [...current, newWorkspace],
      );

      emit(state.copyWith(workspaces: saved, clearError: true));
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed, window: _windowKeys);
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
        UiSnack.showError(
          NotesMessages.cannotDeleteActiveWorkspace,
          window: _windowKeys,
        );
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
      UiSnack.showError(NotesMessages.workspaceSaveFailed, window: _windowKeys);
      emit(state.copyWith(error: 'Failed to remove workspace: $e'));
    }
  }

  Future<void> _onSwitchToWorkspace(
    SwitchToWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    List<Workspace>? saved;
    List<OpenedTab>? sourceTabs;
    var sourceSaved = false;
    bool? hasTabs;
    try {
      if (event.sourceWorkspaceId != state.activeWorkspaceId) return;
      emit(state.copyWith(clearError: true));
      final currentId = event.sourceWorkspaceId;
      final currentTabs = event.readCurrentTabs();
      final snapshotTabs = _cloneTabs(currentTabs.tabs);
      sourceTabs = snapshotTabs;
      List<Workspace> stash(List<Workspace> current) {
        if (!current.any((w) => w.id == event.targetWorkspaceId)) {
          return current;
        }
        // גם מקור שנמחק בחלון אחר נחשב לחלון בלי שולחן: שומרים לפני ההחלפה.
        if (currentId == null || !current.any((w) => w.id == currentId)) {
          if (snapshotTabs.isEmpty) return current;
          sourceSaved = true;
          return [
            ...current,
            Workspace(
              name: uniqueWorkspaceName(current),
              tabs: snapshotTabs,
              activeTabIndex: currentTabs.activeTabIndex,
              activePane: currentTabs.activePane,
            ),
          ];
        }
        return current.map((w) {
          if (w.id == currentId && !w.isPinned) {
            sourceSaved = true;
            return w.withTabs(
              tabs: snapshotTabs,
              activeTabIndex: currentTabs.activeTabIndex,
              activePane: currentTabs.activePane,
            );
          }
          return w;
        }).toList();
      }

      // החלפת הכרטיסיות משחררת את הקודמות; כשל שמירה חייב להקדים אותה.
      saved = await _repository.mutateWorkspaces(stash);
      // 2. Get the target workspace, from the authoritative list.
      //
      // ⚠️ `firstWhereOrNull`: השולחן יכול להיעלם בין בניית התפריט
      // לבחירה, אם חלון אחר מחק אותו. `firstWhere` זרק `StateError`.
      final targetWorkspace = saved.firstWhereOrNull(
        (w) => w.id == event.targetWorkspaceId,
      );
      if (targetWorkspace == null) {
        UiSnack.showError(
          LibraryMessages.workspaceNoLongerExists,
          window: _windowKeys,
        );
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

      emit(
        state.copyWith(
          workspaces: saved,
          activeWorkspaceId: event.targetWorkspaceId,
          clearError: true,
        ),
      );
      await _repository.saveActiveWorkspaceId(event.targetWorkspaceId);
      _warnIfOpenElsewhere(event.targetWorkspaceId);
      hasTabs = targetWorkspace.tabs.isNotEmpty;
    } catch (e) {
      UiSnack.showError(
        NotesMessages.workspaceSwitchFailed,
        window: _windowKeys,
      );
      emit(
        state.copyWith(
          workspaces: saved,
          error: 'Failed to switch workspace: $e',
        ),
      );
    } finally {
      if (saved == null || !sourceSaved) {
        for (final tab in sourceTabs ?? <OpenedTab>[]) {
          tab.dispose();
        }
      }
      _finishTabChange(emit);
      event.onCompleted?.call(hasTabs);
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
      UiSnack.showError(NotesMessages.workspaceSaveFailed, window: _windowKeys);
      emit(state.copyWith(error: 'Failed to rename workspace: $e'));
    }
  }

  Future<void> _onUpdateCurrentWorkspaceTabs(
    UpdateCurrentWorkspaceTabs event,
    Emitter<WorkspaceState> emit,
  ) async {
    var updated = false;
    var completed = false;
    try {
      final currentId = event.sourceWorkspaceId;
      if (currentId == null) return;

      final saved = await _repository.mutateWorkspaces(
        (current) => current.map((w) {
          if (w.id == currentId) {
            updated = true;
            return w.withTabs(
              tabs: event.restoreTabs(),
              activeTabIndex: event.activeTabIndex,
              activePane: event.activePane,
            );
          }
          return w;
        }).toList(),
      );
      emit(state.copyWith(workspaces: saved, clearError: true));
      completed = updated;
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed, window: _windowKeys);
      emit(state.copyWith(error: 'Failed to update workspace tabs: $e'));
    } finally {
      event.onCompleted?.call(completed);
    }
  }

  Future<void> _onSetWorkspacePinned(
    SetWorkspacePinned event,
    Emitter<WorkspaceState> emit,
  ) async {
    var updated = false;
    var completed = false;
    try {
      final saved = await _repository.mutateWorkspaces(
        (current) => current.map((w) {
          if (w.id != event.workspaceId) return w;
          updated = true;
          final tabs = event.restoreTabsToSave();
          final snapshot = tabs == null
              ? w
              : w.withTabs(
                  tabs: tabs,
                  activeTabIndex: event.tabIndexToSave,
                  activePane: event.activePaneToSave,
                );
          return snapshot.copyWith(isPinned: event.isPinned);
        }).toList(),
      );
      emit(state.copyWith(workspaces: saved, clearError: true));
      completed = updated;
    } catch (e) {
      UiSnack.showError(NotesMessages.workspaceSaveFailed, window: _windowKeys);
      emit(state.copyWith(error: 'Failed to pin workspace: $e'));
    } finally {
      event.onCompleted?.call(completed);
    }
  }

  Future<void> _onMoveTabsToWorkspace(
    MoveTabsToWorkspace event,
    Emitter<WorkspaceState> emit,
  ) async {
    var moved = false;
    var targetUpdated = false;
    var sourceSaved = false;
    List<Workspace>? saved;
    List<OpenedTab>? sourceTabs;
    List<OpenedTab>? movedTabs;
    try {
      final currentId = event.sourceWorkspaceId;
      if (currentId != state.activeWorkspaceId ||
          currentId == event.targetWorkspaceId ||
          event.tabs.isEmpty) {
        return;
      }
      final live = event.readCurrentTabs();
      final selected = event.tabs.toSet();
      if (!live.tabs.toSet().containsAll(selected)) return;
      emit(state.copyWith(clearError: true));
      final remaining = live.tabs
          .where((tab) => !selected.contains(tab))
          .toList();
      final removedBefore = live.tabs
          .take(live.activeTabIndex)
          .where(selected.contains)
          .length;
      final activeIndex = remaining.isEmpty
          ? 0
          : (live.activeTabIndex - removedBefore).clamp(
              0,
              remaining.length - 1,
            );
      final previousActive = live.tabs.elementAtOrNull(live.activeTabIndex);
      final nextActive = remaining.elementAtOrNull(activeIndex);
      final activePane = identical(previousActive, nextActive)
          ? live.activePane
          : null;
      sourceTabs = _cloneTabs(remaining);
      movedTabs = _cloneTabs(event.tabs);

      saved = await _repository.mutateWorkspaces((current) {
        if (!current.any((w) => w.id == event.targetWorkspaceId) ||
            (currentId != null && !current.any((w) => w.id == currentId))) {
          return current;
        }
        targetUpdated = true;
        return current.map((w) {
          if (w.id == currentId && !w.isPinned) {
            sourceSaved = true;
            return w.withTabs(
              tabs: sourceTabs!,
              activeTabIndex: activeIndex,
              activePane: activePane,
            );
          }
          if (w.id == event.targetWorkspaceId) {
            return w.copyWith(tabs: [..._cloneTabs(w.tabs), ...movedTabs!]);
          }
          return w;
        }).toList();
      });
      emit(state.copyWith(workspaces: saved, clearError: true));
      if (targetUpdated) {
        await event.onTabsMoved?.call();
        moved = true;
      } else {
        UiSnack.showError(
          LibraryMessages.workspaceNoLongerExists,
          window: _windowKeys,
        );
      }
    } catch (e) {
      moved = false;
      UiSnack.showError(NotesMessages.workspaceSaveFailed, window: _windowKeys);
      emit(state.copyWith(error: 'Failed to move tab to workspace: $e'));
    } finally {
      if (saved == null || !sourceSaved) {
        for (final tab in sourceTabs ?? <OpenedTab>[]) {
          tab.dispose();
        }
      }
      if (saved == null || !targetUpdated) {
        for (final tab in movedTabs ?? <OpenedTab>[]) {
          tab.dispose();
        }
      }
      _finishTabChange(emit);
      event.onCompleted?.call(moved);
    }
  }
}
