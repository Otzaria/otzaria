import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tour/models/tour_steps.dart';

/// issue #3779 — כרטיס הפתיחה של הסיור מזכיר שייתכנו טעויות בטקסט.
void main() {
  for (final libraryLoaded in [true, false]) {
    test('כרטיס הפתיחה כולל הבהרת דיוק (libraryLoaded=$libraryLoaded)', () {
      final welcome = TourSteps.build(
        libraryLoaded: libraryLoaded,
      ).firstWhere((step) => step.id == 'welcome');

      expect(welcome.body, contains('שגיאות מי יבין'));
    });
  }
}
