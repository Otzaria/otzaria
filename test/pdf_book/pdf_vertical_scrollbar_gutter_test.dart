import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_scrollbar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/pdf_viewer_mounted.dart';
import '../test_helpers/pdf_document_dispose.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  testWidgets('תעלת הגלילה מופרדת מהדף ושומרת על יישור הדפדוף (#4485)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await Settings.init(cacheProvider: MemorySettingsCache());
    final directory = Directory.systemTemp.createTempSync('otzaria-4485-');
    addTearDown(() => directory.deleteSync(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final originalModulePath = Pdfrx.pdfiumModulePath;
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/'
      '${Platform.isWindows
          ? 'pdfium.dll'
          : Platform.isMacOS
          ? 'libpdfium_dart.dylib'
          : 'libpdfium.so'}',
    ).absolute.path;
    addTearDown(() => Pdfrx.pdfiumModulePath = originalModulePath);

    final path = '${directory.path}/book.pdf';
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 6; i++) {
        pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('$i'))));
      }
      File(path).writeAsBytesSync(await pdf.save());
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר', path: path),
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
    final bloc = await pumpUntilPdfViewer(tester);
    final track = find.descendant(
      of: find.byType(PdfScrollbar),
      matching: find.byType(GestureDetector),
    );
    for (
      var i = 0;
      i < 200 && (bloc.state is! PdfBookLoaded || track.evaluate().isEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    final document = tab.pdfViewerController.document;

    expect(track, findsWidgets);
    final trackRect = tester.getRect(track.first);
    final viewerRect = tester.getRect(find.byType(PdfViewer));
    expect(trackRect.width, greaterThan(0));
    // הסרגל בתעלה משלו מימין לצפיין, ולא מעל הדף עצמו.
    expect(viewerRect.right, lessThanOrEqualTo(trackRect.left));

    Future<void> nextFrame() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }

    bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
    for (var i = 0; i < 60; i++) {
      await nextFrame();
    }
    await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);

    final animation = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() ==
              '_BookPageTurnBackgroundPainter',
    );
    ui.Image? source;
    ui.Image? target;
    for (var i = 0; i < 100 && target == null; i++) {
      await nextFrame();
      if (animation.evaluate().isEmpty) continue;
      final dynamic painter = tester.widget<CustomPaint>(animation).painter;
      source = painter.snapshot as ui.Image;
      target = painter.targetSnapshot as ui.Image?;
    }
    expect(target, isNotNull);
    expect((target!.width, target.height), (source!.width, source.height));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
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
