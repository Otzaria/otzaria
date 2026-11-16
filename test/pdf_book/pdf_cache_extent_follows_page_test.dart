import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_settings_bloc.dart';

/// #4175: עמוד גבוה מהמסך — טווח המטמון מגיע לעמוד הבא, כדי שיוכן לפני שנראה.
void main() {
  testWidgets('טווח המטמון של הצפיין עוקב אחרי גובה העמוד בזום הנוכחי', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await Settings.init(cacheProvider: MemorySettingsCache());
    final directory = Directory.systemTemp.createTempSync('otzaria-pdf-ext-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => directory.path,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));
    final originalModulePath = Pdfrx.pdfiumModulePath;
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/${Platform.isWindows
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
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(595, i == 5 ? 920 : 842),
            build: (_) => pw.Center(child: pw.Text('$i')),
          ),
        );
      }
      File(path).writeAsBytesSync(await pdf.save());
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: path),
      pageNumber: 2,
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
        navigatorKey: navigatorKey,
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
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    PdfViewerParams params() =>
        tester.widget<PdfViewer>(find.byType(PdfViewer)).params;

    await settle();
    final controller = tab.pdfViewerController;
    expect(controller.isReady, isTrue);
    expect(
      params().behaviorControlParams.partialImageLoadingDelay,
      greaterThan(Duration.zero),
    );

    // לרוחב: העמוד גבוה מהמסך, והטווח מראש העמוד מגיע לראש העמוד הבא.
    final layouts = controller.layout.pageLayouts;
    final stride = layouts[2].top - layouts[1].top;
    expect(stride, greaterThan(controller.visibleRect.height * 1.5));
    final extent = params().verticalCacheExtent;
    expect(extent, greaterThan(1));
    expect(
      controller.visibleRect.height * (1 + extent),
      greaterThan(stride),
    );

    // עמוד שלם: חוזרים לטווח הרגיל, ולא מחזיקים עמודים רחוקים.
    final page = layouts[1];
    final fitPage = math.min(
      controller.viewSize.width / page.width,
      controller.viewSize.height / page.height,
    );
    await controller.goTo(
      controller.calcMatrixFor(page.center, zoom: fitPage * 0.95),
      duration: Duration.zero,
    );
    await settle();
    expect(params().verticalCacheExtent, 1);

    // בסוף המסמך גם הרווח שלפני הדף נדרש כדי להגיע לדף הקודם.
    final last = layouts.last;
    final previous = layouts[layouts.length - 2];
    final gap = last.top - previous.bottom;
    final visibleHeight = (last.height + gap / 2) / 2;
    await controller.goTo(
      controller.calcMatrixFor(
        Offset(last.center.dx, last.bottom - visibleHeight / 2),
        zoom: controller.viewSize.height / visibleHeight,
      ),
      duration: Duration.zero,
    );
    await settle();
    expect(controller.pageNumber, layouts.length);
    final cache = controller.visibleRect.inflate(
      controller.visibleRect.height * params().verticalCacheExtent,
    );
    expect(cache.overlaps(previous), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
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
