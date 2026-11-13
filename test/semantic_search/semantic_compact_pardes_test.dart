import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_family.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticHighlightTarget;

import 'semantic_test_support.dart';

void main() {
  const family = SemanticVectorsFamily.pardesWindows;
  final published = kSemanticModelReleases[SemanticQuantization.int8]!;
  final releases = {
    SemanticQuantization.int8: SemanticModelRelease(
      family: family,
      baseUrl: 'https://models.test/pardes',
      graph: published.graph,
      tokenizer: published.tokenizer,
      identity: published.identity,
      license: published.license,
      notice: published.notice,
    ),
    SemanticQuantization.fp32: null,
  };

  test('זהות פרדס המצורפת תואמת בדיוק להורדה ונבדלת מהמודל הישן', () {
    final bytes = File(family.identityAsset).readAsBytesSync();
    final identity = SemanticModelIdentity.parse(utf8.decode(bytes));
    expect(bytes.length, published.identity.size);
    expect(sha256.convert(bytes).toString(), published.identity.sha256);
    expect(published.family, family);
    expect(identity.familyId, 'otzaria/Pardes-QA491-int8-384');
    expect(identity.embeddingDim, 384);
    expect(identity.tokenizerChecksum, published.tokenizer.sha256);
    expect(identity.queryPackages, hasLength(1));
    expect(identity.packageFor(SemanticQuantization.fp32), isNull);
    expect(published.passageGraph, isNull);
    expect(published.graph.name, 'model.onnx');
    expect(published.notice?.name, 'Pardes_NOTICE.txt');
    expect(
      SemanticModelIdentity.parse(
        bundledModelJson(SemanticVectorsFamily.anchor),
      ).familyId,
      isNot(identity.familyId),
    );
  });

  test('UInt64 גבוה נקרא ללא עיגול גם במודל וגם במניפסט', () {
    final raw = bundledModelJson(family);
    final adjacent = raw.replaceFirst(
      '13334152532150206612',
      '13334152532150206613',
    );
    // jsonDecode לבדו מעגל את שני המספרים לאותו double.
    expect(
      (jsonDecode(raw) as Map)['chunking_identity'],
      (jsonDecode(adjacent) as Map)['chunking_identity'],
    );
    final first = SemanticModelIdentity.parse(raw);
    final second = SemanticModelIdentity.parse(adjacent);
    expect(first.chunkingIdentity, isNot(second.chunkingIdentity));
    expect(
      BigInt.from(first.chunkingIdentity).toUnsigned(64).toString(),
      '13334152532150206612',
    );
    final manifest = '{"identity":{"model":$raw}}';
    expect(
      SemanticVectorsRelease.identityOf(
        jsonDecode(manifest) as Map<String, dynamic>,
        rawJson: manifest,
      ).chunkingIdentity,
      first.chunkingIdentity,
    );
    expect(
      () => SemanticModelIdentity.parse(
        raw.replaceFirst('13334152532150206612', '18446744073709551616'),
      ),
      throwsFormatException,
    );
  });

  group('מעבר אטומי לוקטורים של פרדס', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('compact_pardes_app_');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('פרסום Meivin אינו מפעיל הורדת פרדס או התקנת אינדקס שגוי', () async {
      final backend = FakeBackend()
        ..supportsLongLineWindows = true
        ..vectors = const SemanticVectorsSummary(
          present: true,
          modelFamilyId: 'otzaria/Meivin-Embed-QA491-native256',
          libraryVersion: 30,
        );
      final locator = FakeLocator(
        releaseV30(family: SemanticVectorsFamily.anchor),
      );
      final downloads = FakeDownloads();
      final repository = buildRepository(
        root: root,
        backend: backend,
        locator: locator,
        download: downloads.call,
        modelReleases: releases,
        settings: FakeSettingsStore()..dataEnabled = true,
      );
      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
      expect(locator.candidates.single.map((c) => c.family), [family]);
      expect(downloads.urls, isEmpty);
      expect(backend.installRequests, isEmpty);
      expect(
        backend.vectors.modelFamilyId,
        'otzaria/Meivin-Embed-QA491-native256',
      );
      expect(
        repository.availability.phase,
        SemanticAvailabilityPhase.vectorsNotPublished,
      );
    });

    test(
      'פרסום תואם מחליף באותה ספרייה, פותח פרדס ולא מוריד גרף פסקאות',
      () async {
        final backend = FakeBackend()
          ..supportsLongLineWindows = true
          ..vectors = const SemanticVectorsSummary(
            present: true,
            modelFamilyId: 'otzaria/Meivin-Embed-QA491-native256',
            libraryVersion: 30,
          )
          ..installedIdentityDigest = '22' * 32;
        final locator = FakeLocator(
          releaseV30(family: family, identityDigest: '22' * 32),
        );
        final downloads = FakeDownloads();
        final repository = buildRepository(
          root: root,
          backend: backend,
          locator: locator,
          download: downloads.call,
          modelReleases: releases,
          settings: FakeSettingsStore()..dataEnabled = true,
        );
        repository.scheduleVectorsUpdate();
        await repository.pendingJob;
        expect(
          backend.installRequests.single.modelIdentityJson,
          bundledModelJson(family),
        );
        expect(backend.vectors.modelFamilyId, 'otzaria/Pardes-QA491-int8-384');
        expect(locator.chainLookups, isEmpty);
        await repository.ensureOpen();
        expect(
          backend.openRequests.single.modelIdentityJson,
          bundledModelJson(family),
        );
        expect(backend.openRequests.single.modelPath, endsWith('model.onnx'));
        final before = downloads.urls.length;
        await repository.passageHighlights('מצות תפילין', [
          SemanticHighlightTarget(filePath: 'id:1', id: BigInt.one),
        ], SemanticCancelHandle());
        expect(downloads.urls.length, before);
        expect(
          downloads.urls.where((url) => url.endsWith('Pardes_NOTICE.txt')),
          hasLength(1),
        );
        expect(
          downloads.urls.where((url) => url.endsWith('document.fp32.onnx')),
          isEmpty,
        );
        repository.scheduleVectorsUpdate();
        await repository.pendingJob;
        expect(backend.installRequests, hasLength(1));
        expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
        await repository.releaseForLibraryMove();
      },
    );
  });
}
