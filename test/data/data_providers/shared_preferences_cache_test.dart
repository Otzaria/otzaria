import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/shared_preferences_cache.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'integer': 12,
      'decimal': 1.5,
      'boolean': true,
      'text': 'saved',
      'list': <String>['first', 'second'],
    });
    await Settings.init(cacheProvider: SharePreferenceCache());
  });

  test('untyped reads used by backup retain preference values', () {
    expect(Settings.getValue('integer'), 12);
    expect(Settings.getValue('decimal'), 1.5);
    expect(Settings.getValue('boolean'), isTrue);
    expect(Settings.getValue('text'), 'saved');
    expect(Settings.getValue('list'), ['first', 'second']);
  });

  test('typed reads support nullable and wider types', () {
    expect(Settings.getValue<int>('integer'), 12);
    expect(Settings.getValue<double>('decimal'), 1.5);
    expect(Settings.getValue<bool>('boolean'), isTrue);
    expect(Settings.getValue<String>('text'), 'saved');
    expect(Settings.getValue<int?>('integer'), 12);
    expect(Settings.getValue<num>('integer'), 12);
    expect(Settings.getValue<Object>('text'), 'saved');
    expect(Settings.getValue<List<String>>('list'), ['first', 'second']);
  });

  test('missing or mismatched values use the caller default', () {
    expect(Settings.getValue<int>('missing', defaultValue: 7), 7);
    expect(Settings.getValue<int>('text', defaultValue: 7), 7);
    expect(Settings.getValue<String>('integer'), isNull);
    expect(Settings.getValue<int?>('text', defaultValue: 7), 7);
  });

  test(
    'direct nullable reads use the default for a missing preference',
    () async {
      final cache = SharePreferenceCache();
      await cache.init();

      expect(cache.getValue<int?>('missing', defaultValue: 7), 7);
      expect(
        cache.getValue<dynamic>('missing', defaultValue: 'default'),
        'default',
      );
    },
  );

  test('null writes still remove preferences', () async {
    await Settings.setValue<int?>('integer', null);

    expect(Settings.containsKey('integer'), isFalse);
    expect(Settings.getValue<int>('integer', defaultValue: 7), 7);
  });

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
