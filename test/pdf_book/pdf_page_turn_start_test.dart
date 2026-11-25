import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/utils/pdf_image_budget.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart'
    show PdfLayoutMode;
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/pdf.dart' show PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/pdf_viewer_mounted.dart';
import '../test_helpers/pdf_document_dispose.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  for (final cancelQueuedTurn in [false, true]) {
    testWidgets(
      cancelQueuedTurn
          ? 'שחרור מקש בזמן הכנת היעד מחזיר משך דפדוף מלא'
          : 'לחיצה בזמן הכנת היעד מקצרת את הדפדוף שעומד להתחיל',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await Settings.init(cacheProvider: MemorySettingsCache());
        await Settings.setValue(
          SettingsRepository.keyPdfBookViewByDefault,
          true,
        );
        await Settings.setValue(
          SettingsRepository.keyEnablePerBookSettings,
          false,
        );
        final directory = Directory.systemTemp.createTempSync(
          'pdf-turn-start-',
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

        final file = File('${directory.path}/book.pdf');
        await tester.runAsync(() async {
          await pdfrxFlutterInitialize();
          final pdf = pw.Document();
          for (var page = 1; page <= 8; page++) {
            pdf.addPage(
              pw.Page(
                pageFormat: const PdfPageFormat(200, 300),
                build: (_) => pw.Center(
                  child: pw.Container(
                    width: 100,
                    height: page * 20.0,
                    color: PdfColors.black,
                  ),
                ),
              ),
            );
          }
          await file.writeAsBytes(await pdf.save());
        });
        final tab = PdfBookTab(
          book: PdfBook(title: 'בדיקת קלט בזמן הכנת דפדוף', path: file.path),
          pageNumber: 1,
        );
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

        Future<void> frame() async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }

        Future<void> until(bool Function() ready, String reason) async {
          for (var i = 0; i < 300 && !ready(); i++) {
            await frame();
          }
          expect(ready(), isTrue, reason: reason);
        }

        final overlay = find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter.runtimeType.toString() ==
                  '_BookPageTurnBackgroundPainter',
        );
        PdfDocument? document;
        final originalImageCallback = ui.Image.onCreate;
        try {
          await tester.pumpWidget(
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
          );
          final bloc = await pumpUntilPdfViewer(tester);
          await until(
            () =>
                tab.pdfViewerController.isReady &&
                tab.pdfViewerController.visibleRenderState.value ==
                    PdfVisibleRenderState.ready &&
                pdfSharedImageBudget.pendingBytes == 0,
            'The native reader did not become ready',
          );
          document = tab.pdfViewerController.document;
          expect(
            (bloc.state as PdfBookLoaded).layoutMode,
            PdfLayoutMode.bookView,
          );
          for (var i = 0; i < 20; i++) {
            await frame();
          }
          final input = tester
              .widgetList<Focus>(
                find.ancestor(
                  of: find.byType(PdfViewer),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Focus &&
                        widget.onKeyEvent != null &&
                        widget.focusNode != null,
                  ),
                ),
              )
              .first;
          void send(KeyEvent event) {
            expect(
              input.onKeyEvent!(input.focusNode!, event),
              KeyEventResult.handled,
            );
          }

          const down = KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.pageDown,
            logicalKey: LogicalKeyboardKey.pageDown,
            timeStamp: Duration.zero,
          );
          const repeat = KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.pageDown,
            logicalKey: LogicalKeyboardKey.pageDown,
            timeStamp: Duration.zero,
          );
          const up = KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.pageDown,
            logicalKey: LogicalKeyboardKey.pageDown,
            timeStamp: Duration.zero,
          );
          AnimationController? turn;
          var inputDuringComposition = false;
          ui.Image.onCreate = (image) {
            originalImageCallback?.call(image);
            if (inputDuringComposition || overlay.evaluate().isEmpty) return;
            final dynamic painter = tester.widget<CustomPaint>(overlay).painter;
            final source = painter.snapshot as ui.Image;
            if (painter.targetSnapshot != null ||
                image.isCloneOf(source) ||
                image.width != source.width ||
                image.height != source.height) {
              return;
            }
            final builder = tester.widget<AnimatedBuilder>(
              find
                  .ancestor(of: overlay, matching: find.byType(AnimatedBuilder))
                  .first,
            );
            turn = builder.animation as AnimationController;
            expect(turn!.isAnimating, isFalse);
            expect(turn!.value, 0);
            inputDuringComposition = true;
            // הקלט מגיע בזמן יצירת תמונת היעד, לפני השלמת ה־await שלה.
            if (!cancelQueuedTurn) send(down);
            send(up);
          };

          send(down);
          if (cancelQueuedTurn) {
            send(repeat);
          } else {
            send(up);
          }
          await until(
            () => inputDuringComposition && turn!.isAnimating,
            'The test did not insert input before the native page turn started',
          );
          expect(
            turn!.duration,
            Duration(milliseconds: cancelQueuedTurn ? 500 : 250),
            reason: 'Duration must use the queue after snapshot preparation',
          );
          await until(
            () =>
                overlay.evaluate().isEmpty &&
                tab.pdfViewerController.pageNumber ==
                    (cancelQueuedTurn ? 2 : 4) &&
                tab.pdfViewerController.visibleRenderState.value ==
                    PdfVisibleRenderState.ready,
            'The reader did not preserve the queued navigation target',
          );
          expect(tester.takeException(), isNull);
        } finally {
          ui.Image.onCreate = originalImageCallback;
          await tester.pumpWidget(const SizedBox.shrink());
          if (document != null) await disposePdfDocument(tester, document);
          await until(
            () => pdfSharedImageBudget.pendingBytes == 0,
            'The page turn left native image reservations pending',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
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
