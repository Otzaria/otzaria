/// סידור עמודי PDF בגיליונות באמצעות PDFium, תוך שימור טקסט וגרפיקה וקטורית.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_export_cancellation.dart';

/// סדר עמודי המקור בתאי הגיליון; null שומר תא ריק רק לפני עמוד מאוחר יותר.
@visibleForTesting
List<int?> sheetSlotOrder({
  required int firstIndex,
  required int lastIndex,
  required int rows,
  required int cols,
  bool rightToLeft = true,
}) {
  final count = lastIndex - firstIndex + 1;
  final cells = rows * cols;
  final slots = <int?>[];
  for (var sheet = 0; sheet * cells < count; sheet++) {
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final logicalCol = rightToLeft ? cols - 1 - col : col;
        final offset = sheet * cells + row * cols + logicalCol;
        slots.add(offset < count ? firstIndex + offset : null);
      }
    }
  }
  while (slots.isNotEmpty && slots.last == null) {
    slots.removeLast();
  }
  return slots;
}

/// מסדר טווח עמודים (אינדקס מאפס) בגיליונות; תא יחיד משמר את גודל העמוד.
/// [document] נשאר בבעלות הקורא וחייב להישאר פתוח עד ההשלמה.
Future<Uint8List> composePdfSheets(
  PdfDocument document, {
  required int firstIndex,
  required int lastIndex,
  required int rows,
  required int cols,
  required double sheetWidth,
  required double sheetHeight,
  bool rightToLeft = true,
}) async {
  final request = await _composeRequest(
    document,
    firstIndex: firstIndex,
    lastIndex: lastIndex,
    rows: rows,
    cols: cols,
    sheetWidth: sheetWidth,
    sheetHeight: sheetHeight,
    rightToLeft: rightToLeft,
  );
  final result = await PdfrxEntryFunctions.instance.compute(_compose, request);
  return result.bytes!;
}

/// כותב ישירות לקובץ ביניים בבעלות הקורא ומחזיר את מספר הבתים שנכתבו.
/// אינו מפרסם או מוחק את הקובץ; [document] חייב להישאר פתוח עד ההשלמה.
Future<int> composePdfSheetsToFile(
  PdfDocument document, {
  required String outputPath,
  required int firstIndex,
  required int lastIndex,
  required int rows,
  required int cols,
  required double sheetWidth,
  required double sheetHeight,
  bool rightToLeft = true,
  PdfExportCancellationToken? cancellationToken,
}) async {
  final lease = cancellationToken?.acquire();
  try {
    final request = await _composeRequest(
      document,
      firstIndex: firstIndex,
      lastIndex: lastIndex,
      rows: rows,
      cols: cols,
      sheetWidth: sheetWidth,
      sheetHeight: sheetHeight,
      rightToLeft: rightToLeft,
      outputPath: outputPath,
      cancellationAddress: lease?.address ?? 0,
    );
    // All PDFium calls stay on its worker; synchronous file writes also stay off UI.
    final result = await PdfrxEntryFunctions.instance.compute(
      _composeToFile,
      request,
    );
    if (result is _FileComposeFailure) {
      Error.throwWithStackTrace(
        result.error,
        StackTrace.fromString(result.stack),
      );
    }
    PdfExportCancellationToken.throwIfCancelledAt(lease?.address ?? 0);
    return result as int;
  } finally {
    lease?.dispose();
  }
}

Future<_ComposeRequest> _composeRequest(
  PdfDocument document, {
  required int firstIndex,
  required int lastIndex,
  required int rows,
  required int cols,
  required double sheetWidth,
  required double sheetHeight,
  required bool rightToLeft,
  String? outputPath,
  int cancellationAddress = 0,
}) async {
  if (firstIndex < 0 ||
      lastIndex < firstIndex ||
      rows <= 0 ||
      cols <= 0 ||
      !sheetWidth.isFinite ||
      sheetWidth <= 0 ||
      !sheetHeight.isFinite ||
      sheetHeight <= 0) {
    throw ArgumentError('Invalid PDF sheet range or dimensions.');
  }
  PdfExportCancellationToken.throwIfCancelledAt(cancellationAddress);
  final handle = await document.useNativeDocumentHandle((handle) => handle);
  return (
    document: handle,
    modulePath: Pdfrx.pdfiumModulePath,
    slots: sheetSlotOrder(
      firstIndex: firstIndex,
      lastIndex: lastIndex,
      rows: rows,
      cols: cols,
      rightToLeft: rightToLeft,
    ),
    rows: rows,
    cols: cols,
    sheetWidth: sheetWidth,
    sheetHeight: sheetHeight,
    rightToLeft: rightToLeft,
    outputPath: outputPath,
    cancellationAddress: cancellationAddress,
  );
}

