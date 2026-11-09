import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/download_space.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  late Directory dir;
  late String dest;
  const identity = 'v31';
  const split = SplitAsset(
    archive: 'seforim.db.zst',
    size: 70,
    sha256: 'whole',
    manifestName: 'seforim.db.zst.manifest.json',
    parts: [
      SplitAssetPart(
        name: 'part-0',
        size: 50,
        sha256: 'first',
        downloadUrl: 'x',
      ),
      SplitAssetPart(
        name: 'part-1',
        size: 20,
        sha256: 'second',
        downloadUrl: 'y',
      ),
    ],
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('download_space_test');
    dest = '${dir.path}/seforim.db.zst';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<int> needed() => additionalDownloadBytes(
    destPath: dest,
    identity: identity,
    size: split.size,
    split: split,
  );

  void cache(String file, int length, String token, [String? etag]) {
    File(file).writeAsBytesSync(List.filled(length, 0));
    File(PatchDownloader.resumeSidecarPath(file)).writeAsStringSync(
      etag == null ? token : '$token\n$etag',
    );
  }

  test('הורדה חדשה שומרת מקום לכל החלקים ולארכיון המחובר', () async {
    expect(await needed(), 140);
  });

  test('חלק שלם וחלקי עם validator מזוכים לפי הטוקן שלהם', () async {
    cache(PatchDownloader.splitPartPath(dest, 0), 50, 'v31|part-0|first');
    cache(
      PatchDownloader.splitPartPath(dest, 1),
      10,
      'v31|part-1|second',
      '"e"',
    );
    expect(await needed(), 80);
  });

  test('חלקים מלאים נשמרים בזמן חיבור ולכן דרוש ארכיון נוסף', () async {
    cache(PatchDownloader.splitPartPath(dest, 0), 50, 'v31|part-0|first');
    cache(PatchDownloader.splitPartPath(dest, 1), 20, 'v31|part-1|second');
    expect(await needed(), 70);
  });

  test('קובץ חיבור שנקטע אינו מזוכה כעותק שניתן להמשך', () async {
    File('$dest.joining').writeAsBytesSync(List.filled(60, 0));
    expect(await needed(), 140);
  });

  test('טוקן שונה, validator חלש וחלק ארוך מדי אינם מזוכים', () async {
    cache(PatchDownloader.splitPartPath(dest, 0), 50, 'v30|part-0|first');
    cache(
      PatchDownloader.splitPartPath(dest, 1),
      10,
      'v31|part-1|second',
      'W/"e"',
    );
    expect(await needed(), 140);
    cache(PatchDownloader.splitPartPath(dest, 0), 51, 'v31|part-0|first');
    expect(await needed(), 140);
  });

  test('ארכיון מחובר מהורדה קודמת אינו דורש הורדה או חיבור שוב', () async {
    cache(dest, 70, 'v31|joined:whole');
    expect(await needed(), 0);
  });

  test('ארכיון מחובר חלקי אינו ניתן להמשך', () async {
    cache(dest, 69, 'v31|joined:whole', '"e"');
    expect(await needed(), 140);
  });

  test('קובץ יחיד מזוכה רק עם זהות תואמת ו-validator או גודל מלא', () async {
    cache(dest, 35, 'v31', '"e"');
    expect(
      await additionalDownloadBytes(
        destPath: dest,
        identity: identity,
        size: 70,
      ),
      35,
    );
    cache(dest, 35, 'v30', '"e"');
    expect(
      await additionalDownloadBytes(
        destPath: dest,
        identity: identity,
        size: 70,
      ),
      70,
    );
    cache(dest, 70, 'v31');
    expect(
      await additionalDownloadBytes(
        destPath: dest,
        identity: identity,
        size: 70,
      ),
      0,
    );
  });
}
