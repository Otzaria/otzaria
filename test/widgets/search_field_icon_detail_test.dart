import 'dart:io';

import 'package:test/test.dart';

/// בדיקה סטטית: `search_in_the_library_24_regular` — זכוכית מגדלת שבתוכה
/// ספרים עומדים — לא יופיע בשדה קלט. שדות החיפוש מציגים 18–20 פיקסלים,
/// והספרים שבתוך העדשה נמרחים שם לכתם (issue #1209). בגדלים גדולים
/// (מצב ריק, אריח הגדרות, הרשאת תוסף) הוא קריא ונשאר.
void main() {
  const detailedIcon = 'search_in_the_library_24_regular';

  late List<File> sources;

  setUpAll(() {
    sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  });

  test('האייקון עם הספרים אינו משמש בשדה קלט (issue #1209)', () {
    final violations = <String>[];

    for (final file in sources) {
      final text = file.readAsStringSync();
      if (!text.contains(detailedIcon)) continue;

      for (final block in _searchFieldBlocks(text)) {
        if (block.contains(detailedIcon)) {
          violations.add('${file.path}: OtzariaSearchField');
        }
      }
      for (final prefix in _prefixIconValues(text)) {
        if (prefix.contains(detailedIcon)) {
          violations.add('${file.path}: prefixIcon');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'שדה קלט מציג את האייקון ב-18–20 פיקסלים והספרים שבעדשה נמרחים.\n'
          'השתמש ב-OtzariaIcons.search_24_regular:\n${violations.join('\n')}',
    );
  });

  test('האייקון עם הספרים נשאר בשימוש בגדלים גדולים (issue #1209)', () {
    final remaining = sources
        .where((f) => f.readAsStringSync().contains(detailedIcon))
        .map((f) => f.path)
        .toList();

    expect(
      remaining,
      isNotEmpty,
      reason:
          'האייקון נכון במצבי ריק, באריח ההגדרות ובהרשאת התוסף — '
          'התיקון אמור לגעת בשדות הקלט בלבד',
    );
  });
}

/// הטקסט של כל בנייה של `OtzariaSearchField(...)`, עד הסוגר המאזן.
Iterable<String> _searchFieldBlocks(String source) sync* {
  const marker = 'OtzariaSearchField(';
  var from = 0;
  while (true) {
    final start = source.indexOf(marker, from);
    if (start == -1) return;
    final open = start + marker.length - 1;
    final end = _matchingParen(source, open);
    if (end == -1) return;
    yield source.substring(open, end);
    from = end;
  }
}

/// הערך של כל `prefixIcon:` — עד הפסיק שמסיים אותו ברמת הסוגריים שלו.
Iterable<String> _prefixIconValues(String source) sync* {
  const marker = 'prefixIcon:';
  var from = 0;
  while (true) {
    final start = source.indexOf(marker, from);
    if (start == -1) return;
    var depth = 0;
    var i = start + marker.length;
    for (; i < source.length; i++) {
      final ch = source[i];
      if (ch == '(' || ch == '[' || ch == '{') depth++;
      if (ch == ')' || ch == ']' || ch == '}') {
        if (depth == 0) break;
        depth--;
      }
      if (ch == ',' && depth == 0) break;
    }
    yield source.substring(start, i);
    from = i + 1;
  }
}

/// מיקום הסוגר הסוגר שמאזן את הסוגר שב-[openIndex].
int _matchingParen(String source, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < source.length; i++) {
    final ch = source[i];
    if (ch == '(') depth++;
    if (ch == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}
