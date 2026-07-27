import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

import '../../helpers/memory_settings_cache.dart';

/// ניקוי קיצורים שהמקש שלהם אינו מוכר. קיצור שהוקלט בפריסה לא-לטינית לפני
/// שההקלטה נורמלה נשמר עם התו המקומי (`ctrl+shift+כ`) ולעולם לא נתפס —
/// מחיקתו מחזירה את הפעולה לקיצור ברירת המחדל שעובד.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const newSearchKey = 'key-shortcut-open-new-search';
  const closeTabKey = 'key-shortcut-close-tab';

  late MemorySettingsCache cache;
  late SettingsRepository repository;

  setUp(() async {
    cache = MemorySettingsCache();
    await Settings.init(cacheProvider: cache);
    repository = SettingsRepository();
  });

  Future<void> storeShortcut(String key, String value) async {
    await cache.setString(key, value);
    final stored = Map<String, String>.from(
      (cache.getValue<Map<dynamic, dynamic>>('shortcuts') ??
              <dynamic, dynamic>{})
          .cast<String, String>(),
    );
    stored[key] = value;
    await cache.setObject('shortcuts', stored);
  }

  Map<String, String> storedMap() => Map<String, String>.from(
    (cache.getValue<Map<dynamic, dynamic>>('shortcuts') ?? <dynamic, dynamic>{})
        .cast<String, String>(),
  );

  group('removeUnrecognizedShortcuts', () {
    test('מוחק קיצור עם תו עברי ומחזיר את ברירת המחדל', () async {
      await storeShortcut(newSearchKey, 'ctrl+shift+כ');

      await repository.removeUnrecognizedShortcuts();

      expect(cache.getString(newSearchKey), isNull);
      expect(storedMap(), isNot(contains(newSearchKey)));

      final shortcuts = await repository.getShortcuts();
      expect(shortcuts[newSearchKey], 'ctrl+shift+f');
      expect(ShortcutValidator.getShortcutValue(newSearchKey), 'ctrl+shift+f');
    });

    test('מוחק קיצור שנשמר בלי מקש ראשי כלל', () async {
      await storeShortcut(newSearchKey, 'ctrl+shift+');

      await repository.removeUnrecognizedShortcuts();

      expect(cache.getString(newSearchKey), isNull);
      expect((await repository.getShortcuts())[newSearchKey], 'ctrl+shift+f');
    });

    test('אינו נוגע בקיצור מותאם אישית תקין', () async {
      await storeShortcut(newSearchKey, 'ctrl+shift+d');

      await repository.removeUnrecognizedShortcuts();

      expect(cache.getString(newSearchKey), 'ctrl+shift+d');
      expect(storedMap()[newSearchKey], 'ctrl+shift+d');
      expect((await repository.getShortcuts())[newSearchKey], 'ctrl+shift+d');
    });

    test('אינו נוגע בקיצורים שאינם אות (F11, Alt+חץ, Ctrl+פסיק)', () async {
      await storeShortcut(newSearchKey, 'f11');
      await storeShortcut(closeTabKey, 'alt+arrowup');
      await storeShortcut('key-shortcut-open-settings', 'ctrl+comma');

      await repository.removeUnrecognizedShortcuts();

      final shortcuts = await repository.getShortcuts();
      expect(shortcuts[newSearchKey], 'f11');
      expect(shortcuts[closeTabKey], 'alt+arrowup');
      expect(shortcuts['key-shortcut-open-settings'], 'ctrl+comma');
    });

    test('אינו מוחק קיצור ריק (פעולה שהמשתמש השאיר בלי קיצור)', () async {
      await storeShortcut(ShortcutValidator.openAdvancedSearchKey, '');

      await repository.removeUnrecognizedShortcuts();

      expect(
        (await repository
            .getShortcuts())[ShortcutValidator.openAdvancedSearchKey],
        '',
      );
    });

    test('מוחק את השבורים בלבד כששמורים גם תקינים וגם שבורים', () async {
      await storeShortcut(newSearchKey, 'ctrl+shift+כ');
      await storeShortcut(closeTabKey, 'ctrl+shift+d');
      await storeShortcut('key-shortcut-open-history', 'alt+ש');

      await repository.removeUnrecognizedShortcuts();

      expect(storedMap().keys, contains(closeTabKey));
      expect(storedMap().keys, isNot(contains(newSearchKey)));
      expect(storedMap().keys, isNot(contains('key-shortcut-open-history')));

      final shortcuts = await repository.getShortcuts();
      expect(shortcuts[closeTabKey], 'ctrl+shift+d');
      expect(shortcuts[newSearchKey], 'ctrl+shift+f');
      expect(shortcuts['key-shortcut-open-history'], 'ctrl+h');
    });

    test('מוחק קיצור שבור גם ממפתח legacy', () async {
      await storeShortcut(ShortcutValidator.legacySearchInBookKey, 'ctrl+כ');

      await repository.removeUnrecognizedShortcuts();

      expect(cache.getString(ShortcutValidator.legacySearchInBookKey), isNull);
      expect(
        (await repository
            .getShortcuts())[ShortcutValidator.currentWindowSearchKey],
        'ctrl+f',
      );
    });

    test('מוחק קיצור שבור של תוסף שאינו רשום כרגע', () async {
      final pluginKey = ShortcutValidator.openPluginShortcutKey('some.plugin');
      await storeShortcut(pluginKey, 'ctrl+shift+ע');

      await repository.removeUnrecognizedShortcuts();

      expect(cache.getString(pluginKey), isNull);
      expect(storedMap(), isNot(contains(pluginKey)));
    });

    test('פעולה חוזרת אינה משנה דבר (idempotent)', () async {
      await storeShortcut(newSearchKey, 'ctrl+shift+כ');
      await storeShortcut(closeTabKey, 'ctrl+shift+d');

      await repository.removeUnrecognizedShortcuts();
      final afterFirst = await repository.getShortcuts();

      await repository.removeUnrecognizedShortcuts();
      final afterSecond = await repository.getShortcuts();

      expect(afterSecond, afterFirst);
      expect(afterSecond[closeTabKey], 'ctrl+shift+d');
    });

    test('ללא קיצורים שמורים כלל אינו זורק ואינו משנה ברירות מחדל', () async {
      await repository.removeUnrecognizedShortcuts();

      final shortcuts = await repository.getShortcuts();
      expect(shortcuts[newSearchKey], 'ctrl+shift+f');
      expect(shortcuts[closeTabKey], 'ctrl+w');
    });

    test('loadSettings מריץ את הניקוי אוטומטית בעליית האפליקציה', () async {
      await storeShortcut(newSearchKey, 'ctrl+shift+כ');

      final settings = await repository.loadSettings();

      final shortcuts = settings['shortcuts'] as Map<String, String>;
      expect(shortcuts[newSearchKey], 'ctrl+shift+f');
      expect(cache.getString(newSearchKey), isNull);
    });

    test('הקיצורים שנותרו לאחר הניקוי כולם ניתנים לזיהוי', () async {
      await storeShortcut(newSearchKey, 'ctrl+shift+כ');
      await storeShortcut(closeTabKey, 'ctrl+ד');
      await storeShortcut('key-shortcut-open-more', 'ctrl+shift+d');

      await repository.removeUnrecognizedShortcuts();

      final shortcuts = await repository.getShortcuts();
      for (final entry in shortcuts.entries) {
        expect(
          ShortcutValidator.getShortcutValue(entry.key),
          isNotNull,
          reason: '${entry.key} נותר ללא ערך תקין',
        );
      }
    });
  });
}
