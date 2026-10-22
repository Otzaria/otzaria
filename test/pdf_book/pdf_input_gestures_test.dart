import 'dart:io';

import 'package:flutter/gestures.dart';
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
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/utils/tab_content_vertical_drag_recognizer.dart';
import 'package:otzaria/tabs/utils/touch_tab_swipe_recognizer.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final originalModulePath = Pdfrx.pdfiumModulePath;
  late Directory directory;
  late PdfBookTab tab;
  var tabSwipeUpdates = 0;
  var autoScrollDistance = 0.0;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-input-');
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
    tabSwipeUpdates = 0;
    autoScrollDistance = 0.0;
  });

  tearDown(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(condition(), isTrue);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      final source = pw.Document();
      for (var page = 0; page < 8; page++) {
        source.addPage(pw.Page(build: (_) => pw.SizedBox()));
      }
      await file.writeAsBytes(await source.save());
    });
    tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקת מחוות', path: file.path),
      pageNumber: 2,
    );
    final tabs = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = _SettingsBloc();
    final tour = TourCubit();
    addTearDown(tab.dispose);
    addTearDown(tabs.close);
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
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child: MiddleClickAutoScroll(
            child: RawGestureDetector(
              gestures: {
                TabContentVerticalDragRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      TabContentVerticalDragRecognizer
                    >(
                      TabContentVerticalDragRecognizer.new,
                      (recognizer) => recognizer.onStart = (_) {},
                    ),
                TouchTabSwipeRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      TouchTabSwipeRecognizer
                    >(
                      () => TouchTabSwipeRecognizer(
                        singleFingerPansContent: () => tab.canPanHorizontally,
                      ),
                      (recognizer) =>
                          recognizer.onUpdate = (_) => tabSwipeUpdates++,
                    ),
                HorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      HorizontalDragGestureRecognizer
                    >(
                      () => HorizontalDragGestureRecognizer(
                        supportedDevices: const {PointerDeviceKind.trackpad},
                      ),
                      (recognizer) =>
                          recognizer.onUpdate = (_) => tabSwipeUpdates++,
                    ),
              },
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      event.device == kAutoScrollSyntheticDevice) {
                    autoScrollDistance += event.scrollDelta.dy;
                  }
                },
                child: PdfBookScreen(tab: tab),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpUntil(tester, () {
      final viewer = find.byType(PdfViewer);
      if (viewer.evaluate().isEmpty || !tab.pdfViewerController.isReady) {
        return false;
      }
      final bloc = tester.element(viewer).read<PdfBookBloc>();
      return bloc.state is PdfBookLoaded;
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tab.pdfViewerController.goToPage(
      pageNumber: 2,
      duration: Duration.zero,
    );
    await tester.pump();
    addTearDown(() => finish(tester));
  }

  Future<void> wheel(WidgetTester tester, {double delta = 120}) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(PdfViewer)),
        scrollDelta: Offset(0, delta),
      ),
    );
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('גלגלת גוללת ברצף בתוך העמוד וממשיכה אחרי idle ו-resume', (
    tester,
  ) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    final initial = controller.visibleRect.top;
    await wheel(tester);
    final first = controller.visibleRect.top;
    expect(first, greaterThan(initial));
    expect(first - initial, lessThan(controller.layout.pageLayouts[1].height));
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.hidden,
    );
    await tester.pump(const Duration(hours: 8));
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();
    final resumed = controller.visibleRect.top;
    await wheel(tester);
    expect(controller.visibleRect.top, greaterThan(resumed));
    await controller.goToPage(pageNumber: 5, duration: Duration.zero);
    await tester.pump();
    expect(controller.pageNumber, 5);
    await finish(tester);
  });

  testWidgets('מגע אנכי מזיז PDF רחב בלי מעבר טאב', (tester) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    await controller.setZoom(
      controller.centerPosition,
      controller.currentZoom * 2,
      duration: Duration.zero,
    );
    await tester.pump();
    expect(tab.canPanHorizontally, isTrue);
    final initial = controller.visibleRect;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PdfViewer)),
      kind: PointerDeviceKind.touch,
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.visibleRect.top, greaterThan(initial.top));
    expect(controller.visibleRect.left, closeTo(initial.left, 0.1));
    expect(tabSwipeUpdates, 0);
    await gesture.up();
    await finish(tester);
  });

  testWidgets('צביטת לוח מגע שומרת על הנקודה שמתחת לסמן', (tester) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    final viewer = find.byType(PdfViewer);
    final global = tester.getCenter(viewer) + const Offset(-80, 60);
    final local = global - tester.getTopLeft(viewer);
    final documentPoint = controller.localToDocument(local);
    final zoom = controller.currentZoom;
    await tester.sendEventToBinding(
      PointerScaleEvent(position: global, scale: 1.5),
    );
    await tester.pump();
    expect(controller.currentZoom, greaterThan(zoom));
    expect(
      (controller.localToDocument(local) - documentPoint).distance,
      lessThan(1),
    );
    expect(tabSwipeUpdates, 0);
    await finish(tester);
  });

  testWidgets('צביטת מגע עם הזזה מגדילה את ה-PDF בלי מעבר טאב', (
    tester,
  ) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    final viewer = find.byType(PdfViewer);
    final center = tester.getCenter(viewer);
    final halfWidth = tester.getSize(viewer).width * 0.4;
    final initialZoom = controller.currentZoom;
    final left = await tester.startGesture(
      center - Offset(halfWidth, 0),
      pointer: 1,
    );
    final right = await tester.startGesture(
      center + Offset(halfWidth, 0),
      pointer: 2,
    );
    for (var step = 0; step < 8; step++) {
      await left.moveBy(const Offset(5, 0));
      await right.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.currentZoom, greaterThan(initialZoom));
    expect(tabSwipeUpdates, 0);
    await left.up();
    await right.up();
    await finish(tester);
  });

  testWidgets('גלילה וצביטה מדויקות ב-trackpad אינן מעבירות טאב', (
    tester,
  ) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    final center = tester.getCenter(find.byType(PdfViewer));
    final initialTop = controller.visibleRect.top;
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center);
    for (var step = 1; step <= 8; step++) {
      await gesture.panZoomUpdate(center, pan: Offset(0, -10.0 * step));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.panZoomEnd();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.visibleRect.top, greaterThan(initialTop));
    final zoom = controller.currentZoom;
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, scale: 1.1);
    await gesture.panZoomUpdate(center, scale: 1.4);
    await gesture.panZoomEnd();
    await tester.pump();
    expect(controller.currentZoom, greaterThan(zoom));
    expect(tabSwipeUpdates, 0);
    await finish(tester);
  });

  testWidgets('לחיצה אמצעית מפעילה את הגלילה הגלובלית ב-PDF', (tester) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    final initial = controller.visibleRect.top;
    final center = tester.getCenter(find.byType(PdfViewer));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.down(center);
    await tester.pump();
    await gesture.moveTo(center + const Offset(0, 120));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.visibleRect.top, greaterThan(initial));
    await gesture.up();
    await finish(tester);
  });

  testWidgets('trackpad שמתחיל בהזזה קצרה עדיין יכול לצבוט באותה מחווה', (
    tester,
  ) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    await controller.setZoom(
      controller.centerPosition,
      controller.currentZoom * 2,
      duration: Duration.zero,
    );
    await tester.pump();
    final center = tester.getCenter(find.byType(PdfViewer));
    final zoom = controller.currentZoom;
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, pan: const Offset(0, -8));
    await tester.pump(const Duration(milliseconds: 300));
    final localCenter = center - tester.getTopLeft(find.byType(PdfViewer));
    // הסמן לא זז במחוות לוח מגע - הזום מעוגן לנקודה שמתחתיו בתחילת הצביטה.
    final anchor = controller.localToDocument(localCenter);
    for (final (pan, scale) in [
      (const Offset(4, -12), 1.1),
      (const Offset(8, -20), 1.4),
      (const Offset(12, -24), 1.0),
      (const Offset(15, -30), 0.8),
    ]) {
      await gesture.panZoomUpdate(center, pan: pan, scale: scale);
      final target = localCenter + pan - const Offset(0, -8);
      expect(controller.currentZoom, closeTo(zoom * scale, 0.000001));
      expect(
        (controller.documentToLocal(anchor) - target).distance,
        lessThan(0.001),
        reason:
            'scale=$scale point=${controller.documentToLocal(anchor)} target=$target',
      );
      expect(tabSwipeUpdates, 0);
    }
    await gesture.panZoomEnd();
    await finish(tester);
  });

  for (final interruptedScale in [1.0, 1.2]) {
    testWidgets(
      'מחוות trackpad חדשה אחרי resume אינה יורשת נעילת ציר ישנה: scale=$interruptedScale',
      (
        tester,
      ) async {
        await pumpScreen(tester);
        final controller = tab.pdfViewerController;
        await controller.setZoom(
          controller.centerPosition,
          controller.currentZoom * 2,
          duration: Duration.zero,
        );
        await tester.pump();
        final center = tester.getCenter(find.byType(PdfViewer));
        final interrupted = await tester.createGesture(
          pointer: 21,
          kind: PointerDeviceKind.trackpad,
        );
        final next = await tester.createGesture(
          pointer: 22,
          kind: PointerDeviceKind.trackpad,
        );
        try {
          await interrupted.panZoomStart(center);
          await interrupted.panZoomUpdate(center, pan: const Offset(80, 0));
          await tester.pump(const Duration(milliseconds: 300));
          if (interruptedScale != 1) {
            await interrupted.panZoomUpdate(
              center,
              pan: const Offset(80, 0),
              scale: interruptedScale,
            );
            await tester.pump();
          }
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          await tester.pump(const Duration(hours: 8));
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          final top = controller.visibleRect.top;
          await next.panZoomStart(center);
          await next.panZoomUpdate(center, pan: const Offset(0, -80));
          await tester.pump(const Duration(milliseconds: 300));
          expect(controller.visibleRect.top, greaterThan(top));
        } finally {
          await next.panZoomEnd();
          await interrupted.panZoomEnd();
          await finish(tester);
        }
      },
    );
  }

  // גלגלת בספר טקסט זזה 1:1 עם scrollDelta, ו-PDF זז באותו מרחק (issue #2960).
  testWidgets('גלגלת מזיזה את ה-PDF כמו ספר טקסט, 1:1 עם scrollDelta', (
    tester,
  ) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    final top = controller.value.getTranslation().y;
    await wheel(tester, delta: 100);
    expect(top - controller.value.getTranslation().y, closeTo(100, 1));
    await finish(tester);
  });

  testWidgets('Ctrl+גלגלת מגדיל את ה-PDF פעם אחת לכל אירוע', (tester) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    final dampening = tester
        .widget<PdfViewer>(find.byType(PdfViewer))
        .params
        .scaleByPointerScale;
    final zoom = controller.currentZoom;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await wheel(tester, delta: -120);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      controller.currentZoom / zoom,
      closeTo((1.2 - 1) * dampening + 1, 0.001),
    );
    await finish(tester);
  });

  testWidgets('נעילת הציר חלה על כל תנועת הגלגלת', (tester) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    await controller.setZoom(
      controller.centerPosition,
      controller.currentZoom * 2,
      duration: Duration.zero,
    );
    await tester.pump();
    final start = controller.value.getTranslation();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(PdfViewer)),
        scrollDelta: const Offset(30, 100),
      ),
    );
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final end = controller.value.getTranslation();
    expect(start.y - end.y, closeTo(100, 1));
    expect(end.x, closeTo(start.x, 0.5));
    await finish(tester);
  });

  testWidgets('גלילה אוטומטית ב-PDF זזה כמו בטקסט, 1:1 עם האירועים', (
    tester,
  ) async {
    await pumpScreen(tester);
    final controller = tab.pdfViewerController;
    final top = controller.value.getTranslation().y;
    final center = tester.getCenter(find.byType(PdfViewer));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.down(center);
    await tester.pump();
    await gesture.up();
    await gesture.moveTo(center + const Offset(0, 100));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.down(center);
    await tester.pump();
    await gesture.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(autoScrollDistance, greaterThan(50));
    expect(
      top - controller.value.getTranslation().y,
      closeTo(autoScrollDistance, 1),
    );
    await finish(tester);
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
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
