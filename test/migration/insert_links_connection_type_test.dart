import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/link.dart';
import 'package:path/path.dart' as p;

/// רגרסיה: insertLinksBatch מאתר את connectionTypeId לפי *שם* הסוג.
/// המטמון ממופתח באותיות גדולות (COMMENTARY) ואילו enum.name קטן (commentary);
/// בלי toUpperCase כל לינק נפל ל-default ונשמר עם הסוג הראשון במקום הסוג האמיתי.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-link-type-');
    database = MyDatabase.withPath(p.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'insertLinksBatch שומר לינק TARGUM עם ה-id של TARGUM (לא default)',
    () async {
      final db = await database.database;
      final targumId =
          db
                  .select(
                    "SELECT id FROM connection_type WHERE name = 'TARGUM'",
                  )
                  .first['id']
              as int;
      final otherId =
          db
                  .select("SELECT id FROM connection_type WHERE name = 'OTHER'")
                  .first['id']
              as int;

      await repository.insertLinksBatch([
        const Link(
          sourceBookId: 1,
          targetBookId: 2,
          sourceLineId: 10,
          targetLineId: 20,
          connectionType: ConnectionType.targum,
        ),
      ]);

      final stored =
          db
                  .select('SELECT connectionTypeId FROM link')
                  .first['connectionTypeId']
              as int;
      expect(
        stored,
        targumId,
        reason: 'הסוג נשמר לפי שם — TARGUM, לא נפילה ל-default',
      );
      expect(
        stored,
        isNot(otherId),
        reason: 'לפני התיקון הלינק נפל ל-default (הסוג הראשון)',
      );
    },
  );
}
