import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/hang_report_symbolizer.dart';

/// ELF64 מינימלי: build-id ושתי פונקציות, במבנה של קובץ `--save-debugging-info`.
Uint8List debugElf({
  List<int> buildId = const [0xde, 0xad, 0xbe, 0xef],
  Map<String, (int, int)> functions = const {
    'WidgetsBinding.drawFrame': (0x1000, 0x180),
    '_InactiveElements._unmount': (0x2000, 0x79),
  },
}) {
  final strings = BytesBuilder()..addByte(0);
  final symbols = BytesBuilder()..add(Uint8List(24));
  functions.forEach((name, range) {
    final entry = ByteData(24)
      ..setUint32(0, strings.length, Endian.little)
      ..setUint8(4, 0x12)
      ..setUint64(8, range.$1, Endian.little)
      ..setUint64(0x10, range.$2, Endian.little);
    symbols.add(entry.buffer.asUint8List());
    strings
      ..add(utf8.encode(name))
      ..addByte(0);
  });
  final note = ByteData(16 + buildId.length)
    ..setUint32(0, 4, Endian.little)
    ..setUint32(4, buildId.length, Endian.little)
    ..setUint32(8, 3, Endian.little);
  final noteBytes = note.buffer.asUint8List()
    ..setAll(12, utf8.encode('GNU\x00'))
    ..setAll(16, buildId);

  final bodies = [noteBytes, symbols.toBytes(), strings.toBytes()];
  final offsets = <int>[];
  var at = 64;
  for (final body in bodies) {
    offsets.add(at);
    at += body.length;
  }
  final shoff = at;
  // NULL, .note (7), .symtab (2, link → 3), .strtab (3)
  final sections = [
    (0, 0, 0, 0),
    (7, offsets[0], bodies[0].length, 0),
    (2, offsets[1], bodies[1].length, 3),
    (3, offsets[2], bodies[2].length, 0),
  ];

  final out = BytesBuilder();
  final header = ByteData(64)
    ..setUint32(0, 0x464c457f, Endian.little)
    ..setUint8(4, 2)
    ..setUint8(5, 1)
    ..setUint64(0x28, shoff, Endian.little)
    ..setUint16(0x3a, 64, Endian.little)
    ..setUint16(0x3c, sections.length, Endian.little);
  out.add(header.buffer.asUint8List());
  for (final body in bodies) {
    out.add(body);
  }
  for (final (type, offset, size, link) in sections) {
    out.add(
      (ByteData(64)
            ..setUint32(4, type, Endian.little)
            ..setUint64(0x18, offset, Endian.little)
            ..setUint64(0x20, size, Endian.little)
            ..setUint32(0x28, link, Endian.little))
          .buffer
          .asUint8List(),
    );
  }
  return out.toBytes();
}

void main() {
  test('קורא build-id ומאתר פונקציה לפי כתובת', () {
    final symbols = DartSymbols.parse(debugElf());
    expect(symbols.buildId, 'deadbeef');
    expect(symbols.lookup(0x10c4), 'WidgetsBinding.drawFrame+0xc4');
    expect(symbols.lookup(0x2000), '_InactiveElements._unmount+0x0');
    expect(symbols.lookup(0x1180), isNull);
    expect(symbols.lookup(0x10), isNull);
  });

  test('קובץ שאינו ELF64 נדחה', () {
    expect(
      () => DartSymbols.parse(Uint8List.fromList(List.filled(64, 0))),
      throwsFormatException,
    );
  });

  test('מוסיף שמות לפריימי app.so, ומשאיר בלי שמות רשומה של בנייה אחרת', () {
    final symbols = DartSymbols.parse(debugElf());
    final output = symbolizeHangReport(
      '=== App hang 2026-10-23T00:03:14Z ===\n'
      'Dart build-id: DEADBEEF\n'
      'Stack (module+RVA):\n'
      '  app.so+0x204f\n'
      '  app.so+0x10c4\n'
      '  flutter_windows.dll+0x7fa88b\n'
      '=== App hang 2026-10-24T00:03:14Z ===\n'
      'Dart build-id: 0123\n'
      'Module PDB: dwrite.dll dwrite.pdb 3F2A0B1C4D5E6F708192A3B4C5D6E7F81\n'
      'Stack (module+RVA):\n'
      '  app.so+0x204f\n',
      symbols,
    );
    expect(
      const LineSplitter().convert(output),
      [
        '=== App hang 2026-10-23T00:03:14Z ===',
        'Dart build-id: DEADBEEF',
        'Stack (module+RVA):',
        '  app.so+0x204f  _InactiveElements._unmount+0x4f',
        '  app.so+0x10c4  WidgetsBinding.drawFrame+0xc4',
        '  flutter_windows.dll+0x7fa88b',
        '=== App hang 2026-10-24T00:03:14Z ===',
        'Dart build-id: 0123',
        '  (symbols file build-id deadbeef does not match; frames left unnamed)',
        'Module PDB: dwrite.dll dwrite.pdb 3F2A0B1C4D5E6F708192A3B4C5D6E7F81',
        '  https://msdl.microsoft.com/download/symbols/dwrite.pdb/'
            '3F2A0B1C4D5E6F708192A3B4C5D6E7F81/dwrite.pdb',
        'Stack (module+RVA):',
        '  app.so+0x204f',
      ],
    );
  });

  test('שורת ההשמטה נשארת כמו שהיא, ופריימי התחתית מקבלים שמות', () {
    final symbols = DartSymbols.parse(debugElf());
    final output = symbolizeHangReport(
      '=== App hang 2026-10-30T00:03:14Z ===\n'
      'Dart build-id: deadbeef\n'
      'Stack (module+RVA):\n'
      '  app.so+0x204f\n'
      '  ... (1234 frames omitted) ...\n'
      '  app.so+0x10c4\n',
      symbols,
    );
    expect(const LineSplitter().convert(output), [
      '=== App hang 2026-10-30T00:03:14Z ===',
      'Dart build-id: deadbeef',
      'Stack (module+RVA):',
      '  app.so+0x204f  _InactiveElements._unmount+0x4f',
      '  ... (1234 frames omitted) ...',
      '  app.so+0x10c4  WidgetsBinding.drawFrame+0xc4',
    ]);
  });
}
