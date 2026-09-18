import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import '../unit/mocks/mock_settings_wrapper.mocks.dart';

/// המעבר משלושה מתגי bool לקבוצת ספקים חייב לשמר את הבחירה של משתמשים
/// קיימים. בדיקה שנשברת כאן פירושה שמשתמש יאבד את ההגדרה שלו בשדרוג.
void main() {
  late MockSettingsWrapper settings;
  late SettingsRepository repository;

  setUp(() {
    settings = MockSettingsWrapper();
    repository = SettingsRepository(settings: settings);
  });

  void stubLegacy({
    required bool external,
    required bool otzar,
    required bool hebrewBooks,
  }) {
    when(
      settings.getValue<bool>(
        SettingsRepository.keyShowExternalBooks,
        defaultValue: false,
      ),
    ).thenReturn(external);
    when(
      settings.getValue<bool>(
        SettingsRepository.keyShowOtzarHachochma,
        defaultValue: false,
      ),
    ).thenReturn(otzar);
    when(
      settings.getValue<bool>(
        SettingsRepository.keyShowHebrewBooks,
        defaultValue: false,
      ),
    ).thenReturn(hebrewBooks);
  }

  void stubNewKey(String? value) {
    when(
      settings.getValue<String>(
        SettingsRepository.keyEnabledExternalProviders,
        defaultValue: '',
      ),
    ).thenReturn(value ?? '');
  }

  group('מיגרציה ממתגי bool לקבוצת ספקים', () {
    test('אוצר החכמה דלוק והיברובוקס כבוי → {otzar}', () {
      stubNewKey(null);
      stubLegacy(external: true, otzar: true, hebrewBooks: false);

      expect(repository.loadEnabledExternalProviders(), {
        ExternalProviderRegistry.otzar.id,
      });
    });

    test('שניהם דלוקים → שני הספקים', () {
      stubNewKey(null);
      stubLegacy(external: true, otzar: true, hebrewBooks: true);

      expect(repository.loadEnabledExternalProviders(), {
        ExternalProviderRegistry.otzar.id,
        ExternalProviderRegistry.hebrewBooks.id,
      });
    });

    test('מתג-האב כבוי → קבוצה ריקה, גם כששני הספקים דלוקים', () {
      stubNewKey(null);
      stubLegacy(external: false, otzar: true, hebrewBooks: true);

      expect(repository.loadEnabledExternalProviders(), isEmpty);
    });

    test('פרויקט השו"ת לעולם אינו נדלק במיגרציה', () {
      stubNewKey(null);
      stubLegacy(external: true, otzar: true, hebrewBooks: true);

      expect(
        repository.loadEnabledExternalProviders(),
        isNot(contains(ExternalProviderRegistry.responsa.id)),
      );
    });
  });

  group('הערך החדש גובר על המתגים הישנים', () {
    test('קבוצה שמורה נקראת כמות שהיא', () {
      stubNewKey('v1:responsa,hebrewbooks');
      stubLegacy(external: true, otzar: true, hebrewBooks: false);

      expect(repository.loadEnabledExternalProviders(), {
        ExternalProviderRegistry.hebrewBooks.id,
        ExternalProviderRegistry.responsa.id,
      });
    });

    test('קבוצה ריקה שמורה אינה מפעילה מיגרציה מחדש', () {
      // בלי התחילית `v1:` הערך הזה לא היה נבדל מ"מעולם לא נכתב",
      // והמתגים הישנים היו מחזירים את הספקים בכל עלייה.
      stubNewKey('v1:');
      stubLegacy(external: true, otzar: true, hebrewBooks: true);

      expect(repository.loadEnabledExternalProviders(), isEmpty);
    });

    test('מזהה ספק לא מוכר בערך שמור מסונן החוצה', () {
      stubNewKey('v1:otzar,nosuchprovider');
      stubLegacy(external: false, otzar: false, hebrewBooks: false);

      expect(repository.loadEnabledExternalProviders(), {
        ExternalProviderRegistry.otzar.id,
      });
    });
  });

  test('שמירה כותבת בפורמט עם תחילית גרסה', () async {
    await repository.updateEnabledExternalProviders({
      ExternalProviderRegistry.responsa.id,
      ExternalProviderRegistry.otzar.id,
    });

    verify(
      settings.setValue<String>(
        SettingsRepository.keyEnabledExternalProviders,
        'v1:otzar,responsa',
      ),
    ).called(1);
  });
}
