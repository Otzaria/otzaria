// פתיחה, סגירה ומעבר לשונית בחלונית הצד אינם בונים מחדש את הקורא, ושינוי
// גודל הגופן עדיין מגיע אליו.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_personal_notes_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_tabs_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

const _content = ['פסקה א', 'פסקה ב'];
final _book = TextBook(title: 'ספר בדיקה');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('החלונית אינה בונה מחדש את הקורא, וגודל הגופן מגיע אליו', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bloc = EmittingStubTextBookBloc(_state(18));
    final settings = StubSettingsBloc(SettingsState.initial());
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final tab = TextBookTab(book: _book, index: 0, blocOverride: bloc);
    final tabs = StubTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final tour = _TestTourCubit();
    addTearDown(() async {
      debugOnRebuildDirtyWidget = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await settings.close();
      await notes.close();
      await tabs.close();
      await tour.close();
      tab.dispose();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<TourCubit>.value(value: tour),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SplitedViewScreen(
              content: _content,
              openBookCallback: (_) {},
              searchTextController: TextEditingValue.empty,
              openLeftPaneTab: (_, {searchText}) {},
              tab: tab,
              showSplitView: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var readerBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is CombinedView) readerBuilds++;
    };

    tab.toggleCommentatorsPaneNotifier.value++;
    await tester.pumpAndSettle();
    expect(find.byType(TabbedCommentaryPanel), findsOneWidget);
    expect(find.byType(PanelOpenHandle), findsNothing);

    await tester.tap(find.text('קישורים'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('מפרשים'));
    await tester.pumpAndSettle();

    tab.toggleCommentatorsPaneNotifier.value++;
    await tester.pumpAndSettle();
    expect(find.byType(PanelOpenHandle), findsOneWidget);
    expect(readerBuilds, 0, reason: 'פתיחה, מעבר לשונית וסגירה');

    bloc.emitState(_state(24));
    await tester.pumpAndSettle();
    expect(readerBuilds, greaterThan(0));
    expect(tester.widget<CombinedView>(find.byType(CombinedView)).textSize, 24);
  });
}

TextBookLoaded _state(double fontSize) => TextBookLoaded(
  book: _book,
  showLeftPane: false,
  content: _content,
  fontSize: fontSize,
  showSplitView: true,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const <Link>[],
  visibleLinks: const <Link>[],
  linksByLine: const {},
  tableOfContents: const [],
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
);

class _TestTourCubit extends Cubit<TourState> implements TourCubit {
  _TestTourCubit() : super(const TourState.inactive());

  @override
  Future<void> recordInteraction(TourInteraction interaction) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
