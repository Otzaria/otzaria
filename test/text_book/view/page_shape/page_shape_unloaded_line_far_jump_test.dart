import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/widgets/unloaded_paragraph_placeholder.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/reading_toc.dart';
import '../../../test_helpers/stub_navigation_bloc.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

/// ספר בצורת מגן אברהם: אלפי שורות, כותרת סימן כל 10 שורות, ורק תחילתו
/// נטענה כשקופצים רחוק.
const _count = 18119;
const _target = 1993;
final List<String> _lines = [
  for (var i = 0; i < _count; i++)
    i % 10 == 0
        ? '<h2>סימן ${i ~/ 10}</h2>'
        : '(א) היה קורא - ה"ה לד"ת שאם היה עוסק בתורה ונכנס לבית הכנסת '
              'ומצא צבור שקורין ק"ש צריך לקרות עמהם פסוק ראשון $i',
];

List<bool> _loaded(List<(int, int)> ranges) => [
  for (var i = 0; i < _count; i++) ranges.any((r) => i >= r.$1 && i <= r.$2),
];

TextBookLoaded _state(
  List<bool> loaded, {
  required bool continuous,
  int version = 1,
}) => TextBookLoaded(
  book: TextBook(title: 'מגן אברהם'),
  showLeftPane: false,
  content: [for (var i = 0; i < _count; i++) loaded[i] ? _lines[i] : ''],
  contentVersion: version,
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: headerToc(_lines),
  removeNikud: false,
  visibleIndices: const [0],
  searchText: '',
  supportsContinuousReadingMode: true,
  continuousReadingMode: continuous,
  loadedLineFlags: loaded,
);

class _Bloc extends Bloc<TextBookEvent, TextBookState> implements TextBookBloc {
  _Bloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }
  void emitForTest(TextBookState state) => emit(state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(TextBookTab, _Bloc)> _mount(
  WidgetTester tester,
  TextBookLoaded initial,
) async {
  final bloc = _Bloc(initial);
  final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = StubSettingsBloc(SettingsState.initial());
  // מסך שאינו הקריאה: התצוגה לא מבקשת פוקוס ואינה נזקקת ל-TabsBloc.
  final navigation = StubNavigationBloc(
    const NavigationState(currentScreen: Screen.library),
  );
  final tab = TextBookTab(book: initial.book, index: 0);
  addTearDown(bloc.close);
  addTearDown(notes.close);
  addTearDown(settings.close);
  addTearDown(navigation.close);
  addTearDown(tab.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<NavigationBloc>.value(value: navigation),
        ],
        child: Scaffold(
          body: BlocBuilder<TextBookBloc, TextBookState>(
            builder: (context, state) => SimpleTextViewer(
              content: (state as TextBookLoaded).content,
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
              lines: tab.lines,
              tab: tab,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (tab, bloc);
}

int _builtItems() =>
    find.byType(ReaderLineBlock, skipOffstage: false).evaluate().length +
    find
        .byType(UnloadedParagraphPlaceholder, skipOffstage: false)
        .evaluate()
        .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('צורת הדף: קפיצה רחוקה לאזור שלא נטען בונה רק את פריטי התצוגה', (
    tester,
  ) async {
    final (tab, _) = await _mount(
      tester,
      _state(_loaded([(0, 1500)]), continuous: false),
    );
    final loadedJump = _builtItems();

    unawaited(tab.lines.jumpToLine(_target));
    await tester.pump();

    // שורות בגובה אפס בונות כאן כ-600 פריטים, מקום שמור כ-90 (נמוך משורה
    // טעונה, 19 פריטים). הסף ביניהם, כדי ששינוי גובה קטן לא יפיל את הבדיקה.
    expect(_builtItems(), lessThan(loadedJump * 10));
  });

  testWidgets('צורת הדף: שורה ריקה שנטענה נשארת בגובה אפס', (tester) async {
    final (tab, bloc) = await _mount(
      tester,
      _state(_loaded([(0, 1500)]), continuous: false),
    );

    final navigation = tab.lines.jumpToLine(_target);
    await tester.pump();
    final state = _state(
      _loaded([(0, 1500), (_target - 120, _target + 260)]),
      continuous: false,
      version: 2,
    );
    final emptyLine = _target + 1;
    state.content[emptyLine] = '';
    bloc.emitForTest(state);
    await tester.pumpAndSettle();
    await navigation;

    expect(tab.index, inInclusiveRange(_target - 1, _target + 1));
    expect(
      find.byType(UnloadedParagraphPlaceholder, skipOffstage: false),
      findsNothing,
    );
    final empty = tester.getSize(
      find.byWidgetPredicate(
        (w) => w is ReaderLineBlock && w.lineIndex == emptyLine,
      ),
    );
    expect(empty.height, lessThan(10));
  });
}
