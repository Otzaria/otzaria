import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria/printing/pdf_export_cancellation.dart';
import 'package:otzaria/printing/pdf_file_stream.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdf-file-stream-test-');
    file = File('${directory.path}/output.pdf');
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final version in PdfVersion.values) {
    for (final compress in [true, false]) {
      test('saved-byte parity: ${version.name}, compress=$compress', () async {
        final document = _document(version: version, compress: compress);
        await writePdfDocumentToFile(document, file.path, bufferSize: 31);
        final bytes = await file.readAsBytes();
        expect(bytes, orderedEquals(await document.save()));
        expect(latin1.decode(bytes), endsWith('%%EOF\n'));
      });
    }
  }

  test('verbose serialization patches bytes already flushed to disk', () async {
    final document = _document(
      version: PdfVersion.pdf_1_4,
      compress: false,
      verbose: true,
    );
    final handle = file.openSync(mode: FileMode.write);
    try {
      final output = _MirroredPdfFileStream(handle);
      await document.write(output);
      output.flush();
      final bytes = await file.readAsBytes();
      expect(output.patches, greaterThan(0));
      expect(latin1.decode(bytes), contains('Verbose dart_pdf'));
      expect(bytes, orderedEquals(output.reference.output()));
    } finally {
      handle.closeSync();
    }
  });

  test('patches span buffers and keep the following append at the end', () {
    final handle = file.openSync(mode: FileMode.write);
    try {
      final output = PdfFileStream(handle, bufferSize: 3)
        ..putString('abcdefghijklmnop')
        ..setBytes(2, [1, 2, 3, 4, 5, 6, 7, 8])
        ..setBytes(13, [9, 10, 11])
        ..setBytes(16, const [])
        ..putByte(99)
        ..putStream(PdfStream()..putString('tail'))
        ..flush();
      expect(output.offset, 21);
      expect(output.output, throwsUnsupportedError);
      expect(
        file.readAsBytesSync(),
        orderedEquals([
          97,
          98,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          107,
          108,
          109,
          9,
          10,
          11,
          99,
          116,
          97,
          105,
          108,
        ]),
      );
    } finally {
      handle.closeSync();
    }
  });

  test('rejects out-of-range patches and retains the append cursor', () {
    final handle = file.openSync(mode: FileMode.write);
    try {
      final output = PdfFileStream(handle, bufferSize: 2)..putString('abcd');
      expect(() => output.setBytes(-1, [1]), throwsRangeError);
      expect(() => output.setBytes(5, []), throwsRangeError);
      expect(() => output.setBytes(4, [1]), throwsRangeError);
      output
        ..putString('ef')
        ..flush();
      expect(output.offset, 6);
      expect(latin1.decode(file.readAsBytesSync()), 'abcdef');
    } finally {
      handle.closeSync();
    }
  });

  test(
    'large real output writes only bounded chunks and never output()',
    () async {
      final document = pw.Document(
        compress: false,
        title: 'large metadata ' * (1024 * 1024),
      )..addPage(pw.Page(build: (_) => pw.Text('bounded PDF output')));
      final handle = file.openSync(mode: FileMode.write);
      final tracked = _TrackedFile(handle);
      try {
        final output = PdfFileStream(tracked);
        await document.write(output);
        output.flush();
        handle.flushSync();
        expect(file.lengthSync(), greaterThan(12 * 1024 * 1024));
        expect(output.offset, file.lengthSync());
        expect(tracked.writeCount, greaterThan(100));
        expect(tracked.largestWrite, lessThanOrEqualTo(64 * 1024));
      } finally {
        handle.closeSync();
      }
    },
  );

  test(
    'the document helper never calls the memory-producing save method',
    () async {
      final document = _SaveForbiddenDocument()
        ..addPage(pw.Page(build: (_) => pw.Text('write directly to the file')));
      await writePdfDocumentToFile(document, file.path);
      expect(await file.length(), greaterThan(100));
    },
  );

  test(
    'write failure closes the destination and removes partial output',
    () async {
      final error = FileSystemException('injected write failure', file.path);
      final failure = _FailingFile(file, error);
      await IOOverrides.runZoned(
        () async {
          await expectLater(
            writePdfDocumentToFile(_document(), file.path, bufferSize: 7),
            throwsA(same(error)),
          );
        },
        createFile: (path) => path == file.path
            ? failure
            : throw StateError('Unexpected file: $path'),
      );
      expect(failure.closed, isTrue);
      expect(await file.exists(), isFalse);
    },
  );

  test(
    'cancellation after a flushed block closes and deletes staging',
    () async {
      final token = PdfExportCancellationToken();
      final lease = token.acquire();
      final intercepted = _CancellingFile(file, token.cancel);
      try {
        await IOOverrides.runZoned(
          () => expectLater(
            writePdfDocumentToFile(
              _document(),
              file.path,
              cancellationAddress: lease.address,
              bufferSize: 7,
            ),
            throwsA(isA<PdfExportCancelledException>()),
          ),
          createFile: (path) => path == file.path
              ? intercepted
              : throw StateError('Unexpected file: $path'),
        );
        expect(intercepted.closed, isTrue);
        expect(await file.exists(), isFalse);
      } finally {
        lease.dispose();
        token.dispose();
      }
    },
  );

  test('pre-cancelled output is removed without writing', () async {
    final token = PdfExportCancellationToken();
    final lease = token.acquire();
    await file.create(exclusive: true);
    token.cancel();
    try {
      await expectLater(
        writePdfDocumentToFile(
          _document(),
          file.path,
          cancellationAddress: lease.address,
        ),
        throwsA(isA<PdfExportCancelledException>()),
      );
      expect(await file.exists(), isFalse);
    } finally {
      lease.dispose();
      token.dispose();
    }
  });
}

