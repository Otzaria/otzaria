import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

// כל שינוי בבחירה בגרירה בנה מחדש את שכבת תפריט ההקשר של כל שורה גלויה,
// אף שהטקסט הנבחר נדרש רק בפתיחת התפריט.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 600);
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
    );
    final textBookBloc = _TestTextBookBloc(state);
    final personalNotesBloc = StubPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
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
  }

  Rect lineRect(WidgetTester tester, int lineIndex) =>
      tester.getRect(find.byKey(ValueKey('html_${_title}_$lineIndex')));

  testWidgets('גרירת בחירה אינה בונה מחדש את תפריט ההקשר של כל שורה', (
    tester,
  ) async {
    await pumpView(tester);
    final first = lineRect(tester, 1);
    final last = lineRect(tester, 4);

    final gesture = await tester.startGesture(
      Offset(first.center.dx, first.top + 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    var menuRegionBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is AppContextMenuRegion) menuRegionBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    const moves = 8;
    final step = (last.center - first.topCenter) / moves.toDouble();
    for (var i = 0; i < moves; i++) {
      await gesture.moveBy(step);
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = null;

    // התפריט של שורה בתוך הבחירה עדיין מקבל את הטקסט הנבחר.
    final region = find
        .ancestor(
          of: find.byKey(const ValueKey('html_${_title}_2')),
          matching: find.byType(AppContextMenuRegion),
        )
        .first;
    final center = tester.getCenter(region);
    final entries = tester
        .widget<AppContextMenuRegion>(region)
        .menuBuilder(tester.element(region), center);
    final labels = entries.map((entry) => entry.label).toList();

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));

    expect(labels, contains(startsWith('חפש "')));
    expect(menuRegionBuilds, 0);
  });
}
