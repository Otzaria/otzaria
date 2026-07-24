import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';

void main() {
  group('shouldRemoveNikudForBook', () {
    test('returns false when default setting keeps nikud', () {
      expect(
        shouldRemoveNikudForBook(
          defaultRemoveNikud: false,
          removeNikudFromTanach: true,
          isTanach: true,
        ),
        isFalse,
      );
    });

    test('returns false for Tanach when only non-Tanach should hide nikud', () {
      expect(
        shouldRemoveNikudForBook(
          defaultRemoveNikud: true,
          removeNikudFromTanach: false,
          isTanach: true,
        ),
        isFalse,
      );
    });

    test('returns true for Tanach when hide-all is enabled', () {
      expect(
        shouldRemoveNikudForBook(
          defaultRemoveNikud: true,
          removeNikudFromTanach: true,
          isTanach: true,
        ),
        isTrue,
      );
    });
  });

  group('shouldReloadForNikudSettingsChange', () {
    test('returns true when removeNikudFromTanach changes', () {
      final previous = SettingsState.initial().copyWith(
        defaultRemoveNikud: true,
        removeNikudFromTanach: false,
      );
      final current = previous.copyWith(removeNikudFromTanach: true);

      expect(
        shouldReloadForNikudSettingsChange(
          previous: previous,
          current: current,
        ),
        isTrue,
      );
    });

    test('returns false when nikud settings are unchanged', () {
      final state = SettingsState.initial().copyWith(
        defaultRemoveNikud: true,
        removeNikudFromTanach: false,
      );

      expect(
        shouldReloadForNikudSettingsChange(
          previous: state,
          current: state.copyWith(fontFamily: 'Rubik'),
        ),
        isFalse,
      );
    });
  });

  group('shouldReloadForPunctuationSettingsChange', () {
    test('returns true when defaultRemovePunctuation changes', () {
      final previous = SettingsState.initial();
      final current = previous.copyWith(defaultRemovePunctuation: true);

      expect(
        shouldReloadForPunctuationSettingsChange(
          previous: previous,
          current: current,
        ),
        isTrue,
      );
    });

    test('returns false when punctuation setting is unchanged', () {
      final state = SettingsState.initial().copyWith(
        defaultRemovePunctuation: true,
      );

      expect(
        shouldReloadForPunctuationSettingsChange(
          previous: state,
          current: state.copyWith(fontFamily: 'Rubik'),
        ),
        isFalse,
      );
    });
  });
}
