import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// המסלול הקודם: דירוג ו-RegExp מחושבים מחדש בכל השוואה של המיון.
List<Map<String, String>> _referenceSearch(
  List<Map<String, String>> data,
  String field,
  String query, {
  void Function()? onRank,
}) {
  int rank(String text) {
    onRank?.call();
    if (text == query) return 0;
    if (text.startsWith(query)) return 1;
    if (RegExp('(^|\\s)${RegExp.escape(query)}(\$|\\s)').hasMatch(text)) {
      return 2;
    }
    return 3;
  }

  // בשוויון נשמר סדר הקלט: המיון של Dart אינו יציב, והמסך דורש תוצאה יציבה.
  final matches = [
    for (final (i, entry) in data.indexed)
      if (entry[field]!.contains(query)) (i, entry),
  ];
  matches.sort((a, b) {
    final textA = a.$2[field]!;
    final textB = b.$2[field]!;
    final rankCompare = rank(textA).compareTo(rank(textB));
    if (rankCompare != 0) return rankCompare;
    final posCompare = textA.indexOf(query).compareTo(textB.indexOf(query));
    if (posCompare != 0) return posCompare;
    final lengthCompare = textA.length.compareTo(textB.length);
    return lengthCompare != 0 ? lengthCompare : a.$1.compareTo(b.$1);
  });
  return [for (final m in matches) m.$2];
}

List<Map<String, String>> _loadRealDictionary() {
  final json =
      jsonDecode(File('assets/dictionary.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final entry
        in (json['מילון פשיטא'] as List).whereType<Map<String, dynamic>>())
      if (entry.isNotEmpty)
        {
          'aramaicPlain': removeVolwels(entry.keys.first),
          'hebrewPlain': removeVolwels('${entry.values.first}'),
        },
  ];
}

void main() {
  final data = _loadRealDictionary();
  const queries = ['א', 'ד', 'ה', 'אי', 'מאי', 'של', 'לא', 'דא', 'זה'];

  test('הדירוג זהה למסלול הקודם על המילון האמיתי', () {
    expect(data.length, greaterThan(1000));
    for (final field in ['aramaicPlain', 'hebrewPlain']) {
      for (final query in queries) {
        final expected = _referenceSearch(data, field, query);
        final actual = rankAramaicMatches(data, field, query);
        expect(actual.length, expected.length, reason: '$field/$query');
        for (var i = 0; i < expected.length; i++) {
          expect(
            identical(actual[i], expected[i]),
            isTrue,
            reason: '$field/$query @$i',
          );
        }
      }
    }
  });

  test('הקשת אות ראשונה מחשבת דירוג פעם אחת לכל התאמה', () {
    var previousRanks = 0;
    var ranks = 0;
    final expected = _referenceSearch(
      data,
      'hebrewPlain',
      'א',
      onRank: () => previousRanks++,
    );
    final actual = rankAramaicMatches(
      data,
      'hebrewPlain',
      'א',
      debugOnRank: () => ranks++,
    );
    printOnFailure(
      'matches=${actual.length} ranks=$ranks referenceRanks=$previousRanks',
    );
    expect(actual, orderedEquals(expected));
    expect(actual.length, greaterThan(100));
    // בודקים את החיסכון בחישוב עצמו, ללא תלות בתזמון ה-CPU של הראנר.
    expect(ranks, actual.length);
    expect(previousRanks, greaterThan(ranks));
  });
}
