import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/data/repository/base_list_repository.dart';
import 'package:otzaria/data/repository/user_state_list_repository.dart';

class BookmarkRepository extends BaseListRepository<Bookmark> {
  /// סימניות מרוכזות — באותו מאגר תחת מפתח נפרד, כך שהן נכללות אוטומטית
  /// בגיבוי של הסימניות.
  final UserStateListRepository<BookmarkGroup> _groupsRepository;

  BookmarkRepository({super.store})
    : _groupsRepository = UserStateListRepository<BookmarkGroup>(
        boxName: 'bookmarks',
        key: 'key-bookmark-groups',
        fromJson: (json) => BookmarkGroup.fromJson(json),
        toJson: (group) => group.toJson(),
        store: store,
      ),
      super(
        boxName: 'bookmarks',
        key: 'key-bookmarks',
        fromJson: (json) => Bookmark.fromJson(json),
        toJson: (bookmark) => bookmark.toJson(),
      );

  Future<List<Bookmark>> loadBookmarks() async => load();

  /// נתיב הכתיבה. [apply] מקבל את הסימניות **הטריות** — של כל החלונות.
  Future<List<Bookmark>> mutateBookmarks(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async => mutate(apply);

  /// שחזור מגיבוי: דריסה מוחלטת.
  Future<void> replaceBookmarks(List<Bookmark> bookmarks) async =>
      overwrite(bookmarks);

  Future<void> clearBookmarks() async => clear();

  Future<List<BookmarkGroup>> loadGroups() async => _groupsRepository.load();

  Future<List<BookmarkGroup>> mutateGroups(
    List<BookmarkGroup> Function(List<BookmarkGroup> current) apply,
  ) async => _groupsRepository.mutate(apply);

  /// שחזור מגיבוי: דריסה מוחלטת.
  Future<void> replaceGroups(List<BookmarkGroup> groups) async =>
      _groupsRepository.overwrite(groups);

  /// אות ששכבת הסימניות המרוכזות שונתה בחלון אחר.
  Stream<void> get groupsRemoteChanges => _groupsRepository.remoteChanges;
}
