import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/native_sha256.dart';

void main() {
  late Directory dir;
  setUpAll(() => dir = Directory.systemTemp.createTempSync('native_sha_'));
  tearDownAll(() => dir.deleteSync(recursive: true));

  final nativeSupported = Platform.isWindows || Platform.isMacOS;
  const chunk = 8 * 1024 * 1024;
  final rnd = Random(7);

  for (final size in [
    0,
    1,
    55,
    64,
    chunk - 1,
    chunk,
    chunk + 1,
    10 * 1024 * 1024,
    2 * chunk + 5,
  ]) {
    test('זהה ל-package:crypto בגודל $size', () async {
      final bytes = Uint8List.fromList(
        List.generate(size, (_) => rnd.nextInt(256)),
      );
      final file = File('${dir.path}/f$size')..writeAsBytesSync(bytes);
      expect(
        await sha256OfFileFast(file.path),
        sha256.convert(bytes).toString(),
      );
    }, skip: nativeSupported ? false : 'אין מימוש נייטיבי בפלטפורמה זו');
  }

  test('כשל טעינת הספרייה נופל ל-package:crypto', () async {
    final bytes = Uint8List.fromList(
      List.generate(1000, (_) => rnd.nextInt(256)),
    );
    final file = File('${dir.path}/fallback')..writeAsBytesSync(bytes);
    final digest = await sha256OfFileFast(
      file.path,
      loadNative: () => throw ArgumentError('simulated load failure'),
    );
    expect(digest, sha256.convert(bytes).toString());
  });

  test('קובץ חסר: PathNotFoundException ולא נבלע', () async {
    await expectLater(
      sha256OfFileFast('${dir.path}/missing'),
      throwsA(isA<PathNotFoundException>()),
    );
  });

  test('הספרייה הנייטיבית נטענת ללא מעבר למסלול Dart', () async {
    final file = File('${dir.path}/native')..writeAsStringSync('abc');
    final messages = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    try {
      expect(
        await sha256OfFileFast(file.path),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(messages, isEmpty);
    } finally {
      debugPrint = originalDebugPrint;
    }
  }, skip: nativeSupported ? false : 'אין מימוש נייטיבי בפלטפורמה זו');

  test('חישובים ב-isolates מקבילים משתמשים בהקשרים נפרדים', () async {
    final files = List.generate(4, (index) {
      final bytes = Uint8List.fromList(
        List.generate(chunk + index, (offset) => (offset + index) % 256),
      );
      final file = File('${dir.path}/parallel$index')..writeAsBytesSync(bytes);
      return (path: file.path, digest: sha256.convert(bytes).toString());
    });
    final results = await Future.wait(
      files.map((file) => Isolate.run(() => sha256OfFileFast(file.path))),
    );
    expect(results, files.map((file) => file.digest).toList());
  }, skip: nativeSupported ? false : 'אין מימוש נייטיבי בפלטפורמה זו');

  test('קובץ חסר משחרר hasher בלי לאתחל אותו', () async {
    final calls = <String>[];
    await expectLater(
      sha256OfFileFast(
        '${dir.path}/missing-with-hasher',
        loadNative: () => NativeSha256(
          () => calls.add('init'),
          (_, _) => calls.add('update'),
          (_) => calls.add('finish'),
          () => calls.add('dispose'),
        ),
      ),
      throwsA(isA<PathNotFoundException>()),
    );
    expect(calls, ['dispose']);
  });

  for (final failure in ['init', 'update', 'finish']) {
    test('כשל $failure מועבר לקורא ומשחרר את המשאבים', () async {
      final file = File('${dir.path}/failure-$failure')
        ..writeAsStringSync('abc');
      final calls = <String>[];
      final error = StateError('simulated $failure failure');
      void call(String stage) {
        calls.add(stage);
        if (stage == failure) throw error;
      }

      await expectLater(
        sha256OfFileFast(
          file.path,
          loadNative: () => NativeSha256(
            () => call('init'),
            (Pointer<Uint8> _, int _) => call('update'),
            (_) => call('finish'),
            () => call('dispose'),
          ),
        ),
        throwsA(same(error)),
      );
      expect(calls, [
        ...['init', 'update', 'finish'].takeWhile((stage) => stage != failure),
        failure,
        'dispose',
      ]);
      await file.delete();
      expect(file.existsSync(), isFalse);
    });
  }
}
