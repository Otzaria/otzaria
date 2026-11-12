import 'dart:io';

import 'package:test/test.dart';

/// בדיקה סטטית: מסכי הספרייה מגלגלים ברשימות רגילות, ופס הגלילה האוטומטי של
/// Material נופל בעברית לקצה שמאל. LibraryBrowser תלוי בכל ה-BLoCs של
/// האפליקציה ואינו נבנה בטסט, ולכן הכיסוי כאן הוא על העטיפה עצמה. התנהגות
/// [EdgeScrollbarBehavior] עצמה נבדקת ב-test/widgets/edge_scrollbar_behavior_test.dart.
void main() {
  final source = File(
    'lib/library/view/library_browser.dart',
  ).readAsStringSync();

  test('העטיפה חלה על אזור התוכן הראשי (mainContent) של הספרייה', () {
    final mainContentIdx = source.indexOf('mainContent: RepaintBoundary');
    expect(mainContentIdx, greaterThan(-1), reason: 'מבנה mainContent השתנה');

    final block = source.substring(
      mainContentIdx,
      mainContentIdx + 400 > source.length
          ? source.length
          : mainContentIdx + 400,
    );
    expect(
      block,
      contains('EdgeScrollbarBehavior.right()'),
      reason: 'העטיפה אינה על אזור התוכן של הספרייה',
    );
  });
}
