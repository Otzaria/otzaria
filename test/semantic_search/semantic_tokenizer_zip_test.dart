import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled;

import 'semantic_test_support.dart';

const _base = 'https://model.test';

/// release שה-URL שלו עונה בבתים או בשגיאה; כל בקשה נרשמת.
class _Server {
  final Map<String, Object> responses;
  final List<String> urls = [];

  _Server(this.responses);

  Future<void> call({
    required String url,
    required String destPath,
    required String resumeIdentity,
    int? expectedSize,
    String? expectedSha256,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    urls.add(url);
    final response = responses[url];
    if (response is! List<int>) throw response ?? StateError('no $url');
    await File(destPath).create(recursive: true);
    await File(destPath).writeAsBytes(response);
    onProgress?.call(response.length, response.length);
  }
}

SemanticModelFile _file(
  String name,
  List<int> bytes, {
  SemanticModelFile? zipped,
}) => SemanticModelFile(
  name: name,
  size: bytes.length,
  sha256: sha256.convert(bytes).toString(),
  zipped: zipped,
);

List<int> _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach(
    (name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)),
  );
  return ZipEncoder().encode(archive);
}

void main() {
  late Directory root;
  late SemanticPaths paths;
  final tokenizer = utf8.encode('{"version":"1.0","model":{"vocab":{}}}');
  final zip = _zip({kSemanticTokenizerFileName: tokenizer});
  final tokenizerUrl = '$_base/$kSemanticTokenizerFileName';
  final zipUrl = '$_base/$kSemanticTokenizerFileName.zip';

  setUp(() {
    root = Directory.systemTemp.createTempSync('semantic_tokenizer_zip_');
    paths = SemanticPaths(p.join(root.path, 'otzaria'));
    installModelFiles(root);
    File(paths.tokenizerFile).deleteSync();
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// מוריד את ה-tokenizer החסר מ-[server], כש-[archive] הוא ה-zip המפורסם.
  Future<SemanticFailure?> install(_Server server, {List<int>? archive}) async {
    final shipped = archive ?? zip;
    final release = SemanticModelRelease(
      baseUrl: _base,
      graph: testModelReleases[SemanticQuantization.int8]!.graph,
      tokenizer: _file(
        kSemanticTokenizerFileName,
        tokenizer,
        zipped: _file('$kSemanticTokenizerFileName.zip', shipped),
      ),
      identity: testModelReleases[SemanticQuantization.int8]!.identity,
      license: testModelReleases[SemanticQuantization.int8]!.license,
    );
    final repo = buildRepository(
      root: root,
      backend: FakeBackend()..vectors = installedV30,
      download: server.call,
      modelReleases: {SemanticQuantization.int8: release},
    );
    await repo.enableAndDownload();
    return repo.availability.failure;
  }

  List<String> leftovers() => Directory(paths.modelDirectory)
      .listSync()
      .map((entity) => p.basename(entity.path))
      .where((name) => name.contains('.part') || name.endsWith('.zip'))
      .toList();

  test('the published tokenizer.json.zip is the one pinned', () {
    final published = kSemanticModelReleases[SemanticQuantization.int8]!;
    expect(published.tokenizer.zipped, isNotNull);
    expect(published.tokenizer.zipped!.name, 'tokenizer.json.zip');
    expect(published.tokenizer.zipped!.zipped, isNull);
    expect(published.graph.zipped, isNull);
    expect(published.license.zipped, isNull);
    expect(published.identity.zipped, isNull);
  });

  test('a tokenizer that downloads is never fetched as a zip', () async {
    final server = _Server({tokenizerUrl: tokenizer, zipUrl: zip});
    expect(await install(server), isNull);
    expect(server.urls, [tokenizerUrl]);
    expect(File(paths.tokenizerFile).readAsBytesSync(), tokenizer);
  });

  for (final (label, error) in [
    ('a network failure', const SocketException('blocked')),
    ('a body that fails its digest', StateError('checksum mismatch')),
  ]) {
    test('$label falls back to the zip and installs its tokenizer', () async {
      final server = _Server({tokenizerUrl: error, zipUrl: zip});
      expect(await install(server), isNull);
      expect(server.urls, [tokenizerUrl, zipUrl]);
      expect(File(paths.tokenizerFile).readAsBytesSync(), tokenizer);
      expect(leftovers(), isEmpty);
    });
  }

  test('a cancelled download is not retried as a zip', () async {
    final server = _Server({
      tokenizerUrl: const PatchDownloadCancelled(),
      zipUrl: zip,
    });
    await install(server);
    expect(server.urls, [tokenizerUrl]);
    expect(File(paths.tokenizerFile).existsSync(), isFalse);
  });

  test('a zip that fails too reports its own failure', () async {
    final server = _Server({
      tokenizerUrl: const SocketException('blocked'),
      zipUrl: const SocketException('blocked too'),
    });
    expect((await install(server))?.kind, SemanticFailureKind.network);
    expect(server.urls, [tokenizerUrl, zipUrl]);
    expect(File(paths.tokenizerFile).existsSync(), isFalse);
  });

  for (final (label, archive) in [
    ('other content', _zip({kSemanticTokenizerFileName: utf8.encode('{}')})),
    ('another entry name', _zip({'other.json': tokenizer})),
    (
      'a second entry',
      _zip({
        kSemanticTokenizerFileName: tokenizer,
        'extra.txt': [1],
      }),
    ),
    ('no zip at all', tokenizer),
  ]) {
    test('a zip holding $label installs nothing', () async {
      final server = _Server({
        tokenizerUrl: const SocketException('blocked'),
        zipUrl: archive,
      });
      expect(
        (await install(server, archive: archive))?.kind,
        SemanticFailureKind.checksumMismatch,
      );
      expect(File(paths.tokenizerFile).existsSync(), isFalse);
      expect(leftovers(), isEmpty);
    });
  }

  test('a file with no zip fails as before', () async {
    File(paths.licenseFile).deleteSync();
    final license = testModelReleases[SemanticQuantization.int8]!.license;
    final server = _Server({
      tokenizerUrl: tokenizer,
      '$_base/${license.name}': const SocketException('blocked'),
    });
    expect((await install(server))?.kind, SemanticFailureKind.network);
    expect(server.urls.where((url) => url.endsWith('.zip')), isEmpty);
  });
}
