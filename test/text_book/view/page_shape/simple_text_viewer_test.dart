import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    if (!Settings.isInitialized) {
      await Settings.init();
    }
  });

  testWidgets('לחיצה על אינדיקטור הערה פותחת את טאב ההערות הפנימי',
      (tester) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final personalNotesBloc = _TestPersonalNotesBloc(
      PersonalNotesState(
        isLoading: false,
        bookId: 'ספר בדיקה',
        locatedNotes: [_note()],
        missingNotes: const [],
        errorMessage: null,
        filteredLocatedNotes: [_note()],
        filteredMissingNotes: const [],
      ),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    int? openedTab;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: SimpleTextViewer(
              content: const ['שורה א'],
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
              onOpenSidebarTab: (tabIndex) => openedTab = tabIndex,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FluentIcons.note_24_filled));
    await tester.pumpAndSettle();

    expect(openedTab, 1);
  });
}

PersonalNote _note() {
  final now = DateTime(2026, 3, 15);
  return PersonalNote(
    id: '1',
    bookId: 'ספר בדיקה',
    lineNumber: 1,
    displayTitle: 'שורה א',
    lastKnownLineNumber: 1,
    status: PersonalNoteStatus.located,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: true,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
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
