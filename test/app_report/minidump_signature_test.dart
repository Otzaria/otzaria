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

    // כמו ב-dump אמיתי של crashpad: סגמנט ה-text של app.so ב-0xfec000 מבסיס ההקצאה.
    const dartText = (
      base: 0x20840b7c000,
      allocationBase: 0x2083fb90000,
      size: 0x133e000,
      protect: 0x20, // PAGE_EXECUTE_READ
      type: 0x20000, // MEM_PRIVATE
    );

    test('קריסה בקוד Dart — app.so+היסט מבסיס ההקצאה', () async {
      final signature = await readMinidumpSignature(
        write(
          buildMinidump(
            exceptionAddress: 0x20840d6b25a,
            memoryRegions: const [dartText],
          ),
        ),
      );
      expect(signature!.exceptionType, '0xc0000005 app.so+0x11db25a');
      expect(signature.frames, ['app.so+0x11db25a']);
    });

    test(
      'זיכרון פרטי שאינו קוד, או image בלי מודול — קוד החריגה בלבד',
      () async {
        for (final region in [
          (
            base: dartText.base,
            allocationBase: dartText.allocationBase,
            size: dartText.size,
            protect: 0x04, // PAGE_READWRITE
            type: 0x20000,
          ),
          (
            base: dartText.base,
            allocationBase: dartText.allocationBase,
            size: dartText.size,
            protect: 0x20,
            type: 0x1000000, // MEM_IMAGE
          ),
        ]) {
          final signature = await readMinidumpSignature(
            write(
              buildMinidump(
                exceptionAddress: 0x20840d6b25a,
                memoryRegions: [region],
              ),
            ),
          );
          expect(signature!.exceptionType, '0xc0000005');
          expect(signature.frames, isEmpty);
        }
      },
    );

    test('מודול קודם למפת הזיכרון', () async {
      final signature = await readMinidumpSignature(
        write(
          buildMinidump(
            memoryRegions: const [
              (
                base: 0x7ffa10000000,
                allocationBase: 0x7ffa10000000,
                size: 0x2000000,
                protect: 0x20,
                type: 0x20000,
              ),
            ],
          ),
        ),
      );
      expect(signature!.frames, ['flutter_windows.dll+0x1e220']);
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