typedef _ComposeRequest = ({
  int document,
  String? modulePath,
  List<int?> slots,
  int rows,
  int cols,
  double sheetWidth,
  double sheetHeight,
  bool rightToLeft,
  String? outputPath,
  int cancellationAddress,
});

typedef _ComposeResult = ({Uint8List? bytes, int length});

class _FileComposeFailure {
  const _FileComposeFailure(this.error, this.stack);
  final Object error;
  final String stack;
}

// compute stringifies thrown errors; preserve these sendable errors for callers.
Object _composeToFile(_ComposeRequest request) {
  try {
    return _compose(request).length;
  } on PdfExportCancelledException catch (error, stack) {
    return _FileComposeFailure(error, stack.toString());
  } on FileSystemException catch (error, stack) {
    final osError = error.osError;
    return _FileComposeFailure(
      FileSystemException(
        error.message,
        error.path,
        osError == null ? null : OSError(osError.message, osError.errorCode),
      ),
      stack.toString(),
    );
  }
}

typedef _WriteBlock = Int Function(
  Pointer<pdfium_bindings.FPDF_FILEWRITE>,
  Pointer<Void>,
  UnsignedLong,
);

/// `FPDF_SaveAsCopy` flag: write the whole file rather than an update.
const int _noIncremental = 2;

_ComposeResult _compose(_ComposeRequest request) {
  PdfExportCancellationToken.throwIfCancelledAt(request.cancellationAddress);
  final pdfium = pdfium_bindings.getPdfium(modulePath: request.modulePath);
  final source = pdfium_bindings.FPDF_DOCUMENT.fromAddress(request.document);
  return using((arena) {
    final arranged = pdfium.FPDF_CreateNewDocument();
    if (arranged.address == 0) {
      throw StateError('PDFium could not create the sheet document.');
    }
    pdfium_bindings.FPDF_DOCUMENT? sheets;
    try {
      _arrange(pdfium, source, arranged, request, arena);
      PdfExportCancellationToken.throwIfCancelledAt(
        request.cancellationAddress,
      );
      final single = request.rows * request.cols == 1;
      final output = single
          ? arranged
          : sheets = pdfium.FPDF_ImportNPagesToOne(
              arranged,
              request.sheetWidth,
              request.sheetHeight,
              request.cols,
              request.rows,
            );
      if (output.address == 0) {
        throw StateError('PDFium could not compose the sheets.');
      }
      if (!single && request.rightToLeft) {
        _putCellsInReadingOrder(pdfium, output, request, arena);
      }
      return _save(pdfium, output, request, arena);
    } finally {
      if (sheets != null && sheets.address != 0) {
        pdfium.FPDF_CloseDocument(sheets);
      }
      pdfium.FPDF_CloseDocument(arranged);
    }
  });
}

/// מעתיק לפי סדר התאים; תא ריק מקבל את גודל עמוד המקור הראשון.
void _arrange(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_DOCUMENT source,
  pdfium_bindings.FPDF_DOCUMENT target,
  _ComposeRequest request,
  Arena arena,
) {
  final slots = request.slots;
  final firstPage = slots.firstWhere((slot) => slot != null)!;
  final width = arena<Double>();
  final height = arena<Double>();
  pdfium.FPDF_GetPageSizeByIndex(source, firstPage, width, height);

  final indices = arena<Int>(slots.length);
  var start = 0;
  while (start < slots.length) {
    PdfExportCancellationToken.throwIfCancelledAt(request.cancellationAddress);
    if (slots[start] == null) {
      final page = pdfium.FPDFPage_New(
        target,
        start,
        width.value,
        height.value,
      );
      pdfium.FPDF_ClosePage(page);
      start++;
      continue;
    }
    // Consecutive pages go over in one call.
    var end = start;
    while (end < slots.length && slots[end] != null) {
      indices[end - start] = slots[end]!;
      end++;
    }
    final imported = pdfium.FPDF_ImportPagesByIndex(
      target,
      source,
      indices,
      end - start,
      start,
    );
    if (imported == 0) {
      throw StateError('PDFium could not copy the pages.');
    }
    start = end;
  }
}

