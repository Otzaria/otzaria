import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:path/path.dart' as p;

/// מעביר את נתוני המשתמש מ-Hive ל-`user_state.db` פעם אחת.
///
/// רץ בתהליך המארח לפני שה-blocs נבנים. אידמפוטנטי: box שהועבר מקבל את
/// הסיומת `.migrated` ואינו נפתח שוב, ורשימה שכבר קיימת במסד אינה נדרסת.
class HiveToUserStateMigration {
  HiveToUserStateMigration({
    required this.hiveRoot,
    UserStateDatabase? database,
    UserStateListStore? lists,
    WindowSessionStore? sessions,
    PendingReportStore? reports,
  }) : _database = database ?? UserStateDatabase.instance,
       _lists = lists ?? UserStateListStore.instance,
       _sessions = sessions ?? WindowSessionStore.instance,
       _reports = reports ?? PendingReportStore.instance;

  /// התיקייה שבה שוכנים קובצי ה-`.hive` של החלון הראשון.
  final String hiveRoot;

  final UserStateDatabase _database;
  final UserStateListStore _lists;
  final WindowSessionStore _sessions;
  final PendingReportStore _reports;

  static const String migratedSuffix = '.migrated';

  /// ה-boxes של רשימות: כל מפתח ב-box נכתב כרשימה תחת (box, key).
  static const List<String> listBoxes = ['history', 'bookmarks', 'workspaces'];

  static const String workspacesBox = 'workspaces';
  static const String workspacesKey = 'key-workspaces';
  static const String activeWorkspaceIdKey = 'key-current-workspace-id';
  static const String legacyActiveWorkspaceIndexKey = 'key-current-workspace';

  static const String tabsBox = 'tabs';
  static const String tabsKey = 'key-tabs';
  static const String currentTabKey = 'key-current-tab';

  /// תורי הדיווח: (box, מפתחות הרשימות) → `kind` = `<box>/<key>`.
  static const List<String> reportBoxes = [
    'error_reports_queue',
    'plugin_reports_queue',
  ];
  static const List<String> reportKeys = ['pending_reports', 'sent_reports'];

  static String reportKind(String box, String key) => '$box/$key';

  /// מחזיר כמה boxes הועברו בפועל.
  Future<int> run() async {
    await _database.database;
    var migrated = 0;
    for (final box in listBoxes) {
      if (await _migrateBox(box, _migrateListBox)) migrated++;
    }
    if (await _migrateBox(tabsBox, _migrateTabsBox)) migrated++;
    for (final box in reportBoxes) {
      if (await _migrateBox(box, _migrateReportBox)) migrated++;
    }
    return migrated;
  }

  Future<bool> _migrateBox(
    String name,
    Future<void> Function(Box<dynamic> box) migrate,
  ) async {
    final file = File(p.join(hiveRoot, '$name.hive'));
    if (!file.existsSync()) return false;
    Box<dynamic>? box;
    try {
      box = Hive.isBoxOpen(name)
          ? Hive.box<dynamic>(name)
          : await Hive.openBox<dynamic>(name, path: hiveRoot);
      await migrate(box);
      await box.close();
      _markMigrated(name);
      return true;
    } catch (e, stackTrace) {
      debugPrint('⚠️ migration of Hive box "$name" failed: $e\n$stackTrace');
      try {
        ErrorLogFile.append(
          title: 'Migration of Hive box "$name" to user_state.db failed',
          error: e,
          stackTrace: stackTrace,
        );
      } catch (_) {
        // הלוג הוא best-effort.
      }
      // box שאינו נפתח כלל לא ייפתח גם בהפעלה הבאה: מסומן כדי שלא ינוסה
      // לנצח, והקובץ נשאר לתיקון ידני.
      if (box == null) _rename(name, '.failed');
      return false;
    }
  }

  Future<void> _migrateListBox(Box<dynamic> box) async {
    for (final key in box.keys.whereType<String>()) {
      final value = box.get(key);
      if (value is! List) continue;
      await _writeListIfAbsent(box.name, key, value);
    }
    if (box.name == workspacesBox) await _migrateActiveWorkspace(box);
  }

