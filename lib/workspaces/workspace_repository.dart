import 'dart:async';
import 'dart:developer' as developer;
import 'package:hive_ce/hive.dart';
import 'package:otzaria/utils/file/hive_utils.dart';
import 'package:otzaria/workspaces/workspace.dart';

/// Repository for persisting and loading workspaces.
///
/// Uses Hive for local storage. Now stores active workspace by ID
/// instead of index for safer identification.
class WorkspaceRepository {
  static const String _boxName = 'workspaces';
  static const String _workspacesKey = 'key-workspaces';
  static const String _currentWorkspaceIdKey = 'key-current-workspace-id';
  // Legacy key - kept for migration
  static const String _legacyCurrentWorkspaceKey = 'key-current-workspace';

  Box _getBox() {
    return Hive.box(_boxName);
  }

  /// Loads all workspaces and returns tuple of (workspaces, activeWorkspaceId).
  ///
  /// Handles migration from old index-based storage to new ID-based storage.
  (List<Workspace>, String?) loadWorkspaces() {
    try {
      final box = _getBox();
      final rawWorkspaces = box.get(_workspacesKey, defaultValue: []) as List;

      // Decode each workspace independently so one bad entry doesn't lose all.
      // Keep the full decoded list (with nulls) so legacy-index migration can
      // map directly into the original positions — not into the filtered list.
      final decoded = rawWorkspaces.map((e) {
        try {
          return Workspace.fromJson(castMap(e));
        } catch (wsErr, wsSt) {
          developer.log(
            'Skipping corrupted workspace entry',
            error: wsErr,
            stackTrace: wsSt,
            name: 'WorkspaceRepository',
          );
          return null;
        }
      }).toList();

      final workspaces = decoded.whereType<Workspace>().toList();

      // Try new ID-based key first
      String? currentId = box.get(_currentWorkspaceIdKey) as String?;

      // If no ID stored, try to migrate from old index-based storage.
      // Use `decoded` (original positions) so corrupted entries before the
      // active workspace don't shift the index.
      if (currentId == null && workspaces.isNotEmpty) {
        final legacyIndex =
            box.get(_legacyCurrentWorkspaceKey, defaultValue: 0) as int;
        final workspaceAtLegacy =
            (legacyIndex >= 0 && legacyIndex < decoded.length)
            ? decoded[legacyIndex]
            : null;
        currentId = (workspaceAtLegacy ?? workspaces.first).id;
        unawaited(box.put(_currentWorkspaceIdKey, currentId));
      }

      // Validate that the ID exists in the list
      if (currentId != null && !workspaces.any((w) => w.id == currentId)) {
        currentId = workspaces.isNotEmpty ? workspaces.first.id : null;
      }

      return (workspaces, currentId);
    } catch (e, stackTrace) {
      developer.log(
        'Error loading workspaces from disk',
        error: e,
        stackTrace: stackTrace,
        name: 'WorkspaceRepository',
      );
      // Do NOT overwrite persisted data — leave raw data intact
      return (<Workspace>[], null);
    }
  }

  /// Saves workspaces and the active workspace ID.
  Future<void> saveWorkspaces(
    List<Workspace> workspaces,
    String? currentWorkspaceId,
  ) async {
    try {
      final box = _getBox();
      await box.put(
        _workspacesKey,
        workspaces.map((workspace) => workspace.toJson()).toList(),
      );
      if (currentWorkspaceId != null) {
        await box.put(_currentWorkspaceIdKey, currentWorkspaceId);
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error saving workspaces to disk',
        error: e,
        stackTrace: stackTrace,
        name: 'WorkspaceRepository',
      );
    }
  }
}
