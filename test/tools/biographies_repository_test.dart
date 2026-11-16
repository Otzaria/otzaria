import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/biographies/data/author_biography_links.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';

import 'biographies_codec_test.dart' show encodeBundle, samplePayload;

void main() {
  late Directory tempDir;
  late String updatedPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bio_repo_test_');
    updatedPath = '${tempDir.path}${Platform.pathSeparator}bio.json.gz';
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Map<String, dynamic> payloadWithRelease(String release) =>
      samplePayload()..['release'] = release;

  BiographiesRepository repository({Uint8List? asset}) => BiographiesRepository(
    updatedPathProvider: () async => updatedPath,
    loadAsset: (key) async {
      expect(key, BiographiesRepository.bundledAssetKey);
      if (asset == null) throw StateError('no asset');
      return ByteData.sublistView(asset);
    },
  );

  test('matches exact catalog names and IDs, with an offline fallback', () async {
    final payload = samplePayload();
    final id = (payload['entries'] as List).first['id'] as String;
    final bundledLinks = jsonEncode({
      'version': 1,
      'authors': {'מחבר א': id, 'מחבר ב': 'missing'},
    });
    final linksFile = File(
      '${tempDir.path}${Platform.pathSeparator}${AuthorBiographyLinks.fileName}',
    );
    await linksFile.writeAsString('corrupt');
    final repo = BiographiesRepository(
      updatedPathProvider: () async => updatedPath,
      loadAsset: (key) async => ByteData.sublistView(
        key == AuthorBiographyLinks.assetKey
            ? utf8.encode(bundledLinks)
            : encodeBundle(payload),
      ),
    );
    final found = await repo.forCatalogAuthors(['מחבר א', 'מחבר ב', 'מחבר']);
    expect(found.keys, ['מחבר א']);
    expect(found['מחבר א']?.id, id);

    await linksFile.writeAsString('{"version":1,"authors":{}}');
    expect(await repo.forCatalogAuthors(['מחבר א']), isEmpty);
  });

  test('prefers the downloaded copy', () async {
    await File(updatedPath)
        .writeAsBytes(encodeBundle(payloadWithRelease('new')));
    final bundle = await repository(
      asset: encodeBundle(payloadWithRelease('packed')),
    ).loadBundle();
    expect(bundle.release, 'new');
  });

  test(
    'falls back to the packed copy when the download is unreadable',
    () async {
      await File(updatedPath).writeAsBytes([1, 2, 3]);
      final bundle = await repository(
        asset: encodeBundle(payloadWithRelease('packed')),
      ).loadBundle();
      expect(bundle.release, 'packed');
    },
  );

  test('throws when no copy exists, and retries on the next call', () async {
    final repo = repository();
    await expectLater(repo.loadAll(), throwsStateError);

    await File(
      updatedPath,
    ).writeAsBytes(encodeBundle(payloadWithRelease('new')));
    expect((await repo.loadAll()).length, 2);
  });
}
