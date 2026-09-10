import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tour/widgets/tour_tooltip_card.dart';

/// issue #1318 — במסך טלפון שורת הכפתורים "דלג — אגלה לבד" / "בוא נתחיל"
/// גלשה מרוחב כרטיס הפתיחה (RIGHT OVERFLOWED). הכפתורים חייבים לרדת שורה.
void main() {
  Future<void> pumpNarrow(
    WidgetTester tester, {
    required SettingsLanguage language,
    double width = 320,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SettingsTextScope(
            language: language,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: TourTooltipCard(
                    title: 'ברוכים הבאים לאוצריא',
                    body: 'ספרייה תורנית דיגיטלית חינמית ופתוחה.',
                    currentIndex: -1,
                    totalSteps: 3,
                    isLastStep: false,
                    isWelcomeStep: true,
                    onNext: () {},
                    onSkip: () {},
                    onToggleAutoPlay: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final language in [SettingsLanguage.hebrew, SettingsLanguage.english]) {
    testWidgets('כרטיס הפתיחה ברוחב 320 אינו גולש (${language.name})', (
      tester,
    ) async {
      await pumpNarrow(tester, language: language);
      expect(tester.takeException(), isNull);
      expect(find.byType(FilledButton), findsWidgets);
    });
  }
}
