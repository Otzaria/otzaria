import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/models/books.dart';

class _MemoryStore extends UserStateListStore {
  _MemoryStore(this.payload);
  String? payload;
  @override
  Future<R> readDecoded<R>(
    String box,
    String key,
    R Function(String? payload) decode,
  ) => _decodeLikeStore(payload, decode);
  @override
  Future<void> clear(String box, String key, {Object? origin}) async {
    payload = null;
  }

  @override
  Stream<UserStateListChange> get changes => const Stream.empty();
}

class _TrackedStore extends UserStateListStore {
  _TrackedStore(UserStateDatabase database) : super(database: database);
  final cleared = Completer<void>();

  @override
  Future<void> clear(String box, String key, {Object? origin}) async {
    await super.clear(box, key, origin: origin);
    cleared.complete();
  }
}

class _Repository extends BookmarkRepository {
  _Repository(UserStateListStore store) : super(store: store);
  final loaded = Completer<void>();

  @override
  Future<List<Bookmark>> loadBookmarks() async {
    final value = await super.loadBookmarks();
    loaded.complete();
    return value;
  }

  @override
  Future<List<BookmarkGroup>> loadGroups() async => [];
}

void main() {
  for (final clearFirst in [false, true]) {
    test(
      'real store preserves add/clear order with clearFirst=$clearFirst',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'otzaria_bookmark_order_',
        );
        final database = UserStateDatabase.openAt('${directory.path}/state.db');
        final store = _TrackedStore(database);
        final repository = _Repository(store);
        final bloc = BookmarkBloc(repository);
        try {
          await repository.loaded.future;
          await Future<void>.delayed(Duration.zero);
          if (clearFirst) bloc.clearBookmarks();
          final saved = bloc.addBookmarkAndSave(
            ref: 'בראשית א',
            book: TextBook(title: 'ספר', filePath: '/book.txt'),
            index: 1,
          );
          if (!clearFirst) bloc.clearBookmarks();
          expect(await saved, isTrue);
          await store.cleared.future;
          await Future<void>.delayed(Duration.zero);
          final persisted = await repository.load();
          expect(persisted, hasLength(clearFirst ? 1 : 0));
          expect(bloc.state.bookmarks, hasLength(clearFirst ? 1 : 0));
        } finally {
          await bloc.close();
          store.dispose();
          await database.flushWrites();
          database.close();
          directory.deleteSync(recursive: true);
        }
      },
    );
  }

  test(
    'clear while large initial bookmark load is pending remains cleared',
    () async {
      final bookmark = Bookmark(
        ref: 'בראשית א',
        book: TextBook(title: 'ספר', filePath: '/book.txt'),
        index: 0,
        label: 'א' * 1000000,
      );
      final memory = _MemoryStore(jsonEncode([bookmark.toJson()]));
      final repository = _Repository(memory);
      final bloc = BookmarkBloc(repository);
      addTearDown(memory.dispose);
      addTearDown(bloc.close);
      final cleared = Completer<void>();
      Timer.run(() {
        bloc.clearBookmarks();
        cleared.complete();
      });
      await cleared.future;
      await repository.loaded.future;
      await Future<void>.delayed(Duration.zero);
      expect(memory.payload, isNull);
      expect(
        bloc.state.bookmarks,
        isEmpty,
        reason: 'old load must not resurrect a cleared bookmark',
      );
    },
  );
}

// top-level: closure במתודת מופע הייתה לוכדת את this, שאינו נשלח ל-isolate.
Future<R> _decodeLikeStore<R>(String? payload, R Function(String?) decode) =>
    utf8.encode(payload ?? '').length < UserStateListStore.inlineDecodeMaxBytes
    ? Future.sync(() => decode(payload))
    : Isolate.run(() => decode(payload));
