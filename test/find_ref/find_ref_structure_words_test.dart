import 'package:flutter_test/flutter_test.dart';

import 'support/seeded_reference_library.dart';

/// מילות מבנה חלופיות בשאילתת איתור (issue #4893).
void main() {
  tearDown(resetSeededLibrary);

  const shach = (
    id: 3855,
    title: 'שפתי כהן על שולחן ערוך יורה דעה',
    acronyms: <String>[],
  );

  for (final query in [
    'שפתי כהן על שולחן ערוך יורה דעה א סעיף קטן ב',
    'שפתי כהן על שולחן ערוך יורה דעה א ס"ק ב',
  ]) {
    test('"$query" מגיע ל-TOC כ"סק ב"', () async {
      seedLibrary(const [shach]);
      final seen = <List<String>?>[];
      await buildFindRefRepo(tocQueryTokensSeen: seen).findRefs(query);

      expect(seen, contains(equals(const ['א', 'סק', 'ב'])));
    });
  }

  test('"קטן" שאינו אחרי "סעיף" נשאר במקומו', () async {
    seedLibrary(const [(id: 1, title: 'מועד קטן', acronyms: <String>[])]);
    final seen = <List<String>?>[];
    await buildFindRefRepo(tocQueryTokensSeen: seen).findRefs('מועד קטן ב');

    expect(seen, isNot(contains(contains('סק'))));
  });
}
