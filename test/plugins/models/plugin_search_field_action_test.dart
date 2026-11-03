import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/models/plugin_startup_contributions.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';

void main() {
  group('PluginSearchFieldAction.fromPayload', () {
    test('פריט מלא נקרא כמו שהוא', () {
      final action = PluginSearchFieldAction.fromPayload({
        'id': 'dictate',
        'title': 'חיפוש בדיבור',
        'icon': 'mic_24_regular',
        'activeIcon': 'mic_24_filled',
        'fields': ['library', 'inBook'],
      });
      expect(action.id, 'dictate');
      expect(action.activeIcon, 'mic_24_filled');
      expect(action.fields, {
        PluginSearchField.library,
        PluginSearchField.inBook,
      });
    });

    test('בלי fields — כל השדות; שדה לא מוכר מדולג', () {
      final all = PluginSearchFieldAction.fromPayload({
        'id': 'a',
        'title': 'א',
      });
      expect(all.fields, PluginSearchField.values.toSet());

      final payload = {
        'id': 'a',
        'title': 'א',
        'fields': ['findRef', 'futureField'],
      };
      expect(PluginSearchFieldAction.fromPayload(payload).fields, {
        PluginSearchField.findRef,
      });
      expect(PluginSearchFieldAction.unknownFieldNames(payload), [
        'futureField',
      ]);
    });

    for (final (name, payload) in [
      ('בלי title', {'id': 'a'}),
      ('id לא חוקי', {'id': 'a b', 'title': 'א'}),
      ('שדה לא מוכר', {'id': 'a', 'title': 'א', 'onClick': 'x'}),
      ('fields ריק', {'id': 'a', 'title': 'א', 'fields': <String>[]}),
      ('title עם שבירת שורה', {'id': 'a', 'title': 'א\nב'}),
    ]) {
      test('נדחה: $name', () {
        expect(
          () => PluginSearchFieldAction.fromPayload(payload),
          throwsA(isA<PluginSearchFieldActionException>()),
        );
      });
    }
  });

  group('visibleWhen ו-mode', () {
    test('ברירות מחדל: תמיד מוצג, מצב session', () {
      final action = PluginSearchFieldAction.fromPayload({
        'id': 'a',
        'title': 'א',
      });
      expect(action.visibleWhen, PluginSearchFieldActionVisibility.always);
      expect(action.showOnlyWithText, isFalse);
      expect(action.isVisibleFor(''), isTrue);
      expect(action.mode, PluginSearchFieldActionMode.session);
      expect(action.isProviderBooksFilter, isFalse);
    });

    test('nonEmptyText מוצג רק כשיש טקסט', () {
      final action = PluginSearchFieldAction.fromPayload({
        'id': 'a',
        'title': 'א',
        'visibleWhen': 'nonEmptyText',
      });
      expect(action.showOnlyWithText, isTrue);
      expect(action.isVisibleFor(''), isFalse);
      expect(action.isVisibleFor('ברכות'), isTrue);
    });

    test('providerBooksFilter: ברירת מחדל שדה library בלבד', () {
      final action = PluginSearchFieldAction.fromPayload({
        'id': 'f',
        'title': 'מקור',
        'mode': 'providerBooksFilter',
        'libraryOnlyIcon': 'book_24_regular',
      });
      expect(action.isProviderBooksFilter, isTrue);
      expect(action.fields, {PluginSearchField.library});
      expect(action.libraryOnlyIcon, 'book_24_regular');
    });

    test('תוויות הסינון: חסרות כברירת מחדל, ומה שהתוסף קבע', () {
      final plain = PluginSearchFieldAction.fromPayload({
        'id': 'f',
        'title': 'מקור',
        'mode': 'providerBooksFilter',
      });
      expect(plain.pluginOnlyLabel, isNull);
      expect(plain.libraryOnlyLabel, isNull);

      final labeled = PluginSearchFieldAction.fromPayload({
        'id': 'f',
        'title': 'מקור',
        'mode': 'providerBooksFilter',
        'pluginOnlyLabel': 'רק בר אילן',
        'libraryOnlyLabel': 'רק אוצריא',
      });
      expect(labeled.pluginOnlyLabel, 'רק בר אילן');
      expect(labeled.libraryOnlyLabel, 'רק אוצריא');
    });

    test('תווית באורך המרבי תקפה', () {
      final label = 'א' * PluginSearchFieldAction.maxFilterLabelLength;
      final action = PluginSearchFieldAction.fromPayload({
        'id': 'f',
        'title': 'מקור',
        'mode': 'providerBooksFilter',
        'libraryOnlyLabel': label,
      });
      expect(action.libraryOnlyLabel, label);
    });

    test('providerBooksFilter עם library ושדה עתידי לא מוכר תקף', () {
      final action = PluginSearchFieldAction.fromPayload({
        'id': 'f',
        'title': 'מקור',
        'mode': 'providerBooksFilter',
        'fields': ['library', 'future'],
      });
      expect(action.fields, {PluginSearchField.library});
    });

    for (final (name, payload) in <(String, Map<String, dynamic>)>[
      ('visibleWhen לא מוכר', {'visibleWhen': 'never'}),
      ('visibleWhen לא מחרוזת', {'visibleWhen': true}),
      ('mode לא מוכר', {'mode': 'toggle'}),
      (
        'providerBooksFilter בשדה אחר',
        {
          'mode': 'providerBooksFilter',
          'fields': ['inBook'],
        },
      ),
      (
        'providerBooksFilter בכמה שדות',
        {
          'mode': 'providerBooksFilter',
          'fields': ['library', 'inBook'],
        },
      ),
      ('libraryOnlyIcon בלי providerBooksFilter', {'libraryOnlyIcon': 'x'}),
      ('pluginOnlyLabel בלי providerBooksFilter', {'pluginOnlyLabel': 'רק'}),
      ('libraryOnlyLabel בלי providerBooksFilter', {'libraryOnlyLabel': 'רק'}),
      for (final key in ['pluginOnlyLabel', 'libraryOnlyLabel']) ...[
        ('$key ריק', {'mode': 'providerBooksFilter', key: ''}),
        ('$key רווחים בלבד', {'mode': 'providerBooksFilter', key: '   '}),
        (
          '$key ארוך מדי',
          {
            'mode': 'providerBooksFilter',
            key: 'א' * (PluginSearchFieldAction.maxFilterLabelLength + 1),
          },
        ),
        ('$key לא מחרוזת', {'mode': 'providerBooksFilter', key: 7}),
        (
          '$key עם תו בקרה',
          {'mode': 'providerBooksFilter', key: 'רק\nבר אילן'},
        ),
      ],
    ]) {
      test('נדחה: $name', () {
        expect(
          () => PluginSearchFieldAction.fromPayload({
            'id': 'a',
            'title': 'א',
            ...payload,
          }),
          throwsA(isA<PluginSearchFieldActionException>()),
        );
      });
    }
  });

  test('searchFieldActions במניפסט מעיר את מנוע הרקע ונשמר בהמרה', () {
    final startup = PluginStartupContributions.fromJson({
      'searchFieldActions': [
        {'id': 'dictate', 'title': 'דיבור'},
      ],
    });
    expect(startup.isEmpty, isFalse);
    expect(startup.hasInitialActivationTrigger, isTrue);
    expect(
      PluginStartupContributions.fromJson(
        startup.toJson(),
      ).searchFieldActions.single['id'],
      'dictate',
    );
  });

  group('PluginSearchFieldActionsRegistry', () {
    test('מסנן לפי שדה, מגביל 2 לתוסף ו-3 לשדה', () {
      final registry = PluginSearchFieldActionsRegistry.forTesting();
      registry.registerPayload('p1', {
        'id': 'a',
        'title': 'א',
        'fields': ['library'],
      });
      registry.registerPayload('p1', {'id': 'b', 'title': 'ב'});
      expect(
        () => registry.registerPayload('p1', {'id': 'c', 'title': 'ג'}),
        throwsA(isA<PluginSearchFieldActionException>()),
      );
      registry.registerPayload('p2', {'id': 'a', 'title': 'א'});
      registry.registerPayload('p3', {'id': 'a', 'title': 'א'});

      expect(registry.actionsFor(PluginSearchField.library), hasLength(3));
      expect(
        registry
            .actionsFor(PluginSearchField.inBook)
            .map((e) => '${e.$1}/${e.$2.id}'),
        ['p1/b', 'p2/a', 'p3/a'],
      );

      registry.removeAll('p1');
      expect(registry.find('p1', 'a'), isNull);
      expect(registry.hasActionsFor(PluginSearchField.findRef), isTrue);
    });
  });
}
