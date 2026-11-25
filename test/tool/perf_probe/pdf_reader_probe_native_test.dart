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
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../integration_test/support/perf_pdf_reader.dart';
import '../../../tool/perf_probe/make_pdf_print_preview_fixtures.dart';
import '../../../tool/perf_probe/src/pdf_reader_case.dart';
import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/pdf_document_dispose.dart';
import '../../test_helpers/stub_settings_bloc.dart';

void main() {
  _testReaderCase(PerfPdfCase.defaults);
  _testReaderCase(
    PerfPdfCase.fromJson({
      'schemaVersion': 1,
      'source': {'kind': 'generated', 'pageCount': 10},
      'navigation': {
        'initialPage': 2,
        'forwardPage': 9,
        'backwardPage': 3,
        'zoomFactor': 1.5,
      },
    }, baseDirectory: Directory.systemTemp.path),
  );
}

void _testReaderCase(PerfPdfCase pdfCase) {
  testWidgets('reader follows ${pdfCase.pageCount}-page case with PDFium', (
    tester,
  ) async {
    final targets = pdfCase.navigationTargets;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await Settings.init(cacheProvider: MemorySettingsCache());
    final directory = Directory.systemTemp.createTempSync(
      'pdf-reader-probe-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => directory.path,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final originalModule = Pdfrx.pdfiumModulePath;
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
    addTearDown(() => Pdfrx.pdfiumModulePath = originalModule);

    final file = File('${directory.path}/reader.pdf');
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      await writePdfProbeFixture(
        file,
        pageCount: pdfCase.pageCount,
        mixed: true,
      );
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'קורא למדידה', path: file.path),
      pageNumber: targets.initialPage,
    )..savedLayoutMode = PdfLayoutMode.regularView;
    final initialController = tab.pdfViewerController;
    final tabs = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = StubSettingsBloc();
    final tour = TourCubit();
    addTearDown(tabs.close);
    addTearDown(settings.close);
    addTearDown(tour.close);

    Future<void> advance() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    PdfBookBloc? readerBloc() {
      final builders = find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is PdfBookScreen && identical(widget.tab, tab),
        ),
        matching: find.byType(BlocBuilder<PdfBookBloc, PdfBookState>),
      );
      if (builders.evaluate().isEmpty) return null;
      return tester.element(builders.first).read<PdfBookBloc>();
    }

    final checkpoints = <String, double>{};
    await measurePdfReaderOpening(
      open: () => tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            mui.DefaultMaterialLocalizations.delegate,
          ],
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<TabsBloc>.value(value: tabs),
              BlocProvider<TourCubit>.value(value: tour),
            ],
            child: Scaffold(body: PdfBookScreen(tab: tab)),
          ),
        ),
      ),
      controllerReady: () {
        final state = readerBloc()?.state;
        if (state is PdfBookError) throw StateError(state.message);
        final ready = state is PdfBookLoaded && tab.pdfViewerController.isReady;
        if (ready) pdfCase.verifyPageCount(tab.pdfViewerController.pageCount);
        return ready;
      },
      controller: () => tab.pdfViewerController,
      pageNumber: targets.initialPage,
      nextFrame: () => tester.pump(),
      checkpointsMs: checkpoints,
      advance: advance,
    );
    final bloc = readerBloc()!;
    final controller = tab.pdfViewerController;
    final document = controller.document;
    expect(controller, isNot(same(initialController)));
    expect(document.pages, hasLength(pdfCase.pageCount));
    expect(checkpoints.keys, ['controller_ready', 'final_image_ready']);
    expect(
      checkpoints['final_image_ready'],
      greaterThanOrEqualTo(checkpoints['controller_ready']!),
    );
    expect(
      controller.visibleRenderState.value,
      PdfVisibleRenderState.ready,
    );

    for (final page in [targets.forwardPage, targets.backwardPage]) {
      await controller.goToPage(pageNumber: page, duration: Duration.zero);
      await waitForPdfFinalImage(
        controller,
        pageNumber: page,
        nextFrame: () => tester.pump(),
        advance: advance,
      );
      expect(
        controller.visibleRenderState.value,
        PdfVisibleRenderState.ready,
      );
      expect(
        controller.layout.pageLayouts[page - 1].overlaps(
          controller.visibleRect,
        ),
        isTrue,
      );
    }
    final page = targets.zoomPage;
    final zoom = controller.currentZoom;
    final targetZoom = zoom * targets.zoomFactor;
    await controller.setZoom(
      controller.layout.pageLayouts[page - 1].center,
      targetZoom,
      duration: Duration.zero,
    );
    await waitForPdfFinalImage(
      controller,
      pageNumber: page,
      nextFrame: () => tester.pump(),
      expectedZoom: targetZoom,
      advance: advance,
    );
    expect(controller.currentZoom, closeTo(targetZoom, 0.001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await waitForPdfProbeCondition(
      () => !controller.isReady && bloc.isClosed,
      'reader detached and bloc closed',
      advance: advance,
    );
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
