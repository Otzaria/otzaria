import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

List<AramaicDictionaryEntry> _realEntries() {
  final json =
      jsonDecode(File('assets/dictionary.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final entry
        in (json['מילון פשיטא'] as List).whereType<Map<String, dynamic>>())
      if (entry.isNotEmpty)
        AramaicDictionaryEntry(
          aramaic: entry.keys.first,
          hebrew: '${entry.values.first}',
        ),
  ];
}

String _referenceHebrewPlain(String hebrew) => removeVolwels(
  AramaicDictionaryEntryPresentation.parse(
    hebrew,
  ).meanings.map((meaning) => meaning.hebrewText).join(' '),
);

void main() {
  final entries = _realEntries();
  final keys = [for (final e in entries) removeVolwels(e.aramaic)];

  test('בניית השורות לא מחשבת hebrewPlain', () {
    final rows = buildAramaicRows(entries, keys);
    expect(rows.length, entries.length);
    expect(rows.any((row) => row.containsKey('hebrewPlain')), isFalse);
  });

  test('מילוי hebrewPlain זהה לחישוב הקודם', () {
    final rows = buildAramaicRows(entries, keys);
    fillHebrewPlain(rows);
    for (final (i, row) in rows.indexed) {
      expect(row['hebrewPlain'], _referenceHebrewPlain(entries[i].hebrew));
      expect(row['aramaicPlain'], keys[i]);
      expect(row['hebrew'], entries[i].hebrew);
    }
  });
}
