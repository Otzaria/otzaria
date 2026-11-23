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
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/pdf_book/models/pdf_book_render_observation.dart';
import 'package:otzaria/pdf_book/view/book_view_turn_button.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../integration_test/support/perf_pdf_reader.dart';
import '../../../integration_test/support/perf_pdf_book_reader.dart';
import '../../../tool/perf_probe/make_pdf_print_preview_fixtures.dart';
import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/pdf_document_dispose.dart';
import '../../test_helpers/stub_settings_bloc.dart';

void main() {
  testWidgets(
    'book readiness waits for real PDFium and queued reverse-turn layers',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await Settings.init(cacheProvider: MemorySettingsCache());
      await Settings.setValue(
        SettingsRepository.keyPdfBookViewByDefault,
        true,
      );
      final directory = Directory.systemTemp.createTempSync(
        'pdf-book-reader-probe-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
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
        await writePdfProbeFixture(file, pageCount: 10, mixed: true);
      });
      final tab = PdfBookTab(
        book: PdfBook(title: 'קורא למדידה', path: file.path),
        pageNumber: 2,
      )..savedLayoutMode = PdfLayoutMode.bookView;
      final initialController = tab.pdfViewerController;
      final tabs = TabsBloc(repository: _TabsRepository());
      // ignore: invalid_use_of_visible_for_testing_member
      tabs.emit(TabsState(tabs: [tab], currentTabIndex: 0));
      final settings = StubSettingsBloc(
        SettingsState.initial().copyWith(pdfBookViewByDefault: true),
      );
      final tour = TourCubit();
      addTearDown(tabs.close);
      addTearDown(settings.close);
      addTearDown(tour.close);

      var sawTransitionOverlay = false;
      PdfBookRenderObservation? observe() {
        final elements = find.byType(PdfBookScreen).evaluate();
        if (elements.isEmpty) return null;
        return PdfBookScreen.renderObservationOf(elements.single);
      }

      Future<void> advance() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        sawTransitionOverlay |= observe()?.hasTransitionOverlay ?? false;
      }

      Future<PdfBookRenderObservation> waitForBook(
        int page, {
        Duration timeout = const Duration(seconds: 45),
      }) {
        final controller = tab.pdfViewerController;
        final document = controller.isReady ? controller.document : null;
        return waitForPdfBookFinalImage(
          pageNumber: page,
          ownershipIsCurrent: () =>
              document != null &&
              identical(controller, tab.pdfViewerController) &&
              controller.isReady &&
              identical(controller.document, document),
          observe: observe,
          nextFrame: () => tester.pump(),
          timeout: timeout,
          advance: advance,
        );
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
          return state is PdfBookLoaded &&
              tab.pdfViewerController.isReady &&
              (observe()?.layoutReady ?? false);
        },
        controller: () => tab.pdfViewerController,
        pageNumber: 2,
        nextFrame: () => tester.pump(),
        checkpointsMs: checkpoints,
        advance: advance,
        waitForFinalImage: (remaining) async {
          await waitForBook(2, timeout: remaining);
        },
      );
      final bloc = readerBloc()!;
      final controller = tab.pdfViewerController;
      final document = controller.document;
      expect(controller, isNot(same(initialController)));
      expect(document.pages, hasLength(10));
      expect(checkpoints.keys, ['controller_ready', 'final_image_ready']);
      expect(
        checkpoints['final_image_ready'],
        greaterThanOrEqualTo(checkpoints['controller_ready']!),
      );
      expect(controller.visibleRenderState.value, PdfVisibleRenderState.ready);

      final element = tester.element(find.byType(PdfBookScreen));
      expect(observe()!.finalImageReadyFor(2), isTrue);
      expect(observe()!.finalImageReadyFor(8), isFalse);
      expect(observe()!.visiblePages, containsAll([2, 3]));
      final next = tester
          .widget<BookViewTurnButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is BookViewTurnButton &&
                  widget.tooltip == 'הפוך דף קדימה',
            ),
          )
          .onPressed;
      final previous = tester
          .widget<BookViewTurnButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is BookViewTurnButton &&
                  widget.tooltip == 'הפוך דף אחורה',
            ),
          )
          .onPressed;
      next();
      // Capture/render is asynchronous; the live viewer may still be ready for
      // the previous spread, but it is already owned by an active page turn.
      expect(observe()!.pageTurnActive, isTrue);
      expect(observe()!.finalImageReadyFor(2), isFalse);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      previous();
      final finalState = await waitForBook(2);
      expect(sawTransitionOverlay, isTrue);
      expect(finalState.visiblePages, containsAll([2, 3]));
      expect(finalState.queuedTurns, 0);
      expect(finalState.pageTurnActive, isFalse);
      expect(finalState.animationRunning, isFalse);
      expect(finalState.hasTransitionOverlay, isFalse);
      expect(finalState.finalImageReadyFor(2), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await waitForPdfProbeCondition(
        () => !controller.isReady && bloc.isClosed,
        'reader detached and bloc closed',
        advance: advance,
      );
      expect(PdfBookScreen.renderObservationOf(element), isNull);
      await disposePdfDocument(tester, document);
    },
  );
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}
