import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/pdf_export_cancellation.dart';
import 'package:otzaria/printing/print_pdf_source.dart';

void main() {
  late Directory directory;
  late File source;
  late File destination;
  late Uint8List bytes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('print-source-io-test-');
    source = File('${directory.path}/source.pdf');
    destination = File('${directory.path}/staging.pdf');
    bytes = Uint8List.fromList(
      List.generate(3 * 1024 * 1024 + 123, (i) => i % 251),
    );
    await source.writeAsBytes(bytes);
    await destination.create(exclusive: true);
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final fromFile in [true, false]) {
    test('bounded copy preserves all bytes (fromFile=$fromFile)', () async {
      final input = _FileSpy(source);
      final output = _FileSpy(destination);
      final pdf = fromFile
          ? PrintPdfSource.file(source.path)
          : PrintPdfSource.data(bytes);
      await _withFiles(input, output, () => pdf.writeToFile(destination.path));
      expect(await destination.readAsBytes(), orderedEquals(bytes));
      expect(output.handle!.largestWrite, lessThanOrEqualTo(64 * 1024));
      expect(output.handle!.writes, greaterThan(40));
      expect(output.handle!.closed, isTrue);
      if (fromFile) {
        expect(input.handle!.largestRead, 64 * 1024);
        expect(input.handle!.closed, isTrue);
      } else {
        expect(output.handle!.firstBuffer, same(bytes));
        expect(output.handle!.allBuffersIdentical, isTrue);
        expect(input.handle, isNull);
      }
    });
  }

  test('rejects the source path before truncation or cleanup', () async {
    await expectLater(
      PrintPdfSource.file(source.path).writeToFile(source.path),
      throwsArgumentError,
    );
    expect(await source.readAsBytes(), orderedEquals(bytes));
  });

  test(
    'a missing source still closes and removes its owned staging file',
    () async {
      await source.delete();
      final input = _FileSpy(source);
      final output = _FileSpy(destination);
      await expectLater(
        _withFiles(
          input,
          output,
          () => PrintPdfSource.file(source.path).writeToFile(destination.path),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(output.handle!.closed, isTrue);
      expect(await destination.exists(), isFalse);
    },
  );

  for (final sourceIsLink in [false, true]) {
    test(
      'rejects a symbolic alias before truncation (sourceIsLink=$sourceIsLink)',
      () async {
        await destination.delete();
        await Link(destination.path).create(source.path);
        await expectLater(
          PrintPdfSource.file(
            sourceIsLink ? destination.path : source.path,
          ).writeToFile(sourceIsLink ? source.path : destination.path),
          throwsArgumentError,
        );
        expect(await source.readAsBytes(), orderedEquals(bytes));
        expect(await Link(destination.path).exists(), isTrue);
      },
      skip: Platform.isWindows
          ? 'Creating symbolic links requires host privileges.'
          : false,
    );
  }

  test(
    'a dangling staging link cannot create a missing source',
    () async {
      await destination.delete();
      await source.delete();
      final link = await Link(destination.path).create(source.path);
      await expectLater(
        PrintPdfSource.file(source.path).writeToFile(destination.path),
        throwsArgumentError,
      );
      expect(await source.exists(), isFalse);
      expect(await link.target(), source.path);
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links requires host privileges.'
        : false,
  );

  test('a read failure closes both files and removes only staging', () async {
    final error = FileSystemException('injected input failure', source.path);
    final input = _FileSpy(source, readError: error);
    final output = _FileSpy(destination);
    await expectLater(
      _withFiles(
        input,
        output,
        () => PrintPdfSource.file(source.path).writeToFile(destination.path),
      ),
      throwsA(same(error)),
    );
    expect(input.handle!.closed, isTrue);
    expect(output.handle!.closed, isTrue);
    expect(await destination.exists(), isFalse);
    expect(await source.readAsBytes(), orderedEquals(bytes));
  });

  test('a write failure wins over a secondary delete failure', () async {
    final error = FileSystemException(
      'injected output failure',
      destination.path,
    );
    final input = _FileSpy(source);
    final output = _FileSpy(destination, writeError: error, deleteFails: true);
    await expectLater(
      _withFiles(
        input,
        output,
        () => PrintPdfSource.file(source.path).writeToFile(destination.path),
      ),
      throwsA(same(error)),
    );
    expect(input.handle!.closed, isTrue);
    expect(output.handle!.closed, isTrue);
    expect(output.deleteAttempts, 1);
    expect(await source.readAsBytes(), orderedEquals(bytes));
  });

  test(
    'cancellation between chunks closes files and removes partial output',
    () async {
      final token = PdfExportCancellationToken();
      final lease = token.acquire();
      final input = _FileSpy(source);
      final output = _FileSpy(destination, afterWrite: token.cancel);
      try {
        await expectLater(
          _withFiles(
            input,
            output,
            () => PrintPdfSource.file(
              source.path,
            ).writeToFile(destination.path, cancellationAddress: lease.address),
          ),
          throwsA(isA<PdfExportCancelledException>()),
        );
        expect(output.handle!.writes, 1);
        expect(input.handle!.closed, isTrue);
        expect(output.handle!.closed, isTrue);
        expect(await destination.exists(), isFalse);
        expect(await source.readAsBytes(), orderedEquals(bytes));
      } finally {
        lease.dispose();
        token.dispose();
      }
    },
  );
}

Future<T> _withFiles<T>(
  _FileSpy source,
  _FileSpy destination,
  Future<T> Function() action,
) => IOOverrides.runZoned(
  action,
  createFile: (path) {
    if (path == source.path) return source;
    if (path == destination.path) return destination;
    throw StateError('Unexpected file: $path');
  },
);

class _FileSpy implements File {
  _FileSpy(
    this.base, {
    this.readError,
    this.writeError,
    this.afterWrite,
    this.deleteFails = false,
  }) : _absolute = base.absolute;

  final File base;
  final File _absolute;
  final Object? readError;
  final Object? writeError;
  final void Function()? afterWrite;
  final bool deleteFails;
  _HandleSpy? handle;
  var deleteAttempts = 0;

  @override
  String get path => base.path;

  @override
  File get absolute => _absolute;

  @override
  Future<bool> exists() => base.exists();

  @override
  Future<String> resolveSymbolicLinks() => base.resolveSymbolicLinks();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    deleteAttempts++;
    if (deleteFails) throw const FileSystemException('injected delete failure');
    return base.delete(recursive: recursive);
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      handle = _HandleSpy(await base.open(mode: mode), this);

  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('Full-file read is forbidden.');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HandleSpy implements RandomAccessFile {
  _HandleSpy(this.base, this.owner);
  final RandomAccessFile base;
  final _FileSpy owner;
  var closed = false;
  var writes = 0;
  var largestWrite = 0;
  var largestRead = 0;
  List<int>? firstBuffer;
  var allBuffersIdentical = true;

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) {
    final size = (end ?? buffer.length) - start;
    if (size > largestRead) largestRead = size;
    if (owner.readError case final error?) throw error;
    return base.readInto(buffer, start, end);
  }

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    writes++;
    final size = (end ?? buffer.length) - start;
    if (size > largestWrite) largestWrite = size;
    firstBuffer ??= buffer;
    allBuffersIdentical &= identical(firstBuffer, buffer);
    if (owner.writeError case final error?) throw error;
    await base.writeFrom(buffer, start, end);
    owner.afterWrite?.call();
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    await base.flush();
    return this;
  }

  @override
  Future<void> close() async {
    await base.close();
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
