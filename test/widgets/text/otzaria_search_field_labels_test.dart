import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_library_books_filter.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

const _pluginId = 'labels-test';
const _filterKey = ValueKey('plugin-search-field-action:$_pluginId:source');
const _wholeWordKey = ValueKey('whole-word');

class _EmptyRepository implements PluginRegistryRepository {
  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// תווית הסינון של תוסף לא דוחקת את שאר הכפתורים בשדה ולא מצמצמת את תיבת
/// הקלט (q9 שאלה 14): כשאין לה מקום הכפתור הוא אייקון ו-tooltip.
void main() {
  late PluginLibraryBooksRegistry books;
  late PluginLibraryBooksRegistry previousBooks;

  setUp(() {
    PluginSearchFieldActionsRegistry.instance.registerPayload(_pluginId, {
      'id': 'source',
      'title': 'מקור הספרים',
      'mode': 'providerBooksFilter',
      'pluginOnlyLabel': 'רק בר אילן',
    });
    previousBooks = PluginLibraryBooksRegistry.instance;
    books = PluginLibraryBooksRegistry.forTesting(
      conditions: PluginConditionEvaluator.forTesting(
        settingReader: (_) => null,
      ),
      repository: _EmptyRepository(),
    );
    books.registerPayload(_pluginId, {
      'id': 'books',
      'provider': 'mylib',
      'title': 'הספרייה שלי',
    });
    PluginLibraryBooksRegistry.instance = books;
  });

  tearDown(() {
    PluginSearchFieldActionsRegistry.instance.removeAll(_pluginId);
    PluginLibraryBooksRegistry.instance = previousBooks;
    books.dispose();
  });

  Future<void> pumpIn(WidgetTester tester, double width, Widget field) =>
      tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(width: width, child: field),
              ),
            ),
          ),
        ),
      );

  double inputWidth(WidgetTester tester) =>
      tester.getSize(find.byType(EditableText)).width;

  /// הכפתור גלוי, בתוך גבולות השדה, ומקבל לחיצה.
  void expectShownInField(WidgetTester tester, Finder button) {
    expect(button.hitTestable(), findsOneWidget);
    final field = tester.getRect(find.byType(OtzariaSearchField));
    final rect = tester.getRect(button);
    expect(field.left <= rect.left && rect.right <= field.right, isTrue);
  }

  group('חלונית הניווט (SearchPaneBase) ברוחב 340', () {
    late TextEditingController controller;
    late FocusNode focusNode;

    setUp(() {
      controller = TextEditingController(text: 'שבת');
      focusNode = FocusNode();
    });

    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    Widget pane() => SearchPaneBase(
      searchController: controller,
      focusNode: focusNode,
      resultsWidget: const SizedBox.shrink(),
      isNoResults: false,
      resetSearchCallback: () {},
      onAdvancedSearch: () {},
      searchFieldActions: [
        OtzariaSearchFieldButton(
          key: _wholeWordKey,
          icon: Icons.abc,
          tooltip: 'מילה שלמה',
          onPressed: () {},
        ),
      ],
      searchFieldExtraActions: const PluginSearchFieldExtraActions(
        PluginSearchField.library,
      ),
    );

    testWidgets(
      'סינון פעיל בשורת הפעולות: התווית גלויה בלי לצמצם את הקלט',
      (tester) async {
        await pumpIn(tester, 340, pane());
        await tester.pump();
        final widthAll = inputWidth(tester);
        expect(widthAll, greaterThanOrEqualTo(120));

        books.cycleSource(_pluginId);
        await tester.pump();
        expect(
          books.sourceFilter.value.source,
          PluginLibraryBooksSource.pluginOnly,
        );
        expect(find.text('רק בר אילן'), findsOneWidget);
        expect(
          find.byTooltip('מקור הספרים: מציג רק ספרי התוסף'),
          findsOneWidget,
        );
        expect(inputWidth(tester), widthAll);
        final input = tester.getRect(find.byType(EditableText));
        for (final button in [
          find.byKey(_filterKey),
          find.byKey(_wholeWordKey),
          find.byTooltip('הגדרות חיפוש'),
        ]) {
          expect(tester.getRect(button).top, greaterThan(input.bottom));
        }
        expect(
          tester.getRect(find.byTooltip('נקה')).center.dy,
          inInclusiveRange(input.top, input.bottom),
        );
        for (final button in [
          find.byKey(_filterKey),
          find.byKey(_wholeWordKey),
          find.byTooltip('הגדרות חיפוש'),
          find.byTooltip('נקה'),
        ]) {
          expectShownInField(tester, button);
        }
      },
    );
  });

  group('שדה איתור הספרים', () {
    late TextEditingController controller;

    setUp(() => controller = TextEditingController(text: 'שולחן ערוך'));
    tearDown(() => controller.dispose());

    Widget field() => OtzariaSearchField(
      controller: controller,
      hintText: 'איתור ספר',
      slim: false,
      onClear: () {},
      extraActions: const PluginSearchFieldExtraActions(
        PluginSearchField.library,
      ),
    );

    testWidgets('ברוחב 400 התווית מוצגת, והקלט נשאר שמיש', (tester) async {
      await pumpIn(tester, 400, field());
      books.cycleSource(_pluginId);
      await tester.pump();
      expect(find.text('רק בר אילן'), findsOneWidget);
      expect(inputWidth(tester), greaterThanOrEqualTo(120));
      expectShownInField(tester, find.byKey(_filterKey));
      expectShownInField(tester, find.byTooltip('נקה'));
    });

    testWidgets('בשדה צר התווית יורדת, והקלט לא מצטמצם', (tester) async {
      await pumpIn(tester, 300, field());
      await tester.pump();
      final widthAll = inputWidth(tester);

      books.cycleSource(_pluginId);
      await tester.pump();
      expect(find.text('רק בר אילן'), findsNothing);
      expect(inputWidth(tester), widthAll);
      expect(inputWidth(tester), greaterThanOrEqualTo(120));
      expectShownInField(tester, find.byKey(_filterKey));
      expectShownInField(tester, find.byTooltip('נקה'));
    });
  });
}
