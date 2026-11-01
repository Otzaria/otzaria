import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_selection_preferences.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/search/models/search_configuration.dart';

void main() {
  Map<String, dynamic> item({Object? disabledSearchOptions}) {
    final payload = <String, dynamic>{
      'id': 'include-external',
      'type': 'checkbox',
      'title': 'חפש גם במקור חיצוני',
      'defaultValue': true,
      'openPluginOnSubmit': true,
      'visibleInModes': ['exact', 'advanced'],
    };
    if (disabledSearchOptions != null) {
      payload['disabledSearchOptions'] = disabledSearchOptions;
    }
    return payload;
  }

  test('parses a static checkbox with mode-specific disabled options', () {
    final parsed = PluginSearchDialogItem.fromPayload(
      item(
        disabledSearchOptions: {
          'advanced': ['word.partial', 'word.typo-tolerance'],
        },
      ),
    );

    expect(parsed.defaultValue, isTrue);
    expect(parsed.openPluginOnSubmit, isTrue);
    expect(parsed.isVisibleIn(SearchMode.exact), isTrue);
    expect(parsed.isVisibleIn(SearchMode.advanced), isTrue);
    expect(parsed.isVisibleIn(SearchMode.fuzzy), isFalse);
    expect(parsed.disabledOptionsFor(SearchMode.advanced), {
      'word.partial',
      'word.typo-tolerance',
    });
  });

  group('type ו-persist', () {
    test('ברירת המחדל: checkbox שנשמר', () {
      final parsed = PluginSearchDialogItem.fromPayload(item());
      expect(parsed.type, PluginSearchDialogItemType.checkbox);
      expect(parsed.isSwitch, isFalse);
      expect(parsed.persist, isTrue);
    });

    test('switch נקרא, עם persist ברירת מחדל true', () {
      final parsed = PluginSearchDialogItem.fromPayload({
        ...item(),
        'type': 'switch',
      });
      expect(parsed.type, PluginSearchDialogItemType.switchToggle);
      expect(parsed.isSwitch, isTrue);
      expect(parsed.persist, isTrue);
    });

    test('persist false נקרא גם ב-checkbox וגם ב-switch', () {
      for (final type in ['checkbox', 'switch']) {
        final parsed = PluginSearchDialogItem.fromPayload({
          ...item(),
          'type': type,
          'persist': false,
        });
        expect(parsed.persist, isFalse, reason: type);
      }
    });

    for (final (name, payload) in <(String, Map<String, dynamic>)>[
      ('type לא מוכר', {...item(), 'type': 'radio'}),
      ('type חסר', {...item()..remove('type')}),
      ('persist לא בוליאני', {...item(), 'persist': 'no'}),
    ]) {
      test('נדחה: $name', () {
        expect(
          () => PluginSearchDialogItem.fromPayload(payload),
          throwsA(isA<PluginSearchDialogItemException>()),
        );
      });
    }
  });

  group('PluginSearchSelectionPreferences.resolveSelection', () {
    PluginSearchDialogItem parse({bool persist = true, bool def = false}) =>
        PluginSearchDialogItem.fromPayload({
          ...item(),
          'defaultValue': def,
          'persist': persist,
        });
    final resolve = PluginSearchSelectionPreferences.resolveSelection;

    test('פריט שנשמר: טאב > שמור > ברירת מחדל', () {
      final persisted = parse(def: true);
      expect(resolve(persisted), isTrue);
      expect(resolve(persisted, persistedValue: false), isFalse);
      expect(
        resolve(persisted, tabValue: true, persistedValue: false),
        isTrue,
      );
    });

    test('פריט חד-פעמי מתעלם מהערך השמור וחוזר לברירת המחדל', () {
      final oneShot = parse(persist: false, def: true);
      expect(resolve(oneShot, persistedValue: false), isTrue);
      expect(resolve(oneShot, tabValue: false, persistedValue: true), isFalse);
    });

    test('persistedAfterChange: null לפריט חד-פעמי, מפה חדשה לפריט שנשמר', () {
      final persisted = {'p/a': true};
      final after = PluginSearchSelectionPreferences.persistedAfterChange(
        persisted,
        'p/b',
        parse(),
        false,
      );
      expect(after, {'p/a': true, 'p/b': false});
      expect(persisted, {'p/a': true});
      expect(
        PluginSearchSelectionPreferences.persistedAfterChange(
          persisted,
          'p/b',
          parse(persist: false),
          false,
        ),
        isNull,
      );
    });
  });

  test('resultsProvider תקין נשמר עם כותרת מדור, וסותר openPluginOnSubmit', () {
    final parsed = PluginSearchDialogItem.fromPayload({
      ...item(),
      'openPluginOnSubmit': false,
      'resultsProvider': 'hebrewbooks',
      'resultsTitle': 'היברובוקס',
    });
    expect(parsed.resultsProvider, 'hebrewbooks');
    expect(parsed.resultsTitle, 'היברובוקס');

    // ללא resultsTitle — הכותרת נופלת לכותרת השורה.
    final untitled = PluginSearchDialogItem.fromPayload({
      ...item(),
      'openPluginOnSubmit': false,
      'resultsProvider': 'hebrewbooks',
    });
    expect(untitled.resultsTitle, untitled.title);

    for (final invalid in [
      {'resultsProvider': 'hebrewbooks'}, // עם openPluginOnSubmit: true
      {'openPluginOnSubmit': false, 'resultsProvider': 'Has Spaces'},
      {'openPluginOnSubmit': false, 'resultsTitle': 'ללא ספק'},
    ]) {
      expect(
        () => PluginSearchDialogItem.fromPayload({...item(), ...invalid}),
        throwsA(isA<PluginSearchDialogItemException>()),
        reason: '$invalid היה אמור להידחות',
      );
    }
  });

  test('resultsAction נשמר, ודורש openPluginOnSubmit', () {
    final parsed = PluginSearchDialogItem.fromPayload({
      ...item(),
      'resultsAction': 'המשך במקור החיצוני',
    });
    expect(parsed.resultsAction, 'המשך במקור החיצוני');
    expect(PluginSearchDialogItem.fromPayload(item()).resultsAction, isNull);

    for (final invalid in [
      {'openPluginOnSubmit': false, 'resultsAction': 'המשך'},
      {'resultsAction': ''},
      {'resultsAction': 7},
    ]) {
      expect(
        () => PluginSearchDialogItem.fromPayload({...item(), ...invalid}),
        throwsA(isA<PluginSearchDialogItemException>()),
        reason: '$invalid היה אמור להידחות',
      );
    }
  });

  test('rejects a non-boolean openPluginOnSubmit value', () {
    expect(
      () => PluginSearchDialogItem.fromPayload({
        ...item(),
        'openPluginOnSubmit': 'yes',
      }),
      throwsA(isA<PluginSearchDialogItemException>()),
    );
  });

  test('rejects an unknown native search option id', () {
    expect(
      () => PluginSearchDialogItem.fromPayload(
        item(
          disabledSearchOptions: {
            'advanced': ['word.not-a-real-option'],
          },
        ),
      ),
      throwsA(isA<PluginSearchDialogItemException>()),
    );
  });

  test(
    'registry replaces an item with the same id instead of duplicating it',
    () {
      final registry = PluginSearchDialogRegistry.forTesting();
      addTearDown(registry.dispose);

      registry.registerPayload('test.plugin', item());
      registry.registerPayload('test.plugin', {
        ...item(),
        'title': 'חפש גם במקור אחר',
      });

      final records = registry.getAll();
      expect(records, hasLength(1));
      expect(records.single.$2.title, 'חפש גם במקור אחר');
    },
  );

  test('התנגשות provider אינה משאירה שורת חיפוש של התוסף הזר', () {
    const owner = 'provider-owner-test';
    const attacker = 'provider-attacker-test';
    const provider = 'ownership-test-provider';
    final registry = PluginSearchDialogRegistry.instance;
    addTearDown(() {
      registry.removeAll(owner);
      registry.removeAll(attacker);
      PluginExternalSearchService.instance.removePlugin(owner);
      PluginExternalSearchService.instance.removePlugin(attacker);
    });

    registry.registerPayload(owner, {
      ...item(),
      'openPluginOnSubmit': false,
      'resultsProvider': provider,
    });

    expect(
      () => registry.registerPayload(attacker, {
        ...item(),
        'openPluginOnSubmit': false,
        'resultsProvider': provider,
      }),
      throwsStateError,
    );
    expect(
      registry.getAll().where((record) => record.$1 == attacker),
      isEmpty,
    );
  });
}
