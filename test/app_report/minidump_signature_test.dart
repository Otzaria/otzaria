import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/minidump_signature.dart';
import 'package:path/path.dart' as p;

import 'minidump_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('otzaria_minidump_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(Uint8List bytes) =>
      File(p.join(tmp.path, 'crash.dmp'))..writeAsBytesSync(bytes);

  group('readMinidumpSignature (issue #1978)', () {
    test('קוד החריגה ומודול+היסט, בלי נתיב (issue #1978)', () async {
      final signature = await readMinidumpSignature(write(buildMinidump()));
      expect(
        signature!.exceptionType,
        '0xc0000005 flutter_windows.dll+0x1e220',
      );
      expect(signature.frames, ['flutter_windows.dll+0x1e220']);
    });

    test('כתובת מחוץ לכל מודול — קוד החריגה בלבד (issue #1978)', () async {
      final signature = await readMinidumpSignature(
        write(buildMinidump(exceptionAddress: 0x1234)),
      );
      expect(signature!.exceptionType, '0xc0000005');
      expect(signature.frames, isEmpty);
    });

    test('רשימת מודולים קטועה — קוד החריגה נשמר (issue #1978)', () async {
      final full = buildMinidump();
      final signature = await readMinidumpSignature(
        write(Uint8List.sublistView(full, 0, 120)),
      );
      expect(signature!.exceptionType, '0xc0000005');
      expect(signature.frames, isEmpty);
    });

    test('קובץ פגום, קטוע או בלי זרם חריגה — null (issue #1978)', () async {
      final full = buildMinidump();
      expect(
        await readMinidumpSignature(
          write(Uint8List.fromList('dump'.codeUnits)),
        ),
        isNull,
      );
      expect(
        await readMinidumpSignature(write(Uint8List.sublistView(full, 0, 40))),
        isNull,
      );
      final badMagic = Uint8List.fromList(full)..[0] = 0;
      expect(await readMinidumpSignature(write(badMagic)), isNull);
      expect(
        await readMinidumpSignature(write(buildMinidump(withException: false))),
        isNull,
      );
    });
  });
}
