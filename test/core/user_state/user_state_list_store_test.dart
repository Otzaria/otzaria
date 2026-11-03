import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/data/repository/user_state_list_repository.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otzaria_user_state_');
    dbPath = '${tmp.path}${Platform.pathSeparator}user_state.db';
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('WAL עם synchronous=NORMAL, busy_timeout נשאר 1000', () async {
    final db = UserStateDatabase.openAt(dbPath);
    final conn = await db.database;
    expect(conn.select('PRAGMA journal_mode').first.values.first, 'wal');
    expect(conn.select('PRAGMA synchronous').first.values.first, 1);
    expect(conn.select('PRAGMA busy_timeout').first.values.first, 1000);
    db.close();
  });

  test('קריאה של מפתח שאינו קיים מחזירה רשימה ריקה', () async {
    final db = UserStateDatabase.openAt(dbPath);
    final store = UserStateListStore(database: db);
    expect(await store.read('history', 'history'), isEmpty);
    db.close();
  });

  test('כתיבה, קריאה, מוטציה וניקוי', () async {
    final db = UserStateDatabase.openAt(dbPath);
    final store = UserStateListStore(database: db);

    await store.write('bookmarks', 'key-bookmarks', [
      {'title': 'א'},
    ]);
    expect(await store.read('bookmarks', 'key-bookmarks'), hasLength(1));

    final result = await store.mutate(
      'bookmarks',
      'key-bookmarks',
      (current) => [
        ...current,
        {'title': 'ב'},
      ],
    );
    expect(result, hasLength(2));
    expect(await store.read('bookmarks', 'key-bookmarks'), hasLength(2));

    await store.clear('bookmarks', 'key-bookmarks');
    expect(await store.read('bookmarks', 'key-bookmarks'), isEmpty);
    db.close();
  });

  test('שני חיבורים לאותו קובץ — אף עדכון אינו אובד', () async {
    // שני "חלונות": כל אחד עם חיבור משלו, כותבים לסירוגין לאותה רשימה.
    final dbA = UserStateDatabase.openAt(dbPath);
    final dbB = UserStateDatabase.openAt(dbPath);
    final a = UserStateListStore(database: dbA);
    final b = UserStateListStore(database: dbB);

    for (var i = 0; i < 20; i++) {
      final store = i.isEven ? a : b;
      await store.mutate(
        'history',
        'history',
        (current) => [...current, i],
      );
    }

    final fromA = await a.read('history', 'history');
    final fromB = await b.read('history', 'history');
    expect(fromA, List<int>.generate(20, (i) => i));
    expect(fromB, fromA);
    dbA.close();
    dbB.close();
  });

  group('חלונות Dart באותו isolate', () {
    UserStateListRepository<int> repo(UserStateListStore store) =>
        UserStateListRepository<int>(
          boxName: 'history',
          key: 'history',
          fromJson: (json) => json['v'] as int,
          toJson: (value) => {'v': value},
          store: store,
        );

    test('כתיבה בחלון אחד מגיעה לשני, ולא לכותב עצמו', () async {
      final db = UserStateDatabase.openAt(dbPath);
      final store = UserStateListStore(database: db);
      final a = repo(store);
      final b = repo(store);
      var seenByA = 0;
      var seenByB = 0;
      final subA = a.remoteChanges.listen((_) => seenByA++);
      final subB = b.remoteChanges.listen((_) => seenByB++);
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);

      await a.mutate((current) => [...current, 1]);
      await a.overwrite([2]);
      await a.clear();
      // כתיבה שאינה של אף חלון (למשל שחזור גיבוי) מגיעה לכולם.
      await store.write('history', 'history', const []);
      await Future<void>.delayed(Duration.zero);

      expect(seenByA, 1);
      expect(seenByB, 4);
      db.close();
    });
  });

  group('פענוח רשימה גדולה (#3380)', () {
    // הערך המפוענח הוא שם ה-isolate שבו רץ fromJson.
    UserStateListRepository<String> repo(
      UserStateListStore store, {
      required bool background,
    }) => UserStateListRepository<String>(
      boxName: 'history',
      key: 'history',
      fromJson: (json) => '${json['v']}@${Isolate.current.debugName}',
      toJson: (value) => {'v': value},
      decodeInBackground: background,
      store: store,
    );

    List<Map<String, Object?>> entries(int count) => [
      for (var i = 0; i < count; i++) {'v': i, 'pad': 'א' * 100},
    ];

    test('רשימה גדולה מפוענחת מחוץ ל-isolate הנוכחי', () async {
      final db = UserStateDatabase.openAt(dbPath);
      final store = UserStateListStore(database: db);
      await store.write('history', 'history', entries(2000));

      final here = Isolate.current.debugName;
      final loaded = await repo(store, background: true).load();
      expect(loaded, hasLength(2000));
      expect(loaded.first, startsWith('0@'));
      expect(loaded.first, isNot('0@$here'));

      final inline = await repo(store, background: false).load();
      expect(inline.first, '0@$here');
      db.close();
    });

    test('רשימה קטנה נשארת בפענוח מקומי', () async {
      final db = UserStateDatabase.openAt(dbPath);
      final store = UserStateListStore(database: db);
      await store.write('history', 'history', entries(3));

      final loaded = await repo(store, background: true).load();
      expect(loaded.first, '0@${Isolate.current.debugName}');
      db.close();
    });

    test('היסטוריה גדולה נטענת ב-isolate, ורשומה פגומה נשמרת', () async {
      final db = UserStateDatabase.openAt(dbPath);
      final store = UserStateListStore(database: db);
      final book = TextBook(title: 'משנה ברורה', heCategories: 'א' * 300);
      await store.write('history', 'history', [
        for (var i = 0; i < 200; i++)
          Bookmark(ref: 'משנה ברורה $i', book: book, index: i).toJson(),
        {'broken': true},
      ]);

      final history = HistoryRepository(store: store);
      final loaded = await history.load();
      expect(loaded, hasLength(200));
      expect(loaded.last.ref, 'משנה ברורה 199');
      expect(loaded.first.book.heCategories, 'א' * 300);

      await history.mutate((current) => current.take(1).toList());
      final raw = await store.read('history', 'history');
      expect(raw, hasLength(2));
      expect((raw.first as Map)['ref'], 'משנה ברורה 0');
      expect(raw.last, {'broken': true});
      db.close();
    });
  });
}
