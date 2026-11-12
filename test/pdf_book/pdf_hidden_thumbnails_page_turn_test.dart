// חלונית הדפים שנסגרה, או לשונית "דפים" שהוסתרה, נשארת בעץ: דפדוף אינו
// גולל אותה ואינו בונה בה עמודים, וחשיפתה גוללת אל העמוד הנוכחי.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/pdf_book/utils/pdf_image_budget.dart';
import 'package:otzaria/pdf_book/view/pdf_thumbnails_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart'
    show PdfLayoutMode;
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/pdf_document_dispose.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync(
      'otzaria-pdf-hidden-thumbs-',
    );
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
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
    directory.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  double thumbnailsOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(ThumbnailsView, skipOffstage: false),
          matching: find.byType(Scrollable, skipOffstage: false),
        ),
      )
      .position
      .pixels;

  Future<(PdfBookBloc, PdfBookTab)> pumpBook(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 30; i++) {
        pdf.addPage(pw.Page(build: (_) => pw.Text('page ${i + 1}')));
      }
      await file.writeAsBytes(await pdf.save());
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: file.path),
      pageNumber: 1,
    );
    final tabsBloc = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = StubSettingsBloc();
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
          child: PdfBookScreen(tab: tab),
        ),
      ),
    );
    final bloc = tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();
    for (var i = 0; i < 100 && bloc.state is! PdfBookLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(bloc.state, isA<PdfBookLoaded>());
    await settle(tester, rounds: 30);
    return (bloc, tab);
  }

  Future<void> turnPages(WidgetTester tester, PdfBookTab tab) async {
    for (var page = 2; page <= 8; page++) {
      unawaited(
        tab.pdfViewerController.goToPage(
          pageNumber: page,
          duration: Duration.zero,
        ),
      );
      await settle(tester, rounds: 3);
    }
    expect(tab.pdfViewerController.pageNumber, 8);
  }

  testWidgets('מעבר טאב משחרר תמונות ומשהה חיפוש, וחזרה ממשיכה אותו', (
    tester,
  ) async {
    final (_, tab) = await pumpBook(tester);
    final document = tab.pdfViewerController.document;
    try {
      final tabsBloc = tester
          .element(find.byType(PdfBookScreen))
          .read<TabsBloc>();
      await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(
        find.byType(PdfBookSearchView, skipOffstage: false),
        findsOneWidget,
      );
      final searcher = tester
          .widget<PdfBookSearchView>(
            find.byType(PdfBookSearchView, skipOffstage: false),
          )
          .textSearcher;
      await tester.tap(find.text('דפים'));
      await settle(tester);
      expect(pdfSharedImageBudget.retainedBytes, greaterThan(0));

      final other = PdfBookTab(
        book: PdfBook(title: 'טאב אחר', path: '${directory.path}/other.pdf'),
        pageNumber: 1,
      );
      // ignore: invalid_use_of_visible_for_testing_member
      tabsBloc.emit(TabsState(tabs: [tab, other], currentTabIndex: 1));
      await settle(tester);
      expect(
        tester.widget<PdfViewer>(find.byType(PdfViewer)).params.isVisible,
        isFalse,
      );
      expect(searcher.isActive, isFalse);
      expect(pdfSharedImageBudget.pendingBytes, 0);
      expect(pdfSharedImageBudget.retainedBytes, 0);
      searcher.startTextSearch(
        'page',
        searchImmediately: true,
        goToFirstMatch: false,
      );
      await settle(tester, rounds: 3);
      expect(searcher.isSearching, isFalse);
      expect(searcher.matches, isEmpty);

      // ignore: invalid_use_of_visible_for_testing_member
      tabsBloc.emit(TabsState(tabs: [tab, other], currentTabIndex: 0));
      await settle(tester, rounds: 30);
      expect(
        tester.widget<PdfViewer>(find.byType(PdfViewer)).params.isVisible,
        isTrue,
      );
      expect(searcher.isActive, isTrue);
      expect(searcher.matches.length, 30);
      tester.binding.handleMemoryPressure();
      await settle(tester);
      expect(searcher.matches.length, 30);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await disposePdfDocument(tester, document);
    }
    expect(pdfSharedImageBudget.estimatedBytes, 0);
  });

  for (final revealImmediately in [false, true]) {
    testWidgets(
      'הסתרה מבטלת דפדוף ספר רגיל בלי לפגוע בדפדוף חדש: revealImmediately=$revealImmediately',
      (tester) async {
        final (bloc, tab) = await pumpBook(tester);
        final controller = tab.pdfViewerController;
        final document = controller.document;
        try {
          final tabsBloc = tester
              .element(find.byType(PdfBookScreen))
              .read<TabsBloc>();
          bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
          await settle(tester, rounds: 30);
          expect(controller.pageNumber, 1);
          Future<void> focusReader() async {
            final focus = Focus.of(tester.element(find.byType(PdfViewer)));
            expect(focus.canRequestFocus, isTrue);
            focus.requestFocus();
            await tester.pump();
            expect(focus.hasFocus, isTrue);
          }

          await focusReader();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
          expect(
            controller.pageNumber,
            1,
            reason: 'הטאב צריך להיות מוסתר בזמן הצילום, לפני הניווט',
          );
          final other = PdfBookTab(
            book: PdfBook(
              title: 'טאב אחר',
              path: '${directory.path}/other.pdf',
            ),
            pageNumber: 1,
          );
          // ignore: invalid_use_of_visible_for_testing_member
          tabsBloc.emit(TabsState(tabs: [tab, other], currentTabIndex: 1));
          await tester.pump();
          await tester.pump();
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
          expect(
            tester.widget<PdfViewer>(find.byType(PdfViewer)).params.isVisible,
            isFalse,
          );
          if (!revealImmediately) {
            await settle(tester, rounds: 20);
            expect(
              controller.pageNumber,
              1,
              reason: 'המשך הדפדוף שהתיישן ניווט בטאב המוסתר',
            );
            expect(pdfSharedImageBudget.estimatedBytes, 0);
          }
          // ignore: invalid_use_of_visible_for_testing_member
          tabsBloc.emit(TabsState(tabs: [tab, other], currentTabIndex: 0));
          await tester.pump();
          await tester.pump();
          await focusReader();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await settle(tester, rounds: 40);
          expect(
            tester.widget<PdfViewer>(find.byType(PdfViewer)).params.isVisible,
            isTrue,
          );
          expect(
            controller.pageNumber,
            2,
            reason: 'דפדוף חדש צריך להגיע לכפולה הבאה בדיוק פעם אחת',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await disposePdfDocument(tester, document);
        }
        expect(pdfSharedImageBudget.estimatedBytes, 0);
      },
    );
  }

  testWidgets('דפדוף כשחלונית הדפים סגורה אינו גולל אותה, ופתיחתה גוללת '
      'אל העמוד הנוכחי', (tester) async {
    final (bloc, tab) = await pumpBook(tester);
    bloc.add(const ToggleLeftPane(true));
    await settle(tester);
    await tester.tap(find.text('דפים'));
    await settle(tester);
    bloc.add(const ToggleLeftPane(false));
    await settle(tester);
    final closedOffset = thumbnailsOffset(tester);

    await turnPages(tester, tab);
    expect(
      thumbnailsOffset(tester),
      closedOffset,
      reason: 'חלונית סגורה נגללה אל העמוד החדש',
    );

    bloc.add(const ToggleLeftPane(true));
    await settle(tester);
    expect(thumbnailsOffset(tester), greaterThan(closedOffset));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('דפדוף כשהחלונית פתוחה על "ניווט" אינו בונה את לשונית "דפים", '
      'ומעבר אליה מציג את העמוד הנוכחי', (tester) async {
    final (bloc, tab) = await pumpBook(tester);
    bloc.add(const ToggleLeftPane(true));
    await settle(tester);
    await tester.tap(find.text('דפים'));
    await settle(tester);
    await tester.tap(find.text('ניווט'));
    await settle(tester);
    final hiddenOffset = thumbnailsOffset(tester);

    var thumbnailBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is Text &&
          element.findAncestorWidgetOfExactType<ThumbnailsView>() != null) {
        thumbnailBuilds++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    await turnPages(tester, tab);
    debugOnRebuildDirtyWidget = null;
    expect(thumbnailBuilds, 0, reason: 'לשונית "דפים" המוסתרת נבנתה בדפדוף');
    expect(thumbnailsOffset(tester), hiddenOffset);

    await tester.tap(find.text('דפים'));
    await settle(tester);
    expect(thumbnailsOffset(tester), greaterThan(hiddenOffset));
    expect(
      find.descendant(
        of: find.byType(ThumbnailsView),
        matching: find.text('8'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  for (final turnWhileHidden in [true, false]) {
    for (final closePane in [true, false]) {
      testWidgets(
        'גלילה ידנית ופתיחה מחדש: closePane=$closePane, turnWhileHidden=$turnWhileHidden',
        (tester) async {
          final (bloc, tab) = await pumpBook(tester);
          bloc.add(const ToggleLeftPane(true));
          await settle(tester);
          await tester.tap(find.text('דפים'));
          await settle(tester);
          final list = find.descendant(
            of: find.byType(ThumbnailsView),
            matching: find.byType(Scrollable),
          );
          await tester.drag(list, const Offset(0, -650));
          await settle(tester);
          expect(
            tester
                .state<ScrollableState>(list)
                .position
                .isScrollingNotifier
                .value,
            isFalse,
          );
          final manualOffset = thumbnailsOffset(tester);
          expect(manualOffset, greaterThan(400));
          if (closePane) {
            bloc.add(const ToggleLeftPane(false));
          } else {
            await tester.tap(find.text('ניווט'));
          }
          await settle(tester);
          if (turnWhileHidden) {
            for (final page in [8, 1]) {
              unawaited(
                tab.pdfViewerController.goToPage(
                  pageNumber: page,
                  duration: Duration.zero,
                ),
              );
              await settle(tester);
              expect(tab.pdfViewerController.pageNumber, page);
            }
            unawaited(tab.pdfViewerController.zoomUp(duration: Duration.zero));
            await settle(tester);
            expect(tab.pdfViewerController.pageNumber, 1);
          }
          expect(thumbnailsOffset(tester), manualOffset);
          if (closePane) {
            bloc.add(const ToggleLeftPane(true));
          } else {
            await tester.tap(find.text('דפים'));
          }
          await settle(tester);
          final finalOffset = thumbnailsOffset(tester);
          final activePageVisible = find
              .descendant(
                of: find.byType(ThumbnailsView),
                matching: find.text('1'),
              )
              .hitTestable()
              .evaluate()
              .isNotEmpty;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 200));
          if (!turnWhileHidden) {
            expect(finalOffset, manualOffset);
          }
          expect(
            activePageVisible,
            turnWhileHidden ? isTrue : isFalse,
            reason: turnWhileHidden
                ? 'העמוד הפעיל חייב להופיע לאחר דפדוף מוסתר'
                : 'פתיחה בלי דפדוף חייבת לשמר את הגלילה הידנית',
          );
        },
      );
    }
  }
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}
