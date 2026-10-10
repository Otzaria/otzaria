import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// minidump של sentry-native מהקריסה, דחוס ב-gzip. מכיל זיכרון של התהליך,
/// ולכן נשלח רק בהסכמה מפורשת בטופס ונשמר באתר בלבד, לא ב-GitHub.
@immutable
class AppReportMinidump extends Equatable {
  const AppReportMinidump({required this.gzipBytes, required this.fileName});

  /// גבול ה-dump לפני דחיסה; ב-1000 כדי להישאר מתחת לגבול השרת (16MiB).
  static const int maxRawBytes = 16 * 1000 * 1000;

  /// הנפח המרבי בגוף הבקשה: base64 של dump שלא התכווץ, ועוד השם.
  static const int maxPayloadBytes = (maxRawBytes + 2) ~/ 3 * 4 + 1024;

  static const int maxFileNameLength = 200;

  final Uint8List gzipBytes;
  final String fileName;

  /// קורא ודוחס את [file] ב-isolate. `null` כשהקובץ חסר, גדול מדי או
  /// שאינו minidump — הדיווח יישלח בלעדיו.
  static Future<AppReportMinidump?> fromFile(File file) async {
    try {
      final path = file.path;
      final gzipBytes = await Isolate.run(() => _readAndCompress(path));
      if (gzipBytes == null) return null;
      var name = p.basename(path);
      if (name.length > maxFileNameLength) {
        name = name.substring(name.length - maxFileNameLength);
      }
      return AppReportMinidump(gzipBytes: gzipBytes, fileName: name);
    } catch (error) {
      debugPrint('AppReportMinidump: unreadable: $error');
      return null;
    }
  }

  static Uint8List? _readAndCompress(String path) {
    final file = File(path);
    if (file.lengthSync() > maxRawBytes) return null;
    final bytes = file.readAsBytesSync();
    // 'MDMP'
    if (bytes.length < 4 ||
        bytes[0] != 0x4D ||
        bytes[1] != 0x44 ||
        bytes[2] != 0x4D ||
        bytes[3] != 0x50) {
      return null;
    }
    final compressed = Uint8List.fromList(gzip.encode(bytes));
    // dump שלא התכווץ עדיין נכנס בתקציב, אבל אין טעם לשלוח אותו גדול יותר.
    return compressed.length <= maxRawBytes ? compressed : null;
  }

  /// הרשומה בגוף הבקשה ובתור המקומי.
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'data': base64Encode(gzipBytes),
  };

  /// `null` לרשומה פגומה.
  static AppReportMinidump? fromJson(Object? json) {
    if (json is! Map) return null;
    final data = json['data'];
    if (data is! String) return null;
    try {
      return AppReportMinidump(
        gzipBytes: base64Decode(data),
        fileName: json['fileName'] is String ? json['fileName'] as String : '',
      );
    } on FormatException {
      return null;
    }
  }

  // הבתים נבדקים לפי זהות: השוואת תוכן של מגה-בתים בכל emit מיותרת.
  @override
  List<Object?> get props => [identityHashCode(gzipBytes), fileName];
}
