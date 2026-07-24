import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/repository/base_list_repository.dart';

class BookmarkRepository extends BaseListRepository<Bookmark> {
  BookmarkRepository()
    : super(
        boxName: 'bookmarks',
        key: 'key-bookmarks',
        fromJson: (json) => Bookmark.fromJson(json),
        toJson: (bookmark) => bookmark.toJson(),
      );

  Future<List<Bookmark>> loadBookmarks() async => load();

  Future<void> saveBookmarks(List<Bookmark> bookmarks) async => save(bookmarks);

  Future<void> clearBookmarks() async => clear();
}
