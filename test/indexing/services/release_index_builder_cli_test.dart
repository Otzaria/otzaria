import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/services/release_index_builder_cli.dart';
import 'package:path/path.dart' as p;

class _Sink implements StringSink {
  final buffer = StringBuffer();

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  String toString() => buffer.toString();
}

void main() {
  late _Sink out;
  late _Sink err;

  setUp(() {
    out = _Sink();
    err = _Sink();
  });

  test('מעביר לבונה את שלושת הנתיבים כנתיבים מוחלטים', () async {
    ReleaseIndexBuilderConfig? received;

    final code = await ReleaseIndexBuilderCli.run(
      const [
        '--library',
        'staging/books',
        '--index=staging/index',
        '--data',
        'staging/data',
      ],
      out: out,
      err: err,
      build: (config, log) async => received = config,
    );

    expect(code, ReleaseIndexBuilderCliExitCode.success);
    expect(received, isNotNull);
    expect(received!.libraryPath, p.absolute('staging/books'));
    expect(received!.indexPath, p.absolute('staging/index'));
    expect(received!.dataPath, p.absolute('staging/data'));
    expect(err.toString(), isEmpty);
  });

  test('מחזיר usage error כשנתיב חובה חסר', () async {
    final code = await ReleaseIndexBuilderCli.run(
      const ['--library', 'books', '--index', 'index'],
      out: out,
      err: err,
      build: (_, _) async => fail('אסור להפעיל את הבונה'),
    );

    expect(code, ReleaseIndexBuilderCliExitCode.usageError);
    expect(err.toString(), contains('--library, --index'));
  });

  test('--help אינו מפעיל בנייה', () async {
    final code = await ReleaseIndexBuilderCli.run(
      const ['--help'],
      out: out,
      err: err,
      build: (_, _) async => fail('אסור להפעיל את הבונה'),
    );

    expect(code, ReleaseIndexBuilderCliExitCode.success);
    expect(out.toString(), contains('build-release-index'));
    expect(err.toString(), isEmpty);
  });

  test('כשל בנייה מוחזר כקוד 1 ונכתב ל-stderr', () async {
    final code = await ReleaseIndexBuilderCli.run(
      const [
        '--library=books',
        '--index=index',
        '--data=data',
      ],
      out: out,
      err: err,
      build: (_, _) async => throw const FileSystemException('boom'),
    );

    expect(code, ReleaseIndexBuilderCliExitCode.buildFailed);
    expect(err.toString(), contains('boom'));
  });
}
