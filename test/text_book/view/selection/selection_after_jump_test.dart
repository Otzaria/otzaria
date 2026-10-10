import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const _title = 'ספר בדיקה';

final _content = <String>[
  for (var i = 0; i < 80; i++) 'פסקה$i ${List.filled(6, 'מילה$i').join(' ')}',
];

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<TextBookTab> pumpView(WidgetTester tester, {Widget? sibling}) async {
    tester.view.physicalSize = const Size(700, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = TextBookLoaded(
      book: TextBook(title: _title),
      showLeftPane: false,
      content: _content,
      fontSize: 18,
      showSplitView: false,
      showPageShapeView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [0],
      selectedIndex: null,
      pinLeftPane: false,
      searchText: '',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    );
    final textBookBloc = _TestTextBookBloc(state);
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: TextBook(title: _title), index: 0);
    addTearDown(textBookBloc.close);
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: CombinedView(
                    data: _content,
                    openBookCallback: (_) {},
                    openLeftPaneTab: (_, {searchText}) {},
                    textSize: 18,
                    showCommentaryAsExpansionTiles: false,
                    tab: tab,
                  ),
                ),
                ?sibling,
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    return tab;
  }

  Rect lineRect(WidgetTester tester, int lineIndex) =>
      tester.getRect(find.byKey(ValueKey('html_${_title}_$lineIndex')));

  /// ה-registrar של ה-Scrollable — הילדים שלו הם פריטי הרשימה, בסדר שבו
  /// אזור הבחירה סורק אותם.
  MultiSelectableSelectionContainerDelegate scrollableRegistrar(
    WidgetTester tester,
  ) {
    final ctx = tester.element(find.byType(SliverList).first);
    return SelectionContainer.maybeOf(ctx)!
        as MultiSelectableSelectionContainerDelegate;
  }

  String selectedText(WidgetTester tester) => scrollableRegistrar(
    tester,
  ).selectables.map((s) => s.getSelectedContent()?.plainText ?? '').join();

  Future<void> selectWord(WidgetTester tester) async {
    final line = lineRect(tester, 8);
    final word = Offset(line.right - 20, line.center.dy);
    await tester.tapAt(word, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(word, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(selectedText(tester), 'מילה8');
  }

  // קפיצה של הרשימה מאפסת את היסט הגלילה; הבחירה אסור שתנחת על טקסט אחר
  // באותו גובה על המסך (issue #1589).
  Future<void> selectThenMove(
    WidgetTester tester, {
    required double scrolledBy,
    required Future<void> Function(TextBookTab tab) move,
    required Object expected,
  }) async {
    final tab = await pumpView(tester);
    if (scrolledBy > 0) {
      unawaited(
        tab.mainOffsetController.animateScroll(
          offset: scrolledBy,
          duration: const Duration(milliseconds: 100),
        ),
      );
      await tester.pumpAndSettle();
    }
    await selectWord(tester);

    await move(tab);
    await tester.pumpAndSettle();

    expect(selectedText(tester), expected);
  }

  testWidgets('בחירת מקלדת אינה משאירה שורות במטמון', (tester) async {
    await pumpView(tester);
    final dynamic state = tester.state(find.byType(CombinedView));
    final region = tester.state<SelectableRegionState>(
      find.descendant(
        of: find.byType(SelectionArea),
        matching: find.byType(SelectableRegion),
      ),
    );
    region.selectAll();
    await tester.pump();
    expect(selectedText(tester), isNotEmpty);
    expect(state.debugSelectionCachedLineCount, 0);
    region.clearSelection();
    await tester.pump();
    expect(selectedText(tester), isEmpty);
    expect(state.debugSelectionCachedLineCount, 0);
  });

  for (final cancel in [false, true]) {
    testWidgets('מטמון גרירה מתנקה בשחרור סמן, cancel=$cancel', (tester) async {
      await pumpView(tester);
      final dynamic state = tester.state(find.byType(CombinedView));
      final line = lineRect(tester, 8);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(Offset(line.right - 20, line.center.dy));
      await gesture.moveBy(const Offset(-70, 0));
      await tester.pump();
      expect(selectedText(tester), isNotEmpty);
      expect(state.debugSelectionCachedLineCount, greaterThan(0));
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();
      expect(state.debugSelectionCachedLineCount, 0);
    });
  }

  for (final scrolledBy in [0.0, 150.0]) {
    testWidgets('jumpTo אחרי גלילה של $scrolledBy', (tester) async {
      await selectThenMove(
        tester,
        scrolledBy: scrolledBy,
        move: (tab) async => tab.scrollController.jumpTo(index: 50),
        expected: isEmpty,
      );
    });
    testWidgets('scrollTo אחרי גלילה של $scrolledBy', (tester) async {
      await selectThenMove(
        tester,
        scrolledBy: scrolledBy,
        move: (tab) async => unawaited(
          tab.scrollController.scrollTo(
            index: 50,
            duration: const Duration(milliseconds: 300),
          ),
        ),
        expected: isEmpty,
      );
    });
  }

  // מעבר למסך שלם ומנוחה מפעילים עיגון מחדש; בחזרה הבחירה על אותה מילה.
  testWidgets('גלילה של יותר ממסך וחזרה שומרת את הבחירה', (tester) async {
    Future<void> scrollBy(TextBookTab tab, double offset) async {
      unawaited(
        tab.mainOffsetController.animateScroll(
          offset: offset,
          duration: const Duration(milliseconds: 100),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay * 2);
    }

    await selectThenMove(
      tester,
      scrolledBy: 150,
      move: (tab) async {
        await scrollBy(tab, 520);
        await scrollBy(tab, -520);
      },
      expected: 'מילה8',
    );
  });

  // ב-Windows החלון מאבד פוקוס בעוד שה-lifecycle עדיין resumed (issue #1585).
  testWidgets('מעבר לחלון אחר שומר את הבחירה', (tester) async {
    final otherFocus = FocusNode();
    addTearDown(otherFocus.dispose);
    await pumpView(
      tester,
      sibling: Focus(focusNode: otherFocus, child: const SizedBox.shrink()),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await selectWord(tester);

    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.unfocused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    await tester.pumpAndSettle();
    expect(selectedText(tester), 'מילה8');

    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    await tester.pumpAndSettle();
    expect(selectedText(tester), 'מילה8');

    otherFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(selectedText(tester), isEmpty);
  });

  testWidgets('מעבר פוקוס לרכיב אחר באפליקציה מנקה את הבחירה', (tester) async {
    final otherFocus = FocusNode();
    addTearDown(otherFocus.dispose);
    await pumpView(
      tester,
      sibling: Focus(focusNode: otherFocus, child: const SizedBox.shrink()),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await selectWord(tester);

    otherFocus.requestFocus();
    await tester.pumpAndSettle();

    expect(selectedText(tester), isEmpty);
  });
}
