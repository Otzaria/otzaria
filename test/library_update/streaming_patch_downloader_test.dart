import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/services/streaming_patch_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('streaming_dl_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // "patch" מדומה: הדחוס הוא הבייטים שמוגשים; ה"חילוץ" מעתיק קובץ ומהפך אותו.
  final compressed = Uint8List.fromList(List.generate(4096, (i) => i % 251));
  final uncompressed = Uint8List.fromList(compressed.reversed.toList());

  PatchFileEntry entry({String? uncompressedHash, int? uncompressedSize}) =>
      PatchFileEntry(
        file: 'patch-v1-v2.db.zst',
        compression: 'zstd',
        sha256: sha256.convert(compressed).toString(),
        size: compressed.length,
        uncompressedSha256:
            uncompressedHash ?? sha256.convert(uncompressed).toString(),
        uncompressedSize: uncompressedSize ?? uncompressed.length,
      );

  var extractorCalls = 0;
  Future<void> reversingExtractor(String src, String dst) async {
    extractorCalls++;
    final bytes = File(src).readAsBytesSync();
    File(dst).writeAsBytesSync(bytes.reversed.toList(), flush: true);
  }

  StreamingPatchDownloader build() {
    extractorCalls = 0;
    final mock = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(compressed),
        200,
        contentLength: compressed.length,
        headers: {'etag': '"v1"'},
      );
    });
    return StreamingPatchDownloader(
      httpClient: mock,
      extractor: reversingExtractor,
    );
  }

  // כל הגעה לרשת בבדיקות השימוש-החוזר היא כשל הבדיקה עצמה.
  StreamingPatchDownloader buildNoNetwork() {
    extractorCalls = 0;
    return StreamingPatchDownloader(
      httpClient: MockClient.streaming(
        (request, bodyStream) async => throw StateError('אסור להוריד'),
      ),
      extractor: reversingExtractor,
    );
  }

  test('מחולץ מאומת שנשאר בקאש → שימוש חוזר בלי הורדה', () async {
    final extractedPath = p.join(tmp.path, 'patch-v1-v2.db');
    File(extractedPath).writeAsBytesSync(uncompressed, flush: true);
    final leftoverArchive = File(p.join(tmp.path, 'patch-v1-v2.db.zst'))
      ..writeAsBytesSync(compressed, flush: true);
    final progress = <(int, int?)>[];

    final path = await buildNoNetwork().downloadAndExtract(
      patchFile: entry(),
      downloadUrl: 'https://x/patch-v1-v2.db.zst',
      destDir: tmp,
      onProgress: (d, t) => progress.add((d, t)),
    );

    expect(path, extractedPath);
    expect(extractorCalls, 0);
    expect(progress.last, (compressed.length, compressed.length));
    expect(leftoverArchive.existsSync(), isFalse);
  });

  test('אימות המחולץ מדווח התקדמות בבייטים, מ-0 ועד גודל הקובץ', () async {
    final extractedPath = p.join(tmp.path, 'patch-v1-v2.db');
    File(extractedPath).writeAsBytesSync(uncompressed, flush: true);
    final verify = <(int, int)>[];

    await buildNoNetwork().downloadAndExtract(
      patchFile: entry(),
      downloadUrl: 'https://x/patch-v1-v2.db.zst',
      destDir: tmp,
      onVerifyProgress: (d, t) => verify.add((d, t)),
    );

    expect(verify.first, (0, uncompressed.length));
    expect(verify.last, (uncompressed.length, uncompressed.length));
    expect(verify.every((e) => e.$2 == uncompressed.length), isTrue);
  });

  // ב-bloc ה-callbacks לוכדים Emitter עם Completer — אסור שייגררו ל-isolate.
  test('callbacks שלוכדים אובייקט לא-sendable לא מפילים את האימות', () async {
    final extractedPath = p.join(tmp.path, 'patch-v1-v2.db');
    File(extractedPath).writeAsBytesSync(uncompressed, flush: true);
    final unsendable = Completer<void>();

    final path = await buildNoNetwork().downloadAndExtract(
      patchFile: entry(),
      downloadUrl: 'https://x/patch-v1-v2.db.zst',
      destDir: tmp,
      onVerifyProgress: (d, t) => unsendable.isCompleted,
      isCancelled: () => unsendable.isCompleted,
    );

    expect(path, extractedPath);
  });

  test(
    'ביטול באמצע אימות המחולץ → PatchDownloadCancelled, הקובץ נשאר',
    () async {
      final extractedPath = p.join(tmp.path, 'patch-v1-v2.db');
      File(extractedPath).writeAsBytesSync(uncompressed, flush: true);
      var cancelled = false;

      await expectLater(
        buildNoNetwork().downloadAndExtract(
          patchFile: entry(),
          downloadUrl: 'https://x/patch-v1-v2.db.zst',
          destDir: tmp,
          onVerifyProgress: (d, t) => cancelled = true,
          isCancelled: () => cancelled,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      // הקובץ תקין — נמחק רק כשהאימות נכשל, לא כשהופסק.
      expect(File(extractedPath).existsSync(), isTrue);
    },
  );

  test('מחולץ בגודל תואם אך hash שגוי → נמחק ומורידים מחדש', () async {
    final extractedPath = p.join(tmp.path, 'patch-v1-v2.db');
    File(extractedPath).writeAsBytesSync(
      Uint8List(uncompressed.length), // אותו גודל, תוכן אחר
      flush: true,
    );

    final path = await build().downloadAndExtract(
      patchFile: entry(),
      downloadUrl: 'https://x/patch-v1-v2.db.zst',
      destDir: tmp,
    );

    expect(path, extractedPath);
    expect(extractorCalls, 1);
    expect(File(path).readAsBytesSync(), uncompressed);
  });

  test('הורדה לדיסק + חילוץ זורם → .db מאומת, הדחוס נמחק', () async {
    final path = await build().downloadAndExtract(
      patchFile: entry(),
      downloadUrl: 'https://x/patch-v1-v2.db.zst',
      destDir: tmp,
    );
    expect(p.basename(path), 'patch-v1-v2.db');
    expect(File(path).readAsBytesSync(), uncompressed);
    expect(extractorCalls, 1);
    expect(File(p.join(tmp.path, 'patch-v1-v2.db.zst')).existsSync(), isFalse);
    expect(
      File(p.join(tmp.path, 'patch-v1-v2.db.zst.resume')).existsSync(),
      isFalse,
    );
  });

  test(
    'sha256 מחולץ שגוי → PatchDownloadException ושום קובץ לא נשאר',
    () async {
      await expectLater(
        build().downloadAndExtract(
          patchFile: entry(uncompressedHash: 'deadbeef'),
          downloadUrl: 'https://x/p.zst',
          destDir: tmp,
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(tmp.listSync(), isEmpty);
    },
  );

  test('onVerifyProgress מדווח את גודל המחולץ בסיום האימות', () async {
    final reports = <(int, int)>[];
    await build().downloadAndExtract(
      patchFile: entry(),
      downloadUrl: 'https://x/patch-v1-v2.db.zst',
      destDir: tmp,
      onVerifyProgress: (done, total) => reports.add((done, total)),
    );
    expect(reports, isNotEmpty);
    expect(reports.last, (uncompressed.length, uncompressed.length));
  });

  test('גודל מחולץ שגוי → PatchDownloadException', () async {
    await expectLater(
      build().downloadAndExtract(
        patchFile: entry(uncompressedSize: uncompressed.length + 1),
        downloadUrl: 'https://x/p.zst',
        destDir: tmp,
      ),
      throwsA(isA<PatchDownloadException>()),
    );
    expect(File(p.join(tmp.path, 'p')).existsSync(), isFalse);
  });
}
