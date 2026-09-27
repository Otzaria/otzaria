import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_backup.dart';
import 'package:path/path.dart' as p;

/// עותק הביטחון: קטלוג שנמחק עם תיקיית הספרייה חוזר, ועותק ישן מתעדכן.
void main() {
  late Directory dir;
  late String catalog;
  late String backups;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('responsa_backup');
    catalog = p.join(dir.path, 'books', 'responsa_catalog.db');
    backups = p.join(dir.path, 'backups');
    Directory(p.dirname(catalog)).createSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  File backupFile() => File(
    p.join(backups, ResponsaCatalogBackup.folderName, 'responsa_catalog.db'),
  );

  Future<bool> sync() => ResponsaCatalogBackup.sync(
    catalogPath: catalog,
    backupDirectory: backups,
  );

  test('קטלוג קיים — נוצר עותק', () async {
    File(catalog).writeAsStringSync('v1');
    expect(await sync(), isFalse);
    expect(backupFile().readAsStringSync(), 'v1');
  });

  test('קטלוג חסר — משוחזר מהעותק', () async {
    File(catalog).writeAsStringSync('v1');
    await sync();
    File(catalog).deleteSync();

    expect(await sync(), isTrue);
    expect(File(catalog).readAsStringSync(), 'v1');
  });

  test('בנייה חדשה — העותק מתעדכן', () async {
    File(catalog).writeAsStringSync('v1');
    await sync();
    File(catalog)
      ..writeAsStringSync('version 2')
      ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));

    await sync();
    expect(backupFile().readAsStringSync(), 'version 2');
  });

  test('אחרי שחזור אין העתקה חוזרת — זמן השינוי נשמר', () async {
    File(catalog).writeAsStringSync('v1');
    await sync();
    File(catalog).deleteSync();
    await sync();

    final before = backupFile().lastModifiedSync();
    await sync();
    expect(backupFile().lastModifiedSync(), before);
  });

  test('אין קטלוג ואין עותק — כלום, ובלי חריג', () async {
    expect(await sync(), isFalse);
    expect(File(catalog).existsSync(), isFalse);
  });
}
