import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart' as pdf_events;
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:otzaria/search/in_book_search_preferences.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync(
      'otzaria-pdf-restored-search-',
    );
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });

  tearDown(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, int rounds) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<PdfBookTab> openRestored(
    WidgetTester tester,
    String query, {
    double width = 1600,
    bool withOutline = false,
    bool initiallyOpen = false,
    Widget Function(Widget)? wrapScreen,
    void Function(PdfBookTab, TabsBloc)? afterMount,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final font = pw.Font.ttf(
        File(
          'fonts/FrankRuehlCLM-Medium.ttf',
        ).readAsBytesSync().buffer.asByteData(),
      );
      final pdf = pw.Document()
        ..addPage(
          pw.Page(
            build: (_) => pw.Column(
              children: [
                if (withOutline) pw.Header(text: 'Navigation section'),
                pw.Text('page zero page pageboy'),
                pw.Text(
                  'שָׁלוֹם שלום שלוםשלום',
                  style: pw.TextStyle(font: font),
                  textDirection: pw.TextDirection.rtl,
                ),
              ],
            ),
          ),
        );
      await file.writeAsBytes(await pdf.save());
    });
    final saved = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: file.path),
      pageNumber: 1,
      searchText: query,
    );
    final tab = PdfBookTab.fromJson(saved.toJson());
    saved.dispose();
    tab.showLeftPane.value = initiallyOpen;
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    final tabsBloc = TabsBloc(repository: _TabsRepository());
    tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = _SettingsBloc();
    final tour = TourCubit();
    addTearDown(tabsBloc.close);
    addTearDown(settings.close);
    addTearDown(tour.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child:
              wrapScreen?.call(PdfBookScreen(tab: tab)) ??
              PdfBookScreen(tab: tab),
        ),
      ),
    );
    if (afterMount != null) {
      afterMount(tab, tabsBloc);
      await tester.pump();
    }
    addTearDown(() async {
      final document = tab.pdfViewerController.isReady
          ? tab.pdfViewerController.document
          : null;
      await tester.pumpWidget(const SizedBox.shrink());
      if (document != null) await tester.runAsync(document.dispose);
    });
    await settle(tester, 30);
    expect(tab.showLeftPane.value, initiallyOpen);
    expect(tab.pinLeftPane.value, initiallyOpen);
    return tab;
  }

  PdfTextSearchSession searcherOf(WidgetTester tester) {
    final dynamic screen = tester.state(find.byType(PdfBookScreen));
    return screen.textSearcher as PdfTextSearchSession;
  }

  testWidgets('טעינת סימניות אינה חוטפת פוקוס מחלונית שהופעלה בינתיים', (
    tester,
  ) async {
    final peerFocus = FocusNode();
    addTearDown(peerFocus.dispose);
    final tab = await openRestored(
      tester,
      '',
      withOutline: true,
      initiallyOpen: true,
      wrapScreen: (screen) => Row(
        children: [
          SizedBox(
            width: 300,
            child: Material(child: TextField(focusNode: peerFocus)),
          ),
          Expanded(child: screen),
        ],
      ),
      afterMount: (tab, tabsBloc) {
        expect(tab.outline.value, isNull);
        final peer = PdfBookTab(book: tab.book, pageNumber: 1);
        tabsBloc.emit(
          TabsState(
            tabs: [CombinedTab(rightTab: peer, leftTab: tab)],
            currentTabIndex: 0,
            rawActivePane: peer,
          ),
        );
        peerFocus.requestFocus();
      },
    );
    final outline = find.byType(OutlineView);
    expect(
      find.descendant(of: outline, matching: find.byType(OtzariaSearchField)),
      findsOneWidget,
    );
    expect(tester.widget<OutlineView>(outline).focusNode.hasFocus, isFalse);
    expect(peerFocus.hasFocus, isTrue);
    final tabsBloc = tester.element(outline).read<TabsBloc>();
    tabsBloc.emit(
      tabsBloc.state.copyWith(activePane: ActivePaneUpdate.set(tab)),
    );
    await settle(tester, 4);
    await tester.tap(
      find.descendant(
        of: outline,
        matching: find.byType(OtzariaSearchField),
      ),
    );
    await tester.pump();
    expect(tester.widget<OutlineView>(outline).focusNode.hasFocus, isTrue);
  });

  for (final width in [360.0, 1600.0]) {
    for (final initiallyOpen in [false, true]) {
      testWidgets('ניווט PDF קבוע ומיקוד בטוח: $width, פתוח=$initiallyOpen', (
        tester,
      ) async {
        final tab = await openRestored(
          tester,
          '',
          width: width,
          withOutline: true,
          initiallyOpen: initiallyOpen,
        );
        if (!initiallyOpen) {
          expect(tester.testTextInput.isVisible, isFalse);
          await tester.tap(find.byType(NavPanelToggleButton));
          await settle(tester, 8);
        }
        final outline = find.byType(OutlineView);
        final field = find.descendant(
          of: outline,
          matching: find.byType(OtzariaSearchField),
        );
        expect(field.hitTestable(), findsOneWidget);
        expect(
          tester.widget<OutlineView>(outline).focusNode.hasFocus,
          width >= 600,
        );
        if (width < 600) expect(tester.testTextInput.isVisible, isFalse);

        final controller = tester
            .widget<TabBarView>(
              find.byType(TabBarView).first,
            )
            .controller!;
        controller.index = 1;
        await settle(tester, 4);
        final searchField = find.descendant(
          of: find.byType(PdfBookSearchView),
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(searchField).focusNode.hasFocus,
          isTrue,
        );
        controller.index = 0;
        await settle(tester, 4);
        expect(
          tester.widget<OutlineView>(outline).focusNode.hasFocus,
          width >= 600,
        );

        await tester.tap(find.byType(NavPanelToggleButton));
        await settle(tester, 4);
        expect(tab.showLeftPane.value, isFalse);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<OtzariaSearchField>(),
          isNull,
        );
      });
    }
  }

  for (final (query, wholeWord, matches) in [
    ('/page/', true, 2),
    ('page', true, 3),
    ('page', false, 3),
    ('שלום', true, 2),
    ('שָׁלוֹם', true, 2),
    ('שלום', false, 4),
  ]) {
    testWidgets('restored closed PDF searches $query (wholeWord=$wholeWord)', (
      tester,
    ) async {
      await InBookSearchPreferences.saveWholeWord(wholeWord);
      final tab = await openRestored(tester, query);
      final searcher = searcherOf(tester);
      expect(searcher.isSearching, isFalse);
      expect(searcher.pattern, isA<RegExp>());
      expect(searcher.matches, hasLength(matches));
      expect(
        TickerMode.valuesOf(
          tester.element(find.byType(PdfBookSearchView)),
        ).enabled,
        isFalse,
      );
      final editable = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(editable.focusNode.hasFocus, isFalse);
      final before = tab.searchController.text;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      expect(tab.searchController.text, before);
    });
  }

  testWidgets(
    'opening, navigation tab and closing preserve the search session',
    (tester) async {
      final tab = await openRestored(tester, '/page/');
      final view = tester.state(find.byType(PdfBookSearchView));
      final searcher = searcherOf(tester);
      final pattern = searcher.pattern;
      final matches = searcher.matches;
      final session = searcher.searchSession;
      final navigation = searcher.goToMatchOfIndex(1);
      await settle(tester, 8);
      await navigation;
      await tester.tap(find.byType(NavPanelToggleButton));
      await settle(tester, 8);
      expect(tester.state(find.byType(PdfBookSearchView)), same(view));
      expect(searcher.currentIndex, 1);
      final editable = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(searcher.pattern, same(pattern));
      expect(searcher.matches, same(matches));
      expect(searcher.searchSession, session);
      expect(
        TickerMode.valuesOf(
          tester.element(find.byType(PdfBookSearchView)),
        ).enabled,
        isTrue,
      );
      final settings =
          tester.element(find.byType(PdfBookScreen)).read<SettingsBloc>()
              as _SettingsBloc;
      settings.emit(settings.state.copyWith(sidebarWidth: 340));
      await settle(tester, 4);
      expect(tester.state(find.byType(PdfBookSearchView)), same(view));
      expect(searcher.currentIndex, 1);
      expect(searcher.searchSession, session);
      final tabs = find.byType(TabBarView).first;
      final controller = tester.widget<TabBarView>(tabs).controller!;
      controller.index = 0;
      await settle(tester, 8);
      await tester.tap(find.byType(NavPanelToggleButton));
      await settle(tester, 8);
      tab.applyIncomingSearchConfiguration(
        const ReadingTabSearchState(searchText: '/zero/'),
      );
      await settle(tester, 12);
      expect(tab.showLeftPane.value, isFalse);
      expect(searcher.matches, hasLength(1));
      controller.index = 1;
      await settle(tester, 8);
      expect(
        tester.state(find.byType(PdfBookSearchView, skipOffstage: false)),
        same(view),
      );
      expect((searcher.pattern as RegExp).pattern, contains('zero'));
    },
  );

  testWidgets('opening then closing before a frame keeps focus on the PDF', (
    tester,
  ) async {
    final tab = await openRestored(tester, '/page/');
    final bloc = tester
        .element(find.byType(PdfBookSearchView))
        .read<PdfBookBloc>();
    bloc.add(const pdf_events.ToggleLeftPane(true));
    await tester.idle();
    bloc.add(const pdf_events.ToggleLeftPane(false));
    await tester.idle();
    await settle(tester, 4);
    expect(tab.showLeftPane.value, isFalse);
    final editable = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(editable.focusNode.hasFocus, isFalse);
    final before = tab.searchController.text;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    expect(tab.searchController.text, before);
  });

  testWidgets('a new query starts search in an initially lazy closed pane', (
    tester,
  ) async {
    final tab = await openRestored(tester, '');
    expect(find.byType(PdfBookSearchView), findsNothing);
    expect(searcherOf(tester).pattern, isNull);
    tab.applyIncomingSearchConfiguration(
      const ReadingTabSearchState(searchText: '/page/'),
    );
    await settle(tester, 20);
    expect(tab.showLeftPane.value, isFalse);
    expect(find.byType(PdfBookSearchView), findsOneWidget);
    expect(searcherOf(tester).matches, hasLength(2));
  });
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, _) => events.add(event));
  }

  final events = <SettingsEvent>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
