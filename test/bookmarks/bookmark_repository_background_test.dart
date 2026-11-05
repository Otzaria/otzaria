import 'dart:convert';
import 'dart:isolate';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/models/books.dart';

class _Store extends UserStateListStore {
  _Store(this.payload);
  final String payload;

  @override
  Future<R> readDecoded<R>(
    String box,
    String key,
    R Function(String? payload) decode,
  ) => _decodeLikeStore(payload, decode);
}

Future<List<T>> _load<T>(
  Future<List<T>> Function() load, {
  required bool background,
}) async {
  final fake = FakeAsync();
  List<T>? result;
  fake.run((_) => load().then((value) => result = value));
  fake.flushMicrotasks();
  if (background) {
    expect(result, isNull, reason: 'large payload must yield to an isolate');
    for (var i = 0; result == null && i < 1000; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      fake.flushMicrotasks();
    }
  }
  expect(result, isNotNull);
  return result!;
}

void main() {
  for (final large in [false, true]) {
    final bookmarks = [
      for (final type in [
        'TextBook',
        'PdfBook',
        'DocxBook',
        'EpubBook',
        'DocumentBook',
        'ExternalLibraryBook',
      ])
        Bookmark(
          ref: 'בראשית א',
          book: Book.fromJson({
            'type': type,
            'id': 1,
            'title': 'ספר',
            'path': '/book.txt',
            'filePath': '/book.txt',
            'fileType': 'txt',
            'link': 'https://example.com/book',
            'source': 'd:attached',
          }),
          index: 3,
          label: large ? 'א' * 70000 : 'תיאור',
          alternativeWords: {
            0: ['א', 'ב'],
          },
          searchOptions: {
            'א_0': {'קידומות': true},
          },
        ),
    ];

    test('bookmark DTOs round-trip with background=$large', () async {
      final json = bookmarks.map((bookmark) => bookmark.toJson()).toList();
      final store = _Store(jsonEncode(json));
      addTearDown(store.dispose);
      final repository = BookmarkRepository(store: store);
      final loaded = await _load(repository.loadBookmarks, background: large);
      expect(loaded.map((bookmark) => bookmark.toJson()).toList(), json);
    });

    test('group DTOs round-trip with background=$large', () async {
      final groups = [
        BookmarkGroup(id: 'group', name: 'קבוצה', items: bookmarks),
      ];
      final json = groups.map((group) => group.toJson()).toList();
      final store = _Store(jsonEncode(json));
      addTearDown(store.dispose);
      final repository = BookmarkRepository(store: store);
      final loaded = await _load(repository.loadGroups, background: large);
      expect(loaded.map((group) => group.toJson()).toList(), json);
    });
  }
}

// top-level: closure במתודת מופע הייתה לוכדת את this, שאינו נשלח ל-isolate.
Future<R> _decodeLikeStore<R>(String? payload, R Function(String?) decode) =>
    (payload?.length ?? 0) < UserStateListStore.inlineDecodeMaxLength
    ? Future.sync(() => decode(payload))
    : Isolate.run(() => decode(payload));
