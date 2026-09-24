import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../helpers/memory_settings_cache.dart';

class _RecordingSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _RecordingSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, _) => events.add(event));
  }

  final events = <SettingsEvent>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc() : super(const PersonalNotesState.initial()) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loaded(TextBook book) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: const ['שורה א', 'שורה ב'],
  fontSize: 25,
  showSplitView: false,
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

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('זום בכרטיסיית המפרשים משנה את גודל גופן המפרשים (issue #1520)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final book = TextBook(title: 'חולין');
    final sourceBloc = _TestTextBookBloc(_loaded(book));
    final tabBloc = _TestTextBookBloc(_loaded(book));
    final sourceTab = TextBookTab(
      book: book,
      index: 0,
      blocOverride: sourceBloc,
    );
    final tab = CommentatorsTab(sourceTab: sourceTab, blocOverride: tabBloc);
    final settings = _RecordingSettingsBloc(
      SettingsState.initial().copyWith(commentatorsFontSize: 20),
    );
    final notes = _TestPersonalNotesBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.close();
      await notes.close();
      await tabBloc.close();
      await sourceBloc.close();
      sourceTab.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
          ],
          child: Scaffold(
            body: CommentatorsTabScreen(tab: tab, openBookCallback: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('הגדל את גודל הטקסט').first);
    await tester.pump();

    expect(
      settings.events.whereType<UpdateCommentatorsFontSize>().map(
        (e) => e.commentatorsFontSize,
      ),
      [22.0],
    );
  });
}
