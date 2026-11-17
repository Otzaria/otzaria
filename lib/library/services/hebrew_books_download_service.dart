import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/download_http_client.dart';
import 'package:otzaria/core/download_network_policy.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:path/path.dart' as path;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/http_redirect_download.dart';

class HebrewBookDownload {
  final Uint8List bytes;
  final String fileName;

  const HebrewBookDownload({required this.bytes, required this.fileName});
}

/// השרת ענה בסטטוס שאינו הצלחה.
class HebrewBookDownloadStatusException implements Exception {
  final int statusCode;

  const HebrewBookDownloadStatusException(this.statusCode);
}

/// מוריד קובצי PDF של ספרי היברובוקס. השרת דורש את [appKeyHeader].
class HebrewBooksDownloadService {
  static const String appKeyHeader = 'x-app-key';
  static const String appKeyValue = 'otzariatokendownload';

  static const String _baseUrl =
      'https://files.hebrewbooksoffline.dpdns.org/HebrewBooks/books';

  final http.Client _client;
  final bool _ownsClient;
  bool _disposed = false;

  HebrewBooksDownloadService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  void dispose() {
    _disposed = true;
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
    void Function()? onWaitingForWifi,
  }) => _runDownload(() async {
    final builder = BytesBuilder(copy: false);
    await _readBook(bookId, builder.add, onProgress: onProgress);
    return HebrewBookDownload(
      bytes: builder.takeBytes(),
      fileName: fileNameFor(bookId),
    );
  }, onWaitingForWifi);

  /// כותב לתיקיית הספרייה במקטעים ומפרסם את שם הספר לאחר סיום ההורדה.
  Future<String> downloadToFolder(
    int bookId,
    String folder, {
    void Function(int received, int? total)? onProgress,
    void Function()? onWaitingForWifi,
  }) => _runDownload(() async {
    final target = await _targetDirectory(folder);
    final staging = await target.createTemp('.hebrewbooks-');
    try {
      final temporary = File(path.join(staging.path, 'download.part'));
      final output = await temporary.open(mode: FileMode.write);
      try {
        await _readBook(bookId, (chunk) async {
          await output.writeFrom(chunk);
        }, onProgress: onProgress);
        await output.flush();
      } finally {
        await output.close();
      }
      _checkCancelled();
      final saved = await temporary.rename(
        path.join(target.path, fileNameFor(bookId)),
      );
      return saved.path;
    } finally {
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // כשל בניקוי לא משנה את תוצאת ההורדה או את ההמתנה ל־WiFi.
      }
    }
  }, onWaitingForWifi);

  Future<T> _runDownload<T>(
    Future<T> Function() download,
    void Function()? onWaitingForWifi,
  ) => DownloadNetworkPolicy.instance.runResumable(
    download,
    checkCancelled: _checkCancelled,
    onWaiting: onWaitingForWifi,
  );

  void _checkCancelled() {
    if (_disposed) throw http.RequestAbortedException();
  }

  Future<void> _readBook(
    int bookId,
    FutureOr<void> Function(List<int>) consume, {
    void Function(int received, int? total)? onProgress,
  }) async {
    _checkCancelled();
    final response = await sendGetFollowingRedirects(
      createDownloadClient(_client),
      fileUrl(bookId),
      headers: const {appKeyHeader: appKeyValue},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen((_) {}).cancel();
      throw HebrewBookDownloadStatusException(response.statusCode);
    }

    final total = response.contentLength;
    var received = 0;
    await for (final chunk in response.stream) {
      _checkCancelled();
      await consume(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    _checkCancelled();
  }

  static Future<Directory> _targetDirectory(String folder) async {
    final booksDir = Directory(path.join(folder, 'Books'));
    final target = (await booksDir.exists()) ? booksDir : Directory(folder);
    return target.create(recursive: true);
  }

  /// מחזיר `null` כשלא הוגדרה תיקייה — אז על הקורא לבקש יעד מהמשתמש.
  static Future<String?> saveToConfiguredFolder(
    int bookId,
    Uint8List bytes,
  ) async {
    final folder = configuredFolder();
    if (folder == null) return null;
    final target = await _targetDirectory(folder);
    final file = File(path.join(target.path, fileNameFor(bookId)));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
