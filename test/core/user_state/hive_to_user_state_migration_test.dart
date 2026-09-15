import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/user_state/hive_to_user_state_migration.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late UserStateDatabase db;
  late HiveToUserStateMigration migration;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_hive_migration_');
    Hive.init(tmp.path);
    db = UserStateDatabase.openAt(p.join(tmp.path, 'user_state.db'));
    migration = HiveToUserStateMigration(
      hiveRoot: tmp.path,
      database: db,
      lists: UserStateListStore(database: db),
      sessions: WindowSessionStore(database: db),
      reports: PendingReportStore(database: db),
    );
  });

  tearDown(() async {
    await Hive.close();
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> seedHive() async {
    final history = await Hive.openBox<dynamic>('history');
    await history.put('history', [
      {'title': 'בראשית', 'index': 3},
    ]);
    await history.close();

    final bookmarks = await Hive.openBox<dynamic>('bookmarks');
    await bookmarks.put('key-bookmarks', [
      {'title': 'סימניה'},
    ]);
    await bookmarks.put('key-bookmark-groups', [
      {'id': 'g1', 'name': 'קבוצה'},
    ]);
    await bookmarks.close();

    final tabs = await Hive.openBox<dynamic>('tabs');
    await tabs.put('key-tabs', [
      {'type': 'text', 'title': 'א'},
      {'type': 'text', 'title': 'ב'},
    ]);
    await tabs.put('key-current-tab', 1);
    await tabs.put('key-tabs-window-2', [
      {'type': 'text', 'title': 'יתום'},
    ]);
    await tabs.put('key-current-tab-window-2', 0);
    await tabs.close();

    final reports = await Hive.openBox<dynamic>('error_reports_queue');
    await reports.put('pending_reports', [
      {'error': 'x'},
      {'error': 'y'},
    ]);
    await reports.put('sent_reports', [
      {'error': 'z'},
    ]);
    await reports.close();
  }

  test('מעביר רשימות, סשנים ותורי דיווח ומסמן את הקבצים', () async {
    await seedHive();

    final migrated = await migration.run();
    expect(migrated, 4);

    final lists = UserStateListStore(database: db);
    expect(
      (await lists.read('history', 'history')).single['title'],
      'בראשית',
    );
    expect(await lists.read('bookmarks', 'key-bookmarks'), hasLength(1));
    expect(
      (await lists.read('bookmarks', 'key-bookmark-groups')).single['id'],
      'g1',
    );

    final sessions = WindowSessionStore(database: db);
    final main = (await sessions.load(UserStateSlot.single))!;
    expect(jsonDecode(main.tabsJson), hasLength(2));
    expect(main.currentIndex, 1);
    final orphan = (await sessions.load(2))!;
    expect((jsonDecode(orphan.tabsJson) as List).single['title'], 'יתום');

    final reports = PendingReportStore(database: db);
    expect(
      await reports.countByKind(
        HiveToUserStateMigration.reportKind(
          'error_reports_queue',
          'pending_reports',
        ),
      ),
      2,
    );
    expect(
      await reports.countByKind(
        HiveToUserStateMigration.reportKind(
          'error_reports_queue',
          'sent_reports',
        ),
      ),
      1,
    );

    expect(File(p.join(tmp.path, 'history.hive')).existsSync(), isFalse);
    expect(
      File(p.join(tmp.path, 'history.hive.migrated')).existsSync(),
      isTrue,
    );
    expect(File(p.join(tmp.path, 'tabs.hive.migrated')).existsSync(), isTrue);
  });

  test('אידמפוטנטי: ריצה שנייה אינה מעבירה דבר ואינה דורסת', () async {
    await seedHive();
    await migration.run();

    final lists = UserStateListStore(database: db);
    await lists.write('history', 'history', [
      {'title': 'חדש'},
    ]);

    expect(await migration.run(), 0);
    expect((await lists.read('history', 'history')).single['title'], 'חדש');
  });

  test('box קיים אך הרשימה כבר במסד — המסד מנצח', () async {
    final lists = UserStateListStore(database: db);
    await lists.write('history', 'history', [
      {'title': 'מהמסד'},
    ]);
    final history = await Hive.openBox<dynamic>('history');
    await history.put('history', [
      {'title': 'מה-Hive'},
    ]);
    await history.close();

    expect(await migration.run(), 1);
    expect(
      (await lists.read('history', 'history')).single['title'],
      'מהמסד',
    );
    expect(
      File(p.join(tmp.path, 'history.hive.migrated')).existsSync(),
      isTrue,
    );
  });

  test('ללא קובצי Hive — לא קורה דבר', () async {
    expect(await migration.run(), 0);
  });
}
