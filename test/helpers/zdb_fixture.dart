import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria_zvfs/otzaria_zvfs.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// מסד ספרייה זעיר עם schema_meta ושורת marker, בסכמה [schemaVersion].
void writeFixtureLibraryDb(
  String dbPath, {
  required int version,
  int schemaVersion = 6,
  String marker = 'fixture',
}) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute(
      "INSERT INTO schema_meta VALUES ('db_version', ?), "
      "('db_schema_version', ?)",
      ['$version', '$schemaVersion'],
    );
    db.execute('CREATE TABLE marker (id INTEGER PRIMARY KEY, value TEXT)');
    db.execute('INSERT INTO marker VALUES (1, ?)', [marker]);
    db.execute('PRAGMA journal_mode=DELETE');
  } finally {
    db.close();
  }
}

/// ממיר מסד fixture ל-zdb ב-[zdbPath] (דרך convertToZdb) ומוחק את המקור.
Future<String> writeFixtureZdb(
  String zdbPath, {
  required int version,
  int schemaVersion = 6,
  String marker = 'fixture',
}) async {
  final plain = '$zdbPath.source.db';
  writeFixtureLibraryDb(
    plain,
    version: version,
    schemaVersion: schemaVersion,
    marker: marker,
  );
  await convertToZdb(source: ZdbSource.file(plain), destination: zdbPath);
  File(plain).deleteSync();
  return zdbPath;
}

/// מניפסט כפי ש-SeforimLibrary מפרסם ל-[zdbPath], עם שינויים אופציונליים.
FullDbManifest fixtureManifestFor(
  String zdbPath, {
  required int dbVersion,
  int dbSchemaVersion = 6,
  String? file,
  int? size,
  String? sha256Hex,
  int? formatMajor,
  String? fileUuid,
  String? contentXxh64,
  int? logicalSize,
}) => FullDbManifest.fromJson(
  fixtureManifestJsonFor(
    zdbPath,
    dbVersion: dbVersion,
    dbSchemaVersion: dbSchemaVersion,
    file: file,
    size: size,
    sha256Hex: sha256Hex,
    formatMajor: formatMajor,
    fileUuid: fileUuid,
    contentXxh64: contentXxh64,
    logicalSize: logicalSize,
  ),
);

/// ה-JSON של [fixtureManifestFor], כפי שהוא יושב ב-release.
Map<String, dynamic> fixtureManifestJsonFor(
  String zdbPath, {
  required int dbVersion,
  int dbSchemaVersion = 6,
  String? file,
  int? size,
  String? sha256Hex,
  int? formatMajor,
  String? fileUuid,
  String? contentXxh64,
  int? logicalSize,
}) {
  final bytes = File(zdbPath).readAsBytesSync();
  final header = readLibraryZdbHeader(zdbPath);
  return {
    'manifestVersion': kSupportedFullDbManifestVersion,
    'file': file ?? p.basename(zdbPath),
    'size': size ?? bytes.length,
    'sha256': sha256Hex ?? sha256.convert(bytes).toString(),
    'zdb': {
      'formatMajor': formatMajor ?? header.formatMajor,
      'formatMinor': header.formatMinor,
      'fileUuid': fileUuid ?? header.fileUuidHex,
      'contentXxh64': contentXxh64 ?? header.contentXxh64Hex,
      'logicalSize': logicalSize ?? header.logicalSize,
      'pageSize': header.pageSize,
      'dictName': header.dictName,
      'dictId': header.dictId,
      'level': header.level,
    },
    'dbVersion': dbVersion,
    'dbSchemaVersion': dbSchemaVersion,
    'contentHash': 'unused',
    'converter': {'repository': 'Otzaria/SeforimLibrary', 'commit': 'test'},
  };
}

/// מגדיל את ה-overlay של [zdbPath] בכתיבה דרך zvfs (בערך [bytes] בתים).
void growZdbOverlay(String zdbPath, {int bytes = 200000}) {
  ensureLibraryVfs();
  final db = sqlite3.sqlite3.open(zdbPath);
  try {
    db.execute('CREATE TABLE IF NOT EXISTS junk (b BLOB)');
    db.execute('INSERT INTO junk VALUES (randomblob(?))', [bytes]);
  } finally {
    db.close();
  }
}

/// קריאת שדה marker ו-db_version דרך zvfs.
({int version, String? marker}) readFixtureLibrary(String dbPath) {
  ensureLibraryVfs();
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    final version = db.select(
      "SELECT value FROM schema_meta WHERE key = 'db_version'",
    );
    final marker = db.select('SELECT value FROM marker WHERE id = 1');
    return (
      version: int.parse(version.first.values.first.toString()),
      marker: marker.isEmpty ? null : marker.first.values.first as String?,
    );
  } finally {
    db.close();
  }
}
