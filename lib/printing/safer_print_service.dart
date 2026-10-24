import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:otzaria/printing/safer_printer_filter.dart';
import 'package:otzaria/printing/print_work_status.dart';
import 'package:otzaria/printing/windows_printer_ports.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

/// נקרא פעם אחת, כשה-PDF נמסר להדפסה; [printerName] — כשהמדפסת ידועה מראש.
typedef OnPrintSpooling = void Function(String? printerName);

/// שולח PDF להדפסה. מחוץ למצב סייפר — דיאלוג ההדפסה של המערכת, כרגיל.
/// במצב סייפר הדיאלוג הזה מוביל לסייר הקבצים (Print to PDF, "הדפס לקובץ",
/// "הוסף מדפסת"), ולכן הבחירה נעשית בתוך התוכנה, מתוך מדפסות הנייר בלבד,
/// וההדפסה ישירה. דיאלוג המערכת נפתח בסייפר רק אחרי סיסמה.
///
/// מחזיר האם ההדפסה נשלחה. [context] — לבדיקת מצב הסייפר ולדיאלוגים;
/// כשלא סופק משתמשים בחלון הפעיל בתחילת הפעולה. [onSpooling] נקרא רק ב-Windows: שם
/// onLayout מגיע אחרי אישור המשתמש, ובמקומות אחרים לפני תצוגה מקדימה.
Future<bool> printPdfWithSaferMode({
  required LayoutCallback onLayout,
  required String name,
  PdfPageFormat format = PdfPageFormat.standard,
  bool dynamicLayout = true,
  bool usePrinterSettings = false,
  BuildContext? context,
  int? ownerWindowHandle,
  int? ownerViewId,
  OnPrintSpooling? onSpooling,
}) async {
  final requestedFormat = format;
  // דרייבר שלא מדווח את מידות ההתקן נותן עמוד NaN או אינסופי, ו-pdf מניח עמוד
  // סופי (#3172). מדפיסים בגודל שהתבקש, ורושמים מה המדפסת החזירה.
  FutureOr<Uint8List> layout(PdfPageFormat printerFormat) {
    if (isUsablePageFormat(printerFormat)) return onLayout(printerFormat);
    ErrorLogFile.append(
      title: 'Printer page size',
      error: 'The printer reported an unusable page size: $printerFormat',
      details: {'Used instead': '$requestedFormat'},
    );
    return onLayout(requestedFormat);
  }

  LayoutCallback reportSpooling(String? printerName) {
    if (onSpooling == null || defaultTargetPlatform != TargetPlatform.windows) {
      return layout;
    }
    var reported = false;
    return (format) async {
      final bytes = await layout(format);
      if (!reported) {
        reported = true;
        onSpooling(printerName);
      }
      return bytes;
    };
  }

  final effectiveContext = context ?? navigatorKey.currentContext;
  if (effectiveContext != null && !effectiveContext.mounted) return false;
  final viewId =
      ownerViewId ??
      (effectiveContext == null
          ? null
          : View.maybeOf(effectiveContext)?.viewId);
  final owner =
      ownerWindowHandle ??
      DialogOwner.hwnd(context: effectiveContext) ??
      (effectiveContext != null ? 0 : null);
  if (effectiveContext == null ||
      !shouldRequireSaferModePassword(effectiveContext)) {
    return PrintWorkStatus.track(
      () => Printing.layoutPdf(
        windowHandle: owner,
        viewId: viewId,
        onLayout: reportSpooling(null),
        name: name,
        format: format,
        dynamicLayout: dynamicLayout,
        usePrinterSettings: usePrinterSettings,
      ),
    );
  }

  final printers = SaferPrinterFilter.allowed(
    await Printing.listPrinters(),
    await Isolate.run(windowsPrinterPorts),
  );
  if (!effectiveContext.mounted) return false;

  if (printers.isEmpty) {
    final useSystemDialog = await showTwoActionsDialog(
      context: effectiveContext,
      title: 'אין מדפסת זמינה',
      content: PdfMessages.saferModeNoPrinter,
      confirmText: 'הזן סיסמה',
    );
    if (useSystemDialog != true || !effectiveContext.mounted) return false;
    if (!await verifySaferModePassword(effectiveContext)) return false;
    if (!effectiveContext.mounted) return false;
    return PrintWorkStatus.track(
      () => Printing.layoutPdf(
        windowHandle: owner,
        viewId: viewId,
        onLayout: reportSpooling(null),
        name: name,
        format: format,
        dynamicLayout: dynamicLayout,
        usePrinterSettings: usePrinterSettings,
      ),
    );
  }

  final Printer? printer;
  if (printers.length == 1) {
    printer = printers.single;
  } else {
    printer = await showSelectionDialog<Printer>(
      context: effectiveContext,
      title: 'בחירת מדפסת',
      items: [
        for (final p in printers) SelectionItem(label: p.name, value: p),
      ],
      initialValue: printers.where((p) => p.isDefault).firstOrNull,
      searchHint: 'חיפוש מדפסת...',
    );
  }
  if (printer == null || !effectiveContext.mounted) return false;
  final selected = printer;

  UiSnack.show(PdfMessages.saferDirectPrint(selected.name));
  final printed = await PrintWorkStatus.track(
    () => Printing.directPrintPdf(
      windowHandle: owner,
      viewId: viewId,
      printer: selected,
      onLayout: reportSpooling(selected.name),
      name: name,
      format: format,
      dynamicLayout: dynamicLayout,
      usePrinterSettings: usePrinterSettings,
    ),
  );
  if (!printed) UiSnack.showError(PdfMessages.printFailed(selected.name));
  return printed;
}

/// עמוד שאפשר לפרוס עליו: מידות סופיות וחיוביות, ושוליים סופיים.
@visibleForTesting
bool isUsablePageFormat(PdfPageFormat format) =>
    format.width.isFinite &&
    format.width > 0 &&
    format.height.isFinite &&
    format.height > 0 &&
    [
      format.marginLeft,
      format.marginTop,
      format.marginRight,
      format.marginBottom,
    ].every((margin) => margin.isFinite);
