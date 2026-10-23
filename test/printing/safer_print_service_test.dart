import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Printer;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/plugins/services/plugin_print_service.dart';
import 'package:otzaria/printing/print_work_status.dart';
import 'package:otzaria/printing/safer_print_service.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';

class _PdfWebView extends Fake implements InAppWebViewController {
  @override
  Future<Uint8List?> createPdf({
    // ignore: deprecated_member_use
    IOSWKPDFConfiguration? iosWKPdfConfiguration,
    PDFConfiguration? pdfConfiguration,
  }) async => Uint8List.fromList([37, 80, 68, 70]);
}

class _PendingPrinting extends PrintingPlatform {
  final jobs = <Completer<bool>>[];
  final layouts = <LayoutCallback>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

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
    layouts.add(onLayout);
    final job = Completer<bool>();
    jobs.add(job);
    return job.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrintingPlatform original;
  late _PendingPrinting platform;

  setUp(() {
    original = PrintingPlatform.instance;
    platform = _PendingPrinting();
    PrintingPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() {
    PrintingPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    expect(PrintWorkStatus.hasActiveJobs, isFalse);
  });

  Future<bool> print({OnPrintSpooling? onSpooling}) => printPdfWithSaferMode(
    name: 'ספר',
    onLayout: (_) => Uint8List.fromList([37, 80, 68, 70]),
    onSpooling: onSpooling,
  );

  test('מעקב מתחיל לפני onLayout גם ללא callback ומסתיים בביטול', () async {
    final printing = print();
    expect(PrintWorkStatus.hasActiveJobs, isTrue);
    platform.jobs.single.complete(false);
    expect(await printing, isFalse);
  });

  test('מסירת PDF אינה מסיימת את המעקב או את תוצאת ההדפסה', () async {
    var spooling = 0;
    var completed = false;
    final printing = print(onSpooling: (_) => spooling++).then((result) {
      completed = true;
      return result;
    });
    await platform.layouts.single(PdfPageFormat.a4);
    await platform.layouts.single(PdfPageFormat.a5);
    expect(spooling, 1);
    expect(completed, isFalse);
    expect(PrintWorkStatus.hasActiveJobs, isTrue);
    platform.jobs.single.complete(true);
    expect(await printing, isTrue);
  });

  test('ui.print עובר במעקב בלי onSpooling ומשמר את תוצאת הביטול', () async {
    final printing = const PluginPrintService().printWebView(
      _PdfWebView(),
      jobName: 'תוסף',
    );
    await Future<void>.delayed(Duration.zero);
    expect(PrintWorkStatus.hasActiveJobs, isTrue);
    await platform.layouts.single(PdfPageFormat.a4);
    platform.jobs.single.complete(false);
    expect(await printing, isFalse);
  });

  test('עמוד אינסופי מהמדפסת מוחלף בגודל שהתבקש ונרשם ביומן (#3172)', () async {
    final received = <PdfPageFormat>[];
    final printing = printPdfWithSaferMode(
      name: 'ספר',
      format: PdfPageFormat.a5,
      usePrinterSettings: true,
      onLayout: (format) {
        received.add(format);
        return Uint8List.fromList([37, 80, 68, 70]);
      },
    );
    // כך מגיע עמוד מ-DC ש-GetDeviceCaps שלו מחזיר 0 (חלוקה ב-dpi אפס).
    await platform.layouts.single(
      const PdfPageFormat(double.infinity, double.infinity),
    );
    await platform.layouts.single(PdfPageFormat.letter);
    platform.jobs.single.complete(true);
    expect(await printing, isTrue);

    expect(received, [PdfPageFormat.a5, PdfPageFormat.letter]);
    final log = File(ErrorLogFile.resolvePath()).readAsStringSync();
    expect(log, contains('=== Printer page size'));
    expect(log, contains('unusable page size'));
  });

  test('isUsablePageFormat: מידות סופיות וחיוביות ושוליים סופיים', () {
    expect(isUsablePageFormat(PdfPageFormat.a4), isTrue);
    expect(
      isUsablePageFormat(const PdfPageFormat(double.infinity, 800)),
      isFalse,
    );
    expect(
      isUsablePageFormat(
        const PdfPageFormat(500, 800, marginLeft: double.negativeInfinity),
      ),
      isFalse,
    );
  });

  test('כשל בעבודה אחת אינו מסיר מעקב של עבודה מקבילה', () async {
    final first = print();
    final second = print();
    final error = StateError('spooler');
    final failed = expectLater(first, throwsA(same(error)));
    platform.jobs.first.completeError(error);
    await failed;
    expect(PrintWorkStatus.hasActiveJobs, isTrue);
    platform.jobs.last.complete(true);
    expect(await second, isTrue);
  });
}
