import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

/// #5748: כל סעיפי הסימן בשורה אחת; הטאב נפתח בסמן [סעיף ו] שבתוכה.
const _target = 5;
const _reference = 'טור סימן שח סעיף ו';
final _filler = List.filled(
  60,
  'דברי הברית אשר צוה לכרת את בני ישראל',
).join(' ');
final _content = [
  for (var i = 0; i < 120; i++)
    i == _target
        ? '[סעיף א] $_filler [סעיף ו] יעדמדויק $_filler'
        : 'שורה $i: דברי הברית אשר צוה',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => Settings.init(cacheProvider: MemoryCacheProvider()));

  for (final pageShape in [false, true]) {
    testWidgets('טאב חדש נפתח בסמן (צורת הדף: $pageShape)', (tester) async {
      await _pump(tester, markerReference: _reference, pageShape: pageShape);

      final list = tester.getRect(find.byType(ScrollablePositionedList));
      final anchor = list.top + kReadingAnchorAlignment * list.height;
      expect(_rowTopOf(tester, 'יעדמדויק'), closeTo(anchor, 40));
    });

    testWidgets('טאב קיים נוחת בסמן אחרי טעינה (צורת הדף: $pageShape)', (
      tester,
    ) async {
      final tabs = _tabs();
      final (tab, bookBloc) = await _pump(
        tester,
        targetLoaded: false,
        pageShape: pageShape,
        tabs: tabs,
      );
      _openTarget(tabs, tab);
      await tester.pumpAndSettle();
      expect(tab.index, _target);
      expect(tabs.state.tabs, [tab]);
      expect(tab.lines.history.value.back?.line, 0);

      bookBloc.loadTarget();
      await tester.pumpAndSettle();
      final list = tester.getRect(find.byType(ScrollablePositionedList));
      expect(_rowTopOf(tester, 'יעדמדויק'), closeTo(list.top, 40));

      final back = tab.lines.goBack();
      await tester.pumpAndSettle();
      await back;
      expect(tab.lines.captureAnchor()?.line, 0);
    });
  }

  testWidgets('בקשת סעיף לפני חיבור הטאב נשמרת עד טעינת השורה', (tester) async {
    final tabs = _tabs();
    final (tab, bookBloc) = await _pump(
      tester,
      targetLoaded: false,
      tabs: tabs,
      beforeMount: (tab) async {
        _openTarget(tabs, tab);
        await tester.pumpAndSettle();
        expect(tab.lines.hasPendingTarget, isTrue);
      },
    );
    expect(tab.index, _target);

    bookBloc.loadTarget();
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byType(ScrollablePositionedList));
    expect(_rowTopOf(tester, 'יעדמדויק'), closeTo(list.top, 40));
  });

  testWidgets('בקשה חדשה מבטלת את הדיוק של יעד שעדיין נטען', (tester) async {
    final tabs = _tabs();
    final (tab, bookBloc) = await _pump(
      tester,
      targetLoaded: false,
      tabs: tabs,
    );
    _openTarget(tabs, tab);
    await tester.pump();

    _openTarget(tabs, tab, index: 2, marker: null);
    await tester.pumpAndSettle();
    expect(tab.index, 2);
    bookBloc.loadTarget();
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byType(ScrollablePositionedList));
    expect(_rowTopOf(tester, 'שורה 2:'), closeTo(list.top, 40));
  });

  testWidgets('בלי הפניה נפתח בתחילת השורה', (tester) async {
    await _pump(tester);

    final list = tester.getRect(find.byType(ScrollablePositionedList));
    final anchor = list.top + kReadingAnchorAlignment * list.height;
    expect(_rowTopOf(tester, '[סעיף א]'), closeTo(anchor, 40));
  });
}

TabsBloc _tabs() {
  final bloc = TabsBloc(repository: _TabsRepository());
  addTearDown(bloc.close);
  return bloc;
}

void _openTarget(
  TabsBloc tabs,
  TextBookTab tab, {
  int index = _target,
  String? marker = _reference,
}) => tabs.add(
  OpenOrFocusTab(
    TextBookTab(book: tab.book, index: index, markerReference: marker),
    navigateToPositionIfReused: true,
  ),
);

double _rowTopOf(WidgetTester tester, String text) {
  final paragraph = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .firstWhere((p) => p.text.toPlainText().contains(text));
  final offset = paragraph.text.toPlainText().indexOf(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
        boxHeightStyle: ui.BoxHeightStyle.max,
      )
      .first;
  return paragraph.localToGlobal(Offset(0, box.top)).dy;
}

Future<(TextBookTab, _TestTextBookBloc)> _pump(
  WidgetTester tester, {
  String? markerReference,
  bool targetLoaded = true,
  bool pageShape = false,
  TabsBloc? tabs,
  Future<void> Function(TextBookTab)? beforeMount,
}) async {
  final book = TextBook(title: 'טור', categoryId: 7);
  final bloc = _TestTextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: targetLoaded ? _content : ([..._content]..[_target] = ''),
      loadedLineFlags: [
        for (var i = 0; i < _content.length; i++) i != _target || targetLoaded,
      ],
      fontSize: 18,
      showSplitView: false,
      showPageShapeView: pageShape,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: [targetLoaded ? _target : 0],
      pinLeftPane: false,
      searchText: '',
    ),
  );
  final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = StubSettingsBloc(SettingsState.initial());
  final tab = TextBookTab(
    book: book,
    index: targetLoaded ? _target : 0,
    markerReference: markerReference,
    blocOverride: bloc,
  );
  addTearDown(notes.close);
  addTearDown(settings.close);
  if (tabs == null) {
    addTearDown(tab.dispose);
  } else {
    tabs.add(AddTab(tab));
    await tester.pumpAndSettle();
  }
  await beforeMount?.call(tab);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<NavigationBloc>(
            create: (_) => NavigationBloc(
              repository: NavigationRepository(),
              tabsRepository: _TabsRepository(),
            ),
          ),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: Scaffold(
          body: BlocBuilder<TextBookBloc, TextBookState>(
            builder: (context, state) {
              final data = (state as TextBookLoaded).content;
              return pageShape
                  ? SimpleTextViewer(
                      content: data,
                      fontSize: 18,
                      openBookCallback: (_) {},
                      isMainText: true,
                      lines: tab.lines,
                      tab: tab,
                    )
                  : CombinedView(
                      data: data,
                      openBookCallback: (_) {},
                      openLeftPaneTab: (_, {searchText}) {},
                      textSize: 18,
                      showCommentaryAsExpansionTiles: false,
                      tab: tab,
                    );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (tab, bloc);
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void loadTarget() => emit(
    (state as TextBookLoaded).copyWith(
      content: _content,
      loadedLineFlags: [for (final _ in _content) true],
      contentVersion: 1,
    ),
  );

  @override
  final TextBookRepository repository = _Repository();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements TextBookRepository {
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

class _TabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}
