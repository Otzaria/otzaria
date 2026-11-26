import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/data/repository/user_state_list_repository.dart';

/// בסיס למאגרי רשימה של מצב המשתמש, עם הפעולות המשותפות.
abstract class BaseListRepository<T> {
  final UserStateListRepository<T> _repo;

  BaseListRepository({
    required String boxName,
    required String key,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    bool decodeInBackground = false,
    UserStateListStore? store,
  }) : _repo = UserStateListRepository<T>(
         boxName: boxName,
         key: key,
         fromJson: fromJson,
         toJson: toJson,
         decodeInBackground: decodeInBackground,
         store: store,
       );

  Future<List<T>> load() async => _repo.load();

  /// הרשימה כ-JSON. ראו [UserStateListRepository.loadJson].
  Future<List<Map<String, dynamic>>> loadJson() => _repo.loadJson();

  /// נתיב הכתיבה. ראו [UserStateListRepository.mutate] — [apply] חייב להיות
  /// טהור.
  Future<List<T>> mutate(List<T> Function(List<T> current) apply) async =>
      _repo.mutate(apply);

  /// דריסה מוחלטת, בלי מיזוג. שחזור מגיבוי בלבד.
  Future<void> overwrite(List<T> items) async => _repo.overwrite(items);

  List<T> decodeJson(List<dynamic> raw) => _repo.decodeJson(raw);

  /// שחזור מגיבוי. ראו [UserStateListRepository.overwriteJson].
  Future<void> overwriteJson(List<dynamic> raw) => _repo.overwriteJson(raw);

  Future<void> clear() async => _repo.clear();

  /// אות שהרשימה שונתה בחלון אחר.
  Stream<void> get remoteChanges => _repo.remoteChanges;
}
