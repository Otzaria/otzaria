import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_export_cancellation.dart';
import 'pdf_file_cleanup.dart';

/// כותב ב-worker לקובץ staging בבעלות הקורא; גרף המסמך נשאר בזיכרון.
Future<void> writePdfDocumentToFile(
  pw.Document document,
  String stagingPath, {
  int cancellationAddress = 0,
  int bufferSize = PdfFileStream.maximumBufferSize,
}) async {
  final destination = File(stagingPath);
  var completed = false;
  await withPdfFileCleanup(
    () async {
      PdfExportCancellationToken.throwIfCancelledAt(cancellationAddress);
      final file = destination.openSync(mode: FileMode.write);
      await withPdfFileCleanup(() async {
        final output = PdfFileStream(
          file,
          cancellationAddress: cancellationAddress,
          bufferSize: bufferSize,
        );
        await document.write(output);
        output.flush();
        file.flushSync();
      }, file.closeSync);
      PdfExportCancellationToken.throwIfCancelledAt(cancellationAddress);
      completed = true;
    },
    () {
      if (!completed && destination.existsSync()) destination.deleteSync();
    },
  );
}

/// פלט בעל buffer מוגבל; הקורא אחראי לסגירת ה-RandomAccessFile.
class PdfFileStream extends PdfStream {
  PdfFileStream(
    this._file, {
    this.cancellationAddress = 0,
    int bufferSize = maximumBufferSize,
  }) : _buffer = Uint8List(_checkedBufferSize(bufferSize));

  static const maximumBufferSize = 64 * 1024;

  final RandomAccessFile _file;
  final int cancellationAddress;
  final Uint8List _buffer;
  var _buffered = 0;
  var _offset = 0;

  static int _checkedBufferSize(int size) {
    if (size < 1 || size > maximumBufferSize) {
      throw RangeError.range(size, 1, maximumBufferSize, 'bufferSize');
    }
    return size;
  }

  @override
  int get offset => _offset;

  @override
  void putByte(int value) {
    PdfExportCancellationToken.throwIfCancelledAt(cancellationAddress);
    _buffer[_buffered++] = value;
    _offset++;
    if (_buffered == _buffer.length) flush();
  }

  @override
  void putBytes(List<int> bytes) {
    var start = 0;
    while (start < bytes.length) {
      PdfExportCancellationToken.throwIfCancelledAt(cancellationAddress);
      final count = min(bytes.length - start, _buffer.length - _buffered);
      _buffer.setRange(_buffered, _buffered + count, bytes, start);
      _buffered += count;
      _offset += count;
      start += count;
      if (_buffered == _buffer.length) flush();
    }
  }

  @override
  void putStream(PdfStream stream) {
    if (stream is PdfFileStream) {
      throw UnsupportedError(
        'Copy file-backed PDFs through their source file.',
      );
    }
    super.putStream(stream);
  }

  @override
  void setBytes(int offset, Iterable<int> bytes) {
    RangeError.checkValueInInterval(offset, 0, _offset, 'offset');
    flush();
    final iterator = bytes.iterator;
    var position = offset;
    _file.setPositionSync(position);
    withPdfFileCleanupSync(() {
      var count = 0;
      while (iterator.moveNext()) {
        PdfExportCancellationToken.throwIfCancelledAt(cancellationAddress);
        if (position + count >= _offset) {
          throw RangeError('A PDF patch cannot extend the output.');
        }
        _buffer[count++] = iterator.current;
        if (count == _buffer.length) {
          _file.writeFromSync(_buffer, 0, count);
          position += count;
          count = 0;
        }
      }
      if (count != 0) _file.writeFromSync(_buffer, 0, count);
    }, () => _file.setPositionSync(_offset));
  }

  void flush() {
    PdfExportCancellationToken.throwIfCancelledAt(cancellationAddress);
    if (_buffered == 0) return;
    _file.writeFromSync(_buffer, 0, _buffered);
    _buffered = 0;
  }

  @override
  Uint8List output() =>
      throw UnsupportedError('A file-backed PDF is not an in-memory output.');
}
