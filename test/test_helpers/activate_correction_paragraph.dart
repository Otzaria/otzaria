import 'package:flutter_test/flutter_test.dart';

/// לחיצה אחת מפעילה עריכה בפסקה. ההמתנה ארוכה מחלון הלחיצה הכפולה, כדי
/// שלחיצה נוספת של הבדיקה בתוך העורך לא תיחשב לחיצה כפולה (יציאה מעריכה).
Future<void> activateCorrectionParagraph(
  WidgetTester tester,
  Finder paragraph, {
  Offset? position,
}) async {
  final point = position ?? tester.getCenter(paragraph);
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}
