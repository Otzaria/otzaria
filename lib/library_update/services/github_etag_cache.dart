import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// תשובת GitHub שמורה יחד עם ה-ETag שלה.
class GithubEtagEntry {
  final String etag;
  final String? contentType;
  final Uint8List body;

  const GithubEtagEntry({
    required this.etag,
    required this.contentType,
    required this.body,
  });
}

/// מטמון תשובות GET של GitHub בקובץ לכל כתובת: שורת כותרת JSON ואחריה הגוף.
/// קובץ אחד לכל כתובת ושינוי שלו אטומי, כך שה-ETag והגוף לא יתפצלו.
class GithubEtagCache {
  final Future<String> Function() _directoryProvider;

  static int _writeCounter = 0;

  GithubEtagCache(this._directoryProvider);

  Future<File> _fileFor(Uri url) async {
    final key = sha1.convert(utf8.encode(url.toString())).toString();
    return File(p.join(await _directoryProvider(), '$key.etag'));
  }

  /// הערך השמור לכתובת, או `null` כשאין או שהקובץ פגום.
  Future<GithubEtagEntry?> read(Uri url) async {
    try {
      final file = await _fileFor(url);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final newline = bytes.indexOf(0x0A);
      if (newline < 0) return null;
      final header =
          jsonDecode(
                utf8.decode(bytes.sublist(0, newline)),
              )
              as Map<String, dynamic>;
      final etag = header['etag'];
      if (etag is! String || etag.isEmpty) return null;
      final body = Uint8List.sublistView(bytes, newline + 1);
      if (header['length'] != body.length) return null;
      return GithubEtagEntry(
        etag: etag,
        contentType: header['contentType'] as String?,
        body: body,
      );
    } catch (_) {
      return null;
    }
  }

  /// שומר את התשובה. כשל כתיבה אינו שובר את הבקשה: פשוט אין מטמון.
  Future<void> write(Uri url, GithubEtagEntry entry) async {
    try {
      final file = await _fileFor(url);
      await file.parent.create(recursive: true);
      final content = BytesBuilder(copy: false)
        ..add(
          utf8.encode(
            jsonEncode({
              'etag': entry.etag,
              'contentType': entry.contentType,
              'length': entry.body.length,
            }),
          ),
        )
        ..addByte(0x0A)
        ..add(entry.body);
      // שם ייחודי: חלונות או תהליכים שכותבים לאותה כתובת לא חולקים קובץ זמני.
      final temp = File('${file.path}.$pid.${_writeCounter++}.tmp');
      try {
        await temp.writeAsBytes(content.takeBytes(), flush: true);
        await temp.rename(file.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    } catch (_) {}
  }
}
