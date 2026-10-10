import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/text_book/utils/dibburim_structure.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';

List<AltTocEntry> _fixtureEntries() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/toc/maadanei_yom_tov_berakhot_dibburim.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final toc = (fixture['toc'] as List)
      .map(
        (row) => TocEntry(
          text: row[4] as String,
          index: row[3] as int,
          level: row[2] as int,
        ),
      )
      .toList();
  final dibburim = {
    for (final row in fixture['dh'] as List) row[0] as int: row[1] as String,
  };
  return buildDibburimEntries(toc, dibburim);
}

void main() {
  test('הטקסט המנורמל של כל ערך זהה לנרמול הישיר', () {
    final entries = [
      ..._fixtureEntries(),
      const AltTocEntry(id: 1, structureId: 1, textId: 1, level: 0),
      const AltTocEntry(
        id: 2,
        structureId: 1,
        textId: 2,
        level: 1,
        text: 'פָּרָשַׁת בְּרֵאשִׁית — "פרק א׳"',
      ),
    ];
    expect(entries.length, greaterThan(900));
    for (final entry in entries) {
      expect(
        altTocEntryMatchText(entry),
        normalizeFindText(entry.text ?? ''),
        reason: entry.text,
      );
    }
  });

  test('הנרמול מחושב פעם אחת לכל ערך ולא בכל הקשה', () {
    // רק ערכים שהנרמול משנה, כי בהם כל נרמול מחדש יוצר מחרוזת חדשה.
    final changed = _fixtureEntries()
        .where((entry) => normalizeFindText(entry.text!) != entry.text)
        .toList();
    expect(changed, isNotEmpty);
    for (final entry in changed) {
      expect(
        identical(altTocEntryMatchText(entry), altTocEntryMatchText(entry)),
        isTrue,
        reason: entry.text,
      );
    }
  });
}
