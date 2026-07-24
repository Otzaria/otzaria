import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';

void main() {
  group('resolveLibraryPageBuildDecision', () {
    test(
      'מחזיר placeholder כשמסך הפתיחה אינו ספרייה והדף האמיתי עוד לא נבנה',
      () {
        final decision = resolveLibraryPageBuildDecision(
          hasBuiltRealPage: false,
          currentScreen: Screen.reading,
        );

        expect(decision, LibraryPageBuildDecision.usePlaceholder);
      },
    );

    test('בונה את הדף האמיתי כשנכנסים לראשונה למסך הספרייה', () {
      final decision = resolveLibraryPageBuildDecision(
        hasBuiltRealPage: false,
        currentScreen: Screen.library,
      );

      expect(decision, LibraryPageBuildDecision.buildRealPage);
    });

    test('שומר את הדף הקיים לאחר שהדף האמיתי כבר נבנה', () {
      final decision = resolveLibraryPageBuildDecision(
        hasBuiltRealPage: true,
        currentScreen: Screen.reading,
      );

      expect(decision, LibraryPageBuildDecision.keepExistingPage);
    });

    test('שומר את הדף הקיים גם כשחוזרים למסך הספרייה', () {
      final decision = resolveLibraryPageBuildDecision(
        hasBuiltRealPage: true,
        currentScreen: Screen.library,
      );

      expect(decision, LibraryPageBuildDecision.keepExistingPage);
    });
  });
}