  /// השולחן הפעיל של החלון הראשון: מזהה, או אינדקס מהמפתח הישן יותר.
  Future<void> _migrateActiveWorkspace(Box<dynamic> box) async {
    var id = box.get(activeWorkspaceIdKey);
    if (id is! String) {
      final index = box.get(legacyActiveWorkspaceIndexKey);
      final raw = box.get(workspacesKey);
      if (index is int && raw is List && index >= 0 && index < raw.length) {
        final entry = raw[index];
        if (entry is Map) id = entry['id'];
      }
    }
    if (id is! String) return;
    final existing = await _sessions.load(UserStateSlot.single);
    if (existing?.activeWorkspaceId != null) return;
    await _sessions.saveActiveWorkspace(UserStateSlot.single, id);
  }

  /// `key-tabs`/`key-current-tab` → משבצת החלון הראשון; `…-window-<slot>` →
  /// אותה משבצת (סשן יתום שההפעלה הבאה תאמץ). מפתח לא מוכר נשמר כרשימה.
  Future<void> _migrateTabsBox(Box<dynamic> box) async {
    final keys = box.keys.whereType<String>().toList();
    final slots = <int>{};
    for (final key in keys) {
      if (key == tabsKey) {
        slots.add(UserStateSlot.single);
      } else if (key.startsWith('$tabsKey-window-')) {
        final slot = int.tryParse(key.substring('$tabsKey-window-'.length));
        if (slot != null) slots.add(slot);
      }
    }
    for (final slot in slots) {
      final suffix = slot == UserStateSlot.single ? '' : '-window-$slot';
      final tabs = box.get('$tabsKey$suffix');
      final current = box.get('$currentTabKey$suffix');
      if (tabs is! List) continue;
      if (await _sessions.load(slot) != null) continue;
      await _sessions.save(
        slot,
        tabsJson: _encodeList(tabs),
        currentIndex: current is int ? current : 0,
      );
    }
    for (final key in keys) {
      final known =
          key == tabsKey ||
          key == currentTabKey ||
          key.startsWith('$tabsKey-window-') ||
          key.startsWith('$currentTabKey-window-');
      if (known) continue;
      final value = box.get(key);
      debugPrint('migration: unknown key "$key" in tabs box kept as list');
      await _writeListIfAbsent(box.name, key, value is List ? value : [value]);
    }
  }

  Future<void> _migrateReportBox(Box<dynamic> box) async {
    for (final key in reportKeys) {
      final value = box.get(key);
      if (value is! List) continue;
      final kind = reportKind(box.name, key);
      if (await _reports.countByKind(kind) > 0) continue;
      for (final item in value) {
        if (item is Map) {
          await _reports.add(kind, _stringKeyed(item));
        }
      }
    }
    final total = box.get(SentReportsCounter.defaultKey);
    if (total is int) {
      await _writeListIfAbsent(box.name, SentReportsCounter.defaultKey, [
        total,
      ]);
    }
  }

  Future<void> _writeListIfAbsent(
    String box,
    String key,
    List<dynamic> value,
  ) async {
    if ((await _lists.read(box, key)).isNotEmpty) return;
    await _lists.write(box, key, value.map(_plainJson).toList());
  }

  void _markMigrated(String name) => _rename(name, '.migrated');

  void _rename(String name, String suffix) {
    for (final ext in const ['.hive', '.lock']) {
      final file = File(p.join(hiveRoot, '$name$ext'));
      if (!file.existsSync()) continue;
      final target = '${file.path}$migratedSuffix';
      final existing = File(target);
      if (existing.existsSync()) existing.deleteSync();
      file.renameSync(target);
    }
  }

  static String _encodeList(List<dynamic> value) =>
      jsonEncode(value.map(_plainJson).toList());

  /// Hive מחזיר `Map<dynamic, dynamic>`; JSON דורש מפתחות מחרוזת.
  static Object? _plainJson(Object? value) {
    if (value is Map) return _stringKeyed(value);
    if (value is List) return value.map(_plainJson).toList();
    return value;
  }

  static Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> map) => {
    for (final e in map.entries) '${e.key}': _plainJson(e.value),
  };
}
