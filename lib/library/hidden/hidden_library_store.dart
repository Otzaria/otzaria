import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// שמירה וטעינה של ההסתרות ב-`app_preferences`, הנכלל בגיבוי ההגדרות.
class HiddenLibraryStore {
  static final StreamController<HiddenLibrarySelection> _changes =
      StreamController<HiddenLibrarySelection>.broadcast(sync: true);

  /// בחירה שנשמרה (בכל חלון), אחרי ששני המפתחות נכתבו.
  Stream<HiddenLibrarySelection> get changes => _changes.stream;

  static final Stream<void> _visibilityChanges = _changes.stream.map((_) {});

  /// כמו [changes], בלי הבחירה עצמה.
  Stream<void> get visibilityChanges => _visibilityChanges;

  /// המפתחות מוצהרים ב-[SettingsRepository] ונמצאים ב-`allKeys`, כדי
  /// שהגיבוי יתפוס אותם גם במסלול הנסיגה שבו Hive אינו פתוח ונאספת רשימת
  /// המפתחות המוצהרת בלבד.
  static const String bookKeysSetting = SettingsRepository.keyHiddenBookKeys;
  static const String categoryPathsSetting =
      SettingsRepository.keyHiddenCategoryPaths;
  static const String pendingIndexReconciliationSetting =
      'pending-hidden-index-reconciliation';
  static const String pendingVisibilityIndexSetting =
      'pending-visibility-index-reconciliation';
  static int _visibilityRevision = 0;
  static bool _visibilityWorkFailed = false;
  static final Set<int> _visibilityWorkInFlight = {};
  // תור נפרד: פעולה ב-[HiddenLibraryUpdateQueue.instance] ממתינה לכתיבות האלה.
  static final _markerWrites = HiddenLibraryUpdateQueue();

  const HiddenLibraryStore();

  bool get hasPendingIndexReconciliation {
    try {
      return Settings.getValue<bool>(pendingIndexReconciliationSetting) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markIndexReconciliationPending() => Settings.setValue<bool>(
    pendingIndexReconciliationSetting,
    true,
  );

  Future<void> clearPendingIndexReconciliation() => Settings.setValue<bool>(
    pendingIndexReconciliationSetting,
    false,
  );

  bool get hasPendingVisibilityIndex {
    try {
      return Settings.getValue<bool>(pendingVisibilityIndexSetting) ?? false;
    } catch (_) {
      return false;
    }
  }

  int get visibilityRevision => _visibilityRevision;

  Future<int> beginVisibilityIndexUpdate() => _markerWrites.run(() async {
    final revision = ++_visibilityRevision;
    await Settings.setValue<bool>(pendingVisibilityIndexSetting, true);
    _visibilityWorkInFlight.add(revision);
    return revision;
  });

  Future<void> completeVisibilityIndexUpdate(int revision, bool success) =>
      _markerWrites.run(() async {
        if (!_visibilityWorkInFlight.remove(revision)) return;
        if (!success) _visibilityWorkFailed = true;
        if (success &&
            !_visibilityWorkFailed &&
            _visibilityWorkInFlight.isEmpty &&
            revision == _visibilityRevision) {
          await Settings.setValue<bool>(pendingVisibilityIndexSetting, false);
        }
      });

  Future<void> resetRuntimeStateForAppRestart() => _markerWrites.run(() async {
    ++_visibilityRevision;
    _visibilityWorkInFlight.clear();
    _visibilityWorkFailed = false;
  });

  Future<void> clearPendingVisibilityIndex(int revision) =>
      _markerWrites.run(() async {
        if (revision != _visibilityRevision ||
            _visibilityWorkInFlight.isNotEmpty) {
          return;
        }
        await Settings.setValue<bool>(pendingVisibilityIndexSetting, false);
        _visibilityWorkFailed = false;
      });

  HiddenLibrarySelection load() => HiddenLibrarySelection(
    bookKeys: _readSet(bookKeysSetting),
    categoryPaths: _readSet(categoryPathsSetting),
  );

  Future<void> save(HiddenLibrarySelection selection) async {
    final before = load();
    try {
      await Settings.setValue<String>(
        bookKeysSetting,
        jsonEncode(selection.bookKeys.toList()..sort()),
      );
      await Settings.setValue<String>(
        categoryPathsSetting,
        jsonEncode(selection.categoryPaths.toList()..sort()),
      );
    } finally {
      final actual = load();
      if (actual != before) _changes.add(actual);
    }
  }

  /// מחזיר את המצב שנשמר בפועל גם כשכתיבת המפתח השני נכשלת.
  Future<({HiddenLibrarySelection actual, Object? error})> saveAndRead(
    HiddenLibrarySelection selection,
  ) async {
    Object? error;
    try {
      await save(selection);
    } catch (caught) {
      error = caught;
    }
    return (actual: load(), error: error);
  }

  /// ערך פגום או הגדרות שטרם אותחלו אינם מפילים את מסך הספרייה — במקרה כזה
  /// אין הסתרות, וזו ברירת המחדל הבטוחה: ספר מוצג ולא נעלם בשקט.
  Set<String> _readSet(String key) {
    final String? raw;
    try {
      raw = Settings.getValue<String>(key);
    } catch (error) {
      debugPrint('[HiddenLibrary] settings unavailable for $key: $error');
      return const {};
    }
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return decoded
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (error) {
      debugPrint('[HiddenLibrary] corrupt value for $key: $error');
      return const {};
    }
  }
}
