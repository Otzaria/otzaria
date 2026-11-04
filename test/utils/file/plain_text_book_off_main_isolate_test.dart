import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:path/path.dart' as p;

/// פענוח ספר txt גדול רץ מחוץ ל-main isolate, כדי שפתיחת ספר אישי גדול
/// לא תקפיא את הממשק.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('plain-text-isolate-');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// טקסט עברי ב-Windows-1255 (אותיות 0xE0–0xFA), כך שהמסלול המהיר של
  /// UTF-8 נכשל ומתבצע הזיהוי המלא.
  Uint8List legacyHebrewBytes(int size) {
    final bytes = Uint8List(size);
    for (var i = 0; i < size; i++) {
      bytes[i] = i % 61 == 60
          ? 0x0A
          : i % 6 == 5
          ? 0x20
          : 0xE0 + (i * 7) % 27;
    }
    return bytes;
  }

  Future<int> maxMainIsolateBlockMs(Future<void> Function() action) async {
    var maxGapUs = 0;
    final sinceTick = Stopwatch()..start();
    var done = false;
    Future<void> ticker() async {
      while (true) {
        if (sinceTick.elapsedMicroseconds > maxGapUs) {
          maxGapUs = sinceTick.elapsedMicroseconds;
        }
        if (done) return;
        sinceTick.reset();
        await Future<void>.delayed(Duration.zero);
      }
    }

    final ticking = ticker();
    await action();
    done = true;
    await ticking;
    return maxGapUs ~/ 1000;
  }

  test('ספר txt גדול אינו חוסם את ה-main isolate בפענוח', () async {
    final file = File(p.join(tempDir.path, 'גדול.txt'))
      ..writeAsBytesSync(legacyHebrewBytes(8 << 20));

    // חימום: טעינת הקוד והקצאות ראשונות אינן חלק מהמדידה.
    await readFileBackedBookText(file, 'txt', 'גדול');

    String? text;
    final blockMs = await maxMainIsolateBlockMs(() async {
      text = await readFileBackedBookText(file, 'txt', 'גדול');
    });

    expect(text, decodeTextBytesSmart(file.readAsBytesSync()));
    expect(blockMs, lessThan(60), reason: 'main isolate נחסם ל-${blockMs}ms');
  });

  test('התוצאה זהה לפענוח הישיר, בכל גודל וקידוד', () async {
    final hebrew = utf8.encode('${'שורה ראשונה בספר\n' * 70000}סוף');
    final cases = <String, Uint8List>{
      'קטן-utf8.txt': Uint8List.fromList(utf8.encode('שלום עולם\nשורה')),
      'קטן-1255.txt': legacyHebrewBytes(4096),
      'גדול-utf8.txt': Uint8List.fromList(hebrew),
      'גדול-bom.txt': Uint8List.fromList([0xEF, 0xBB, 0xBF, ...hebrew]),
      'גדול-1255.txt': legacyHebrewBytes(2 << 20),
      'ריק.txt': Uint8List(0),
    };
    for (final entry in cases.entries) {
      final file = File(p.join(tempDir.path, entry.key))
        ..writeAsBytesSync(entry.value);
      expect(
        await readFileBackedBookText(file, 'txt', 'ספר'),
        decodeTextBytesSmart(entry.value),
        reason: entry.key,
      );
    }
  });

  // כל קישור מפרש גלוי קרא את הקובץ כולו ב-isolate משלו, במקביל.
  test('קריאות מקבילות של אותו txt חולקות קריאה אחת', () async {
    final file = File(p.join(tempDir.path, 'מפרש.txt'))
      ..writeAsBytesSync(legacyHebrewBytes(1 << 20));

    final texts = await Future.wait([
      for (var i = 0; i < 12; i++) readFileBackedBookText(file, 'txt', 'מפרש'),
    ]);

    expect(texts.first, decodeTextBytesSmart(file.readAsBytesSync()));
    for (final text in texts) {
      expect(identical(text, texts.first), isTrue);
    }

    final later = await readFileBackedBookText(file, 'txt', 'מפרש');
    expect(identical(later, texts.first), isFalse, reason: 'אין מטמון קבוע');
  });

  test('מכולה בינארית גדולה בסיומת txt עדיין נדחית', () async {
    final zip = Uint8List(2 << 20)..setAll(0, [0x50, 0x4B, 0x03, 0x04]);
    final file = File(p.join(tempDir.path, 'מוסווה.txt'))
      ..writeAsBytesSync(zip);
    await expectLater(
      readFileBackedBookText(file, 'txt', 'ספר'),
      throwsA(isA<UnsupportedDocumentFormatException>()),
    );
  });
}
