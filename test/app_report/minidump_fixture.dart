import 'dart:typed_data';

/// minidump מינימלי: כותרת, זרם חריגה ורשימת מודולים — במבנה של Windows.
Uint8List buildMinidump({
  int exceptionCode = 0xc0000005,
  int exceptionAddress = 0x7ffa1001e220,
  bool withException = true,
  List<({String path, int base, int size})> modules = const [
    (
      path: r'C:\Program Files\Otzaria\otzaria.exe',
      base: 0x7ff600000000,
      size: 0x100000,
    ),
    (
      path: r'C:\Users\someone\AppData\Local\Otzaria\flutter_windows.dll',
      base: 0x7ffa10000000,
      size: 0x2000000,
    ),
  ],
}) {
  const headerSize = 32;
  const exceptionSize = 168;
  const moduleSize = 108;
  final streamCount = withException ? 2 : 1;
  final directoryRva = headerSize;
  final exceptionRva = directoryRva + streamCount * 12;
  final moduleListRva = exceptionRva + (withException ? exceptionSize : 0);
  var namesRva = moduleListRva + 4 + modules.length * moduleSize;
  final nameRvas = <int>[];
  for (final module in modules) {
    nameRvas.add(namesRva);
    namesRva += 4 + module.path.length * 2;
  }

  final data = ByteData(namesRva);
  data.setUint32(0, 0x504d444d, Endian.little);
  data.setUint32(4, 0xa793, Endian.little);
  data.setUint32(8, streamCount, Endian.little);
  data.setUint32(12, directoryRva, Endian.little);

  var entry = directoryRva;
  void directoryEntry(int type, int size, int rva) {
    data.setUint32(entry, type, Endian.little);
    data.setUint32(entry + 4, size, Endian.little);
    data.setUint32(entry + 8, rva, Endian.little);
    entry += 12;
  }

  if (withException) {
    directoryEntry(6, exceptionSize, exceptionRva);
    data.setUint32(exceptionRva, 4242, Endian.little);
    data.setUint32(exceptionRva + 8, exceptionCode, Endian.little);
    data.setUint64(exceptionRva + 24, exceptionAddress, Endian.little);
  }
  directoryEntry(4, 4 + modules.length * moduleSize, moduleListRva);
  data.setUint32(moduleListRva, modules.length, Endian.little);
  for (var i = 0; i < modules.length; i++) {
    final at = moduleListRva + 4 + i * moduleSize;
    data.setUint64(at, modules[i].base, Endian.little);
    data.setUint32(at + 8, modules[i].size, Endian.little);
    data.setUint32(at + 20, nameRvas[i], Endian.little);
    final path = modules[i].path;
    data.setUint32(nameRvas[i], path.length * 2, Endian.little);
    for (var j = 0; j < path.length; j++) {
      data.setUint16(
        nameRvas[i] + 4 + j * 2,
        path.codeUnitAt(j),
        Endian.little,
      );
    }
  }
  return data.buffer.asUint8List();
}
