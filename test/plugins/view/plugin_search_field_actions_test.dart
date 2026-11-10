import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_library_books_filter.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

const _buttonKey = ValueKey('plugin-search-field-action:voice:dictate');
const _filterKey = ValueKey('plugin-search-field-action:voice:source');

class _EmptyRepository implements PluginRegistryRepository {
  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _KvRepository extends _EmptyRepository {
  final Map<String, String> values = {};

  @override
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async => {
    for (final key in keys)
      if (values.containsKey(key)) key: values[key]!,
  };
}

void main() {
  group('OtzariaSearchField', () {
    tearDown(
      () => PluginSearchFieldActionsRegistry.instance.removeAll('voice'),
    );

    Future<TextEditingController> pumpField(
      WidgetTester tester, {
      PluginSearchField? field,
      String text = '',
    }) async {
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtzariaSearchField(
              controller: controller,
              hintText: 'חיפוש',
              extraActions: field == null
                  ? null
                  : PluginSearchFieldExtraActions(field),
              autofocus: true,
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('מציג כפתור תוסף רק בשדה שהוצהר', (tester) async {
      await pumpField(tester, field: PluginSearchField.library);
      expect(find.byKey(_buttonKey), findsNothing);

      PluginSearchFieldActionsRegistry.instance.registerPayload('voice', {
        'id': 'dictate',
        'title': 'חיפוש בדיבור',
        'icon': 'mic_24_regular',
        'fields': ['library'],
      });
      await tester.pump();
      expect(find.byKey(_buttonKey), findsOneWidget);
      expect(find.byTooltip('חיפוש בדיבור'), findsOneWidget);

      await pumpField(tester, field: PluginSearchField.inBook);
      expect(find.byKey(_buttonKey), findsNothing);
      await pumpField(tester);
      expect(find.byKey(_buttonKey), findsNothing);
    });

    testWidgets(
      'הכתבה אחרי לחיצת עכבר מחליפה את הטקסט המסומן (issue #3878)',
      (tester) async {
        PluginSearchFieldActionsRegistry.instance.registerPayload('voice', {
          'id': 'dictate',
          'title': 'חיפוש בדיבור',
          'icon': 'mic_24_regular',
        });
        final sessions = PluginSearchFieldSessionService.instance;
        for (final field in [
          PluginSearchField.library,
          PluginSearchField.inBook,
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());
          final controller = await pumpField(
            tester,
            field: field,
            text: 'ברכות דף ב',
          );
          await tester.pump();
          controller.selection = const TextSelection(
            baseOffset: 0,
            extentOffset: 10,
          );

          // לחיצת עכבר אמיתית ארוכה מ-kPressTimeout, ואז השדה כבר מגיב ל-tap down.
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(_buttonKey)),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump(kPressTimeout * 2);
          await gesture.up();
          await tester.pump();

          final binding =
              tester.state(find.byType(PluginSearchFieldActions))
                  as PluginSearchFieldBinding;
          final session = sessions.sessionFor(binding, 'voice', 'dictate')!;
          sessions.setFieldText('voice', session.id, 'שבת דף ג');
          expect(controller.text, 'שבת דף ג', reason: field.name);
        }
      },
      variant: TargetPlatformVariant.all(),
    );
  });

  group('PluginSearchFieldActions', () {
    late PluginSearchFieldActionsRegistry registry;
    late PluginSearchFieldSessionService sessions;
    late List<(String topic, Map<String, dynamic> payload)> sent;

    setUp(() {
      sent = [];
      registry = PluginSearchFieldActionsRegistry.forTesting()
        ..registerPayload('voice', {
          'id': 'dictate',
          'title': 'חיפוש בדיבור',
          'icon': 'mic_24_regular',
          'activeIcon': 'mic_24_filled',
        });
      sessions = PluginSearchFieldSessionService.forTesting((
        pluginId,
        topic,
        payload, {
        preferBackground = false,
        instanceId,
        viewId,
        windowKeys,
      }) async {
        sent.add((topic, payload));
      });
    });

    testWidgets(
      'לחיצה → טקסט מהתוסף נכתב ומדווח כהקלדה → עריכה סוגרת → סגירת השדה',
      (tester) async {
        final controller = TextEditingController(text: 'ברכות');
        addTearDown(controller.dispose);
        final changes = <String>[];
        final submits = <String>[];
        final show = ValueNotifier(true);
        addTearDown(show.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: show,
                builder: (context, visible, _) => visible
                    ? PluginSearchFieldActions(
                        field: PluginSearchField.findRef,
                        controller: controller,
                        onChanged: changes.add,
                        onSubmitted: submits.add,
                        registry: registry,
                        sessions: sessions,
                      )
                    : const SizedBox(),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(_buttonKey));
        await tester.pump();
        expect(sent.single.$1, 'search.fieldAction.invoked');
        expect(sent.single.$2['field'], 'findRef');
        final id = sent.single.$2['sessionId'] as String;

        sessions.setActionState('voice', id, 'active', tooltip: 'מקשיב');
        await tester.pump();
        expect(find.byTooltip('מקשיב'), findsOneWidget);

        sessions.setFieldText('voice', id, 'דף ב');
        expect(controller.text, 'ברכות דף ב');
        expect(changes, ['ברכות דף ב']);

        controller.text = 'ברכות דף ג';
        await tester.pump();
        expect(sent.last.$2['reason'], 'edited');
        expect(find.byTooltip('חיפוש בדיבור'), findsOneWidget);

        await tester.tap(find.byKey(_buttonKey));
        await tester.pump();
        final id2 = sent.last.$2['sessionId'] as String;
        sessions.endSession('voice', id2, submit: true);
        expect(submits, ['ברכות דף ג']);

        await tester.tap(find.byKey(_buttonKey));
        await tester.pump();
        show.value = false;
        await tester.pump();
        expect(sent.last.$1, 'search.fieldAction.ended');
        expect(sent.last.$2['reason'], 'closed');
      },
    );

    Future<void> pumpActions(
      WidgetTester tester,
      TextEditingController controller, {
      PluginSearchField field = PluginSearchField.fullText,
      Map<String, dynamic> Function()? invocationContext,
      PluginLibraryBooksRegistry? libraryBooks,
      PluginConditionEvaluator? conditions,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginSearchFieldActions(
            field: field,
            controller: controller,
            invocationContext: invocationContext,
            registry: registry,
            sessions: sessions,
            libraryBooks: libraryBooks,
            conditions: conditions,
          ),
        ),
      ),
    );

    testWidgets('כפתור עם visibleWhen: nonEmptyText מופיע רק כשיש טקסט', (
      tester,
    ) async {
      registry.registerPayload('voice', {
        'id': 'dictate',
        'title': 'חיפוש בדיבור',
        'icon': 'mic_24_regular',
        'visibleWhen': 'nonEmptyText',
      });
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpActions(tester, controller);
      expect(find.byKey(_buttonKey), findsNothing);

      controller.text = 'ברכות';
      await tester.pump();
      expect(find.byKey(_buttonKey), findsOneWidget);

      controller.clear();
      await tester.pump();
      expect(find.byKey(_buttonKey), findsNothing);
    });

    group('when', () {
      const storageWhen = {
        'storage': {'key': 'showDictate', 'equals': true},
      };

      testWidgets('ערך אחסון: הכפתור מופיע ונעלם מיד כשהערך משתנה', (
        tester,
      ) async {
        final repository = _KvRepository();
        final conditions = PluginConditionEvaluator.forTesting();
        addTearDown(conditions.dispose);
        await conditions.registerStorageKeys('voice', {
          'showDictate',
        }, repository);
        registry.registerPayload('voice', {
          'id': 'dictate',
          'title': 'חיפוש בדיבור',
          'icon': 'mic_24_regular',
          'when': storageWhen,
        });
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpActions(tester, controller, conditions: conditions);
        expect(find.byKey(_buttonKey), findsNothing);

        conditions.onStorageValueChanged('voice', 'showDictate', true);
        await tester.pump();
        expect(find.byKey(_buttonKey), findsOneWidget);

        conditions.onStorageValueChanged('voice', 'showDictate', false);
        await tester.pump();
        expect(find.byKey(_buttonKey), findsNothing);

        conditions.onStorageRemoved('voice', 'showDictate');
        conditions.onStorageValueChanged('voice', 'showDictate', true);
        await tester.pump();
        expect(find.byKey(_buttonKey), findsOneWidget);
      });

      testWidgets('הגדרת תוכנה: ההחלפה מורגשת בלי מנוע התוסף', (tester) async {
        Object? darkMode = false;
        final conditions = PluginConditionEvaluator.forTesting(
          settingReader: (_) => darkMode,
        );
        addTearDown(conditions.dispose);
        registry.registerPayload('voice', {
          'id': 'dictate',
          'title': 'חיפוש בדיבור',
          'when': {
            'setting': {'key': 'key-dark-mode', 'equals': true},
          },
        });
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpActions(tester, controller, conditions: conditions);
        expect(find.byKey(_buttonKey), findsNothing);

        darkMode = true;
        conditions.notifySettingsChanged();
        await tester.pump();
        expect(find.byKey(_buttonKey), findsOneWidget);
        expect(sent, isEmpty);
      });

      testWidgets('מצטרף ל-visibleWhen: שני התנאים חייבים להתקיים', (
        tester,
      ) async {
        final conditions = PluginConditionEvaluator.forTesting();
        addTearDown(conditions.dispose);
        await conditions.registerStorageKeys('voice', {
          'showDictate',
        }, _KvRepository());
        registry.registerPayload('voice', {
          'id': 'dictate',
          'title': 'חיפוש בדיבור',
          'visibleWhen': 'nonEmptyText',
          'when': storageWhen,
        });
        final controller = TextEditingController(text: 'ברכות');
        addTearDown(controller.dispose);
        await pumpActions(tester, controller, conditions: conditions);
        expect(find.byKey(_buttonKey), findsNothing);

        conditions.onStorageValueChanged('voice', 'showDictate', true);
        await tester.pump();
        expect(find.byKey(_buttonKey), findsOneWidget);

        controller.clear();
        await tester.pump();
        expect(find.byKey(_buttonKey), findsNothing);
      });

      testWidgets('כפתור סינון ספרי תוסף מכבד when', (tester) async {
        final conditions = PluginConditionEvaluator.forTesting();
        addTearDown(conditions.dispose);
        await conditions.registerStorageKeys('voice', {
          'showDictate',
        }, _KvRepository());
        registry.removeAll('voice');
        registry.registerPayload('voice', {
          'id': 'source',
          'title': 'מקור הספרים',
          'mode': 'providerBooksFilter',
          'when': storageWhen,
        });
        final books = PluginLibraryBooksRegistry.forTesting(
          conditions: conditions,
          repository: _EmptyRepository(),
        );
        addTearDown(books.dispose);
        books.registerPayload('voice', {
          'id': 'books',
          'provider': 'mylib',
          'title': 'הספרייה שלי',
        });
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpActions(
          tester,
          controller,
          field: PluginSearchField.library,
          libraryBooks: books,
          conditions: conditions,
        );
        expect(find.byKey(_filterKey), findsNothing);

        conditions.onStorageValueChanged('voice', 'showDictate', true);
        await tester.pump();
        expect(find.byKey(_filterKey), findsOneWidget);
      });

      testWidgets('כפתור בלי when לא מאזין להגדרות ולאחסון', (tester) async {
        final conditions = PluginConditionEvaluator.forTesting();
        addTearDown(conditions.dispose);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpActions(tester, controller, conditions: conditions);
        expect(find.byKey(_buttonKey), findsOneWidget);

        conditions.notifySettingsChanged();
        await tester.pump();
        expect(find.byKey(_buttonKey), findsOneWidget);
      });
    });

    testWidgets('ההקשר של השדה מצורף לאירוע, ובחירות רק של התוסף הקורא', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'ברכות');
      addTearDown(controller.dispose);
      await pumpActions(
        tester,
        controller,
        invocationContext: () => {
          PluginSearchFieldContext.requestKey: {'query': 'ברכות'},
          PluginSearchFieldContext.categoryPathKey: 'שו"ת, אחרונים',
          PluginSearchFieldContext.pluginSelectionsKey: {
            'voice/exact': true,
            'other/exact': false,
          },
        },
      );

      await tester.tap(find.byKey(_buttonKey));
      await tester.pump();

      final payload = sent.single.$2;
      expect(payload['request'], {'query': 'ברכות'});
      expect(payload['categoryPath'], 'שו"ת, אחרונים');
      expect(payload['pluginSelections'], {'exact': true});
    });

    group('providerBooksFilter', () {
      late PluginLibraryBooksRegistry books;

      setUp(() {
        registry.removeAll('voice');
        registry.registerPayload('voice', {
          'id': 'source',
          'title': 'מקור הספרים',
          'icon': 'library_24_regular',
          'activeIcon': 'library_24_filled',
          'libraryOnlyIcon': 'book_24_regular',
          'mode': 'providerBooksFilter',
        });
        books = PluginLibraryBooksRegistry.forTesting(
          conditions: PluginConditionEvaluator.forTesting(
            settingReader: (_) => null,
          ),
          repository: _EmptyRepository(),
        );
        addTearDown(books.dispose);
      });

      void registerProvider() => books.registerPayload('voice', {
        'id': 'books',
        'provider': 'mylib',
        'title': 'הספרייה שלי',
      });

      IconData shownIcon(WidgetTester tester) => tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(_filterKey),
              matching: find.byType(Icon),
            ),
          )
          .icon!;

      testWidgets('לחיצה מחליפה מקור, אייקון וטולטיפ במחזור', (tester) async {
        registerProvider();
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpActions(
          tester,
          controller,
          field: PluginSearchField.library,
          libraryBooks: books,
        );
        expect(shownIcon(tester), pluginIconFromName('library_24_regular'));
        expect(find.byTooltip('מקור הספרים: מציג את כולם'), findsOneWidget);

        await tester.tap(find.byKey(_filterKey));
        await tester.pump();
        expect(
          books.sourceFilter.value.source,
          PluginLibraryBooksSource.pluginOnly,
        );
        expect(shownIcon(tester), pluginIconFromName('library_24_filled'));
        expect(
          find.byTooltip('מקור הספרים: מציג רק ספרי התוסף'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(_filterKey));
        await tester.pump();
        expect(shownIcon(tester), pluginIconFromName('book_24_regular'));
        expect(
          find.byTooltip('מקור הספרים: מציג רק ספרי הספרייה'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(_filterKey));
        await tester.pump();
        expect(books.sourceFilter.value, PluginLibraryBooksFilter.all);
        expect(sent, isEmpty, reason: 'הכפתור אינו פותח סשן');
      });

      testWidgets('במצבי הסינון תווית: ברירת המחדל "רק התוסף" / "רק הספרייה"', (
        tester,
      ) async {
        registerProvider();
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpActions(
          tester,
          controller,
          field: PluginSearchField.library,
          libraryBooks: books,
        );
        expect(find.text('רק התוסף'), findsNothing, reason: 'במצב "הכל" אין');
        expect(find.text('רק הספרייה'), findsNothing);

        await tester.tap(find.byKey(_filterKey));
        await tester.pump();
        expect(find.text('רק התוסף'), findsOneWidget);
        expect(
          find.byTooltip('מקור הספרים: מציג רק ספרי התוסף'),
          findsOneWidget,
          reason: 'ה-tooltip נשאר',
        );

        await tester.tap(find.byKey(_filterKey));
        await tester.pump();
        expect(find.text('רק התוסף'), findsNothing);
        expect(find.text('רק הספרייה'), findsOneWidget);

        await tester.tap(find.byKey(_filterKey));
        await tester.pump();
        expect(find.text('רק הספרייה'), findsNothing);
      });

      testWidgets('התוסף קובע את שתי התוויות', (tester) async {
        registry.removeAll('voice');
        registry.registerPayload('voice', {
          'id': 'source',
          'title': 'מקור הספרים',
          'mode': 'providerBooksFilter',
          'pluginOnlyLabel': 'רק בר אילן',
          'libraryOnlyLabel': 'רק אוצריא',
        });
        registerProvider();
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpActions(
          tester,
          controller,
          field: PluginSearchField.library,
          libraryBooks: books,
        );

        await tester.tap(find.byKey(_filterKey));
        await tester.pump();
        expect(find.text('רק בר אילן'), findsOneWidget);
        expect(find.text('רק התוסף'), findsNothing);

        await tester.tap(find.byKey(_filterKey));
        await tester.pump();
        expect(find.text('רק אוצריא'), findsOneWidget);
        expect(find.text('רק הספרייה'), findsNothing);
      });

      testWidgets('בלי ספק רשום לתוסף הכפתור מוסתר', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpActions(
          tester,
          controller,
          field: PluginSearchField.library,
          libraryBooks: books,
        );
        expect(find.byKey(_filterKey), findsNothing);

        registerProvider();
        await tester.pump();
        expect(find.byKey(_filterKey), findsOneWidget);
      });
    });

    testWidgets('בלי כפתורים לשדה — לא תופס מקום', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      registry.removeAll('voice');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PluginSearchFieldActions(
                field: PluginSearchField.fullText,
                controller: controller,
                registry: registry,
                sessions: sessions,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(PluginSearchFieldActions)),
        Size.zero,
      );
    });
  });
}
