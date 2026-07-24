import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_scope_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchScopePreferences', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('שומר ומחזיר מצב של חיפוש בכל הקטגוריות', () async {
      await SearchScopePreferences.save(
        searchAllCategories: true,
        manualFacets: {'/תנ"ך', '/הלכה/שולחן ערוך'},
      );

      final loaded = SearchScopePreferences.load();

      expect(loaded.searchAllCategories, isTrue);
      expect(
        loaded.manualFacets,
        {'/תנ"ך', '/הלכה/שולחן ערוך'},
      );
    });

    test('מסנן ערכים לא תקינים ושומר facets מנורמלים בלבד', () async {
      await Settings.setValue<String>(
        'key-search-manual-category-facets',
        '["", "/", "תנך", "//הלכה///שוע"]',
      );
      await Settings.setValue<bool>(
        'key-search-all-categories-enabled',
        false,
      );

      final loaded = SearchScopePreferences.load();

      expect(loaded.searchAllCategories, isFalse);
      expect(loaded.manualFacets, {'/תנך', '/הלכה/שוע'});
    });

    test(
      'שומר מצב של תחום חיפוש ידני ריק בלי להדליק את כל הקטגוריות',
      () async {
        await SearchScopePreferences.save(
          searchAllCategories: false,
          manualFacets: const {},
        );

        final loaded = SearchScopePreferences.load();

        expect(loaded.searchAllCategories, isFalse);
        expect(loaded.manualFacets, isEmpty);
      },
    );

    test('טוען מצב persisted של תחום ידני ריק כפי שנשמר', () async {
      await Settings.setValue<bool>('key-search-all-categories-enabled', false);
      await Settings.setValue<String>(
        'key-search-manual-category-facets',
        '[]',
      );

      final loaded = SearchScopePreferences.load();

      expect(loaded.searchAllCategories, isFalse);
      expect(loaded.manualFacets, isEmpty);
    });

    test('מטפל ב-payload חוקי שאינו רשימה בלי לשנות את מצב הסוויץ׳', () async {
      await Settings.setValue<bool>('key-search-all-categories-enabled', false);
      await Settings.setValue<String>(
        'key-search-manual-category-facets',
        '{"unexpected":true}',
      );

      final loaded = SearchScopePreferences.load();

      expect(loaded.searchAllCategories, isFalse);
      expect(loaded.manualFacets, isEmpty);
    });
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
