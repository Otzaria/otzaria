import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/printing_raster_idle.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

/// פלטפורמת הדפסה שרק שומרת את onLayout, כדי שהבדיקה תפיק את הפלט בעצמה.
class _CapturingPrintingPlatform extends PrintingPlatform {
  LayoutCallback? onLayout;
  final job = Completer<bool>();

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) {
    this.onLayout = onLayout;
    return job.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Uint8List> _fivePagePdf() {
  final doc = pw.Document();
  for (var i = 1; i <= 5; i++) {
    doc.addPage(pw.Page(build: (_) => pw.Text('page $i')));
  }
  return doc.save();
}

Future<int> _pageCount(Uint8List bytes) async {
  final doc = await PdfDocument.openData(bytes);
  try {
    return doc.pages.length;
  } finally {
    await doc.dispose();
  }
}

/// ה-worker של pdfrx נפתח בתצוגה המקדימה בתוך ה-FakeAsync, ולכן התשובות
/// שלו מתקדמות רק כשמריצים גם זמן אמיתי וגם pump.
Future<T> _settle<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  late T result;
  unawaited(
    future.then((value) {
      result = value;
      done = true;
    }),
  );
  for (var i = 0; i < 400 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  expect(done, isTrue, reason: 'הפעולה לא הסתיימה');
  return result;
}

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final originalModulePath = Pdfrx.pdfiumModulePath;
  late PrintingPlatform originalPlatform;
  late Directory tempDir;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    originalPlatform = PrintingPlatform.instance;
    tempDir = Directory.systemTemp.createTempSync('otzaria-print-output-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (_) async => tempDir.path,
        );
  });

  tearDownAll(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    PrintingPlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    tempDir.deleteSync(recursive: true);
  });

  for (final fromFile in [false, true]) {
    testWidgets(
      'שינוי הגדרה בזמן הפקת הפלט אינו מחליף את טווח העמודים (${fromFile ? 'path' : 'bytes'})',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final platform = _CapturingPrintingPlatform();
        PrintingPlatform.instance = platform;
        final settingsBloc = _MockSettingsBloc();
        whenListen(
          settingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial(),
        );

        final source = await tester.runAsync(() async {
          await pdfrxFlutterInitialize();
          return _fivePagePdf();
        });
        final sourceFile = File('${tempDir.path}/source.pdf');
        if (fromFile) {
          await tester.runAsync(() => sourceFile.writeAsBytes(source!));
        }

        await tester.pumpWidget(
          RepositoryProvider<SettingsRepository>.value(
            value: _FakeSettingsRepository(),
            child: BlocProvider<SettingsBloc>.value(
              value: settingsBloc,
              child: MaterialApp(
                // גופן הבדיקה רחב מהגופן האמיתי וגולש מפאנל ההגדרות הצר.
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(0.5)),
                  child: child!,
                ),
                home: PrintingScreen(
                  data: Future.value(''),
                  bookId: 'test',
                  createPdfOverride: fromFile ? null : (_) async => source!,
                  pdfFilePath: fromFile ? sourceFile.path : null,
                  initialPage: 2,
                ),
              ),
            ),
          ),
        );

        // ממתינים לסיום התצוגה המקדימה, שמשחררת את נעילת ה-pdfrx וקובעת את מספר העמודים.
        bool previewDone() =>
            find.byType(RawImage).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty;
        for (var i = 0; i < 200 && !previewDone(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(previewDone(), isTrue);

        await tester.tap(find.text('הדפסה'));
        await tester.pump();
        final onLayout = platform.onLayout;
        expect(onLayout, isNotNull);

        final pending = Future.value(onLayout!(PdfPageFormat.a4));
        // מריצים עד פתיחת המסמך לרסטור, ואז המשתמש משנה הגדרה באמצע הפקת הפלט.
        await tester.pump();
        tester
            .widget<AppDropdownField<PdfPageFormat>>(
              find.byType(AppDropdownField<PdfPageFormat>),
            )
            .onSelected!(PdfPageFormat.a4);
        final output = await _settle(tester, pending);
        // סוף ה-spool: ב-Windows pdfrx מושהה עד שההדפסה מסתיימת.
        platform.job.complete(false);
        await tester.pump();

        expect(await _settle(tester, _pageCount(output)), 1);

        // שינוי ההגדרה מתחיל תצוגה נוספת. הפירוק מבטל אותה, והמחסום ממתין
        // לסגירת המסמך לפני שסביבת ה-FakeAsync של הבדיקה מסתיימת.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpWidget(const SizedBox());
        await drainPrintingRasterQueue(tester);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  testWidgets('הדפסת PDF מוכן מציעה את כל גדלי הדף של הדפסת טקסט', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    final source = await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      return _fivePagePdf();
    });

    await tester.pumpWidget(
      RepositoryProvider<SettingsRepository>.value(
        value: _FakeSettingsRepository(),
        child: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(0.5)),
              child: child!,
            ),
            home: PrintingScreen(
              data: Future.value(''),
              bookId: 'test',
              createPdfOverride: (_) async => source!,
            ),
          ),
        ),
      ),
    );
    bool previewDone() =>
        find.byType(RawImage).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty;
    for (var i = 0; i < 200 && !previewDone(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(previewDone(), isTrue);

    final field = tester.widget<AppDropdownField<PdfPageFormat>>(
      find.byType(AppDropdownField<PdfPageFormat>),
    );
    expect(field.entries.map((e) => e.label), [
      'A4',
      'Letter',
      'Legal',
      'A5',
      'A3',
    ]);

    await _settle(tester, Future<void>.value());
    await tester.pumpWidget(const SizedBox());
    await drainPrintingRasterQueue(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
