import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));
  setUp(() {
    SearchDefaults.saveModeDefault(SearchMode.exact);
    SearchDefaults.saveDistanceDefault(0);
    SearchDefaults.saveExactDefaults(const {});
  });
  tearDown(() {
    TargetLineLinksService.resetInstanceForTesting();
    debugSelectedTextCopyHandler = null;
  });

  for (final combined in [true, false]) {
    testWidgets(
      '${combined ? 'הקורא המשולב' : 'צורת הדף'} מחפש את המילה בלי סמן ההערה ושומר את הבחירה',
      (tester) async {
        const prefix = 'הרי שסמך על מקצת ';
        const source = '${prefix}הודאתו<sup class="footnote-marker">3963</sup>';
        const shownSuffix = 'הודאתו\u20663963\u2069';
        final book = TextBook(title: 'ספר בדיקה');
        final bloc = _TextBookBloc(_loaded(book, source, combined));
        final settings = _SettingsBloc(
          SettingsState.initial().copyWith(copyWithHeaders: 'none'),
        );
        final notes = _PersonalNotesBloc(const PersonalNotesState.initial());
        final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
        final tabs = _TabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
        final history = _HistoryBloc();
        addTearDown(() async {
          await tabs.close();
          await history.close();
          await settings.close();
          await notes.close();
          tab.dispose();
        });
        await tester.binding.setSurfaceSize(const Size(1000, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final inBookQueries = <String?>[];
        ({String? text, int? line, int? column})? combinedSelection;
        final copied = <String>[];
        debugSelectedTextCopyHandler = (content) =>
            copied.add(content.plainText);
        final viewer = combined
            ? CombinedView(
                data: const [source],
                tab: tab,
                openBookCallback: (_) {},
                openLeftPaneTab: (index, {searchText}) {
                  expect(index, 1);
                  inBookQueries.add(searchText);
                },
                onSelectedTextChanged: (text, line, column) {
                  combinedSelection = (text: text, line: line, column: column);
                },
              )
            : SimpleTextViewer(
                content: const [source],
                fontSize: 18,
                isMainText: true,
                tab: tab,
                openBookCallback: (_) {},
                onOpenSearch: inBookQueries.add,
              );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('he', 'IL'),
            supportedLocales: const [Locale('he', 'IL')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MultiBlocProvider(
              providers: [
                BlocProvider<TextBookBloc>.value(value: bloc),
                BlocProvider<SettingsBloc>.value(value: settings),
                BlocProvider<PersonalNotesBloc>.value(value: notes),
                BlocProvider<TabsBloc>.value(value: tabs),
                BlocProvider<HistoryBloc>.value(value: history),
              ],
              child: Scaffold(body: viewer),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final viewerFinder = find.byType(
          combined ? CombinedView : SimpleTextViewer,
        );
        final rendered = tester
            .renderObjectList<RenderParagraph>(
              find.descendant(
                of: viewerFinder,
                matching: find.byType(RichText),
              ),
            )
            .map((paragraph) => paragraph.text.toPlainText())
            .where((text) => text.contains('הודאתו') && text.contains('3963'))
            .toList();
        expect(rendered, hasLength(1));
        final selected = rendered.single.substring(
          rendered.single.indexOf('הודאתו'),
        );
        expect(
          selected,
          shownSuffix,
          reason: 'הבחירה חייבת לכלול את תווי המרנדר',
        );
        final regionFinder = find.descendant(
          of: viewerFinder,
          matching: find.byType(SelectableRegion),
        );
        expect(regionFinder, findsOneWidget);
        tester.widget<SelectableRegion>(regionFinder).onSelectionChanged!(
          SelectedContent(plainText: selected),
        );
        await tester.pump();

        if (combined) {
          expect(combinedSelection?.text, selected);
          expect(
            combinedSelection?.line,
            0,
            reason: 'הבחירה חייבת להגיע לשורת המקור',
          );
          expect(combinedSelection?.column, prefix.length);
        } else {
          final anchor = bloc.received
              .whereType<UpdateSelectedTextForNote>()
              .last;
          expect(anchor.text, selected);
          expect(
            anchor.sectionIndex,
            0,
            reason: 'הבחירה חייבת להגיע לשורת המקור',
          );
          expect(anchor.start, prefix.length);
          expect(anchor.end, prefix.length + selected.length);
        }

        final menuFinder = find
            .descendant(
              of: viewerFinder,
              matching: find.byType(AppContextMenuRegion),
            )
            .first;
        final menuRegion = tester.widget<AppContextMenuRegion>(menuFinder);
        final entries = menuRegion.menuBuilder(
          tester.element(menuFinder),
          tester.getCenter(menuFinder),
        );
        final search = entries.singleWhere(
          (entry) => entry.label.endsWith('בספר זה'),
        );
        search.onTap!();
        expect(inBookQueries, hasLength(1));
        expect(
          inBookQueries.single,
          'הודאתו',
          reason: 'שאילתת החיפוש בספר משמיטה רק את סמן ההערה',
        );
        expect(search.label, 'חפש "הודאתו" בספר זה');

        final actions = entries.first.iconRowActions!;
        final globalSearch = actions.firstWhere(
          (action) => action.label == 'חיפוש',
        );
        expect(globalSearch.enabled, isTrue);
        expect(globalSearch.tooltip, 'חיפוש "הודאתו" בכל הספרים');
        globalSearch.onTap!();
        await tester.pump();
        final searchTab =
            tabs.received.whereType<AddTab>().single.tab as SearchingTab;
        addTearDown(searchTab.dispose);
        expect(searchTab.queryController.text, 'הודאתו');
        expect(
          history.received.whereType<AddHistory>().single.tab,
          same(searchTab),
        );

        final copy = actions.firstWhere((action) => action.label == 'העתקה');
        expect(copy.enabled, isTrue);
        copy.onTap!();
        await tester.pumpAndSettle();
        expect(copied, hasLength(1));
        expect(copied.single, contains('הודאתו'));
        expect(
          copied.single,
          contains('3963'),
          reason: 'ההעתקה משאירה את מספר ההערה',
        );
        if (combined) {
          expect(combinedSelection?.text, selected);
          expect(combinedSelection?.column, prefix.length);
        } else {
          final anchor = bloc.received
              .whereType<UpdateSelectedTextForNote>()
              .last;
          expect(anchor.text, selected);
          expect(anchor.start, prefix.length);
          expect(anchor.end, prefix.length + selected.length);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

TextBookLoaded _loaded(TextBook book, String source, bool combined) =>
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: [source],
      fontSize: 18,
      showSplitView: false,
      showPageShapeView: !combined,
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
    );

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) => received.add(event));
  }
  final received = <TextBookEvent>[];
  @override
  final TextBookRepository repository = _TextBookRepository();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookRepository implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _PersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) => received.add(event));
  }
  final received = <TabsEvent>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _HistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((event, emit) => received.add(event));
  }
  final received = <HistoryEvent>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
