import 'package:flutter_test/flutter_test.dart';

Future<void> activateCorrectionParagraph(
  WidgetTester tester,
  Finder paragraph, {
  Offset? position,
}) async {
  final point = position ?? tester.getCenter(paragraph);
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 50));
}
