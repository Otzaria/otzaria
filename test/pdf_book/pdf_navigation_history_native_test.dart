import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_page_number_display.dart';
import 'package:otzaria/pdf_book/view/pdf_scrollbar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
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
  testWidgets('PDF אמיתי משחזר עוגן וזום בכפתור, במקלדת ובחזרת המערכת', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await Settings.init(cacheProvider: MemorySettingsCache());
    final directory = Directory.systemTemp.createTempSync(
      'otzaria-pdf-history-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final originalModulePath = Pdfrx.pdfiumModulePath;
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/${Platform.isWindows
          ? 'pdfium.dll'
          : Platform.isMacOS
          ? 'libpdfium.dylib'
          : 'libpdfium.so'}',
    ).absolute.path;
    addTearDown(() => Pdfrx.pdfiumModulePath = originalModulePath);
    final path = '${directory.path}/book.pdf';
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 8; i++) {
        pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('$i'))));
      }
      File(path).writeAsBytesSync(await pdf.save());
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: path),
      pageNumber: 3,
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
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child: Scaffold(body: PdfBookScreen(tab: tab)),
        ),
      ),
    );
    final viewer = find.byType(PdfViewer);
    final bloc = tester.element(viewer).read<PdfBookBloc>();
    Future<void> settle([int frames = 15]) async {
      for (var i = 0; i < frames; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    for (var i = 0; i < 200 && bloc.state is! PdfBookLoaded; i++) {
      await settle(1);
    }
    expect(bloc.state, isA<PdfBookLoaded>());
    final controller = tab.pdfViewerController;
    final document = controller.document;
    final page = controller.layout.pageLayouts[2];
    unawaited(
      controller.goTo(
        controller.calcMatrixFor(page.center + const Offset(20, 60), zoom: 1.8),
        duration: Duration.zero,
      ),
    );
    await settle();
    final saved = PdfReadingLocation.capture(controller)!;
    void expectRestored(PdfReadingLocation location) {
      final current = PdfReadingLocation.capture(controller)!;
      expect(current.pageNumber, location.pageNumber);
      expect(current.zoom, closeTo(location.zoom, 0.001));
      expect((current.pageOffset - location.pageOffset).distance, lessThan(1));
    }

    final pageNumber = tester.widget<PageNumberDisplay>(
      find.byType(PageNumberDisplay),
    );
    unawaited(pageNumber.onNavigateToPage!(7));
    await settle();
    expect(tab.navigationHistory.canGoBack, isTrue);
    expect(controller.pageNumber, isNot(saved.pageNumber));
    await tester.tap(find.byKey(const ValueKey('pdf-back-location')));
    await settle();
    expectRestored(saved);
    expect(tab.navigationHistory.canGoBack, isFalse);

    unawaited(controller.goToPage(pageNumber: 5, duration: Duration.zero));
    await settle();
    expect(tab.navigationHistory.canGoBack, isFalse);
    final keyboardLocation = PdfReadingLocation.capture(controller)!;
    unawaited(pageNumber.onNavigateToPage!(1));
    await settle();
    await tester.tapAt(tester.getCenter(viewer));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settle();
    expectRestored(keyboardLocation);
    expect(tab.navigationHistory.canGoBack, isFalse);

    final scrollbar = tester.widget<PdfScrollbar>(find.byType(PdfScrollbar));
    final systemLocation = PdfReadingLocation.capture(controller)!;
    scrollbar.onNavigationStarted!();
    unawaited(controller.goToPage(pageNumber: 1, duration: Duration.zero));
    await settle();
    await tester.binding.handlePopRoute();
    await settle();
    expectRestored(systemLocation);
    expect(tab.navigationHistory.canGoBack, isFalse);
    await tester.tapAt(tester.getCenter(viewer));
    final shortcutModifier = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(shortcutModifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(shortcutModifier);
    await settle();
    final widthZoom = controller.currentZoom;
    await tester.sendKeyDownEvent(shortcutModifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(shortcutModifier);
    await settle();
    expect(controller.currentZoom, lessThan(widthZoom));
    expect(tab.navigationHistory.canGoBack, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    await disposePdfDocument(tester, document);
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
