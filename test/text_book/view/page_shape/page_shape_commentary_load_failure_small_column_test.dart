// מצב השגיאה של טור מפרש נכנס בכל גובה של הטור התחתון: הגובה הוא יחס
// מגובה הדף (0.08 מ-450 פיקסלים = 36), ו"נסה שוב" נשאר זמין (issue #5744).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';

import 'page_shape_commentary_failure_harness.dart';

const _commentator = 'מפרש בטור התחתון';
const _retry = 'נסה שוב';

void main() {
  setUpPageShapeFailureTests();

  testWidgets('טור תחתון נמוך מציג את מצב השגיאה בלי גלישה (issue #5744)', (
    tester,
  ) async {
    final provider = FakeCommentaryProvider(const [_commentator])
      ..textFailures = 1;
    await pumpPageShape(
      tester,
      provider,
      bookTitle: 'ספר נמוך',
      column: 'bottom',
      size: const Size(900, 450),
      bottomHeight: 0.08,
    );
    await pumpUntil(tester, () => provider.textFailures == 0);
    await pumpUntil(tester, () => false);
    expect(tester.takeException(), isNull);
    expect(find.text(_retry), findsOneWidget);

    // גבהים נוספים של אותו יחס: חלון נמוך מאוד וחלון רגיל.
    for (final height in [300.0, 1000.0]) {
      tester.view.physicalSize = Size(900, height);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'height $height');
    }

    await tester.tap(find.text(_retry));
    await pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
    expect(
      tester.widget<SimpleTextViewer>(commentaryViewer()).bookTitle,
      _commentator,
    );
  });
}
