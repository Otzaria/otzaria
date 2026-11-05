import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/shared_preferences_cache.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharePreferenceCache היא הנסיגה כש-HiveCache לא נפתח (main.dart). קריאות
/// עם סוג nullable (`getValue<bool?>(key, defaultValue: null)`) זרקו בה
/// "cannot read type bool?", ולכן הגדרה שנשמרה ("צפיפות ממשק", גודל תוצאות
/// החיפוש) הפילה את טעינת ההגדרות בכל הפעלה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharePreferenceCache.getValue עם סוג nullable', () {
    late SharePreferenceCache cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'b': true,
        'd': 20.0,
        'i': 3,
        's': 'x',
      });
      cache = SharePreferenceCache();
      await cache.init();
    });

    test('מחזירה את הערך השמור', () {
      expect(cache.getValue<bool?>('b', defaultValue: null), isTrue);
      expect(cache.getValue<double?>('d', defaultValue: null), 20.0);
      expect(cache.getValue<int?>('i', defaultValue: null), 3);
      expect(cache.getValue<String?>('s', defaultValue: null), 'x');
    });

    test('מחזירה null כשאין ערך', () {
      expect(cache.getValue<bool?>('missing', defaultValue: null), isNull);
      expect(cache.getValue<double?>('missing', defaultValue: null), isNull);
    });

    test('הסוגים בלי ? עובדים כמו קודם', () {
      expect(cache.getValue<bool>('b'), isTrue);
      expect(cache.getValue<double>('d'), 20.0);
      expect(cache.getValue('missing', defaultValue: 7), 7);
    });

    test('סוג שונה מהשמור מחזיר את ברירת המחדל', () {
      expect(cache.getValue<bool>('s', defaultValue: false), isFalse);
      expect(cache.getValue<int?>('d', defaultValue: null), isNull);
    });
  });

  test('ההגדרות נקראות מעל SharePreferenceCache אחרי שנשמרה צפיפות', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init(cacheProvider: SharePreferenceCache());
    await Settings.setValue<bool>(SettingsRepository.keyCompactMenuMode, true);
    await Settings.setValue<double>(
      SettingsRepository.keySearchResultsFontSize,
      20.0,
    );

    final settings = SettingsRepository().readSettings();

    expect(settings['compactMenuMode'], isTrue);
  });
}
