import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:path/path.dart' as p;

class _PausedFirstReadFile implements File {
  _PausedFirstReadFile(this.file);

  final File file;
  final started = Completer<void>();
  final resume = Completer<void>();

  @override
  String get path => file.path;

  @override
  Future<FileStat> stat() => file.stat();

  @override
  Future<String> resolveSymbolicLinks() => file.resolveSymbolicLinks();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    if (!started.isCompleted) {
      started.complete();
      await resume.future;
    }
    return file.open(mode: mode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  for (final sameSize in [false, true]) {
    test(
      'קריאה אחרי שמירה אינה מצטרפת לקריאה הישנה (אותו גודל: $sameSize)',
      () async {
        final source = File(p.join(tempDir.path, 'מתעדכן.txt'));
        await source.writeAsString('old content');
        final modified = DateTime(2025);
        await source.setLastModified(modified);
        final file = File(await source.resolveSymbolicLinks());
        final paused = _PausedFirstReadFile(file);
        final updated = sameSize ? 'new content' : 'a longer updated content';

        await IOOverrides.runZoned(() async {
          final first = readFileBackedBookText(paused, 'txt', 'ספר');
          try {
            await paused.started.future.timeout(const Duration(seconds: 5));
            await file.writeAsString(updated, flush: true);
            await file.setLastModified(
              sameSize ? modified.add(const Duration(seconds: 1)) : modified,
            );

            expect(
              await readFileBackedBookText(
                paused,
                'txt',
                'ספר',
              ).timeout(const Duration(seconds: 5)),
              updated,
            );
          } finally {
            paused.resume.complete();
            await first;
          }
        }, createFile: (path) => paused);
      },
    );
  }

  test('החלפת symlink בזמן קריאה משאירה כל קריאה עם היעד שלה', () async {
    final oldSource = File(p.join(tempDir.path, 'ישן.txt'));
    final newSource = File(p.join(tempDir.path, 'חדש.txt'));
    await oldSource.writeAsString('old content');
    await newSource.writeAsString('new content');
    final oldFile = File(await oldSource.resolveSymbolicLinks());
    final newFile = File(await newSource.resolveSymbolicLinks());
    final link = await Link(
      p.join(tempDir.path, 'קישור.txt'),
    ).create(oldFile.path);
    final linkedFile = File(link.path);
    final paused = _PausedFirstReadFile(oldFile);

    await IOOverrides.runZoned(() async {
      final first = readFileBackedBookText(linkedFile, 'txt', 'ספר');
      try {
        await paused.started.future.timeout(const Duration(seconds: 5));
        await link.update(newFile.path);
        expect(
          await readFileBackedBookText(
            linkedFile,
            'txt',
            'ספר',
          ).timeout(const Duration(seconds: 5)),
          'new content',
        );
      } finally {
        paused.resume.complete();
        expect(await first, 'old content');
      }
    }, createFile: (path) => path == oldFile.path ? paused : newFile);
  }, skip: Platform.isWindows);

  test('כשל בקריאת txt משותף מתנקה ומאפשר ניסיון חוזר', () async {
    final zip = Uint8List(2 << 20)..setAll(0, [0x50, 0x4B, 0x03, 0x04]);
    final file = File(p.join(tempDir.path, 'מוסווה.txt'))
      ..writeAsBytesSync(zip);
    Future<Object?> readOrError() => readFileBackedBookText(
      file,
      'txt',
      'ספר',
    ).then<Object?>((text) => text, onError: (Object error) => error);

    final errors = await Future.wait([
      for (var i = 0; i < 4; i++) readOrError(),
    ]);
    expect(errors, everyElement(isA<UnsupportedDocumentFormatException>()));
    final retry = await readOrError();
    expect(retry, isA<UnsupportedDocumentFormatException>());
    expect(
      identical(retry, errors.first),
      isFalse,
      reason: 'ניסיון חוזר באותה גרסה אינו מקבל שגיאה שמורה',
    );
    await file.writeAsString('restored content');
    expect(
      await readFileBackedBookText(file, 'txt', 'ספר'),
      'restored content',
    );
  });
}
