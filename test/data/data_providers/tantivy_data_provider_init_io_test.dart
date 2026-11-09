import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as p;

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// פתיחת המנוע רצה ב-UI isolate בעלייה, ולכן אסור לה IO סינכרוני על תיקיית
/// האינדקס — בדיסק איטי או מסונן זה מקפיא את החלון.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  group('TantivyDataProvider — פתיחת המנוע בלי IO סינכרוני', () {
    late Directory root;
    late Directory indexDir;

    setUp(() async {
      if (!engineReady) return;
      root = Directory.systemTemp.createTempSync('otzaria_init_io_');
      indexDir = Directory(p.join(root.path, 'index'))..createSync();
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue(SettingsRepository.keyIndexPath, indexDir.path);
      AppPaths.debugOverrideDataRootPath(p.join(root.path, 'data'));
    });

    tearDown(() async {
      if (!engineReady) return;
      await TantivyDataProvider.instance.dispose();
      AppPaths.debugOverrideDataRootPath(null);
      await Settings.clearCache();
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // ב-Windows המנוע עלול להחזיק קבצים פתוחים בסיום הטסט.
      }
    });

    test(
      'סנטינל של שני כשלונות: האינדקס מוזז הצידה ונפתח מחדש בלי קריאה סינכרונית',
      () async {
        // הסינגלטון פותח מנוע כבר ביצירתו — ממתינים לו לפני הכנת הסנטינל.
        final provider = TantivyDataProvider.instance;
        await provider.engine;
        final sentinel = File(p.join(root.path, '.engine_init_started'));
        sentinel.writeAsStringSync('2');
        final spy = _SyncIoSpy(root.path);

        await IOOverrides.runWithIOOverrides(
          () => provider.reopenIndex(force: true),
          spy,
        );
        await provider.engine;

        expect(spy.unsupported, isEmpty);
        expect(spy.syncCalls, isEmpty);
        expect(provider.isTempFallback, isFalse);
        expect(provider.activeIndexPath, indexDir.path);
        expect(sentinel.existsSync(), isFalse);
        expect(
          spy.asyncCalls,
          containsAll(<String>['readAsString', 'rename', 'create']),
          reason: 'הטסט חייב לעבור במסלולי הסנטינל וההסגר',
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });
}

/// עוטף רק ישויות תחת תיקיית הטסט, ורושם כל קריאת IO סינכרונית עליהן.
final class _SyncIoSpy extends IOOverrides {
  _SyncIoSpy(this.rootPath);

  final String rootPath;
  final syncCalls = <String>[];
  final asyncCalls = <String>{};
  final unsupported = <String>[];

  bool _tracks(String path) =>
      p.equals(path, rootPath) || p.isWithin(rootPath, path);

  @override
  Directory createDirectory(String path) {
    final inner = super.createDirectory(path);
    return _tracks(path) ? _SpyDirectory(inner, this) : inner;
  }

  @override
  File createFile(String path) {
    final inner = super.createFile(path);
    return _tracks(path) ? _SpyFile(inner, this) : inner;
  }

  void _sync(String name, String path) => syncCalls.add('$name $path');
}

class _SpyDirectory implements Directory {
  _SpyDirectory(this._inner, this._spy);

  final Directory _inner;
  final _SyncIoSpy _spy;

  T _async<T>(String name, T result) {
    _spy.asyncCalls.add(name);
    return result;
  }

  @override
  String get path => _inner.path;
  @override
  Uri get uri => _inner.uri;
  @override
  bool get isAbsolute => _inner.isAbsolute;
  @override
  Directory get absolute => Directory(_inner.absolute.path);
  @override
  Directory get parent => Directory(_inner.parent.path);

  @override
  Future<bool> exists() => _async('exists', _inner.exists());
  @override
  bool existsSync() {
    _spy._sync('existsSync', path);
    return _inner.existsSync();
  }

  @override
  Future<Directory> create({bool recursive = false}) =>
      _async('create', _inner.create(recursive: recursive));
  @override
  void createSync({bool recursive = false}) {
    _spy._sync('createSync', path);
    _inner.createSync(recursive: recursive);
  }

  @override
  Future<Directory> rename(String newPath) =>
      _async('rename', _inner.rename(newPath));
  @override
  Directory renameSync(String newPath) {
    _spy._sync('renameSync', path);
    return _inner.renameSync(newPath);
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _async('delete', _inner.delete(recursive: recursive));
  @override
  void deleteSync({bool recursive = false}) {
    _spy._sync('deleteSync', path);
    _inner.deleteSync(recursive: recursive);
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => _async(
    'list',
    _inner.list(recursive: recursive, followLinks: followLinks),
  );
  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) {
    _spy._sync('listSync', path);
    return _inner.listSync(recursive: recursive, followLinks: followLinks);
  }

  @override
  Future<FileStat> stat() => _async('stat', _inner.stat());
  @override
  FileStat statSync() {
    _spy._sync('statSync', path);
    return _inner.statSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    _spy.unsupported.add('Directory.${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class _SpyFile implements File {
  _SpyFile(this._inner, this._spy);

  final File _inner;
  final _SyncIoSpy _spy;

  T _async<T>(String name, T result) {
    _spy.asyncCalls.add(name);
    return result;
  }

  @override
  String get path => _inner.path;
  @override
  Uri get uri => _inner.uri;
  @override
  bool get isAbsolute => _inner.isAbsolute;
  @override
  File get absolute => File(_inner.absolute.path);
  @override
  Directory get parent => Directory(_inner.parent.path);

  @override
  Future<bool> exists() => _async('exists', _inner.exists());
  @override
  bool existsSync() {
    _spy._sync('existsSync', path);
    return _inner.existsSync();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _async('readAsString', _inner.readAsString(encoding: encoding));
  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    _spy._sync('readAsStringSync', path);
    return _inner.readAsStringSync(encoding: encoding);
  }

  @override
  Future<Uint8List> readAsBytes() =>
      _async('readAsBytes', _inner.readAsBytes());
  @override
  Uint8List readAsBytesSync() {
    _spy._sync('readAsBytesSync', path);
    return _inner.readAsBytesSync();
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _async(
    'writeAsString',
    _inner.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    ),
  );
  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    _spy._sync('writeAsStringSync', path);
    _inner.writeAsStringSync(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _async(
    'writeAsBytes',
    _inner.writeAsBytes(bytes, mode: mode, flush: flush),
  );

  @override
  Future<int> length() => _async('length', _inner.length());

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _async('delete', _inner.delete(recursive: recursive));
  @override
  void deleteSync({bool recursive = false}) {
    _spy._sync('deleteSync', path);
    _inner.deleteSync(recursive: recursive);
  }

  @override
  Future<File> rename(String newPath) =>
      _async('rename', _inner.rename(newPath));

  @override
  Future<FileStat> stat() => _async('stat', _inner.stat());

  @override
  dynamic noSuchMethod(Invocation invocation) {
    _spy.unsupported.add('File.${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}
