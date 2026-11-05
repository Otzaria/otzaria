import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/migration/database/daos/book_dao.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/book.dart';

/// איתור ספר במסד הרשמי מה-UI, כולל בדיקת הסכמה, על חיבור ה-worker.
class ReadWorkerBookDao extends BookDao {
  ReadWorkerBookDao(this._database) : super(_database);

  final MyDatabase _database;

  Future<Book?> _lookup(String method, Map<String, Object?> args) async =>
      await DbReadWorker.batched(method, {
            'dbPath': _database.readOnlyTarget.path,
            ...args,
          })
          as Book?;

  @override
  Future<Book?> getBookById(int id) => _lookup('bookById', {'bookId': id});

  @override
  Future<Book?> getBookByTitle(String title) =>
      _lookup('bookByTitle', {'title': title});

  @override
  Future<Book?> getBookByTitleAndCategory(String title, int categoryId) =>
      _lookup('bookByTitleAndCategory', {
        'title': title,
        'categoryId': categoryId,
      });

  @override
  Future<Book?> getBookByTitleCategoryAndFileType(
    String title,
    int categoryId,
    String fileType,
  ) => _lookup('bookByTitleCategoryAndFileType', {
    'title': title,
    'categoryId': categoryId,
    'fileType': fileType,
  });
}
