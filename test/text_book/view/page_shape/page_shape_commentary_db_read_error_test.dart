// כשל קריאה אמיתי של SQLite בטקסט המפרש אינו נבלע כ"ספר חסר": הטור נשאר
// עם "נסה שוב" ואינו מוסתר. מפרש שאינו קיים עדיין מוסתר (issue #5744).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import 'page_shape_commentary_failure_harness.dart';

const _commentator = 'מפרש שהמסד נכשל בו';
const _retry = 'נסה שוב';

void main() {
  setUpPageShapeFailureTests();

  testWidgets('כשל קריאה מהמסד מציע "נסה שוב" ואינו מסתיר את הטור', (
    tester,
  ) async {
    final fixture = await tester.runAsync(_createBrokenLinesFixture);
    addTearDown(() async {
      await DatabaseLibraryProvider.instance.sqliteProvider.dispose();
      SqliteDataProvider.instance.keepWalJournal = false;
      await fixture!.delete(recursive: true);
    });
    await pumpPageShape(
      tester,
      FakeCommentaryProvider(const [_commentator]),
      bookTitle: 'ספר ראשי',
    );
    await pumpUntil(tester, () => find.text(_retry).evaluate().isNotEmpty);
    // ההסתרה של "מפרש חסר" מגיעה בפריים שאחרי ההודעה.
    await pumpUntil(tester, () => false);
    expect(find.text('לא ניתן לטעון את $_commentator'), findsOneWidget);
    expect(find.text(_retry), findsOneWidget);
  });

  testWidgets('מפרש שאינו קיים עדיין מוסתר בלי הודעה', (tester) async {
    const missing = 'מפרש שאינו קיים';
    await pumpPageShape(
      tester,
      FakeCommentaryProvider(const [missing])..missing = true,
      bookTitle: 'ספר בלי המפרש',
    );
    await pumpUntil(tester, () => false);
    expect(find.text('לא ניתן לטעון את $missing'), findsNothing);
    expect(find.text(_retry), findsNothing);
    expect(commentaryViewer(), findsNothing);
  });
}

/// מסד שבו ספר המפרש רשום, אבל טבלת השורות אינה קריאה — כל קריאה של
/// הטקסט נכשלת בחריגת SQLite.
Future<Directory> _createBrokenLinesFixture() async {
  final dir = await Directory.systemTemp.createTemp('page-shape-db-error-');
  final path = '${dir.path}/seforim.db';
  final database = MyDatabase.withPath(path);
  await SeforimRepository(database).ensureInitialized();
  final db = await database.database;
  db.execute(
    "INSERT INTO category (id,title,level) VALUES (61,'ראשי',0),(703,'מפרשים',0)",
  );
  db.execute("INSERT INTO source (id,name) VALUES (1,'test')");
  db.execute(
    "INSERT INTO book (id,categoryId,sourceId,title,orderIndex,totalLines,filePath,fileType) VALUES (2,703,1,?,1,2,'','txt')",
    [_commentator],
  );
  db.execute('DROP TABLE line');
  db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  db.execute('PRAGMA journal_mode=DELETE');
  database.close();
  final provider = DatabaseLibraryProvider.instance;
  await provider.sqliteProvider.dispose();
  provider.sqliteProvider.keepWalJournal = true;
  await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, path);
  await provider.initialize();
  return dir;
}
