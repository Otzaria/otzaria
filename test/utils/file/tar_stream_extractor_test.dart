import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/tar_stream_extractor.dart';
import 'package:path/path.dart' as p;

import '../../empty_library/library_package_test_support.dart';

/// מזין את [bytes] בנתחים לא מיושרים, כמו פלט של מפענח zstd.
void feed(TarStreamExtractor tar, Uint8List bytes, {int chunk = 777}) {
  for (var offset = 0; offset < bytes.length; offset += chunk) {
    final end = (offset + chunk).clamp(0, bytes.length);
    tar.add(Uint8List.sublistView(bytes, offset, end));
  }
}

/// כותרת ustar ידנית — לרשומות שהמקודד אינו מייצר (pax, נתיב זדוני).
Uint8List header(String name, int size, {int type = 0x30}) {
  final h = Uint8List(512);
  h.setAll(0, utf8.encode(name));
  void octal(int offset, int length, int value) => h.setAll(
    offset,
    ascii.encode('${value.toRadixString(8).padLeft(length - 1, '0')}\u0000'),
  );
  octal(100, 8, 420);
  octal(124, 12, size);
  octal(136, 12, 0);
  h[156] = type;
  h.setAll(257, ascii.encode('ustar\u000000'));
  h.fillRange(148, 156, 0x20);
  final sum = h.fold<int>(0, (a, b) => a + b);
  h.setAll(148, ascii.encode('${sum.toRadixString(8).padLeft(6, '0')}\u0000 '));
  return h;
}

Uint8List padded(List<int> data) {
  final size = (data.length + 511) ~/ 512 * 512;
  return Uint8List(size)..setAll(0, data);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('tar_stream_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('פורס שמות בעברית, שם ארוך (GNU) ותיקיות לפי הנתיב', () {
    final longName = 'books/${'תלמוד בבלי/' * 6}ברכות.pdf';
    expect(utf8.encode(longName).length, greaterThan(100));
    final tar = buildTar(
      {
        'books/seforim.db': List.filled(3000, 7),
        'books/תלמוד בבלי/.version': utf8.encode('abc'),
        longName: utf8.encode('דף'),
      },
      dirs: ['books/', 'books/תלמוד בבלי/'],
    );
    final extractor = TarStreamExtractor(dir.path, rootFolder: 'books');
    feed(extractor, tar);
    extractor.close();

    expect(File(p.join(dir.path, 'books', 'seforim.db')).lengthSync(), 3000);
    expect(
      File(
        p.join(dir.path, 'books', 'תלמוד בבלי', '.version'),
      ).readAsStringSync(),
      'abc',
    );
    expect(
      File(p.joinAll([dir.path, ...longName.split('/')])).readAsStringSync(),
      'דף',
    );
    expect(extractor.filesWritten, 3);
  });

  test('נתיב מרשומת pax גובר על השם הקצר', () {
    const path = 'books/מילון.db';
    final record = ' path=$path\n';
    var length = utf8.encode(record).length;
    length += '$length'.length;
    final pax = utf8.encode('$length$record');
    final bytes = BytesBuilder()
      ..add(header('PaxHeader', pax.length, type: 0x78))
      ..add(padded(pax))
      ..add(header('books/x', 2))
      ..add(padded([1, 2]))
      ..add(Uint8List(1024));
    final extractor = TarStreamExtractor(dir.path, rootFolder: 'books');
    feed(extractor, bytes.takeBytes(), chunk: 100);
    extractor.close();
    expect(File(p.join(dir.path, 'books', 'מילון.db')).readAsBytesSync(), [
      1,
      2,
    ]);
  });

  test('נתיב שבורח מהיעד נדחה', () {
    final bytes = BytesBuilder()
      ..add(header('books/../evil.txt', 1))
      ..add(padded([1]));
    final extractor = TarStreamExtractor(dir.path, rootFolder: 'books');
    expect(() => feed(extractor, bytes.takeBytes()), throwsFormatException);
    expect(File(p.join(dir.path, 'evil.txt')).existsSync(), isFalse);
  });

  test('רשומה מחוץ לתיקיית השורש נדחית', () {
    final tar = buildTar({
      'index/meta.json': [1],
    });
    final extractor = TarStreamExtractor(dir.path, rootFolder: 'books');
    expect(() => feed(extractor, tar), throwsFormatException);
  });

  test('tar שנקטע באמצע קובץ נכשל ב-close', () {
    final tar = buildTar({'books/seforim.db': List.filled(5000, 1)});
    final extractor = TarStreamExtractor(dir.path, rootFolder: 'books');
    feed(extractor, Uint8List.sublistView(tar, 0, 2048));
    expect(extractor.close, throwsFormatException);
  });

  test('כותרת פגומה נתפסת ב-checksum', () {
    final tar = buildTar({
      'books/seforim.db': [1, 2, 3],
    });
    tar[10] ^= 0xFF;
    final extractor = TarStreamExtractor(dir.path, rootFolder: 'books');
    expect(() => feed(extractor, tar), throwsFormatException);
  });
}
