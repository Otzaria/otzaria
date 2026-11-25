import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/repository/base_list_repository.dart';

class HistoryRepository extends BaseListRepository<Bookmark> {
  HistoryRepository({super.store})
    : super(
        boxName: 'history',
        key: 'history',
        fromJson: (json) => Bookmark.fromJson(json),
        toJson: (bookmark) => bookmark.toJson(),
        decodeInBackground: true,
      );

  Future<List<Bookmark>> loadHistory() async => load();

  /// נתיב הכתיבה. [apply] מקבל את ההיסטוריה **הטרייה** — של כל החלונות —
  /// ולא את העותק שבזיכרון ה-bloc.
  Future<List<Bookmark>> mutateHistory(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async => mutate(apply);

  Future<void> clearHistory() async => clear();
}
