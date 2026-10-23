import 'dart:convert';
import 'dart:typed_data';

/// טבלת הסמלים וה-build-id מקובץ הסמלים של app.so (`--save-debugging-info`).
class DartSymbols {
  DartSymbols._(this.buildId, this._starts, this._ends, this._names);

  /// מפענח ELF64 little-endian. זורק [FormatException] על קובץ אחר.
  factory DartSymbols.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 64 ||
        bytes[0] != 0x7f ||
        bytes[1] != 0x45 ||
        bytes[2] != 0x4c ||
        bytes[3] != 0x46 ||
        bytes[4] != 2 ||
        bytes[5] != 1) {
      throw const FormatException('not a 64-bit little-endian ELF file');
    }
    final shoff = data.getUint64(0x28, Endian.little);
    final shentsize = data.getUint16(0x3a, Endian.little);
    final shnum = data.getUint16(0x3c, Endian.little);

    final sections = [
      for (var i = 0; i < shnum; i++)
        _Section.read(data, shoff + i * shentsize),
    ];

    String? buildId;
    final symbols = <(int, int, String)>[];
    for (final section in sections) {
      if (section.type == _shtNote) {
        buildId ??= _readBuildId(bytes, section);
      } else if (section.type == _shtSymtab && section.link < sections.length) {
        final strings = sections[section.link];
        for (var at = 0; at + _symSize <= section.size; at += _symSize) {
          final entry = section.offset + at;
          final size = data.getUint64(entry + 0x10, Endian.little);
          if (size == 0) continue;
          symbols.add((
            data.getUint64(entry + 8, Endian.little),
            size,
            _readString(
              bytes,
              strings.offset + data.getUint32(entry, Endian.little),
            ),
          ));
        }
      }
    }
    symbols.sort((a, b) => a.$1.compareTo(b.$1));
    return DartSymbols._(
      buildId,
      [for (final s in symbols) s.$1],
      [for (final s in symbols) s.$1 + s.$2],
      [for (final s in symbols) s.$3],
    );
  }

  final String? buildId;
  final List<int> _starts;
  final List<int> _ends;
  final List<String> _names;

  /// `Function+0xoffset` לכתובת וירטואלית, או null מחוץ לכל פונקציה.
  String? lookup(int address) {
    var low = 0, high = _starts.length - 1, found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_starts[mid] <= address) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (found < 0 || address >= _ends[found]) return null;
    return '${_names[found]}+0x${(address - _starts[found]).toRadixString(16)}';
  }

  static const int _shtSymtab = 2;
  static const int _shtNote = 7;
  static const int _symSize = 24;

  static String? _readBuildId(Uint8List bytes, _Section section) {
    final data = ByteData.sublistView(bytes);
    var at = section.offset;
    final end = section.offset + section.size;
    while (at + 12 <= end) {
      final nameSize = data.getUint32(at, Endian.little);
      final descSize = data.getUint32(at + 4, Endian.little);
      final type = data.getUint32(at + 8, Endian.little);
      final name = at + 12;
      final desc = name + _align4(nameSize);
      if (type == 3 && nameSize == 4 && _readString(bytes, name) == 'GNU') {
        return [
          for (final b in bytes.sublist(desc, desc + descSize))
            b.toRadixString(16).padLeft(2, '0'),
        ].join();
      }
      at = desc + _align4(descSize);
    }
    return null;
  }

  static int _align4(int value) => (value + 3) & ~3;

  static String _readString(Uint8List bytes, int start) {
    var end = start;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    return utf8.decode(bytes.sublist(start, end), allowMalformed: true);
  }
}

class _Section {
  const _Section(this.type, this.offset, this.size, this.link);

  factory _Section.read(ByteData data, int at) => _Section(
    data.getUint32(at + 4, Endian.little),
    data.getUint64(at + 0x18, Endian.little),
    data.getUint64(at + 0x20, Endian.little),
    data.getUint32(at + 0x28, Endian.little),
  );

  final int type;
  final int offset;
  final int size;
  final int link;
}

final RegExp _dartFrame = RegExp(r'^(\s*)app\.so\+0x([0-9a-fA-F]+)\s*$');
final RegExp _buildIdLine = RegExp(r'^Dart build-id:\s*([0-9a-fA-F]+)\s*$');

/// מוסיף שם פונקציה לכל שורת `app.so+0x…` ב-errors.txt.
///
/// רשומה (`=== …`) שה-build-id שלה שונה משל [symbols] נשארת בלי שמות, עם
/// אזהרה: שמות מקובץ סמלים של בנייה אחרת שגויים.
String symbolizeHangReport(String log, DartSymbols symbols) {
  final out = StringBuffer();
  var matches = true;
  for (final line in const LineSplitter().convert(log)) {
    if (line.startsWith('=== ')) matches = true;
    final buildId = _buildIdLine.firstMatch(line);
    if (buildId != null && symbols.buildId != null) {
      matches = buildId.group(1)!.toLowerCase() == symbols.buildId;
      out.writeln(line);
      if (!matches) {
        out.writeln(
          '  (symbols file build-id ${symbols.buildId} does not match; '
          'frames left unnamed)',
        );
      }
      continue;
    }
    final frame = matches ? _dartFrame.firstMatch(line) : null;
    final name = frame == null
        ? null
        : symbols.lookup(int.parse(frame.group(2)!, radix: 16));
    out.writeln(name == null ? line : '${line.trimRight()}  $name');
  }
  return out.toString();
}
