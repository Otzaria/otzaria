import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_packager_cli.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> _manifest({String id = 'test.cli.plugin'}) => {
  'schemaVersion': 1,
  'id': id,
  'name': 'CLI Test',
  'version': '1.0.0',
  'description': '',
  'author': '',
  'homepage': '',
  'entrypoint': 'index.html',
  'minAppVersion': '0.0.0',
  'sdkVersion': '1.x',
  'permissions': const [],
  'contributes': {
    'toolTab': {
      'title': 'CLI Test',
      'order': 900,
      'defaultPinned': true,
    },
    'publishedDataTypes': const [],
  },
};

String _writePluginDir(Directory parent, {String dirName = 'plugin'}) {
  final dir = Directory(p.join(parent.path, dirName))..createSync();
  File(
    p.join(dir.path, 'manifest.json'),
  ).writeAsStringSync(jsonEncode(_manifest()));
  File(
    p.join(dir.path, 'index.html'),
  ).writeAsStringSync('<!doctype html><html lang="he" dir="rtl"></html>');
  return dir.path;
}

class _StringSink implements StringSink {
  final StringBuffer _buf = StringBuffer();
  @override
  void write(Object? obj) => _buf.write(obj);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _buf.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _buf.writeCharCode(charCode);
  @override
  void writeln([Object? obj = '']) => _buf.writeln(obj);
  @override
  String toString() => _buf.toString();
}

void main() {
  late Directory tempDir;
  late _StringSink outSink;
  late _StringSink errSink;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria_cli_test_');
    outSink = _StringSink();
    errSink = _StringSink();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('PluginPackagerCli.run argument parsing', () {
    test('returns 0 and packs when given a valid directory', () async {
      final dir = _writePluginDir(tempDir);

      final code = await PluginPackagerCli.run(
        [dir],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.success);
      expect(errSink.toString(), isEmpty);
      // קובץ פלט נוצר במיקום ברירת המחדל
      final outFile = File(
        p.join(tempDir.path, 'test.cli.plugin-1.0.0.otzplugin'),
      );
      expect(outFile.existsSync(), isTrue);
    });

    test('--help prints usage and returns 0', () async {
      final code = await PluginPackagerCli.run(
        ['--help'],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.success);
      expect(outSink.toString(), contains('שימוש'));
      expect(outSink.toString(), contains('--force'));
      expect(outSink.toString(), contains('--output'));
    });

    test('-h prints usage and returns 0', () async {
      final code = await PluginPackagerCli.run(
        ['-h'],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.success);
      expect(outSink.toString(), contains('שימוש'));
    });

    test('--output writes archive to the specified path', () async {
      // רגרסיה ל-P2: tool/ הסקריפט הקודם התעלם בשקט מ--output. עכשיו
      // שתי הדרכים שקולות ועושות שימוש באותו parser.
      final dir = _writePluginDir(tempDir);
      final customOut = p.join(tempDir.path, 'custom.otzplugin');

      final code = await PluginPackagerCli.run(
        [dir, '--output', customOut],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.success);
      expect(File(customOut).existsSync(), isTrue);
      // לא נוצר הקובץ בנתיב ברירת המחדל
      expect(
        File(
          p.join(tempDir.path, 'test.cli.plugin-1.0.0.otzplugin'),
        ).existsSync(),
        isFalse,
      );
    });

    test('-o (short form) writes archive to the specified path', () async {
      final dir = _writePluginDir(tempDir);
      final customOut = p.join(tempDir.path, 'short.otzplugin');

      final code = await PluginPackagerCli.run(
        [dir, '-o', customOut],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.success);
      expect(File(customOut).existsSync(), isTrue);
    });

    test('--output=<path> (joined form) is accepted', () async {
      final dir = _writePluginDir(tempDir);
      final customOut = p.join(tempDir.path, 'joined.otzplugin');

      final code = await PluginPackagerCli.run(
        [dir, '--output=$customOut'],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.success);
      expect(File(customOut).existsSync(), isTrue);
    });

    test('--output without a value returns usage error (64)', () async {
      final dir = _writePluginDir(tempDir);

      final code = await PluginPackagerCli.run(
        [dir, '--output'],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.usageError);
      expect(errSink.toString(), contains('חסר ערך'));
    });

    test('unknown flag returns usage error (64)', () async {
      // רגרסיה ל-P2: בעבר --whatever היה נשמט בשקט.
      final dir = _writePluginDir(tempDir);

      final code = await PluginPackagerCli.run(
        [dir, '--no-such-flag'],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.usageError);
      expect(errSink.toString(), contains('--no-such-flag'));
    });

    test('two positional dir arguments return usage error (64)', () async {
      // רגרסיה ל-P2: בעבר ארגומנט עודף היה נשמט.
      final dir = _writePluginDir(tempDir);

      final code = await PluginPackagerCli.run(
        [dir, p.join(tempDir.path, 'other-dir')],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.usageError);
      expect(errSink.toString(), contains('אחד בלבד'));
    });

    test('--force overwrites an existing output', () async {
      final dir = _writePluginDir(tempDir);
      final customOut = p.join(tempDir.path, 'forced.otzplugin');
      File(customOut).writeAsStringSync('stale');

      final code = await PluginPackagerCli.run(
        [dir, '--output', customOut, '--force'],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.success);
      // ZIP מתחיל ב-PK
      final bytes = File(customOut).readAsBytesSync();
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });

    test(
      'without --force, an existing output yields blockingError (1)',
      () async {
        final dir = _writePluginDir(tempDir);
        final customOut = p.join(tempDir.path, 'taken.otzplugin');
        File(customOut).writeAsStringSync('stale');

        final code = await PluginPackagerCli.run(
          [dir, '--output', customOut],
          out: outSink,
          err: errSink,
        );

        expect(code, PluginPackagerCliExitCode.blockingError);
        expect(errSink.toString(), contains('--force'));
      },
    );

    test('non-existent directory yields blockingError (1)', () async {
      final code = await PluginPackagerCli.run(
        [p.join(tempDir.path, 'nope')],
        out: outSink,
        err: errSink,
      );

      expect(code, PluginPackagerCliExitCode.blockingError);
      expect(errSink.toString(), contains('שגיאה'));
    });

    test('no dir argument falls back to currentDirectory', () async {
      final dir = _writePluginDir(tempDir);

      final code = await PluginPackagerCli.run(
        const [],
        out: outSink,
        err: errSink,
        currentDirectory: dir,
      );

      expect(code, PluginPackagerCliExitCode.success);
      expect(
        File(
          p.join(tempDir.path, 'test.cli.plugin-1.0.0.otzplugin'),
        ).existsSync(),
        isTrue,
      );
    });

    test('archive content survives end-to-end', () async {
      // Sanity: הפלט באמת זיפ תקין שניתן לחילוץ.
      final dir = _writePluginDir(tempDir);
      final out = p.join(tempDir.path, 'roundtrip.otzplugin');

      await PluginPackagerCli.run(
        [dir, '-o', out],
        out: outSink,
        err: errSink,
      );

      final bytes = File(out).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll({'manifest.json', 'index.html'}));
    });
  });
}
