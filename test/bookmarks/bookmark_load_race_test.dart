import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/models/books.dart';

class _Repository implements BookmarkRepository {
  final bookmarkLoads = <Completer<List<Bookmark>>>[];
  final groupLoads = <Completer<List<BookmarkGroup>>>[];
  final bookmarksChanged = StreamController<void>.broadcast(sync: true);
  final groupsChanged = StreamController<void>.broadcast(sync: true);
  List<Bookmark> bookmarks = [];
  Completer<void>? clearCompletion;
  Completer<void>? bookmarkWriteCompletion;
  Completer<void>? groupWriteCompletion;
  List<BookmarkGroup> groups = [];

  @override
  Future<List<Bookmark>> loadBookmarks() {
    final pending = Completer<List<Bookmark>>();
    bookmarkLoads.add(pending);
    return pending.future;
  }

  @override
  Future<List<BookmarkGroup>> loadGroups() {
    final pending = Completer<List<BookmarkGroup>>();
    groupLoads.add(pending);
    return pending.future;
  }

  @override
  Future<List<Bookmark>> mutateBookmarks(
    List<Bookmark> Function(List<Bookmark>) apply,
  ) async {
    await bookmarkWriteCompletion?.future;
    return bookmarks = apply(bookmarks);
  }

  @override
  Future<List<BookmarkGroup>> mutateGroups(
    List<BookmarkGroup> Function(List<BookmarkGroup>) apply,
  ) async {
    await groupWriteCompletion?.future;
    return groups = apply(groups);
  }

  @override
  Future<void> clearBookmarks() async {
    await clearCompletion?.future;
    bookmarks = [];
  }

  @override
  Stream<void> get remoteChanges => bookmarksChanged.stream;
  @override
  Stream<void> get groupsRemoteChanges => groupsChanged.stream;

  Future<void> dispose() async {
    await bookmarksChanged.close();
    await groupsChanged.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Bookmark _bookmark(int index) => Bookmark(
  ref: 'בראשית א',
  book: TextBook(title: 'ספר', filePath: '/book.txt'),
  index: index,
);

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  late _Repository repository;
  late BookmarkBloc bloc;

  setUp(() {
    repository = _Repository();
    bloc = BookmarkBloc(repository);
  });
  tearDown(() async {
    for (final pending in repository.bookmarkLoads) {
      if (!pending.isCompleted) pending.complete([]);
    }
    await _drain();
    for (final pending in repository.groupLoads) {
      if (!pending.isCompleted) pending.complete([]);
    }
    await _drain();
    await bloc.close();
    await repository.dispose();
  });

  test('initial load cannot restore a cleared bookmark', () async {
    bloc.clearBookmarks();
    repository.bookmarkLoads.single.complete([_bookmark(0)]);
    await _drain();
    expect(bloc.state.bookmarks, isEmpty);
  });

  test(
    'clear completion replaces a remote load started during the write',
    () async {
      repository.bookmarkLoads.single.complete([_bookmark(0)]);
      await _drain();
      repository.clearCompletion = Completer<void>();
      bloc.clearBookmarks();
      repository.bookmarksChanged.add(null);
      repository.bookmarkLoads.last.complete([_bookmark(0)]);
      await _drain();
      repository.clearCompletion!.complete();
      await _drain();
      expect(bloc.state.bookmarks, isEmpty);
    },
  );

  test('clear completion invalidates a still pending remote load', () async {
    repository.bookmarkLoads.single.complete([_bookmark(0)]);
    await _drain();
    repository.clearCompletion = Completer<void>();
    bloc.clearBookmarks();
    repository.bookmarksChanged.add(null);
    repository.clearCompletion!.complete();
    await _drain();
    repository.bookmarkLoads.last.complete([_bookmark(0)]);
    await _drain();
    expect(bloc.state.bookmarks, isEmpty);
  });

  test('initial load cannot replace a saved addition', () async {
    await bloc.addBookmarkAndSave(
      ref: 'שמות א',
      book: _bookmark(1).book,
      index: 1,
    );
    repository.bookmarkLoads.single.complete([_bookmark(0)]);
    await _drain();
    expect(bloc.state.bookmarks.single.index, 1);
  });

  test(
    'saved bookmark invalidates a remote load begun during its write',
    () async {
      repository.bookmarkLoads.single.complete([]);
      await _drain();
      repository.bookmarkWriteCompletion = Completer<void>();
      final saved = bloc.addBookmarkAndSave(
        ref: 'חדש',
        book: _bookmark(1).book,
        index: 1,
      );
      repository.bookmarksChanged.add(null);
      repository.bookmarkWriteCompletion!.complete();
      await saved;
      repository.bookmarkLoads.last.complete([_bookmark(0)]);
      await _drain();
      expect(bloc.state.bookmarks.single.index, 1);
    },
  );

  test(
    'saved group invalidates a remote load begun during its write',
    () async {
      repository.bookmarkLoads.single.complete([]);
      await _drain();
      repository.groupLoads.single.complete([]);
      await _drain();
      repository.groupWriteCompletion = Completer<void>();
      bloc.addGroup(BookmarkGroup(id: 'new', name: 'חדש', items: []));
      repository.groupsChanged.add(null);
      repository.groupWriteCompletion!.complete();
      await _drain();
      repository.groupLoads.last.complete([
        BookmarkGroup(id: 'old', name: 'ישן', items: []),
      ]);
      await _drain();
      expect(bloc.state.groups.single.id, 'new');
    },
  );

  test('older remote load cannot replace the latest remote result', () async {
    repository.bookmarksChanged.add(null);
    expect(repository.bookmarkLoads, hasLength(2));
    repository.bookmarkLoads.last.complete([_bookmark(1)]);
    await _drain();
    repository.bookmarkLoads.first.complete([_bookmark(0)]);
    await _drain();
    expect(bloc.state.bookmarks.single.index, 1);
  });

  test('group load cannot replace a saved group', () async {
    repository.bookmarkLoads.single.complete([]);
    await _drain();
    final group = BookmarkGroup(id: 'new', name: 'חדש', items: [_bookmark(1)]);
    bloc.addGroup(group);
    await _drain();
    repository.groupLoads.single.complete([
      BookmarkGroup(id: 'old', name: 'ישן', items: [_bookmark(0)]),
    ]);
    await _drain();
    expect(bloc.state.groups.single.id, 'new');
  });

  test('older group reload cannot replace the latest remote groups', () async {
    repository.bookmarkLoads.single.complete([]);
    await _drain();
    repository.groupsChanged.add(null);
    repository.groupLoads.last.complete([
      BookmarkGroup(id: 'new', name: 'חדש', items: []),
    ]);
    await _drain();
    repository.groupLoads.first.complete([
      BookmarkGroup(id: 'old', name: 'ישן', items: []),
    ]);
    await _drain();
    expect(bloc.state.groups.single.id, 'new');
  });

  test(
    'bookmark mutation does not invalidate an unrelated group load',
    () async {
      repository.bookmarkLoads.single.complete([]);
      await _drain();
      bloc.clearBookmarks();
      repository.groupLoads.single.complete([
        BookmarkGroup(id: 'group', name: 'קבוצה', items: []),
      ]);
      await _drain();
      expect(bloc.state.groups.single.id, 'group');
    },
  );
}
