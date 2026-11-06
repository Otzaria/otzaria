import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/shared_preferences_cache.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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
}
