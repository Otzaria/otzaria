import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/book_common/view/commentary_search_pane.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/commentary/commentary_search_results_list.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';

class _ListenedValue<T> extends ValueNotifier<T> {
  _ListenedValue(super.value);

  bool get isListening => hasListeners;
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  testWidgets('counts the results and moves between them', (tester) async {
    final controller = TextEditingController(text: 'שלום');
    final focusNode = FocusNode();
    final total = ValueNotifier(3);
    final current = ValueNotifier(0);
    final snippets = ValueNotifier<List<CommentarySearchSnippet>>(const []);
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
      total.dispose();
      current.dispose();
      snippets.dispose();
    });
    var previous = 0;
    var next = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentarySearchPane(
            controller: controller,
            focusNode: focusNode,
            hintText: 'חיפוש במפרשים...',
            totalResults: total,
            currentResult: current,
            snippets: snippets,
            onPrevious: () => previous++,
            onNext: () => next++,
            onSnippetTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('תוצאה 1 מתוך 3'), findsOneWidget);

    current.value = 1;
    await tester.pump();
    expect(find.text('תוצאה 2 מתוך 3'), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.chevron_up_24_regular));
    await tester.tap(find.byIcon(FluentIcons.chevron_down_24_regular));
    expect(previous, 1);
    expect(next, 1);

    total.value = 0;
    await tester.pump();
    expect(find.textContaining('מתוך'), findsNothing);
  });

  testWidgets(
    'refreshes snippets without rebuilding the focused search field',
    (
      tester,
    ) async {
      final settings = _SettingsBloc();
      final controller = TextEditingController(text: 'שלום');
      final focusNode = FocusNode();
      final total = ValueNotifier(8);
      final current = ValueNotifier(0);
      final snippets = ValueNotifier<List<CommentarySearchSnippet>>(const [
        CommentarySearchSnippet(
          path: 'רשי.txt',
          snippet: 'שלום עולם',
          globalIndex: 0,
        ),
      ]);
      addTearDown(() async {
        controller.dispose();
        focusNode.dispose();
        total.dispose();
        current.dispose();
        snippets.dispose();
        await settings.close();
      });
      int? tapped;
      await tester.pumpWidget(
        BlocProvider<SettingsBloc>.value(
          value: settings,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: CommentarySearchPane(
                  controller: controller,
                  focusNode: focusNode,
                  hintText: 'חיפוש במפרשים...',
                  totalResults: total,
                  currentResult: current,
                  snippets: snippets,
                  onPrevious: () {},
                  onNext: () {},
                  onSnippetTap: (index) => tapped = index,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      focusNode.requestFocus();
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      await tester.pump();
      final fieldState = tester.state(find.byType(EditableText));
      final pane = tester.widget<SearchPaneBase>(find.byType(SearchPaneBase));

      snippets.value = const [
        CommentarySearchSnippet(
          path: 'רשי.txt',
          snippet: 'שלום חדש',
          globalIndex: 7,
        ),
      ];
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      );
      expect(tester.state(find.byType(EditableText)), same(fieldState));
      expect(
        tester.widget<SearchPaneBase>(find.byType(SearchPaneBase)),
        same(pane),
      );
      expect(find.text('שלום חדש', findRichText: true), findsOneWidget);
      await tester.tap(find.byType(NavTreeContentRow));
      expect(tapped, 7);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !engineReady,
  );

  testWidgets('replaces all search sources and detaches their old listeners', (
    tester,
  ) async {
    final controllers = [
      TextEditingController(text: 'ישן'),
      TextEditingController(text: 'חדש'),
    ];
    final focusNodes = [FocusNode(), FocusNode()];
    final totals = [_ListenedValue(2), _ListenedValue(4)];
    final currents = [_ListenedValue(0), _ListenedValue(2)];
    final snippets = [
      _ListenedValue<List<CommentarySearchSnippet>>(const []),
      _ListenedValue<List<CommentarySearchSnippet>>(const []),
    ];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
      for (final focus in focusNodes) {
        focus.dispose();
      }
      for (final source in [...totals, ...currents, ...snippets]) {
        source.dispose();
      }
    });
    final calls = <int>[];
    Widget wrap(int index) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: CommentarySearchPane(
            controller: controllers[index],
            focusNode: focusNodes[index],
            hintText: 'חיפוש במפרשים...',
            totalResults: totals[index],
            currentResult: currents[index],
            snippets: snippets[index],
            onPrevious: () => calls.add(index),
            onNext: () => calls.add(index),
            onSnippetTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(wrap(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(wrap(1));
    await tester.pumpAndSettle();

    for (final source in [totals[0], currents[0], snippets[0]]) {
      expect(source.isListening, isFalse);
    }
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller,
      same(controllers[1]),
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode,
      same(focusNodes[1]),
    );
    expect(find.text('תוצאה 3 מתוך 4'), findsOneWidget);
    controllers[0].text = 'לא אמור לעדכן';
    totals[0].value = 99;
    currents[0].value = 90;
    await tester.pump();
    expect(find.text('תוצאה 3 מתוך 4'), findsOneWidget);
    await tester.tap(find.byIcon(FluentIcons.chevron_up_24_regular));
    await tester.tap(find.byIcon(FluentIcons.chevron_down_24_regular));
    expect(calls, [1, 1]);

    totals[1].value = 5;
    currents[1].value = 3;
    await tester.pump();
    expect(find.text('תוצאה 4 מתוך 5'), findsOneWidget);
    expect(
      tester
          .widget<CommentarySearchResultsList>(
            find.byType(CommentarySearchResultsList),
          )
          .query,
      'חדש',
    );
    controllers[1].clear();
    await tester.pump();
    expect(find.textContaining('מתוך'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final source in [totals[1], currents[1], snippets[1]]) {
      expect(source.isListening, isFalse);
    }
    expect(tester.takeException(), isNull);
  });
}
