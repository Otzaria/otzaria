import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_text_book_bloc.dart';

/// מעבר לקטע הקודם בתצוגה המפוצלת לא מבטל את הבחירה של הקטע היעד
/// (issue #5904). visibleIndices מתעדכן באיחור (debounce), ולכן ברגע
/// הנחיתה הוא עוד לא כולל קטע שהיה מעל התצוגה.
final List<String> _lines = [
  for (var i = 0; i < 300; i++) 'שורה $i בספר הבדיקה',
];

TextBookLoaded _state({int? selectedIndex, List<int> visible = const [0]}) =>
    TextBookLoaded(
      book: TextBook(title: 'ספר קטעים'),
      showLeftPane: false,
      content: _lines,
      fontSize: 18,
      showSplitView: true,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      visibleIndices: visible,
      selectedIndex: selectedIndex,
      searchText: '',
    );

/// בלוק שרושם את אירועי הבחירה, ומעדכן את visibleIndices מהמיקום הנמדד
/// באיחור של 160ms, כמו ה-debounce של הבלוק האמיתי.
class _RecordingBloc extends EmittingStubTextBookBloc {
  _RecordingBloc(super.initialState) {
    on<UpdateSelectedIndex>((event, emit) {
      events.add(event);
      emit(_state(selectedIndex: event.index, visible: _loaded.visibleIndices));
    });
  }

  final List<UpdateSelectedIndex> events = [];
  Timer? _debounce;

  TextBookLoaded get _loaded => state as TextBookLoaded;

  void follow(ValueListenable<ReadingPosition?> position) {
    position.addListener(() {
      final measured = position.value;
      if (measured == null || measured.isTarget) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 160), () {
        if (isClosed) return;
        emitState(
          _state(
            selectedIndex: _loaded.selectedIndex,
            visible: measured.visibleLines,
          ),
        );
      });
    });
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<(_RecordingBloc, TextBookTab)> mount(WidgetTester tester) async {
    final initial = _state();
    final bloc = _RecordingBloc(initial);
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settings = StubSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: initial.book, index: 0);
    addTearDown(bloc.close);
    addTearDown(notes.close);
    addTearDown(settings.close);
    addTearDown(tab.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: Scaffold(
            body: CombinedView(
              data: initial.content,
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
    await tester.pumpAndSettle();
    bloc.follow(tab.lines.position);
    final jump = tab.lines.jumpToLine(30, alignment: 0);
    await tester.pumpAndSettle();
    await jump;
    await tester.pump(const Duration(milliseconds: 200));
    final top = tab.lines.position.value!;
    expect(top.topLine, 30);
    expect(top.visibleLines, isNot(contains(29)));
    expect((bloc.state as TextBookLoaded).visibleIndices, top.visibleLines);
    // הבחירה על השורה העליונה.
    bloc.emitState(_state(selectedIndex: 30, visible: top.visibleLines));
    await tester.pump();
    return (bloc, tab);
  }

  /// כמו _scrollByLines ב-text_book_screen: בחירת היעד וגלילה אליו.
  Future<void> navigateTo(
    WidgetTester tester,
    _RecordingBloc bloc,
    TextBookTab tab,
    int target,
  ) async {
    bloc.add(UpdateSelectedIndex(target));
    final navigation = tab.lines.scrollToLine(
      target,
      alignment: 0,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    await navigation;
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('"הקטע הקודם" משאיר את היעד בחור (#5904)', (tester) async {
    final (bloc, tab) = await mount(tester);

    await navigateTo(tester, bloc, tab, 29);

    expect(bloc.events.map((e) => e.index), [29]);
    expect((bloc.state as TextBookLoaded).selectedIndex, 29);
  });

  testWidgets('"הקטע הבא" משאיר את היעד בחור', (tester) async {
    final (bloc, tab) = await mount(tester);

    await navigateTo(tester, bloc, tab, 31);

    expect(bloc.events.map((e) => e.index), [31]);
    expect((bloc.state as TextBookLoaded).selectedIndex, 31);
  });

  testWidgets('גלילה שמוציאה את הקטע הבחור מהתצוגה מבטלת את הבחירה', (
    tester,
  ) async {
    final (bloc, tab) = await mount(tester);

    // גרירה, הפסקה (visibleIndices מתעדכן), ואז גלילה נוספת.
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(list, const Offset(0, -40));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tab.lines.position.value!.visibleLines, isNot(contains(30)));
    expect(bloc.events.map((e) => e.index), [null]);
  });
}
