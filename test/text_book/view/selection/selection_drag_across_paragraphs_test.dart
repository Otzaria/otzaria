import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _title = 'ספר בדיקה';

final _content = List<String>.generate(
  10,
  (i) => '($i) ${List.filled(12, 'מילים בפסקה').join(' ')}:',
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitForTest(TextBookState state) => emit(state);

  @override
  final TextBookRepository repository = _TestTextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTextBookRepository implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<TextBookTab> pumpView(
    WidgetTester tester, {
    Size size = const Size(700, 600),
    int anchor = 0,
  }) async {
    tester.view.physicalSize = size;
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
      visibleIndices: [anchor],
      selectedIndex: null,
      pinLeftPane: false,
      searchText: '',
    );
    final textBookBloc = _TestTextBookBloc(state);
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(
      book: TextBook(title: _title),
      index: anchor,
    );
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
            body: CombinedView(
              data: _content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: false,
              tab: tab,
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

  String selected(WidgetTester tester) {
    final ctx = tester.element(find.byType(SuperSliverList).first);
    final registrar =
        SelectionContainer.maybeOf(ctx)!
            as MultiSelectableSelectionContainerDelegate;
    return registrar.selectables
        .map((s) => s.getSelectedContent()?.plainText ?? '')
        .join();
  }

  // הפסקאות שמעל שורת הפתיחה יושבות ב-sliver ההפוך; גלילה למעלה מעבירה את
  // הגרירה גם דרך הגבול בין שני ה-slivers.
  for (final scrollBy in [0.0, -300.0]) {
    testWidgets(
      'גרירה על פני ארבע פסקאות שומרת את כל הבחירה, גלילה $scrollBy (issue #3771)',
      (tester) async {
        final tab = await pumpView(tester, anchor: scrollBy == 0 ? 0 : 4);
        if (scrollBy != 0) {
          unawaited(
            tab.lines.offsetController.animateScroll(
              offset: scrollBy,
              duration: const Duration(milliseconds: 100),
            ),
          );
          await tester.pumpAndSettle();
        }
        final firstLine =
            [
              for (var i = 0; i < _content.length; i++) i,
            ].firstWhere((i) {
              final text = find.byKey(ValueKey('html_${_title}_$i'));
              return text.evaluate().isNotEmpty &&
                  tester.getRect(text).top >= 0;
            });
        final first = lineRect(tester, firstLine);
        final last = lineRect(tester, firstLine + 3);
        final start = Offset(first.right - 20, first.top + 8);
        final end = Offset(last.left + 40, last.bottom - 8);

        final gesture = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        const moves = 40;
        final step = (end - start) / moves.toDouble();
        var longest = 0;
        for (var i = 0; i < moves; i++) {
          await gesture.moveBy(step);
          await tester.pump();
          final length = selected(tester).length;
          expect(length, greaterThanOrEqualTo(longest));
          longest = length;
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 600));

        final afterUp = selected(tester);
        for (var line = firstLine + 1; line <= firstLine + 3; line++) {
          expect(afterUp, contains('($line)'));
        }
      },
    );
  }

  testWidgets(
    'מעבר למצב רציף מנקה את הבחירה במקום להשאירה באותו מקום על המסך (issue #4143)',
    (tester) async {
      await pumpView(tester);
      final second = lineRect(tester, 2);
      final gesture = await tester.startGesture(
        Offset(second.right - 20, second.top + 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(second.left + 40, second.top + 8));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 600));
      expect(selected(tester), isNotEmpty);

      final bloc =
          BlocProvider.of<TextBookBloc>(
                tester.element(find.byType(CombinedView)),
              )
              as _TestTextBookBloc;
      bloc.emitForTest(
        (bloc.state as TextBookLoaded).copyWith(continuousReadingMode: true),
      );
      await tester.pumpAndSettle();

      expect(selected(tester), isEmpty);
    },
  );
}
