import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/repository/base_list_repository.dart';

class HistoryRepository extends BaseListRepository<Bookmark> {
  HistoryRepository()
    : super(
        boxName: 'history',
        key: 'history',
        fromJson: (json) => Bookmark.fromJson(json),
        toJson: (bookmark) => bookmark.toJson(),
      );

  Future<List<Bookmark>> loadHistory() async => load();

  Future<void> saveHistory(List<Bookmark> history) async => save(history);

  Future<void> clearHistory() async => clear();

  Future<void> addHistoryItem(Bookmark bookmark) async => addItem(bookmark);

  Future<void> removeHistoryItem(int index) async => removeAt(index);
}
