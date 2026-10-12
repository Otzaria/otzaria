import 'dart:convert';

import 'package:crypto/crypto.dart';

/// OCJ-1 (חוזה §4.3), זהה לאתר: מפתחות לפי UTF-16, בלי רווחים, שלמים בלבד.
/// זורק [ArgumentError] על ערך שאינו נתמך (שבר, surrogate בודד, סוג אחר).
String canonicalJsonEncode(Object? value) {
  final buffer = StringBuffer();
  _write(buffer, value);
  return buffer.toString();
}

/// sha256 (hex קטן) על בתי ה-UTF-8 של [canonicalJsonEncode].
String canonicalJsonSha256(Object? value) =>
    sha256.convert(utf8.encode(canonicalJsonEncode(value))).toString();

/// Number.MAX_SAFE_INTEGER — מעבר לו JS מאבד דיוק והאתר דוחה (§4.3).
const int _maxSafeInteger = 9007199254740991;

final RegExp _loneSurrogate = RegExp(
  r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
);

/// surrogate בודד פוסל את הדיווח כולו ב-OCJ-1 (§4.3).
bool hasLoneSurrogate(String value) => _loneSurrogate.hasMatch(value);

/// מחליף surrogate בודד ב-U+FFFD, כמו קידוד UTF-8 של הגוף. לשדות חופשיים בלבד.
String replaceLoneSurrogates(String value) =>
    value.replaceAll(_loneSurrogate, '�');

void _write(StringBuffer out, Object? value) {
  if (value == null) {
    out.write('null');
  } else if (value is bool) {
    out.write(value ? 'true' : 'false');
  } else if (value is int) {
    if (value > _maxSafeInteger || value < -_maxSafeInteger) {
      throw ArgumentError.value(
        value,
        'value',
        'OCJ-1 allows safe integers only',
      );
    }
    out.write(value.toString());
  } else if (value is String) {
    _writeString(out, value);
  } else if (value is Map) {
    final keys = value.keys.map((key) {
      if (key is! String) {
        throw ArgumentError.value(key, 'key', 'OCJ-1 keys must be strings');
      }
      return key;
    }).toList()..sort();
    out.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) out.write(',');
      _writeString(out, keys[i]);
      out.write(':');
      _write(out, value[keys[i]]);
    }
    out.write('}');
  } else if (value is List) {
    out.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) out.write(',');
      _write(out, value[i]);
    }
    out.write(']');
  } else {
    throw ArgumentError.value(value, 'value', 'Unsupported OCJ-1 value');
  }
}

void _writeString(StringBuffer out, String value) {
  out.write('"');
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0C:
        out.write(r'\f');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (unit < 0x20) {
          out.write(r'\u');
          out.write(unit.toRadixString(16).padLeft(4, '0'));
        } else if (unit >= 0xD800 && unit <= 0xDBFF) {
          final next = i + 1 < value.length ? value.codeUnitAt(i + 1) : -1;
          if (next < 0xDC00 || next > 0xDFFF) {
            throw ArgumentError.value(value, 'value', 'Lone surrogate');
          }
          out.writeCharCode(unit);
          out.writeCharCode(next);
          i++;
        } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
          throw ArgumentError.value(value, 'value', 'Lone surrogate');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
}
