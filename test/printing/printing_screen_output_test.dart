import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:ffi/ffi.dart' show using;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/view/widgets/printing_widgets.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
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

typedef _Placement = ({Size page, Size cell});

/// גודל כל עמוד בגיליון הראשון של התצוגה המקדימה, ושל התא שהוא ממורכז בו.
List<_Placement> _previewFirstSheet(WidgetTester tester, int cells) => [
  for (var i = 0; i < cells; i++)
    (
      page: tester.getSize(find.byType(RawImage).at(i)),
      cell: tester.getSize(
        find
            .ancestor(
              of: find.byType(RawImage).at(i),
              matching: find.byType(Center),
            )
            .first,
      ),
    ),
];

/// גודל כל עמוד בגיליון הראשון של [pdf]. PDFium ממרכז את העמוד בתאו, ולכן
/// היסט המטריצה מקצה התא הוא הרווח הריק משני צדי העמוד.
Future<List<_Placement>> _pdfFirstSheet(
  Uint8List pdf,
  int rows,
  int cols,
) async {
  final doc = await PdfDocument.openData(pdf);
  try {
    final sheet = doc.pages.first.size;
    final cell = Size(sheet.width / cols, sheet.height / rows);
    return await doc.useNativeDocumentHandle((handle) {
      final pdfium = pdfium_bindings.getPdfium(
        modulePath: Pdfrx.pdfiumModulePath,
      );
      final page = pdfium.FPDF_LoadPage(
        pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle),
        0,
      );
      try {
        return using((arena) {
          final matrix = arena<pdfium_bindings.FS_MATRIX>();
          final left = arena<Float>();
          final bottom = arena<Float>();
          final right = arena<Float>();
          final top = arena<Float>();
          final placements = <_Placement>[];
          for (var i = 0; i < pdfium.FPDFPage_CountObjects(page); i++) {
            final object = pdfium.FPDFPage_GetObject(page, i);
            if (pdfium.FPDFPageObj_GetType(object) !=
                    pdfium_bindings.FPDF_PAGEOBJ_FORM ||
                pdfium.FPDFPageObj_GetMatrix(object, matrix) == 0 ||
                pdfium.FPDFPageObj_GetBounds(
                      object,
                      left,
                      bottom,
                      right,
                      top,
                    ) ==
                    0) {
              continue;
            }
            // התא לפי מרכז התוכן; הרווח מקצה התא נמדד ממטריצת העמוד.
            final col = ((left.value + right.value) / 2 / cell.width).floor();
            final row = ((bottom.value + top.value) / 2 / cell.height).floor();
            final sideGap = matrix.ref.e - col * cell.width;
            final verticalGap = matrix.ref.f - row * cell.height;
            placements.add((
              page: Size(
                cell.width - 2 * sideGap,
                cell.height - 2 * verticalGap,
              ),
              cell: cell,
            ));
          }
          return placements;
        });
      } finally {
        pdfium.FPDF_ClosePage(page);
      }
    });
  } finally {
    await doc.dispose();
  }
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

  // עמוד הטקסט נוצר בכיוון התא שלו בגיליון, ולא בכיוון הגיליון: בשני עמודים
  // לרוחב התאים לאורך. בגיליון לאורך התא צר, ועמוד לאורך ממלא רק את רוחבו.
  for (final (pagesPerSheet, orientation, expected, commentaryTab) in [
    (2, pw.PageOrientation.portrait, 'portrait 1.00x0.50', false),
    (2, pw.PageOrientation.landscape, 'portrait 1.00x1.00', false),
    (4, pw.PageOrientation.landscape, 'landscape 1.00x1.00', false),
    (2, pw.PageOrientation.landscape, 'portrait 1.00x1.00', true),
  ]) {
    testWidgets(
      '${commentaryTab ? 'כרטיסיית המפרשים, ' : ''}$pagesPerSheet עמודים בגיליון ${orientation == pw.PageOrientation.landscape ? 'לרוחב' : 'לאורך'}: '
      'עמוד הטקסט בכיוון התא, בתצוגה המקדימה ובפלט (issue #3184)',
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
        await tester.runAsync(pdfrxFlutterInitialize);
        final lines = ['ספר', for (var i = 1; i <= 200; i++) 'שורה $i בספר'];
        bool previewShows(int pages) =>
            find.byType(RawImage).evaluate().length >= pages &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty;
        Future<void> waitForPreview(int pages) async {
          await tester.pump(const Duration(milliseconds: 300));
          for (var i = 0; i < 400 && !previewShows(pages); i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump();
          }
          expect(previewShows(pages), isTrue);
        }

        Future<void> setPagesPerSheet(int value) {
          tester
              .widget<PrintingPagesPerSheetDropdownRow>(
                find.byType(PrintingPagesPerSheetDropdownRow),
              )
              .onChanged(value);
          return waitForPreview(value);
        }

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
                  data: Future.value(commentaryTab ? '' : lines.join('\n')),
                  bookId: 'test',
                  startLine: 1,
                  endLine: lines.length,
                  prebuiltBlocks: commentaryTab
                      ? [
                          for (final line in lines)
                            PrintBlock(
                              kind: PrintBlockKind.commentary,
                              text: line,
                            ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        );
        await waitForPreview(1);
        tester
            .widget<PrintingOrientationDropdownRow>(
              find.byType(PrintingOrientationDropdownRow),
            )
            .onChanged(orientation);
        await waitForPreview(1);
        // מספר העמודים בגיליון משתנה אחרי שהתצוגה בכיוון הזה כבר מוכנה.
        await setPagesPerSheet(pagesPerSheet);
        final preview = _previewFirstSheet(tester, pagesPerSheet);

        await tester.tap(find.text('הדפסה'));
        await tester.pump();
        final output = await _settle(
          tester,
          Future.value(platform.onLayout!(PdfPageFormat.a4)),
        );
        platform.job.complete(false);
        await tester.pump();
        final rows = pagesPerSheet == 4 ? 2 : 1;
        final saved = await _settle(
          tester,
          _pdfFirstSheet(output, rows, pagesPerSheet ~/ rows),
        );
        // כיוון העמוד, והחלק שהוא ממלא מרוחב התא ומגובהו.
        String fit(_Placement p) =>
            '${p.page.width > p.page.height ? 'landscape' : 'portrait'} '
            '${(p.page.width / p.cell.width).toStringAsFixed(2)}x'
            '${(p.page.height / p.cell.height).toStringAsFixed(2)}';
        expect(
          {
            'preview': [...preview.map(fit)],
            'pdf': [...saved.map(fit)],
          },
          {
            'preview': List.filled(pagesPerSheet, expected),
            'pdf': List.filled(pagesPerSheet, expected),
          },
        );

        // בחזרה לעמוד אחד בגיליון העמוד שוב בכיוון הגיליון.
        await setPagesPerSheet(1);
        final single = tester.getSize(find.byType(RawImage).first);
        expect(
          single.width > single.height,
          orientation == pw.PageOrientation.landscape,
        );

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpWidget(const SizedBox());
        await drainPrintingRasterQueue(tester);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  for (final prebuilt in [false, true]) {
    for (final initialPages in [1, 2]) {
      testWidgets(
        'שינוי מ-$initialPages ל-${3 - initialPages} עמודים בזמן טעינת נתוני ${prebuilt ? 'מפרשים' : 'טקסט'} שומר את כיוון המשימה',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final pendingNames = Completer<DivineNameSpans>();
          addTearDown(() {
            if (!pendingNames.isCompleted) {
              pendingNames.complete(DivineNameSpans.empty);
            }
          });
          final lines = ['ספר', for (var i = 1; i <= 100; i++) 'שורת בדיקה $i'];
          DivineNamesRepository.instance.clear();
          BookNotesRepository.instance.clear();
          DivineNamesRepository.instance.debugLoader =
              (
                title, {
                categoryId,
                required source,
              }) => pendingNames.future;
          BookNotesRepository.instance.debugLoader =
              (
                title, {
                categoryId,
                required source,
              }) async => BookNotes.empty;
          addTearDown(() {
            DivineNamesRepository.instance
              ..debugLoader = null
              ..clear();
            BookNotesRepository.instance
              ..debugLoader = null
              ..clear();
          });
          final platform = _CapturingPrintingPlatform();
          PrintingPlatform.instance = platform;
          addTearDown(() async {
            if (!platform.job.isCompleted) platform.job.complete(false);
            await tester.pumpWidget(const SizedBox());
            await drainPrintingRasterQueue(tester);
          });
          final settingsBloc = _MockSettingsBloc();
          whenListen(
            settingsBloc,
            const Stream<SettingsState>.empty(),
            initialState: SettingsState.initial(),
          );
          await tester.runAsync(pdfrxFlutterInitialize);
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
                    data: Future.value(lines.join('\n')),
                    prebuiltBlocks: prebuilt
                        ? [
                            for (final line in lines)
                              PrintBlock(
                                kind: PrintBlockKind.commentary,
                                text: line,
                              ),
                          ]
                        : null,
                    startLine: 1,
                    endLine: 101,
                    bookId: 'ספר בדיקה',
                    book: TextBook(title: 'ספר בדיקה'),
                    protection: BookProtection.none,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          tester
              .widget<PrintingOrientationDropdownRow>(
                find.byType(PrintingOrientationDropdownRow),
              )
              .onChanged(pw.PageOrientation.landscape);
          void setPages(int value) => tester
              .widget<PrintingPagesPerSheetDropdownRow>(
                find.byType(PrintingPagesPerSheetDropdownRow),
              )
              .onChanged(value);
          setPages(initialPages);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('הדפסה'));
          await tester.pump();
          expect(platform.onLayout, isNotNull);
          var outputReady = false;
          final pendingOutput = Future.value(
            platform.onLayout!(PdfPageFormat.a4),
          )..then((_) => outputReady = true);
          await tester.pump(const Duration(milliseconds: 50));
          expect(
            outputReady,
            isFalse,
            reason: 'נתוני הספר עדיין ממתינים בזמן שינוי ההגדרות.',
          );
          setPages(3 - initialPages);
          await tester.pump(const Duration(milliseconds: 300));
          expect(outputReady, isFalse);
          pendingNames.complete(DivineNameSpans.empty);
          final output = await _settle(tester, pendingOutput);
          platform.job.complete(false);
          await tester.pump();
          Future<void> expectGeometry(Uint8List bytes, int pages) async {
            final document = await _settle(tester, PdfDocument.openData(bytes));
            final sheet = document.pages.first.size;
            await _settle(tester, document.dispose());
            expect(sheet.width, closeTo(PdfPageFormat.a4.landscape.width, 0.1));
            expect(
              sheet.height,
              closeTo(PdfPageFormat.a4.landscape.height, 0.1),
            );
            if (pages == 2) {
              final placements = await _settle(
                tester,
                _pdfFirstSheet(bytes, 1, 2),
              );
              expect(placements, hasLength(2));
              for (final placement in placements) {
                expect(
                  placement.page.width,
                  closeTo(placement.cell.width, 0.1),
                );
                expect(
                  placement.page.height,
                  closeTo(placement.cell.height, 0.1),
                );
              }
            }
          }

          await expectGeometry(output, initialPages);
          final nextOutput = await _settle(
            tester,
            Future.value(platform.onLayout!(PdfPageFormat.a4)),
          );
          await expectGeometry(nextOutput, 3 - initialPages);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  }
}