pw.Document _document({
  PdfVersion version = PdfVersion.pdf_1_5,
  bool compress = false,
  bool verbose = false,
}) => pw.Document(version: version, compress: compress, verbose: verbose)
  ..addPage(pw.Page(build: (_) => pw.Text('First page')))
  ..addPage(
    pw.MultiPage(
      build: (_) => List.generate(80, (i) => pw.Text('Searchable row $i')),
    ),
  );

class _SaveForbiddenDocument extends pw.Document {
  @override
  Future<Uint8List> save({bool enableEventLoopBalancing = false}) =>
      throw StateError(
        'The file output must not materialize the complete PDF.',
      );
}

class _TrackedFile implements RandomAccessFile {
  _TrackedFile(this.base);
  final RandomAccessFile base;
  var writeCount = 0;
  var largestWrite = 0;

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    final count = (end ?? buffer.length) - start;
    writeCount++;
    if (count > largestWrite) largestWrite = count;
    base.writeFromSync(buffer, start, end);
  }

  @override
  void setPositionSync(int position) => base.setPositionSync(position);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MirroredPdfFileStream extends PdfFileStream {
  _MirroredPdfFileStream(super.file) : super(bufferSize: 7);
  final reference = PdfStream();
  var patches = 0;

  @override
  void putByte(int s) {
    super.putByte(s);
    reference.putByte(s);
  }

  @override
  void putBytes(List<int> s) {
    super.putBytes(s);
    reference.putBytes(s);
  }

  @override
  void setBytes(int offset, Iterable<int> iterable) {
    final patch = iterable.toList();
    patches++;
    super.setBytes(offset, patch);
    reference.setBytes(offset, patch);
  }
}

class _FailingFile implements File {
  _FailingFile(this.base, this.error);
  final File base;
  final Object error;
  var closed = false;

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) => _ControlledFile(
    base.openSync(mode: mode),
    () => throw error,
    () => closed = true,
  );

  @override
  bool existsSync() => base.existsSync();

  @override
  void deleteSync({bool recursive = false}) =>
      base.deleteSync(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CancellingFile extends _FailingFile {
  _CancellingFile(File base, this.cancel) : super(base, StateError('unused'));
  final void Function() cancel;

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _ControlledFile(base.openSync(mode: mode), cancel, () => closed = true);
}

class _ControlledFile extends _TrackedFile {
  _ControlledFile(super.base, this.afterWrite, this.afterClose);
  final void Function() afterWrite;
  final void Function() afterClose;

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    super.writeFromSync(buffer, start, end);
    afterWrite();
  }

  @override
  void flushSync() => base.flushSync();

  @override
  void closeSync() {
    base.closeSync();
    afterClose();
  }
}
