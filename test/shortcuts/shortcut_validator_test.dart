import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  tearDown(() {
    // מנקה רישום קיצורי תוספים כדי שלא יזלוג בין טסטים.
    ShortcutValidator.registerPluginShortcutKeys(const {});
  });

  group('getShortcutValue', () {
    test('מחזיר ברירת מחדל כשלא הוגדר ערך', () {
      expect(
        ShortcutValidator.getShortcutValue('key-shortcut-open-library-browser'),
        'ctrl+l',
      );
    });

    test('ערך שהוגדר גובר על ברירת המחדל', () async {
      await Settings.setValue<String>(
        'key-shortcut-open-library-browser',
        'ctrl+shift+x',
      );
      expect(
        ShortcutValidator.getShortcutValue('key-shortcut-open-library-browser'),
        'ctrl+shift+x',
      );
    });

    test('נופל למפתח legacy כשהמפתח הנוכחי ריק', () async {
      await Settings.setValue<String>(
        ShortcutValidator.legacySearchInBookKey,
        'ctrl+g',
      );
      expect(
        ShortcutValidator.getShortcutValue(
          ShortcutValidator.currentWindowSearchKey,
        ),
        'ctrl+g',
      );
    });

    test('ערך ישיר גובר על מפתח legacy', () async {
      await Settings.setValue<String>(
        ShortcutValidator.legacySearchInBookKey,
        'ctrl+g',
      );
      await Settings.setValue<String>(
        ShortcutValidator.currentWindowSearchKey,
        'ctrl+j',
      );
      expect(
        ShortcutValidator.getShortcutValue(
          ShortcutValidator.currentWindowSearchKey,
        ),
        'ctrl+j',
      );
    });

    test('שאילתה לפי המפתח הישן מנורמלת למפתח הנוכחי', () {
      expect(
        ShortcutValidator.getShortcutValue(
          ShortcutValidator.legacySearchInBookKey,
        ),
        ShortcutValidator.defaultShortcuts[ShortcutValidator
            .currentWindowSearchKey],
      );
    });
  });

  group('canonicalSettingKey / legacyKeysFor', () {
    test('ממפה מפתח legacy למפתח הנוכחי', () {
      expect(
        ShortcutValidator.canonicalSettingKey(
          ShortcutValidator.legacySearchInBookKey,
        ),
        ShortcutValidator.currentWindowSearchKey,
      );
    });

    test('מפתח רגיל מוחזר כמו שהוא', () {
      expect(
        ShortcutValidator.canonicalSettingKey('key-shortcut-print'),
        'key-shortcut-print',
      );
    });

    test('legacyKeysFor מחזיר את המפתחות הישנים', () {
      expect(
        ShortcutValidator.legacyKeysFor(
          ShortcutValidator.currentWindowSearchKey,
        ),
        {ShortcutValidator.legacySearchInBookKey},
      );
      expect(ShortcutValidator.legacyKeysFor('key-shortcut-print'), isEmpty);
    });
  });

  group('checkConflicts', () {
    test('ברירות המחדל נקיות מקונפליקטים', () {
      expect(ShortcutValidator.checkConflicts(), isEmpty);
    });

    test('שני מפתחות עם אותו קיצור יוצרים קונפליקט', () async {
      await Settings.setValue<String>('key-shortcut-open-history', 'ctrl+b');

      final conflicts = ShortcutValidator.checkConflicts();
      expect(conflicts, contains('ctrl+b'));
      expect(
        conflicts['ctrl+b'],
        containsAll(['key-shortcut-open-history', 'key-shortcut-add-bookmark']),
      );
    });

    test('קבוצה תואמת לא נחשבת קונפליקט', () async {
      // add-note + calendar-toggle-events מוגדרים כקבוצה תואמת
      await Settings.setValue<String>('key-shortcut-add-note', 'ctrl+e');

      expect(ShortcutValidator.checkConflicts(), isEmpty);
    });
  });

  group('hasConflict', () {
    test('false כשאין התנגשות', () {
      expect(
        ShortcutValidator.hasConflict('key-shortcut-add-bookmark'),
        isFalse,
      );
    });

    test('true כששני מפתחות חולקים קיצור', () async {
      await Settings.setValue<String>('key-shortcut-open-history', 'ctrl+b');

      expect(
        ShortcutValidator.hasConflict('key-shortcut-add-bookmark'),
        isTrue,
      );
      expect(
        ShortcutValidator.hasConflict('key-shortcut-open-history'),
        isTrue,
      );
    });

    test('false עבור קיצור ריק', () async {
      expect(
        ShortcutValidator.hasConflict('key-shortcut-open-commentators-tab'),
        isFalse,
      );
    });
  });

  group('openToolShortcutKeys', () {
    test(
      'כל מפתח רשום ב-shortcutKeys, defaultShortcuts (ריק) ו-shortcutNames',
      () {
        for (final key in ShortcutValidator.openToolShortcutKeys.keys) {
          expect(ShortcutValidator.shortcutKeys, contains(key));
          expect(ShortcutValidator.defaultShortcuts[key], '');
          expect(ShortcutValidator.shortcutNames[key], isNotNull);
        }
      },
    );

    test('כל מזהה כלי קיים בקטלוג הכלים המובנים', () {
      final catalogIds = kBuiltInToolsCatalog.map((m) => m.toolId).toSet();
      for (final toolId in ShortcutValidator.openToolShortcutKeys.values) {
        expect(
          catalogIds,
          contains(toolId),
          reason: 'הכלי "$toolId" אינו קיים בקטלוג',
        );
      }
    });

    test('ה-deep-link שהקיצור מפעיל מתפענח ל-OpenToolAction של אותו כלי', () {
      for (final toolId in ShortcutValidator.openToolShortcutKeys.values) {
        final action = ExternalUriRouter.parseUri(
          Uri.parse('otzaria://open/tool/$toolId'),
        );
        expect(action, isA<OpenToolAction>());
        expect((action as OpenToolAction).toolId, toolId);
      }
    });
  });

  group('copyLinkShortcutKeys', () {
    test(
      'כל מפתח רשום ב-shortcutKeys, defaultShortcuts (ריק) ו-shortcutNames',
      () {
        for (final key in ShortcutValidator.copyLinkShortcutKeys) {
          expect(ShortcutValidator.shortcutKeys, contains(key));
          expect(ShortcutValidator.defaultShortcuts[key], '');
          expect(ShortcutValidator.shortcutNames[key], isNotNull);
        }
      },
    );

    test('ללא ברירת מחדל — getShortcutValue מחזיר ערך ריק כל עוד לא הוגדר', () {
      for (final key in ShortcutValidator.copyLinkShortcutKeys) {
        expect(ShortcutValidator.getShortcutValue(key), '');
      }
    });
  });

  group('קיצורי תוספים (registerPluginShortcutKeys)', () {
    const pluginId = 'com.example.my_plugin';
    final key = ShortcutValidator.openPluginShortcutKey(pluginId);

    test('openPluginShortcutKey בונה מפתח עם הקידומת', () {
      expect(key, 'key-shortcut-open-plugin-$pluginId');
    });

    test('רישום מוסיף את המפתח ל-shortcutKeys ו-shortcutNames', () {
      expect(ShortcutValidator.shortcutKeys, isNot(contains(key)));
      ShortcutValidator.registerPluginShortcutKeys({key: 'פתיחת התוסף שלי'});
      expect(ShortcutValidator.shortcutKeys, contains(key));
      expect(ShortcutValidator.shortcutNames[key], 'פתיחת התוסף שלי');
    });

    test('רישום ריק מסיר מפתחות תוספים קודמים', () {
      ShortcutValidator.registerPluginShortcutKeys({key: 'פתיחת התוסף שלי'});
      ShortcutValidator.registerPluginShortcutKeys(const {});
      expect(ShortcutValidator.shortcutKeys, isNot(contains(key)));
      expect(ShortcutValidator.shortcutNames[key], isNull);
    });

    test('קיצור תוסף נכלל בזיהוי קונפליקטים מול פעולה מובנית', () async {
      ShortcutValidator.registerPluginShortcutKeys({key: 'פתיחת התוסף שלי'});
      await Settings.setValue<String>(key, 'ctrl+l');
      // ctrl+l הוא ברירת המחדל של פתיחת הספרייה — צפוי קונפליקט.
      expect(ShortcutValidator.hasConflict(key), isTrue);
    });

    test('ה-deep-link שהקיצור מפעיל מתפענח ל-OpenPluginAction', () {
      final action = ExternalUriRouter.parseUri(
        Uri.parse('otzaria://open/plugin/$pluginId'),
      );
      expect(action, isA<OpenPluginAction>());
      expect((action as OpenPluginAction).pluginId, pluginId);
    });
  });

  group('canShareShortcut', () {
    test('מפתח יכול לחלוק עם עצמו', () {
      expect(
        ShortcutValidator.canShareShortcut(
          'key-shortcut-print',
          'key-shortcut-print',
        ),
        isTrue,
      );
    });

    test('מפתחות בקבוצה תואמת יכולים לחלוק', () {
      expect(
        ShortcutValidator.canShareShortcut(
          'key-shortcut-add-note',
          'key-shortcut-calendar-toggle-events',
        ),
        isTrue,
      );
    });

    test('מפתחות לא קשורים אינם יכולים לחלוק', () {
      expect(
        ShortcutValidator.canShareShortcut(
          'key-shortcut-print',
          'key-shortcut-add-note',
        ),
        isFalse,
      );
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
    if (value is T) return value;
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
