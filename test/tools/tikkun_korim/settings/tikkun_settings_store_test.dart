/// מנהג הקריאות (א"י/חו"ל) נגזר מהעיר שבלוח השנה כל עוד לא נבחר במפורש.
library;

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  const store = TikkunSettingsStore();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('בלי עיר בלוח — ארץ ישראל', () {
    expect(store.load().nusachLand, 'israel');
  });

  test('עיר בחוץ לארץ בלוח — חוץ לארץ', () async {
    await Settings.setValue<String>(
      SettingsRepository.keySelectedCity,
      'לונדון',
    );
    expect(store.load().nusachLand, 'diaspora');
  });

  test('שמירת הגדרה אחרת אינה מקבעת את המנהג שנגזר מהלוח', () async {
    await Settings.setValue<String>(
      SettingsRepository.keySelectedCity,
      'לונדון',
    );
    await store.save(store.load().copyWith(zoom: 1.5));
    await Settings.setValue<String>(
      SettingsRepository.keySelectedCity,
      'ירושלים',
    );
    expect(store.load().nusachLand, 'israel');
  });

  test('בחירה מפורשת גוברת על הלוח', () async {
    await Settings.setValue<String>(
      SettingsRepository.keySelectedCity,
      'לונדון',
    );
    await store.save(store.load().copyWith(nusachLand: 'israel'));
    expect(store.load().nusachLand, 'israel');
  });

  for (final cities in [
    ('לונדון', 'ירושלים', 'diaspora', 'israel'),
    ('ירושלים', 'לונדון', 'israel', 'diaspora'),
  ]) {
    test('שמירת מצב ישן לאחר מעבר ${cities.$1} → ${cities.$2}', () async {
      await Settings.setValue<String>(
        SettingsRepository.keySelectedCity,
        cities.$1,
      );
      final opened = store.load();
      expect(opened.nusachLand, cities.$3);
      await Settings.setValue<String>(
        SettingsRepository.keySelectedCity,
        cities.$2,
      );
      await store.save(opened.copyWith(zoom: 1.5, hideNikud: true));
      expect(Settings.getValue<String>(TikkunSettingsKeys.nusachLand), isNull);
      expect(store.load().nusachLand, cities.$4);
      expect(store.load().zoom, 1.5);
      expect(store.load().hideNikud, isTrue);
    });

    test('בחירה מפורשת התואמת לעיר ${cities.$1} נשמרת אחרי מעבר עיר', () async {
      await Settings.setValue<String>(
        SettingsRepository.keySelectedCity,
        cities.$1,
      );
      final derived = store.load();
      final explicit = derived.copyWith(nusachLand: cities.$3);
      expect(explicit, isNot(derived));
      await store.save(explicit);
      expect(
        Settings.getValue<String>(TikkunSettingsKeys.nusachLand),
        cities.$3,
      );
      await Settings.setValue<String>(
        SettingsRepository.keySelectedCity,
        cities.$2,
      );
      await store.save(explicit.copyWith(zoom: 1.5));
      expect(store.load().nusachLand, cities.$3);
    });

    test('מנהג שמור קודם גובר גם כשהוא תואם לעיר ${cities.$1}', () async {
      await Settings.setValue<String>(
        SettingsRepository.keySelectedCity,
        cities.$1,
      );
      await Settings.setValue<String>(TikkunSettingsKeys.nusachLand, cities.$3);
      final opened = store.load();
      await Settings.setValue<String>(
        SettingsRepository.keySelectedCity,
        cities.$2,
      );
      await store.save(opened.copyWith(lineSpacing: 1.5));
      expect(store.load().nusachLand, cities.$3);
      expect(store.load().lineSpacing, 1.5);
    });
  }

  test('מנהג שהועבר לבנאי במפורש נשמר גם כשמתאים לעיר', () async {
    await Settings.setValue<String>(
      SettingsRepository.keySelectedCity,
      'ירושלים',
    );
    await store.save(
      const TikkunSettings(nusachLand: 'israel').copyWith(zoom: 1.5),
    );
    await Settings.setValue<String>(
      SettingsRepository.keySelectedCity,
      'לונדון',
    );
    expect(store.load().nusachLand, 'israel');
  });

  test('בחירה במסך הגדרות אחר נשמרת כשמצב נגזר ישן נשמר', () async {
    await Settings.setValue<String>(
      SettingsRepository.keySelectedCity,
      'ירושלים',
    );
    final opened = store.load();
    await Settings.setValue<String>(TikkunSettingsKeys.nusachLand, 'diaspora');
    await store.save(opened.copyWith(zoom: 1.5));
    expect(store.load().nusachLand, 'diaspora');
  });
}
