import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/data/repository/base_list_repository.dart';
import 'package:otzaria/data/repository/user_state_list_repository.dart';

class BookmarkRepository extends BaseListRepository<Bookmark> {
  /// סימניות מרוכזות — באותו מאגר תחת מפתח נפרד. הגיבוי שומר אותן במפורש
  /// (`bookmarkGroups`), כי הוא קורא כל מפתח בנפרד.
  final UserStateListRepository<BookmarkGroup> _groupsRepository;

  BookmarkRepository({super.store})
    : _groupsRepository = UserStateListRepository<BookmarkGroup>(
        boxName: 'bookmarks',
        key: 'key-bookmark-groups',
        fromJson: (json) => BookmarkGroup.fromJson(json),
        toJson: (group) => group.toJson(),
        store: store,
        decodeInBackground: true,
      ),
      super(
        boxName: 'bookmarks',
        key: 'key-bookmarks',
        decodeInBackground: true,
        fromJson: (json) => Bookmark.fromJson(json),
        toJson: (bookmark) => bookmark.toJson(),
      );

  Future<List<Bookmark>> loadBookmarks() async => load();

  /// נתיב הכתיבה. [apply] מקבל את הסימניות **הטריות** — של כל החלונות.
  Future<List<Bookmark>> mutateBookmarks(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async => mutate(apply);

  Future<void> clearBookmarks() async => clear();

  Future<List<BookmarkGroup>> loadGroups() async => _groupsRepository.load();

  Future<List<Map<String, dynamic>>> loadGroupsJson() =>
      _groupsRepository.loadJson();

  List<BookmarkGroup> decodeGroupsJson(List<dynamic> raw) =>
      _groupsRepository.decodeJson(raw);

  /// שחזור מגיבוי: דריסה מוחלטת.
  Future<void> replaceGroupsJson(List<dynamic> raw) =>
      _groupsRepository.overwriteJson(raw);

  Future<List<BookmarkGroup>> mutateGroups(
    List<BookmarkGroup> Function(List<BookmarkGroup> current) apply,
  ) async => _groupsRepository.mutate(apply);

  /// אות ששכבת הסימניות המרוכזות שונתה בחלון אחר.
  Stream<void> get groupsRemoteChanges => _groupsRepository.remoteChanges;
}
