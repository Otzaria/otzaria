part of 'benchmark.dart';

bool _rawCharactersExceed(List<_CountChunk> chunks, int limit) {
  var total = 0;
  for (final chunk in chunks) {
    for (var line = 0; line < chunk.lines.length; line++) {
      if (chunk.loaded == null || chunk.loaded![line]) {
        total += chunk.lines[line].length;
        if (total >= limit) return true;
      }
    }
  }
  return false;
}

_CountResult _countChunks(List<_CountChunk> chunks) {
  final counts = Int32List(
    chunks.fold<int>(0, (sum, chunk) => sum + chunk.lines.length),
  );
  var cursor = 0;
  var chars = 0;
  var loaded = 0;
  for (final chunk in chunks) {
    for (var line = 0; line < chunk.lines.length; line++) {
      final count = chunk.loaded == null || chunk.loaded![line]
          ? visibleReadingCharCount(chunk.lines[line])
          : -1;
      counts[cursor++] = count;
      if (count >= 0) {
        chars += count;
        loaded++;
      }
    }
  }
  return (counts: counts, chars: chars, loaded: loaded);
}

int visibleReadingCharCount(String text) {
  var plain = notes.stripInlineNotes(text);
  if (plain.contains('<')) plain = removeHtmlTags(plain);
  if (plain.contains('&')) plain = html.parseFragment(plain).text ?? plain;
  var count = 0;
  final length = plain.length;
  for (var i = 0; i < length; i++) {
    var code = plain.codeUnitAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < length) {
      final low = plain.codeUnitAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
        i++;
      }
    }
    if ((code >= 0x591 && code <= 0x5BD) ||
        code == 0x5BF ||
        code == 0x5C1 ||
        code == 0x5C2 ||
        code == 0x5C4 ||
        code == 0x5C5 ||
        code == 0x5C7) {
      continue;
    }
    // שאר הגוש העברי (אותיות, מקף, פסק, סוף פסוק) אינו משולב — בלי RegExp.
    if (code < 0x300 || (code >= 0x591 && code < 0x600)) {
      count++;
    } else if (!_combining.hasMatch(String.fromCharCode(code))) {
      count++;
    }
  }
  return count;
}
