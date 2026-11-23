import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:otzaria/utils/file/atomic_file_publication.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File destination;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('file-publication-');
    destination = File(p.join(directory.path, 'output.pdf'));
  });
  tearDown(() => directory.delete(recursive: true));

  DesktopSaveTarget target({bool overwrite = false}) => DesktopSaveTarget(
    path: destination.path,
    overwriteApproved: overwrite,
  );

  Future<void> expectNoStaging() async {
    expect(
      await directory
          .list()
          .where((file) => file.path != destination.path)
          .toList(),
      isEmpty,
    );
  }

  test('new destination remains absent until the producer finishes', () async {
    final started = Completer<String>();
    final finish = Completer<void>();
    final publication = publishFileAtomically(
      target: target(),
      producer: (path) async {
        started.complete(path);
        await finish.future;
        await File(path).writeAsString('complete PDF');
      },
    );
    try {
      final path = await started.future;
      expect(p.dirname(path), await directory.resolveSymbolicLinks());
      expect(path, isNot(destination.path));
      expect(await File(path).length(), 0);
      expect(await destination.exists(), isFalse);
      finish.complete();
      expect(await publication, isTrue);
      expect(await destination.readAsString(), 'complete PDF');
      await expectNoStaging();
    } finally {
      if (!finish.isCompleted) finish.complete();
      await publication;
    }
  });

  test('approved overwrite replaces the complete file', () async {
    await destination.writeAsString('previous document');
    expect(
      await publishFileAtomically(
        target: target(overwrite: true),
        producer: (path) async {
          expect(await destination.readAsString(), 'previous document');
          await File(path).writeAsString('replacement');
        },
      ),
      isTrue,
    );
    expect(await destination.readAsString(), 'replacement');
    await expectNoStaging();
  });

  test('existing unapproved destination rejects before producing', () async {
    await destination.writeAsString('keep');
    var produced = false;
    await expectLater(
      publishFileAtomically(
        target: target(),
        producer: (_) async => produced = true,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(produced, isFalse);
    expect(await destination.readAsString(), 'keep');
    await expectNoStaging();
  });

  test('a destination created during production is not overwritten', () async {
    await expectLater(
      publishFileAtomically(
        target: target(),
        producer: (path) async {
          await File(path).writeAsString('new output');
          await destination.writeAsString('another save won');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await destination.readAsString(), 'another save won');
    await expectNoStaging();
  });

  test(
    'producer failure preserves the original error and destination',
    () async {
      await destination.writeAsString('keep');
      final error = StateError('producer failed');
      await expectLater(
        publishFileAtomically(
          target: target(overwrite: true),
          producer: (path) async {
            await File(path).writeAsString('partial');
            throw error;
          },
        ),
        throwsA(same(error)),
      );
      expect(await destination.readAsString(), 'keep');
      await expectNoStaging();
    },
  );

  test('a failed producer may delete its own partial output', () async {
    final error = StateError('cancelled by producer');
    await expectLater(
      publishFileAtomically(
        target: target(),
        producer: (path) async {
          await File(path).delete();
          throw error;
        },
      ),
      throwsA(same(error)),
    );
    expect(await destination.exists(), isFalse);
    await expectNoStaging();
  });

  test(
    'missing producer output fails without creating an empty target',
    () async {
      await expectLater(
        publishFileAtomically(
          target: target(),
          producer: (path) async {
            await File(path).delete();
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.exists(), isFalse);
      await expectNoStaging();
    },
  );

  test(
    'pre-cancelled work never starts the producer or creates staging',
    () async {
      var produced = false;
      expect(
        await publishFileAtomically(
          target: target(),
          producer: (_) async => produced = true,
          isCancelled: () => true,
        ),
        isFalse,
      );
      expect(produced, isFalse);
      expect(await destination.exists(), isFalse);
      await expectNoStaging();
    },
  );

  test('cancellation waits for the producer to close before cleanup', () async {
    await destination.writeAsString('keep');
    var cancelled = false;
    var settled = false;
    final started = Completer<String>();
    final finish = Completer<void>();
    final publication = publishFileAtomically(
      target: target(overwrite: true),
      producer: (path) async {
        final handle = await File(path).open(mode: FileMode.write);
        try {
          await handle.writeString('partial');
          started.complete(path);
          await finish.future;
          await handle.writeString(' completed');
        } finally {
          await handle.close();
        }
      },
      isCancelled: () => cancelled,
    ).whenComplete(() => settled = true);
    try {
      final path = await started.future;
      cancelled = true;
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      expect(await File(path).exists(), isTrue);
      expect(await destination.readAsString(), 'keep');
      finish.complete();
      expect(await publication, isFalse);
      expect(await destination.readAsString(), 'keep');
      await expectNoStaging();
    } finally {
      if (!finish.isCompleted) finish.complete();
      await publication;
    }
  });

  test(
    'rename failure never falls back to overwriting a writable file',
    () async {
      await destination.writeAsString('keep');
      const error = FileSystemException('replacement is locked');
      final overrides = _PublicationOverrides(renameError: error);
      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => publishFileAtomically(
            target: target(overwrite: true),
            producer: (path) async {
              await File(path).writeAsString('replacement');
            },
          ),
          overrides,
        ),
        throwsA(same(error)),
      );
      expect(overrides.renameCalls, 1);
      expect(await destination.readAsString(), 'keep');
      await expectNoStaging();
    },
  );

  test('real rename failure leaves a destination directory intact', () async {
    final targetDirectory = await Directory(destination.path).create();
    final marker = await File(
      p.join(targetDirectory.path, 'keep'),
    ).writeAsString('keep');
    await expectLater(
      publishFileAtomically(
        target: target(overwrite: true),
        producer: (path) async {
          await File(path).writeAsString('replacement');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await marker.readAsString(), 'keep');
    await expectNoStaging();
  });

  test('flush failure is retained even when closing also fails', () async {
    await destination.writeAsString('keep');
    const flushError = FileSystemException('flush failed');
    final overrides = _PublicationOverrides(
      flushError: flushError,
      closeError: const FileSystemException('close failed'),
    );
    await expectLater(
      IOOverrides.runWithIOOverrides(
        () => publishFileAtomically(
          target: target(overwrite: true),
          producer: (path) async {
            await File(path).writeAsString('replacement');
          },
        ),
        overrides,
      ),
      throwsA(same(flushError)),
    );
    expect(overrides.closed, isTrue);
    expect(overrides.renameCalls, 0);
    expect(await destination.readAsString(), 'keep');
    await expectNoStaging();
  });

  test(
    'two new saves to the same path publish only one complete result',
    () async {
      final finish = Completer<void>();
      final bothStarted = Completer<void>();
      var started = 0;
      Future<Object> save(String content) async {
        try {
          return await publishFileAtomically(
            target: target(),
            producer: (path) async {
              await File(path).writeAsString(content);
              if (++started == 2) bothStarted.complete();
              await finish.future;
            },
          );
        } catch (error) {
          return error;
        }
      }

      final results = Future.wait([save('first'), save('second')]);
      try {
        await bothStarted.future;
        finish.complete();
        final completed = await results;
        expect(completed.where((result) => result == true), hasLength(1));
        expect(completed.whereType<FileSystemException>(), hasLength(1));
        expect(await destination.readAsString(), isIn(['first', 'second']));
        await expectNoStaging();
      } finally {
        if (!finish.isCompleted) finish.complete();
        await results;
      }
    },
  );

  test(
    'directory aliases share the publication guard',
    () async {
      final alias = Link(
        p.join(directory.parent.path, '${p.basename(directory.path)}-alias'),
      );
      await alias.create(directory.path);
      final finish = Completer<void>();
      final bothStarted = Completer<void>();
      var started = 0;
      Future<Object> save(String path, String content) async {
        try {
          return await publishFileAtomically(
            target: DesktopSaveTarget(path: path),
            producer: (staging) async {
              await File(staging).writeAsString(content);
              if (++started == 2) bothStarted.complete();
              await finish.future;
            },
          );
        } catch (error) {
          return error;
        }
      }

      final results = Future.wait([
        save(destination.path, 'direct'),
        save(p.join(alias.path, 'output.pdf'), 'alias'),
      ]);
      try {
        await bothStarted.future;
        finish.complete();
        final completed = await results;
        expect(completed.where((result) => result == true), hasLength(1));
        expect(completed.whereType<FileSystemException>(), hasLength(1));
        expect(await destination.readAsString(), isIn(['direct', 'alias']));
        await expectNoStaging();
      } finally {
        if (!finish.isCompleted) finish.complete();
        await results;
        await alias.delete();
      }
    },
    skip: Platform.isWindows
        ? 'Creating a symlink may require elevated rights.'
        : null,
  );
}

final class _PublicationOverrides extends IOOverrides {
  _PublicationOverrides({this.renameError, this.flushError, this.closeError});
  final FileSystemException? renameError;
  final FileSystemException? flushError;
  final FileSystemException? closeError;
  var renameCalls = 0;
  var closed = false;

  @override
  File createFile(String path) =>
      _PublicationFile(super.createFile(path), this);
}

class _PublicationFile implements File {
  _PublicationFile(this.delegate, this.overrides);
  final File delegate;
  final _PublicationOverrides overrides;

  @override
  String get path => delegate.path;
  @override
  File get absolute => delegate.absolute;
  @override
  Directory get parent => delegate.parent;
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await delegate.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    final file = await delegate.open(mode: mode);
    return overrides.flushError == null
        ? file
        : _FlushFailureFile(file, overrides);
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => delegate.writeAsString(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
  @override
  Future<File> rename(String newPath) async {
    overrides.renameCalls++;
    final error = overrides.renameError;
    if (error != null) throw error;
    return delegate.rename(newPath);
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      delegate.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FlushFailureFile implements RandomAccessFile {
  _FlushFailureFile(this.delegate, this.overrides);
  final RandomAccessFile delegate;
  final _PublicationOverrides overrides;

  @override
  Future<RandomAccessFile> flush() async => throw overrides.flushError!;

  @override
  Future<void> close() async {
    await delegate.close();
    overrides.closed = true;
    final error = overrides.closeError;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
