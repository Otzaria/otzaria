import 'dart:developer' as developer;

import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/data/repository/user_state_list_repository.dart';
import 'package:otzaria/workspaces/workspace.dart';

/// שמירה וטעינה של שולחנות העבודה.
///
/// **רשימת השולחנות משותפת** לכל החלונות — במסד מצב המשתמש.
///
/// **השולחן הפעיל הוא מצב פר-חלון**, ונשמר בסשן של החלון
/// (`window_sessions.active_workspace_id`). "על איזה שולחן אני עובד" הוא
/// בדיוק כמו "אילו כרטיסיות פתוחות לי".
class WorkspaceRepository {
  WorkspaceRepository({
    UserStateListStore? store,
    WindowSessionStore? sessions,
    int? Function()? slot,
  }) : _list = UserStateListRepository<Workspace>(
         boxName: boxName,
         key: workspacesKey,
         fromJson: Workspace.fromJson,
         toJson: (workspace) => workspace.toJson(),
         store: store,
       ),
       _sessions = sessions ?? WindowSessionStore.instance,
       _slot = slot ?? (() => UserStateSlot.current);

  static const String boxName = 'workspaces';
  static const String workspacesKey = 'key-workspaces';

  final UserStateListRepository<Workspace> _list;
  final WindowSessionStore _sessions;
  final int? Function() _slot;

  /// אות שרשימת השולחנות שונתה בחלון אחר.
  Stream<void> get remoteChanges => _list.remoteChanges;

  /// טוען את השולחנות ואת מזהה השולחן הפעיל של החלון הזה.
  ///
  /// ⚠️ כשל קריאה מתפשט ואינו הופך לרשימה ריקה: גיבוי שכתב `workspaces: []`
  /// בגלל קריאה שלא הצליחה נראה תקין, ושחזור ממנו מוחק את כל השולחנות.
  Future<(List<Workspace>, String?)> loadWorkspaces() async {
    final workspaces = await _list.load();
    try {
      final slot = _slot();
      var currentId = slot == null
          ? null
          : (await _sessions.load(slot))?.activeWorkspaceId;
      // חלון ללא שולחן פעיל מתחיל על הראשון; חלון חדש מקבל אחד רק כשהמשתמש
      // בוחר — כך שני חלונות אינם נועלים על אותו שולחן בלי כוונה.
      if (currentId != null && !workspaces.any((w) => w.id == currentId)) {
        currentId = workspaces.isEmpty ? null : workspaces.first.id;
      }
      return (workspaces, currentId);
    } catch (e, stackTrace) {
      developer.log(
        'Error resolving active workspace',
        error: e,
        stackTrace: stackTrace,
        name: 'WorkspaceRepository',
      );
      // הרשימה כן נטענה — רק זהות השולחן הפעיל אבדה.
      return (workspaces, null);
    }
  }

  /// מחיל [apply] על רשימת השולחנות **הטרייה** ושומר. מחזיר את מה שנשמר.
  ///
  /// ⚠️ [apply] חייב להיות טהור — חישוב מ-`state` בתוכו מחזיר בדיוק את
  /// הבאג שהוא בא למנוע.
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace> current) apply,
  ) => _list.mutate(apply);

  /// שומר את מזהה השולחן הפעיל **של החלון הזה**.
  Future<void> saveActiveWorkspaceId(String? id) async {
    final slot = _slot();
    if (id == null || slot == null) return;
    try {
      await _sessions.saveActiveWorkspace(slot, id);
    } catch (e, stackTrace) {
      developer.log(
        'Error saving active workspace id',
        error: e,
        stackTrace: stackTrace,
        name: 'WorkspaceRepository',
      );
    }
  }

  /// דריסה מוחלטת של רשימת השולחנות. שחזור מגיבוי בלבד.
  Future<void> replaceWorkspaces(
    List<Workspace> workspaces,
    String? currentWorkspaceId,
  ) async {
    await _list.overwrite(workspaces);
    await saveActiveWorkspaceId(currentWorkspaceId);
  }
}
