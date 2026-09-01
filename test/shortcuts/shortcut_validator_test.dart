import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  tearDown(() {
    // מנקה רישום קיצורי תוספים כדי שלא יזלוג בין טסטים.
    ShortcutValidator.registerPluginShortcutKeys(const {});
    ShortcutValidator.registerPluginShortcuts(const {});
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

    test(
      'ערך ריק שנשמר במפורש מבטל את הקיצור ואינו נופל לברירת המחדל',
      () async {
        await Settings.setValue<String>(
          'key-shortcut-open-library-browser',
          '',
        );
        expect(
          ShortcutValidator.getShortcutValue(
            'key-shortcut-open-library-browser',
          ),
          isNull,
        );
      },
    );

    test('ביטול קיצור משחרר את הצירוף מרשימת הקונפליקטים', () async {
      await Settings.setValue<String>('key-shortcut-open-library-browser', '');
      await Settings.setValue<String>('key-shortcut-open-history', 'ctrl+l');

      expect(ShortcutValidator.checkConflicts(), isEmpty);
      expect(
        ShortcutValidator.hasConflict('key-shortcut-open-history'),
        isFalse,
      );
    });

    test('ביטול קיצור אינו נופל למפתח legacy', () async {
      await Settings.setValue<String>(
        ShortcutValidator.legacySearchInBookKey,
        'ctrl+g',
      );
      await Settings.setValue<String>(
        ShortcutValidator.currentWindowSearchKey,
        '',
      );
      expect(
        ShortcutValidator.getShortcutValue(
          ShortcutValidator.currentWindowSearchKey,
        ),
        isNull,
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

  group('קיצורי תוספים (registerPluginShortcuts)', () {
    const pluginId = 'com.example.marker';
    const shortcutId = 'highlight';
    final key = ShortcutValidator.pluginShortcutKey(pluginId, shortcutId);
    const target = (
      pluginId: pluginId,
      shortcutId: shortcutId,
      label: 'הדגשה',
      defaultKey: 'ctrl+alt+h',
      command: null,
      contextMenuItemId: 'highlight-item',
    );

    test('pluginShortcutKey בונה מפתח עם הקידומת והיעד', () {
      expect(key, 'key-shortcut-plugin-$pluginId::$shortcutId');
    });

    test('רישום מוסיף את המפתח ל-shortcutKeys ול-shortcutNames', () {
      expect(ShortcutValidator.shortcutKeys, isNot(contains(key)));
      ShortcutValidator.registerPluginShortcuts({key: target});
      expect(ShortcutValidator.shortcutKeys, contains(key));
      expect(ShortcutValidator.shortcutNames[key], 'הדגשה');
      expect(ShortcutValidator.pluginShortcuts[key], target);
    });

    test('רישום ריק מסיר מפתחות קודמים', () {
      ShortcutValidator.registerPluginShortcuts({key: target});
      ShortcutValidator.registerPluginShortcuts(const {});
      expect(ShortcutValidator.shortcutKeys, isNot(contains(key)));
      expect(ShortcutValidator.shortcutNames[key], isNull);
    });

    test('getShortcutValue נופל לקיצור ברירת המחדל שהתוסף הצהיר', () {
      ShortcutValidator.registerPluginShortcuts({key: target});
      expect(ShortcutValidator.getShortcutValue(key), 'ctrl+alt+h');
    });

    test(
      'קיצור תוסף בלי ברירת מחדל נחשב לא-מוגדר — יוצג ב"הוסף קיצור לפעולה זמינה"',
      () {
        const emptyTarget = (
          pluginId: pluginId,
          shortcutId: 'no-default',
          label: 'פעולה ללא קיצור',
          defaultKey: '',
          command: 'doThing',
          contextMenuItemId: null,
        );
        final emptyKey = ShortcutValidator.pluginShortcutKey(
          pluginId,
          'no-default',
        );
        ShortcutValidator.registerPluginShortcuts({emptyKey: emptyTarget});

        // בלי ברירת מחדל אין ערך — ולכן הקיצור נכלל ב-unconfiguredKeys
        // של מסך ההגדרות ומוצג ב"הוסף קיצור לפעולה זמינה".
        expect(ShortcutValidator.getShortcutValue(emptyKey) ?? '', isEmpty);
        expect(ShortcutValidator.shortcutKeys, contains(emptyKey));
        expect(ShortcutValidator.shortcutNames[emptyKey], 'פעולה ללא קיצור');
      },
    );

    test('ערך שהמשתמש הגדיר גובר על קיצור ברירת המחדל של התוסף', () async {
      ShortcutValidator.registerPluginShortcuts({key: target});
      await Settings.setValue<String>(key, 'ctrl+shift+m');
      expect(ShortcutValidator.getShortcutValue(key), 'ctrl+shift+m');
    });

    test('קיצור תוסף נכלל בזיהוי קונפליקטים מול פעולה מובנית', () async {
      ShortcutValidator.registerPluginShortcuts({key: target});
      await Settings.setValue<String>(key, 'ctrl+l');
      expect(ShortcutValidator.hasConflict(key), isTrue);
    });

    test('זיהוי התנגשות מנרמל אותיות גדולות של קיצור תוסף', () async {
      ShortcutValidator.registerPluginShortcuts({key: target});
      await Settings.setValue<String>(key, 'CTRL+L');

      expect(ShortcutValidator.getShortcutValue(key), 'ctrl+l');
      expect(ShortcutValidator.hasConflict(key), isTrue);
    });

    test(
      'ברירת מחדל שמתנגשת עם קיצור מובנה משאירה את קיצור התוסף לא-מוגדר',
      () {
        const conflicting = (
          pluginId: pluginId,
          shortcutId: 'conflict',
          label: 'מתנגש',
          defaultKey: 'ctrl+l', // תפוס ע"י פתיחת הספרייה
          command: 'x',
          contextMenuItemId: null,
        );
        final conflictingKey = ShortcutValidator.pluginShortcutKey(
          pluginId,
          'conflict',
        );
        ShortcutValidator.registerPluginShortcuts({
          conflictingKey: conflicting,
        });

        expect(ShortcutValidator.getShortcutValue(conflictingKey), isNull);
        // מופיע ברשימה הכללית כדי שיוצג ב"הוסף קיצור לפעולה זמינה".
        expect(ShortcutValidator.shortcutKeys, contains(conflictingKey));
      },
    );

    test('ברירת מחדל באותיות גדולות מתנגשת עם קיצור מובנה', () {
      const conflicting = (
        pluginId: pluginId,
        shortcutId: 'uppercase-conflict',
        label: 'מתנגש',
        defaultKey: 'CTRL+L',
        command: 'x',
        contextMenuItemId: null,
      );
      final conflictingKey = ShortcutValidator.pluginShortcutKey(
        pluginId,
        'uppercase-conflict',
      );
      ShortcutValidator.registerPluginShortcuts({conflictingKey: conflicting});

      expect(ShortcutValidator.getShortcutValue(conflictingKey), isNull);
    });

    test('ב-macOS meta מתנגש סמנטית עם קיצור ctrl קיים', () {
      ShortcutHelper.isMacForTesting = true;
      addTearDown(() => ShortcutHelper.isMacForTesting = null);
      const conflicting = (
        pluginId: pluginId,
        shortcutId: 'mac-conflict',
        label: 'מתנגש',
        defaultKey: 'meta+l',
        command: 'x',
        contextMenuItemId: null,
      );
      final conflictingKey = ShortcutValidator.pluginShortcutKey(
        pluginId,
        'mac-conflict',
      );
      ShortcutValidator.registerPluginShortcuts({conflictingKey: conflicting});

      expect(ShortcutValidator.getShortcutValue(conflictingKey), isNull);
    });

    test('ביטול מפורש (ערך ריק) משאיר קיצור תוסף לא-מוגדר', () async {
      ShortcutValidator.registerPluginShortcuts({key: target});
      await Settings.setValue<String>(key, '');
      expect(ShortcutValidator.getShortcutValue(key), isNull);
    });

    test('שני קיצורי תוסף עם אותה ברירת מחדל — הראשון (ממוין) זוכה', () {
      const first = (
        pluginId: 'com.a',
        shortcutId: 'first',
        label: 'ראשון',
        defaultKey: 'ctrl+alt+x',
        command: 'a',
        contextMenuItemId: null,
      );
      const second = (
        pluginId: 'com.a',
        shortcutId: 'second',
        label: 'שני',
        defaultKey: 'ctrl+alt+x',
        command: 'b',
        contextMenuItemId: null,
      );
      final firstKey = ShortcutValidator.pluginShortcutKey('com.a', 'first');
      final secondKey = ShortcutValidator.pluginShortcutKey('com.a', 'second');
      ShortcutValidator.registerPluginShortcuts({
        secondKey: second,
        firstKey: first,
      });

      expect(ShortcutValidator.getShortcutValue(firstKey), 'ctrl+alt+x');
      expect(ShortcutValidator.getShortcutValue(secondKey), isNull);
      expect(ShortcutValidator.pluginShortcuts[secondKey]?.defaultKey, isEmpty);
    });

    test(
      'ברירת מחדל של תוסף לא מתנגשת עם קיצור שהמשתמש הקצה לתוסף אחר',
      () async {
        const other = (
          pluginId: 'com.b',
          shortcutId: 'other',
          label: 'אחר',
          defaultKey: '',
          command: 'other',
          contextMenuItemId: null,
        );
        final otherKey = ShortcutValidator.pluginShortcutKey('com.b', 'other');
        await Settings.setValue<String>(otherKey, 'ctrl+alt+h');
        ShortcutValidator.registerPluginShortcuts({
          key: target,
          otherKey: other,
        });
        expect(ShortcutValidator.getShortcutValue(key), isNull);
      },
    );
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
