// Settings ו-CacheProvider מבוססים על flutter_settings_screens 0.3.4
// (MIT, Copyright (c) 2019 Harshvardhan Joshi).

/// ממשק האחסון שמתחת ל-[Settings].
abstract class CacheProvider {
  CacheProvider();

  Future<void> init();

  /// שמות המפתחות שהשתנו באחסון, אם הספק תומך בהתראות.
  Stream<String> get changes => const Stream<String>.empty();

  int? getInt(String key, {int? defaultValue});

  String? getString(String key, {String? defaultValue});

  double? getDouble(String key, {double? defaultValue});

  bool? getBool(String key, {bool? defaultValue});

  Future<void> setInt(String key, int? value);

  Future<void> setString(String key, String? value);

  Future<void> setDouble(String key, double? value);

  Future<void> setBool(String key, bool? value);

  bool containsKey(String key);

  Set getKeys();

  Future<void> remove(String key);

  Future<void> removeAll();

  Future<void> setObject<T>(String key, T? value);

  T? getValue<T>(String key, {T? defaultValue});
}

/// גישה סטטית להגדרות האפליקציה מעל [CacheProvider] שנמסר ל-[init].
class Settings {
  Settings._();

  static CacheProvider? _cacheProvider;

  static bool get isInitialized => _cacheProvider != null;

  /// התראות מספק האחסון הפעיל, כולל כתיבות שלא עברו דרך SettingsBloc.
  static Stream<String> get changes =>
      _cacheProvider?.changes ?? const Stream<String>.empty();

  static void _assertInitialized() {
    assert(
      isInitialized,
      'Must call Settings.init(cacheProvider) before using settings!',
    );
  }

  static Future<void> init({required CacheProvider cacheProvider}) async {
    _cacheProvider = cacheProvider;
    await cacheProvider.init();
  }

  static bool containsKey(String key) {
    _assertInitialized();
    return _cacheProvider?.containsKey(key) ?? false;
  }

  /// מחזיר את הערך השמור, או [defaultValue] כשאין ערך או שסוגו שונה.
  static T? getValue<T>(String key, {T? defaultValue}) {
    _assertInitialized();
    final provider = _cacheProvider;
    if (provider == null || !provider.containsKey(key)) return defaultValue;
    return provider.getValue<T>(key, defaultValue: defaultValue) ??
        defaultValue;
  }

  /// שומר את [value]; `null` מוחק את המפתח.
  static Future<void> setValue<T>(String key, T value) async {
    _assertInitialized();
    if (value == null) {
      await _cacheProvider?.remove(key);
      return;
    }
    await _cacheProvider?.setObject<T>(key, value);
  }

  static Future<void> clearCache() async {
    _assertInitialized();
    await _cacheProvider?.removeAll();
  }
}