/// PDFium writes a sheet's cells left to right, which is also the order text
/// is selected and extracted in; right-to-left sheets need the right cell first.
void _putCellsInReadingOrder(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_DOCUMENT sheets,
  _ComposeRequest request,
  Arena arena,
) {
  final cellWidth = request.sheetWidth / request.cols;
  final cellHeight = request.sheetHeight / request.rows;
  final left = arena<Float>();
  final bottom = arena<Float>();
  final right = arena<Float>();
  final top = arena<Float>();

  int readingIndex(pdfium_bindings.FPDF_PAGEOBJECT object) {
    // An empty cell's form has no bounds; its place in the order is moot.
    if (pdfium.FPDFPageObj_GetBounds(object, left, bottom, right, top) == 0) {
      return 1 << 30;
    }
    final centerX = (left.value + right.value) / 2;
    final centerY = (bottom.value + top.value) / 2;
    final row = ((request.sheetHeight - centerY) / cellHeight).floor();
    final col = (centerX / cellWidth).floor();
    return row * request.cols + (request.cols - 1 - col);
  }

  for (var index = 0; index < pdfium.FPDF_GetPageCount(sheets); index++) {
    PdfExportCancellationToken.throwIfCancelledAt(request.cancellationAddress);
    final page = pdfium.FPDF_LoadPage(sheets, index);
    if (page.address == 0) {
      throw StateError('PDFium could not reopen sheet ${index + 1}.');
    }
    try {
      final objects = [
        for (var i = 0; i < pdfium.FPDFPage_CountObjects(page); i++)
          pdfium.FPDFPage_GetObject(page, i),
      ];
      final order = {
        for (final object in objects) object: readingIndex(object),
      };
      final sorted = [...objects]
        ..sort((a, b) => order[a]!.compareTo(order[b]!));
      for (final object in objects) {
        pdfium.FPDFPage_RemoveObject(page, object);
      }
      for (final object in sorted) {
        pdfium.FPDFPage_InsertObject(page, object);
      }
      if (pdfium.FPDFPage_GenerateContent(page) == 0) {
        throw StateError('PDFium could not rewrite sheet ${index + 1}.');
      }
    } finally {
      pdfium.FPDF_ClosePage(page);
    }
  }
}

_ComposeResult _save(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_DOCUMENT document,
  _ComposeRequest request,
  Arena arena,
) {
  PdfExportCancellationToken.throwIfCancelledAt(request.cancellationAddress);
  final path = request.outputPath;
  final file = path == null ? null : File(path).openSync(mode: FileMode.write);
  final output = file == null ? BytesBuilder() : null;
  var written = 0;
  Object? writeError;
  StackTrace? writeStack;
  int write(
    Pointer<pdfium_bindings.FPDF_FILEWRITE> _,
    Pointer<Void> data,
    int size,
  ) {
    if (writeError != null) return 0;
    try {
      PdfExportCancellationToken.throwIfCancelledAt(
        request.cancellationAddress,
      );
      // The native buffer is reused after return; finish the write while it is valid.
      final bytes = data.cast<Uint8>().asTypedList(size);
      if (file != null) {
        file.writeFromSync(bytes);
      } else {
        output!.add(bytes);
      }
      written += size;
      return 1;
    } catch (error, stack) {
      writeError = error;
      writeStack = stack;
      return 0;
    }
  }

  NativeCallable<_WriteBlock>? callback;
  Object? primaryError;
  try {
    callback = NativeCallable<_WriteBlock>.isolateLocal(
      write,
      exceptionalReturn: 0,
    );
    final fileWrite = arena<pdfium_bindings.FPDF_FILEWRITE>();
    fileWrite.ref
      ..version = 1
      ..WriteBlock = callback.nativeFunction;
    final saved = pdfium.FPDF_SaveAsCopy(document, fileWrite, _noIncremental);
    if (writeError != null) {
      Error.throwWithStackTrace(writeError!, writeStack!);
    }
    if (saved == 0) {
      throw StateError('PDFium could not write the sheets.');
    }
    PdfExportCancellationToken.throwIfCancelledAt(request.cancellationAddress);
    file?.flushSync();
    return (bytes: output?.takeBytes(), length: written);
  } catch (error) {
    primaryError = error;
    rethrow;
  } finally {
    callback?.close();
    try {
      file?.closeSync();
    } catch (_) {
      // Cleanup must not hide the write failure or turn cancellation into an error.
      if (primaryError == null) rethrow;
    }
  }
}
