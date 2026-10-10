import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/workspaces/workspace.dart';

/// State for the WorkspaceBloc.
///
/// Uses [activeWorkspaceId] instead of index for safer workspace identification.
class WorkspaceState extends Equatable {
  final List<Workspace> workspaces;
  final bool isLoading;
  final String? error;

  /// The ID of the currently active workspace (instead of index)
  final String? activeWorkspaceId;

  const WorkspaceState({
    required this.workspaces,
    this.isLoading = false,
    this.error,
    this.activeWorkspaceId,
  });

  factory WorkspaceState.initial() {
    return const WorkspaceState(
      workspaces: [],
      isLoading: true,
      error: null,
      activeWorkspaceId: null,
    );
  }

  /// Returns the currently active workspace, or null if none.
  Workspace? get activeWorkspace {
    if (activeWorkspaceId == null) return null;
    try {
      return workspaces.firstWhere((w) => w.id == activeWorkspaceId);
    } catch (_) {
      return null;
    }
  }

  /// הכרטיסיות של [workspace] כפי שהן כעת. בשולחן הפעיל הן חיות ב-TabsBloc
  /// ונשמרות לשולחן רק ביציאה ממנו, ולכן [liveTabs] גובר על העותק השמור.
  List<OpenedTab> tabsOf(Workspace workspace, List<OpenedTab> liveTabs) =>
      workspace.id == activeWorkspaceId ? liveTabs : workspace.tabs;

  /// ⚠️ [clearError] ו-[clearActiveWorkspaceId] הם הדרך היחידה לאפס שדה:
  /// `null` בפרמטר פירושו "אל תיגע", ובלעדיהם כל `emit` מחק את השגיאה.
  WorkspaceState copyWith({
    List<Workspace>? workspaces,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? activeWorkspaceId,
    bool clearActiveWorkspaceId = false,
  }) {
    return WorkspaceState(
      workspaces: workspaces ?? this.workspaces,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      activeWorkspaceId: clearActiveWorkspaceId
          ? null
          : (activeWorkspaceId ?? this.activeWorkspaceId),
    );
  }

  @override
  List<Object?> get props => [workspaces, isLoading, error, activeWorkspaceId];
}
