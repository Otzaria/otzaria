import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:printing/printing.dart';

/// עימוד לייצוא PDF של דף תוסף (`ui.exportPdf`). המידות במילימטרים;
/// שדה שלא סופק משאיר את ברירת המחדל של מנוע ההדפסה.
class PluginPdfLayout {
  final double? pageWidthMm;
  final double? pageHeightMm;

  /// שולי הדף במילימטרים (הערכים ב-[EdgeInsets] הם מ"מ, לא פיקסלים).
  final EdgeInsets? marginsMm;
  final bool? landscape;
  final bool? printBackgrounds;

  const PluginPdfLayout({
    this.pageWidthMm,
    this.pageHeightMm,
    this.marginsMm,
    this.landscape,
    this.printBackgrounds,
  });

  static const _mmPerInch = 25.4;

  /// ההמרה לתצורת ה-WebView — pageWidth/pageHeight והשוליים שם באינצ'ים.
  PDFConfiguration toPdfConfiguration() => PDFConfiguration(
    settings: PrintJobSettings(
      orientation: landscape == null
          ? null
          : (landscape!
                ? PrintJobOrientation.LANDSCAPE
                : PrintJobOrientation.PORTRAIT),
      pageWidth: pageWidthMm == null ? null : pageWidthMm! / _mmPerInch,
      pageHeight: pageHeightMm == null ? null : pageHeightMm! / _mmPerInch,
      margins: marginsMm == null
          ? null
          : EdgeInsets.fromLTRB(
              marginsMm!.left / _mmPerInch,
              marginsMm!.top / _mmPerInch,
              marginsMm!.right / _mmPerInch,
              marginsMm!.bottom / _mmPerInch,
            ),
      shouldPrintBackgrounds: printBackgrounds,
    ),
  );
}

/// מייצר PDF מתוכן WebView של תוסף — להדפסה דרך דיאלוג המערכת או לייצוא
/// לקובץ (`ui.print` / `ui.exportPdf`).
class PluginPrintService {
  const PluginPrintService();

  /// הפלטפורמות שבהן `createPdf` ממומש בצד הנייטיב של ה-WebView.
  static bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isIOS;

  /// מייצר PDF מהדף הנטען ב-[controller]. זורק אם הייצור נכשל או חזר ריק.
  Future<Uint8List> createPdf(
    InAppWebViewController controller, {
    PluginPdfLayout? layout,
  }) async {
    if (!isSupported) {
      throw Exception(
        'error.unsupported_platform: PDF generation is not supported on '
        '${Platform.operatingSystem}',
      );
    }

    final Uint8List? generated;
    try {
      generated = await controller.createPdf(
        pdfConfiguration: layout?.toPdfConfiguration(),
      );
    } catch (e) {
      throw Exception('error.internal: PDF generation failed: $e');
    }
    if (generated == null || generated.isEmpty) {
      throw Exception('error.internal: PDF generation returned no data');
    }
    return generated;
  }

  /// מדפיס את הדף הנטען ב-[controller] בשם עבודה [jobName].
  /// מחזיר האם המשתמש אישר את ההדפסה בדיאלוג המערכת.
  Future<bool> printWebView(
    InAppWebViewController controller, {
    required String jobName,
  }) async {
    final pdf = await createPdf(controller);
    return Printing.layoutPdf(
      name: jobName,
      onLayout: (_) => pdf,
      // ה-PDF כבר מעומד ע"י מנוע ה-WebView; אין מה לפרוס מחדש לפי המדפסת.
      dynamicLayout: false,
      usePrinterSettings: true,
    );
  }
}
