import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/http_redirect_download.dart';

class HebrewBookDownload {
  final Uint8List bytes;
  final String fileName;

  const HebrewBookDownload({required this.bytes, required this.fileName});
}

/// מוריד קובצי PDF של ספרי היברובוקס. השרת דורש את [appKeyHeader].
class HebrewBooksDownloadService {
  static const String appKeyHeader = 'x-app-key';
  static const String appKeyValue = 'otzariatokendownload';

  static const String _baseUrl =
      'https://files.hebrewbooksoffline.dpdns.org/HebrewBooks/books';

  final http.Client _client;
  final bool _ownsClient;

  HebrewBooksDownloadService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static Uri fileUrl(int bookId) => Uri.parse('$_baseUrl/$bookId.pdf');

  /// תבנית השם שסורק תיקיית היברובוקס מזהה כספר מקומי.
  static String fileNameFor(int bookId) => '$bookId.pdf';

  static String? configuredFolder() {
    final value = Settings.getValue<String>(
      SettingsRepository.keyHebrewBooksPath,
    );
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// [onProgress] מקבל בייטים שהתקבלו וגודל כולל (`null` אם לא דווח).
  Future<HebrewBookDownload> download(
    int bookId, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final response = await sendGetFollowingRedirects(
      _client,
      fileUrl(bookId),
      headers: const {appKeyHeader: appKeyValue},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('השרת החזיר ${response.statusCode}');
    }

    final total = response.contentLength;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      onProgress?.call(builder.length, total);
    }
    return HebrewBookDownload(
      bytes: builder.takeBytes(),
      fileName: fileNameFor(bookId),
    );
  }

  /// מחזיר `null` כשלא הוגדרה תיקייה — אז על הקורא לבקש יעד מהמשתמש.
  static Future<String?> saveToConfiguredFolder(
    int bookId,
    Uint8List bytes,
  ) async {
    final folder = configuredFolder();
    if (folder == null) return null;
    final booksDir = Directory(path.join(folder, 'Books'));
    final target = (await booksDir.exists()) ? booksDir.path : folder;
    await Directory(target).create(recursive: true);
    final file = File(path.join(target, fileNameFor(bookId)));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
