import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_fetcher.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_notes.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_store.dart';

void main() {
  late Directory root;
  late LibraryChangesStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library_changes_notes_');
    store = LibraryChangesStore(dataRootProvider: () async => root.path);
  });

  tearDown(() => root.delete(recursive: true));

  for (final startupFirst in [true, false]) {
    for (final statusCode in [200, 404]) {
      test(
        '${startupFirst ? 'עלייה' : 'עדכון'}: תגובת $statusCode במקביל לעדכון נוסף שומרת את התור',
        () async {
          store = _MemoryQueueStore(root.path);
          await store.writeFetchQueue({'v33': DateTime.now()});
          final requested = <String>[];
          final requestStarted = Completer<void>();
          final response = Completer<http.Response>();
          final fetcher = LibraryChangesFetcher(
            store: store,
            clientFactory: () => MockClient((request) async {
              requested.add(request.url.pathSegments[4]);
              if (requested.length == 1) {
                requestStarted.complete();
                return response.future;
              }
              return http.Response('', 404);
            }),
          );
          final notes = LibraryChangesNotes(
            store: store,
            fetcher: fetcher,
            contextProvider: () => null,
            isOffline: () => false,
          );
          final first = startupFirst
              ? notes.onStartup()
              : notes.afterLibraryUpdate(['v33']);
          await requestStarted.future;
          final second = notes.afterLibraryUpdate(['v34']);
          // פעולות התור בזיכרון מסתיימות לפני סבב האירועים הבא.
          await Future<void>.delayed(Duration.zero);
          expect((await store.readFetchQueue()).keys, contains('v34'));
          response.complete(http.Response('# v33', statusCode));
          await Future.wait([first, second]);

          expect((await store.readFetchQueue()).keys.toSet(), {
            if (statusCode == 404) 'v33',
            'v34',
          });
          expect(requested, ['v33', 'v34', if (statusCode == 404) 'v33']);
        },
      );
    }
  }

  test('כשל בהורדה אינו מונע הורדה בעדכון הבא', () async {
    var fail = true;
    final fetcher = LibraryChangesFetcher(
      store: store,
      clientFactory: () {
        if (fail) {
          fail = false;
          throw const SocketException('יצירת לקוח נכשלה');
        }
        return MockClient(
          (_) async => http.Response.bytes(utf8.encode('# ספר חדש'), 200),
        );
      },
    );
    await fetcher.enqueue(['v33']);
    await expectLater(fetcher.fetchQueued(), throwsA(isA<SocketException>()));
    await fetcher.enqueue(['v34']);
    expect(await fetcher.fetchQueued(), 2);

    expect((await store.readPending()).map((n) => n.releaseTag), [
      'v34',
      'v33',
    ]);
    expect(await store.readFetchQueue(), isEmpty);
  });

  test('תוספת לתור נשמרת בדיסק בזמן שהורדה קודמת ממתינה לרשת', () async {
    final saved = Completer<void>();
    store = _ObservedStore(root.path, saved);
    await store.writeFetchQueue({'v33': DateTime.now()});
    final requestStarted = Completer<void>();
    final response = Completer<http.Response>();
    var requests = 0;
    final notes = LibraryChangesNotes(
      store: store,
      fetcher: LibraryChangesFetcher(
        store: store,
        clientFactory: () => MockClient((_) async {
          if (++requests == 1) {
            requestStarted.complete();
            return response.future;
          }
          return http.Response('', 404);
        }),
      ),
      contextProvider: () => null,
      isOffline: () => false,
    );
    final startup = notes.onStartup();
    await requestStarted.future;
    final update = notes.afterLibraryUpdate(['v34']);
    try {
      await saved.future.timeout(const Duration(seconds: 2));
      expect(requests, 1);
      expect((await store.readFetchQueue()).keys, contains('v34'));
    } finally {
      response.complete(http.Response('', 404));
      await Future.wait([startup, update]);
    }
    expect((await store.readFetchQueue()).keys.toSet(), {'v33', 'v34'});
  });

  test('הוספות מקבילות לתור אינן מאבדות תגים', () async {
    final fetcher = LibraryChangesFetcher(store: store);
    await Future.wait([
      fetcher.enqueue(['v33']),
      fetcher.enqueue(['v34']),
    ]);

    expect((await store.readFetchQueue()).keys.toSet(), {'v33', 'v34'});
  });

  test('כשל בשינוי התור אינו מרעיל את הפעולה הבאה', () async {
    store = _FailOnceStore(root.path);
    final fetcher = LibraryChangesFetcher(store: store);
    await expectLater(
      fetcher.enqueue(['v33']),
      throwsA(isA<FileSystemException>()),
    );
    await fetcher.enqueue(['v34']);

    expect((await store.readFetchQueue()).keys, ['v34']);
  });

  test('היסטוריה ריקה מוצגת בבקשה מפורשת בלבד גם במצב מנותק', () async {
    final shown = <List<LibraryChangesNote>>[];
    final context = _Context();
    final notes = LibraryChangesNotes(
      store: store,
      contextProvider: () => context,
      isOffline: () => true,
      showDialog: (_, list) async => shown.add(list),
    );
    await notes.onStartup();
    expect(shown, isEmpty);
    await notes.showAll(context);
    expect(shown, [isEmpty]);
    expect(root.listSync(), isEmpty);
  });

  test('הורדה בזמן היסטוריה פתוחה מוצגת לאחר סגירתה ואחרי הסיור', () async {
    await store.writePending('v33', '# ספרים ישנים');
    await store.markSeen(await store.readPending());
    final historyOpened = Completer<void>();
    final closeHistory = Completer<void>();
    final tourReached = Completer<void>();
    final finishTour = Completer<void>();
    final shown = <List<String>>[];
    final notes =
        LibraryChangesNotes(
            store: store,
            fetcher: LibraryChangesFetcher(
              store: store,
              clientFactory: () => MockClient(
                (_) async => http.Response.bytes(utf8.encode('# ספר חדש'), 200),
              ),
            ),
            contextProvider: () => _Context(),
            showDialog: (_, list) async {
              shown.add(list.map((n) => n.releaseTag).toList());
              if (shown.length == 1) {
                historyOpened.complete();
                await closeHistory.future;
              }
            },
          )
          ..beforeAutoShow = () {
            tourReached.complete();
            return finishTour.future;
          };
    final history = notes.showAll(_Context());
    await historyOpened.future;
    await notes.afterLibraryUpdate(['v34']);
    expect((await store.readPending()).map((n) => n.releaseTag), ['v34']);
    expect(shown, [
      ['v33'],
    ]);
    closeHistory.complete();
    // בדיקת הדגל נעשית לפני המתנה, כדי שהמימוש השבור ייכשל בלי להיתקע.
    await Future.any([history, tourReached.future]);
    expect(tourReached.isCompleted, isTrue);
    expect(shown, [
      ['v33'],
    ]);
    finishTour.complete();
    await history;

    expect(shown, [
      ['v33'],
      ['v34'],
    ]);
    expect(await store.readPending(), isEmpty);
    expect((await store.readSeen()).map((n) => n.releaseTag), ['v34', 'v33']);
  });

  test(
    'סגירת היסטוריה עם הקשר שפג משאירה את ההערות החדשות לפעם הבאה',
    () async {
      await store.writePending('v33', '# ישן');
      final opened = Completer<void>();
      final close = Completer<void>();
      final context = _Context();
      var dialogs = 0;
      final notes = LibraryChangesNotes(
        store: store,
        contextProvider: () => context,
        showDialog: (_, _) async {
          dialogs++;
          opened.complete();
          await close.future;
        },
      );
      final history = notes.showAll(context);
      await opened.future;
      await store.writePending('v34', '# חדש');
      await notes.showPending();
      context.mounted = false;
      close.complete();
      await history;

      expect(dialogs, 1);
      expect((await store.readPending()).map((n) => n.releaseTag), ['v34']);
    },
  );

  test('במצב מנותק מוצגות הערות מהמעדכן הלא-מקוון ללא הורדה', () async {
    await store.writePending('v34', '# חדש');
    final shown = <String>[];
    final notes = LibraryChangesNotes(
      store: store,
      fetcher: LibraryChangesFetcher(
        store: store,
        clientFactory: () => throw StateError('אין לפנות לרשת'),
      ),
      contextProvider: () => _Context(),
      isOffline: () => true,
      showDialog: (_, list) async =>
          shown.addAll(list.map((n) => n.releaseTag)),
    );
    await notes.onStartup();

    expect(shown, ['v34']);
    expect(await store.readPending(), isEmpty);
  });
}

