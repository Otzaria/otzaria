/// מיקומי כל המופעים בגרפמות, כולל חפיפות, בסדר הופעתם בטקסט.
List<int> findGraphemeOccurrences(List<String> source, List<String> needle) {
  if (needle.isEmpty || needle.length > source.length) return const [];

  // טבלת KMP מונעת סריקה חוזרת של קידומות בטקסט חזרתי.
  final prefix = List<int>.filled(needle.length, 0);
  for (var i = 1, matched = 0; i < needle.length; i++) {
    while (matched > 0 && needle[i] != needle[matched]) {
      matched = prefix[matched - 1];
    }
    if (needle[i] == needle[matched]) matched++;
    prefix[i] = matched;
  }

  final matches = <int>[];
  var matched = 0;
  for (var i = 0; i < source.length; i++) {
    while (matched > 0 && source[i] != needle[matched]) {
      matched = prefix[matched - 1];
    }
    if (source[i] == needle[matched]) matched++;
    if (matched == needle.length) {
      matches.add(i + 1 - matched);
      // ממשיכים מהקידומת המשותפת כדי לשמור גם מופעים חופפים.
      matched = prefix[matched - 1];
    }
  }
  return matches;
}
