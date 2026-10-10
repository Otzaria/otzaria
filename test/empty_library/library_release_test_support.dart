import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _dbUrl = 'https://example.com/releases/seforim.db.zst';

/// release מינימלי להורדת ספרייה: seforim.db.zst שתוכנו [db], תלמוד וקטלוג.
/// כש-[db] מחזיר null כל בקשה נכשלת ב-404.
MockClient fakeLibraryReleaseClient(String? Function() db) =>
    MockClient((request) async {
      final content = db();
      if (content == null) return http.Response('not found', 404);
      if (request.url.path.endsWith('/releases/latest')) {
        return http.Response(
          jsonEncode({
            'assets': [
              {'name': 'seforim.db.zst', 'browser_download_url': _dbUrl},
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
  void Function(double progress)? onProgress,
) async {
  await File(archivePath).copy(outputPath);
}

/// מחלץ tar מדומה שאינו כותב דבר.
Future<void> ignoreTarArchive(
  String archivePath,
  String outputDir,
  void Function(double progress)? onProgress,
) async {}
