import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/reading_toc.dart';

/// ←/→ באזור הקריאה עוברים לקטע, ו-Ctrl+←/→ לדף/פרק (issue #2706).
final List<String> _lines = [
  for (var chapter = 1; chapter <= 3; chapter++) ...[
    '<h2>פרק $chapter</h2>',
    for (var verse = 1; verse <= 3; verse++) 'פסוק $verse בפרק $chapter',
  ],
];

TextBookLoaded _state() => TextBookLoaded(
  book: TextBook(title: 'ספר חיצים'),
  showLeftPane: false,
  content: _lines,
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  linksByLine: const {},
  tableOfContents: headerToc(_lines),
  visibleIndices: const [0],
  pinLeftPane: false,
  searchText: '',
);

Future<TextBookTab> _mount(WidgetTester tester) async {
  final initial = _state();
  final bloc = _TestTextBookBloc(initial);
  final notes = _TestPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = _TestSettingsBloc(SettingsState.initial());
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
            showCommentaryAsExpansionTiles: true,
            tab: tab,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tab;
}

List<int> _counts(TextBookTab tab) => [
  tab.navPreviousSegmentNotifier.value,
  tab.navNextSegmentNotifier.value,
  tab.navPreviousTocNotifier.value,
  tab.navNextTocNotifier.value,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('← לקטע הבא ו-→ לקטע הקודם', (tester) async {
    final tab = await _mount(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(_counts(tab), [0, 1, 0, 0]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(_counts(tab), [1, 1, 0, 0]);
  });

  testWidgets('Ctrl+← לדף/פרק הבא ו-Ctrl+→ לקודם', (tester) async {
    final tab = await _mount(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(_counts(tab), [0, 0, 1, 1]);
  });

  testWidgets('Shift+חץ ו-Alt+חץ אינם מנווטים', (tester) async {
    final tab = await _mount(tester);

    for (final modifier in [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(modifier);
    }
    expect(_counts(tab), [0, 0, 0, 0]);
  });

  testWidgets('עם טקסט מסומן Ctrl+חץ לא עובר פרק, וחץ לבד עדיין עובר קטע', (
    tester,
  ) async {
    final tab = await _mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(tab.navNextTocNotifier.value, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(tab.navNextSegmentNotifier.value, 1);
  });
}

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