class _Context extends Fake implements BuildContext {
  @override
  bool mounted = true;
}

class _MemoryQueueStore extends LibraryChangesStore {
  _MemoryQueueStore(String root) : super(dataRootProvider: () async => root);

  Map<String, DateTime> _queue = {};

  @override
  Future<Map<String, DateTime>> readFetchQueue() async => Map.of(_queue);

  @override
  Future<void> writeFetchQueue(Map<String, DateTime> queue) async {
    _queue = Map.of(queue);
  }

  @override
  Future<bool> contains(String releaseTag) async => false;
}

class _ObservedStore extends LibraryChangesStore {
  _ObservedStore(String root, this.saved)
    : super(dataRootProvider: () async => root);

  final Completer<void> saved;

  @override
  Future<void> writeFetchQueue(Map<String, DateTime> queue) async {
    await super.writeFetchQueue(queue);
    if (queue.containsKey('v34') && !saved.isCompleted) saved.complete();
  }
}

class _FailOnceStore extends LibraryChangesStore {
  _FailOnceStore(String root) : super(dataRootProvider: () async => root);

  var _fail = true;

  @override
  Future<Map<String, DateTime>> readFetchQueue() async {
    if (_fail) {
      _fail = false;
      throw const FileSystemException('כתיבת התור נכשלה');
    }
    return super.readFetchQueue();
  }
}
