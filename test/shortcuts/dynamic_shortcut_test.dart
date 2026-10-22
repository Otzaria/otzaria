import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_registry.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  group('DynamicDisplayChange.patchFor', () {
    test('toggle מחליף את הערך הנוכחי, show/hide קובעים', () {
      const change = DynamicDisplayChange(
        nikud: DynamicMarkChange.toggle,
        punctuation: DynamicMarkChange.hide,
      );
      final fromShown = change.patchFor(TextDisplayProfile.defaults);
      expect(fromShown.nikud, MarkVisibility.hide);
      expect(fromShown.punctuation, MarkVisibility.hide);
      expect(fromShown.teamim, isNull);

      final fromHidden = change.patchFor(
        const TextDisplayProfile(nikud: MarkVisibility.hide),
      );
      expect(fromHidden.nikud, MarkVisibility.show);
    });

    test('toggle טעמים מתייחס למה שמוצג בפועל (כולל followNikud)', () {
      const change = DynamicDisplayChange(teamim: DynamicTeamimChange.toggle);
      // ניקוד מוסתר + followNikud ⇒ הטעמים מוסתרים ⇒ toggle מציג.
      final patch = change.patchFor(
        const TextDisplayProfile(nikud: MarkVisibility.hide),
      );
      expect(patch.teamim, TeamimVisibility.show);
    });

    test('שינוי ריק אינו מייצר טלאי', () {
      const change = DynamicDisplayChange();
      expect(change.isEmpty, isTrue);
      expect(change.patchFor(TextDisplayProfile.defaults).isEmpty, isTrue);
    });
  });

  group('DynamicShortcut', () {
    const shortcut = DynamicShortcut(
      id: 'abc',
      key: 'ctrl+shift+n',
      kind: DynamicShortcutKind.setTextDisplay,
      target: TextTarget.commentary,
      change: DynamicDisplayChange(
        nikud: DynamicMarkChange.hide,
        teamim: DynamicTeamimChange.followNikud,
      ),
      persistToBook: true,
    );

    test('JSON הלוך ושוב', () {
      expect(DynamicShortcut.fromJson(shortcut.toJson()), shortcut);
    });

    test('רשומה פגומה מוחזרת כ-null', () {
      expect(DynamicShortcut.fromJson({'key': 'ctrl+x'}), isNull);
      expect(
        DynamicShortcut.fromJson({'id': 'x', 'kind': 'nope'}),
        isNull,
      );
    });

    test('describe מתאר את הפרמטרים בעברית', () {
      final text = shortcut.describe();
      expect(text, contains('הסתר ניקוד'));
      expect(text, contains('טעמים כמו הניקוד'));
      expect(text, contains('מפרשים'));
      expect(text, contains('נשמר לספר'));
    });

    group('ללא עיצוב (issue #1299)', () {
      const copyPlain = DynamicShortcut(
        id: 'p',
        key: 'ctrl+alt+c',
        kind: DynamicShortcutKind.copySelectionWith,
        change: DynamicDisplayChange(),
        plainTextOnly: true,
      );

      test('JSON הלוך ושוב שומר את הדגל', () {
        final restored = DynamicShortcut.fromJson(copyPlain.toJson())!;
        expect(restored.plainTextOnly, isTrue);
        expect(restored, copyPlain);
      });

      test('העתקה ללא עיצוב בלבד היא קיצור תקף ומתוארת כך', () {
        expect(copyPlain.hasEffect, isTrue);
        expect(copyPlain.describe(), 'העתק בחירה: ללא עיצוב');
      });

      test('בשינוי תצוגה הדגל חסר משמעות', () {
        final display = copyPlain.copyWith(
          kind: DynamicShortcutKind.setTextDisplay,
        );
        expect(display.hasEffect, isFalse);
        expect(display.describe(), isNot(contains('ללא עיצוב')));
      });
    });

    test('settingKey נושא את הקידומת הסינתטית', () {
      expect(shortcut.settingKey, 'key-shortcut-dynamic-abc');
    });
  });

  group('DynamicShortcutRegistry', () {
    late DynamicShortcutRegistry registry;

    setUp(() {
      registry = DynamicShortcutRegistry.forTesting();
      ShortcutValidator.registerDynamicShortcuts(const {});
    });

    test('put/remove מסנכרנים את הולידטור', () {
      registry.put(
        const DynamicShortcut(
          id: 'a',
          key: 'ctrl+alt+q',
          kind: DynamicShortcutKind.copySelectionWith,
          change: DynamicDisplayChange(nikud: DynamicMarkChange.hide),
        ),
      );
      expect(
        ShortcutValidator.shortcutKeys,
        contains('key-shortcut-dynamic-a'),
      );
      expect(
        ShortcutValidator.shortcutNames['key-shortcut-dynamic-a'],
        contains('העתק בחירה'),
      );
      registry.remove('a');
      expect(
        ShortcutValidator.shortcutKeys,
        isNot(contains('key-shortcut-dynamic-a')),
      );
    });

    test('loadFromJson מדלג על רשומות פגומות ולא נופל על JSON שבור', () {
      registry.loadFromJson(
        '[{"id":"ok","kind":"setTextDisplay","key":"ctrl+1"},{"kind":"x"}]',
      );
      expect(registry.shortcuts.map((s) => s.id), ['ok']);
      registry.loadFromJson('not json');
      expect(registry.shortcuts, isEmpty);
    });

    test(
      'קיצור דינמי שמור על מקש ניווט נשמט בטעינה, ותקין נשאר (issue #2851)',
      () async {
        final cache = MemorySettingsCache();
        await Settings.init(cacheProvider: cache);
        await cache.setString(
          DynamicShortcutRegistry.settingsKey,
          '[{"id":"ok","kind":"setTextDisplay","key":"ctrl+1"},'
          '{"id":"nav","kind":"setTextDisplay","key":"ctrl+arrowleft"}]',
        );

        expect(DynamicShortcutRegistry.instance.shortcuts.map((s) => s.id), [
          'ok',
        ]);
      },
    );

    test('put עם אותו id מחליף', () {
      registry.put(
        const DynamicShortcut(
          id: 'a',
          key: 'ctrl+1',
          kind: DynamicShortcutKind.setTextDisplay,
          change: DynamicDisplayChange(nikud: DynamicMarkChange.toggle),
        ),
      );
      registry.put(
        const DynamicShortcut(
          id: 'a',
          key: 'ctrl+2',
          kind: DynamicShortcutKind.setTextDisplay,
          change: DynamicDisplayChange(nikud: DynamicMarkChange.toggle),
        ),
      );
      expect(registry.shortcuts.length, 1);
      expect(registry.byId('a')!.key, 'ctrl+2');
    });
  });
}
