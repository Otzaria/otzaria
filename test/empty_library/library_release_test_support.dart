import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:path/path.dart' as p;

const _dbUrl = 'https://example.com/releases/seforim.db.zst';

/// Text fixtures exercise routing/rollback without pretending to be SQLite.
/// Real database validation is covered separately with native SQLite fixtures.
Future<void> verifyFixtureDatabase(
  String dbPath, {
  required bool verifyLibrarySchema,
}) async {
  if (verifyLibrarySchema) EmptyLibraryBloc.requireReadableDbSchema(dbPath);
}

/// release מינימלי להורדת ספרייה: seforim.db.zst שתוכנו [db], תלמוד וקטלוג.
/// כש-[db] מחזיר null כל בקשה נכשלת ב-404.
MockClient fakeLibraryReleaseClient(
  String? Function() db, {
  String? compressedSha256,
}) => MockClient((request) async {
  final content = db();
  if (content == null) return http.Response('not found', 404);
  if (request.url.path.endsWith('/releases/latest')) {
    return http.Response(
      jsonEncode({
        'assets': [
          {
            'name': 'seforim.db.zst',
            'browser_download_url': _dbUrl,
            if (compressedSha256 != null) 'digest': 'sha256:$compressedSha256',
          },
        ],
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
  if (request.url.toString() == _dbUrl) {
    return http.Response.bytes(utf8.encode(content), 200);
  }
  if (request.url.host == 'github.com' &&
      (request.url.path.endsWith('talmud_bavli_latest.tar.zst') ||
          request.url.path.endsWith('otzar-HB_catalog.db.zst'))) {
    return http.Response.bytes(utf8.encode('asset'), 200);
  }
  return http.Response('not found', 404);
});

/// מפענח מדומה: התוכן המחולץ הוא הארכיון עצמו.
Future<void> copyAsExtracted(
  String archivePath,
  String outputPath,
  void Function(double progress)? onProgress, {
  int? maxOutputBytes,
  bool Function()? isCancelled,
}) async {
  await File(archivePath).copy(outputPath);
}

/// מחלץ tar מדומה היוצר את תיקיית השורש הנדרשת, ללא קובצי PDF.
Future<void> ignoreTarArchive(
  String archivePath,
  String outputDir,
  void Function(double progress)? onProgress, {
  int? maxOutputBytes,
  bool Function()? isCancelled,
}) async {
  await Directory(
    p.join(outputDir, DatabaseConstants.talmudBavliFolderName),
  ).create(recursive: true);
}
