import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_import_layout.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria/semantic_search/repository/semantic_release_locator.dart';
import 'package:otzaria/semantic_search/repository/semantic_staged_import.dart';
import 'package:otzaria/semantic_search/semantic_work_status.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled;

import 'semantic_test_support.dart';

const _tag = 'v30-20260930165019';
const _segmentName = 'otzaria-vectors-0c3f95be-v30-base.oxv.zst';
const _manifestName = 'otzaria-vectors-0c3f95be-v30-base.manifest.json';

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

SemanticModelFile _modelFile(String name, String content) => SemanticModelFile(
  name: name,
  size: utf8.encode(content).length,
  sha256: _sha(utf8.encode(content)),
);

/// release מודל קטן, כדי שקבצים מוכנים יתאימו לו בבדיקה.
final Map<SemanticQuantization, SemanticModelRelease?> _smallModel = {
  SemanticQuantization.int8: SemanticModelRelease(
    baseUrl: 'https://models.test/meivin',
    graph: _modelFile(SemanticQuantization.int8.modelFileName, 'graph'),
    tokenizer: _modelFile(kSemanticTokenizerFileName, 'tokenizer'),
    identity: _modelFile(kSemanticModelIdentityFileName, bundledModelJson()),
    license: _modelFile(kSemanticModelLicenseFileName, 'license'),
  ),
  SemanticQuantization.fp32: null,
};

/// מניפסט וקטורים בצורה שמתפרסמת ב-SeforimLibrary.
String _manifest({String segment = 'segment', int version = 30}) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': 'otzaria-vectors-release',
      'kind': 'base',
      'fromLibraryVersion': 0,
      'toLibraryVersion': version,
      'libraryReleaseTag': 'v$version-20260930165019',
      'segment': {'sha256': 'cd' * 32, 'size': 99},
      'files': [
        {
          'file': _segmentName,
          'sha256': _sha(utf8.encode(segment)),
          'size': utf8.encode(segment).length,
        },
      ],
    });

class _UnreachableLocator extends SemanticVectorsReleaseLocator {
  int lookups = 0;

  @override
  Future<SemanticVectorsRelease?> findForLibraryVersion(
    int libraryVersion, {
    String? libraryTag,
  }) async {
    lookups++;
    throw const SocketException('no network');
  }
}

class _TransferFile extends Fake implements File {
  _TransferFile(
    this.file, {
    required this.crossVolume,
    required this.onTransfer,
    this.unreadable = false,
  });

  final File file;
  final bool unreadable;
  final bool crossVolume;
  final void Function() onTransfer;

  @override
  String get path => file.path;

  @override
  Future<FileStat> stat() async {
    if (unreadable) throw const FileSystemException('permission denied');
    return file.stat();
  }

  @override
  Future<File> rename(String newPath) async {
    if (crossVolume) throw const FileSystemException('cross-volume rename');
    final moved = await file.rename(newPath);
    onTransfer();
    return moved;
  }

  @override
  Future<File> copy(String newPath) async {
    final copied = await file.copy(newPath);
    onTransfer();
    return copied;
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);
}

class _TransferImport extends SemanticStagedImport {
  _TransferImport(SemanticPaths paths, this.file) : super(() async => paths);

  final File file;

  @override
  Future<File?> stagedFile(String name) async => file;
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_staged_'));
  tearDown(() async {
    for (var attempt = 0; attempt < 5 && root.existsSync(); attempt++) {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  SemanticPaths paths() => SemanticPaths(p.join(root.path, 'otzaria'));
  String staged(String folder, String name) => p.join(
    root.path,
    kSemanticImportFolderName,
    folder,
    name,
  );

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  /// מה שמסייע ההורדה מכין: קובצי המודל, ה-segment והמניפסט.
  String stageAll({String segment = 'segment'}) {
    final model = _smallModel[SemanticQuantization.int8]!;
    write(staged(kSemanticModelFolderName, model.graph.name), 'graph');
    write(staged(kSemanticModelFolderName, model.tokenizer.name), 'tokenizer');
    write(
      staged(kSemanticModelFolderName, model.identity.name),
      bundledModelJson(),
    );
    write(staged(kSemanticModelFolderName, model.license.name), 'license');
    write(staged(kSemanticImportVectorsFolderName, _segmentName), segment);
    final manifest = _manifest();
    write(staged(kSemanticImportVectorsFolderName, _manifestName), manifest);
    return manifest;
  }

  for (final crossVolume in [false, true]) {
    test('ביטול בזמן העברה משמר מקור (כונן אחר: $crossVolume)', () async {
      final source = File(
        staged(kSemanticImportVectorsFolderName, _segmentName),
      );
      write(source.path, 'segment');
      var cancelled = false;
      final importer = _TransferImport(
        paths(),
        _TransferFile(
          source,
          crossVolume: crossVolume,
          onTransfer: () => cancelled = true,
        ),
      );
      final downloads = FakeDownloads();
      final wrapped = importer.wrap(downloads.call, isOffline: () => false);
      final dest = p.join(paths().vectorsDownloadDirectory, _segmentName);
      await expectLater(
        wrapped(
          url: semanticVectorsAssetUrl(_tag, _segmentName),
          destPath: dest,
          resumeIdentity: 'test',
          expectedSize: 7,
          expectedSha256: _sha(utf8.encode('segment')),
          isCancelled: () => cancelled,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(source.readAsStringSync(), 'segment');
      expect(
        File(dest).existsSync(),
        crossVolume,
        reason: 'עותק שלם נשמר להמשך; rename מבוטל מוחזר למקור',
      );
      expect(downloads.urls, isEmpty);
    });
  }

  for (final afterHash in [false, true]) {
    test('ביטול לפני העברה משמר מקור ויעד (אחרי hash: $afterHash)', () async {
      final source = File(
        staged(kSemanticImportVectorsFolderName, _segmentName),
      );
      write(source.path, 'segment');
      final dest = p.join(paths().vectorsDownloadDirectory, _segmentName);
      write(dest, 'existing partial');
      var cancelled = !afterHash;
      final downloads = FakeDownloads();
      final importer = SemanticStagedImport(() async => paths());
      await expectLater(
        importer.wrap(
          downloads.call,
          isOffline: () => false,
          onChecking: (checking) {
            if (!checking) cancelled = true;
          },
        )(
          url: semanticVectorsAssetUrl(_tag, _segmentName),
          destPath: dest,
          resumeIdentity: 'test',
          expectedSize: 7,
          expectedSha256: _sha(utf8.encode('segment')),
          isCancelled: () => cancelled,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(source.readAsStringSync(), 'segment');
      expect(File(dest).readAsStringSync(), 'existing partial');
      expect(downloads.urls, isEmpty);
    });
  }

  test('אימות קודם אינו מאשר קובץ ששונה באותו גודל', () async {
    final source = File(staged(kSemanticImportVectorsFolderName, _segmentName));
    write(source.path, 'segment');
    final importer = SemanticStagedImport(() async => paths());
    final digest = _sha(utf8.encode('segment'));
    expect(
      await importer.verifiedStagedFile(_segmentName, 7, digest),
      isNotNull,
    );
    write(source.path, 'damaged');
    // הפרדה מפורשת של timestamp כדי שהבדיקה לא תלויה ברזולוציית מערכת הקבצים.
    source.setLastModifiedSync(DateTime(2000));
    expect(await importer.verifiedStagedFile(_segmentName, 7, digest), isNull);
    final downloads = FakeDownloads();
    await importer.wrap(downloads.call, isOffline: () => false)(
      url: semanticVectorsAssetUrl(_tag, _segmentName),
      destPath: p.join(paths().vectorsDownloadDirectory, _segmentName),
      resumeIdentity: 'test',
      expectedSize: 7,
      expectedSha256: digest,
    );
    expect(downloads.urls, hasLength(1));
    expect(source.readAsStringSync(), 'damaged');
  });

  test('קובץ שאינו קריא אינו מאומץ', () async {
    final source = File(staged(kSemanticImportVectorsFolderName, _segmentName));
    write(source.path, 'segment');
    final importer = _TransferImport(
      paths(),
      _TransferFile(
        source,
        crossVolume: false,
        onTransfer: () {},
        unreadable: true,
      ),
    );
    expect(
      await importer.verifiedStagedFile(
        _segmentName,
        7,
        _sha(utf8.encode('segment')),
      ),
      isNull,
    );
  });

  test('נתונים מוכנים ותקינים מותקנים בלי רשת', () async {
    final manifest = stageAll();
    final backend = FakeBackend();
    final downloads = FakeDownloads()..error = const SocketException('none');
    final locator = _UnreachableLocator();
    final repository = buildRepository(
      root: root,
      backend: backend,
      locator: locator,
      download: downloads.call,
      modelReleases: _smallModel,
    );

    await repository.enableAndDownload();

    expect(downloads.urls, isEmpty, reason: 'שום קובץ לא ירד');
    expect(locator.lookups, 1);
    final install = backend.installRequests.single;
    expect(install.manifestJson, manifest);
    expect(install.publishedManifestSha256, _sha(utf8.encode(manifest)));
    expect(
      install.segmentPath,
      p.join(paths().vectorsDownloadDirectory, _segmentName),
    );
    expect(
      File(paths().modelFile(SemanticQuantization.int8)).readAsStringSync(),
      'graph',
    );
    expect(File(paths().tokenizerFile).existsSync(), isTrue);
    expect(File(paths().licenseFile).existsSync(), isTrue);
    expect(
      File(staged(kSemanticImportVectorsFolderName, _segmentName)).existsSync(),
      isFalse,
      reason: 'הקובץ הועבר ולא שוכפל',
    );
    expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
  });

  test(
    'נתונים מוכנים מזוהים לפני הלחיצה, והתקנתם אינה מוצגת כהורדה (issue #2298)',
    () async {
      stageAll();
      final repository = buildRepository(
        root: root,
        backend: FakeBackend(),
        locator: _UnreachableLocator(),
        download: (FakeDownloads()..error = const SocketException('none')).call,
        modelReleases: _smallModel,
      );

      final before = await repository.refresh();
      expect(before.phase, SemanticAvailabilityPhase.needsDownload);
      expect(before.stagedDataFound, isTrue);

      final labels = <String>{};
      final subscription = repository.availabilityChanges.listen((a) {
        final progress = a.progress;
        if (progress != null) {
          labels.add(SemanticSearchMessages.progressAction(progress));
        }
      });
      await repository.enableAndDownload();
      await subscription.cancel();

      expect(labels, isNot(contains(SemanticSearchMessages.downloadingData)));
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
      expect(repository.availability.stagedDataFound, isFalse);
    },
  );

  test('במצב לא מקוון — מותקן מהנתונים המוכנים בלי לפנות לרשת', () async {
    stageAll();
    final backend = FakeBackend();
    final downloads = FakeDownloads();
    final locator = FakeLocator(releaseV30());
    final repository = buildRepository(
      root: root,
      backend: backend,
      settings: FakeSettingsStore()..isOfflineMode = true,
      locator: locator,
      download: downloads.call,
      modelReleases: _smallModel,
    );

    await repository.enableAndDownload();

    expect(locator.lookups, isEmpty);
    expect(downloads.urls, isEmpty);
    expect(backend.installRequests, hasLength(1));
  });

  test('קובץ מוכן שאינו תואם — יורד מהרשת במקומו', () async {
    stageAll(segment: 'corrupted');
    final release = SemanticStagedImport.parseStagedManifest(
      utf8.encode(_manifest()),
      30,
    )!;
    final backend = FakeBackend();
    final downloads = FakeDownloads();
    final repository = buildRepository(
      root: root,
      backend: backend,
      locator: FakeLocator(release),
      download: downloads.call,
      modelReleases: _smallModel,
    );

    await repository.enableAndDownload();

    expect(downloads.urls, [semanticVectorsAssetUrl(_tag, _segmentName)]);
    expect(backend.installRequests, hasLength(1));
    expect(
      File(staged(kSemanticImportVectorsFolderName, _segmentName)).existsSync(),
      isTrue,
      reason: 'קובץ שאינו תואם אינו נוגע',
    );
  });

  test('בלי הסכמה — דבר אינו מותקן והנתונים המוכנים נשארים', () async {
    stageAll();
    final backend = FakeBackend();
    final downloads = FakeDownloads();
    final repository = buildRepository(
      root: root,
      backend: backend,
      consent: FakeConsentStore(SearchFeedbackConsent.declined),
      download: downloads.call,
      modelReleases: _smallModel,
    );

    await repository.enableAndDownload();
    repository.scheduleVectorsUpdate();
    await repository.pendingJob;

    expect(backend.installRequests, isEmpty);
    expect(downloads.urls, isEmpty);
    expect(Directory(paths().modelDirectory).existsSync(), isFalse);
    expect(
      File(staged(kSemanticImportVectorsFolderName, _segmentName)).existsSync(),
      isTrue,
    );
    expect(
      repository.availability.phase,
      SemanticAvailabilityPhase.consentRequired,
    );
  });

  for (final remove in [false, true]) {
    test('ביטול במהלך בדיקה משמר את המקור (מחיקה: $remove)', () async {
      stageAll();
      final downloads = FakeDownloads();
      final backend = FakeBackend();
      final repository = buildRepository(
        root: root,
        backend: backend,
        locator: _UnreachableLocator(),
        download: downloads.call,
        modelReleases: _smallModel,
      );
      Future<void>? cancellation;
      final subscription = repository.availabilityChanges.listen((a) {
        if (a.progress?.checking == true && cancellation == null) {
          cancellation = remove
              ? repository.removeData()
              : repository.cancelDownload();
        }
      });
      await repository.enableAndDownload();
      await cancellation;
      await subscription.cancel();

      expect(cancellation, isNotNull);
      for (final file in [
        _smallModel[SemanticQuantization.int8]!.graph,
        _smallModel[SemanticQuantization.int8]!.tokenizer,
        _smallModel[SemanticQuantization.int8]!.identity,
        _smallModel[SemanticQuantization.int8]!.license,
      ]) {
        expect(
          File(staged(kSemanticModelFolderName, file.name)).existsSync(),
          isTrue,
          reason: file.name,
        );
      }
      expect(downloads.urls, isEmpty);
      expect(backend.installRequests, isEmpty);
      expect(File(paths().tokenizerFile).existsSync(), isFalse);
      expect(repository.availability.failure, isNull);
    });
  }

  test('מניפסט מוכן של גרסת ספרייה אחרת אינו משמש', () {
    expect(
      SemanticStagedImport.parseStagedManifest(
        utf8.encode(_manifest(version: 29)),
        30,
      ),
      isNull,
    );
    expect(
      () => SemanticStagedImport.parseStagedManifest(
        utf8.encode(
          '{"kind":"base","toLibraryVersion":30,'
          '"libraryReleaseTag":"$_tag","files":[{"file":"../x",'
          '"size":1,"sha256":"aa"}],"segment":{"size":1}}',
        ),
        30,
      ),
      throwsFormatException,
    );
  });

  test('בלי רשת ובלי נתונים מוכנים — הכשל המקורי נשאר', () async {
    final repository = buildRepository(
      root: root,
      locator: _UnreachableLocator(),
      modelReleases: _smallModel,
    );

    await repository.enableAndDownload();

    expect(
      repository.availability.failure?.kind,
      SemanticFailureKind.network,
    );
  });

  test('בדיקת קובץ מוכן היא שלב בלי מדידה, והבתים נספרים בסך הכולל', () async {
    stageAll();
    final backend = FakeBackend();
    final repository = buildRepository(
      root: root,
      backend: backend,
      locator: _UnreachableLocator(),
      download: (FakeDownloads()..error = const SocketException('none')).call,
      modelReleases: _smallModel,
    );
    final seen = <SemanticDownloadProgress>[];
    final subscription = repository.availabilityChanges.listen((a) {
      final progress = a.progress;
      if (progress != null) seen.add(progress);
    });

    await repository.enableAndDownload();
    await subscription.cancel();

    final checking = seen.where((p) => p.checking).toList();
    // ארבעה קובצי מודל ו-segment אחד.
    expect(checking, hasLength(5));
    expect(checking.every((p) => p.fraction == null), isTrue);
    expect(checking.first.item, SemanticDownloadItem.model);
    expect(checking.last.item, SemanticDownloadItem.vectors);
    expect(
      SemanticSearchMessages.progressAction(checking.last),
      'בודק את הקבצים שהוכנו מראש',
    );
    expect(
      semanticWorkStatusItem(
        SemanticAvailability(
          phase: SemanticAvailabilityPhase.downloading,
          consentGranted: true,
          progress: checking.last,
        ),
        afterJob: false,
        onCancel: () {},
        onRetry: () {},
      )!.progress,
      isNull,
      reason: 'טבעת בלי ערך בזמן הבדיקה',
    );
    final total = checking.first.totalBytes!;
    final model = _smallModel[SemanticQuantization.int8]!;
    expect(total, model.downloadSize + utf8.encode('segment').length);
    final lastDownload = seen.lastWhere(
      (p) => p.item == SemanticDownloadItem.vectors && !p.checking,
    );
    expect(lastDownload.receivedBytes, total);
    expect(backend.installRequests, hasLength(1));
  });

  group('מקום פנוי', () {
    // segment של 7 בתים, ו-99 בתים פרוסים; 100 פנויים מספיקים רק בלי ההורדה.
    Future<SemanticFailureKind?> run(String stagedVolume) async {
      stageAll();
      final backend = FakeBackend();
      final repository = buildRepository(
        root: root,
        backend: backend,
        locator: _UnreachableLocator(),
        modelReleases: _smallModel,
        diskSpace: (path) async => DiskSpaceInfo(
          volumeId: path.contains(kSemanticImportFolderName)
              ? stagedVolume
              : 'C',
          freeBytes: 100,
        ),
      );
      await repository.enableAndDownload();
      return repository.availability.failure?.kind;
    }

    test('קובץ פגום באותו גודל ובאותו כונן נספר לפני הורדה', () async {
      stageAll(segment: 'damaged');
      final downloads = FakeDownloads();
      final backend = FakeBackend();
      final repository = buildRepository(
        root: root,
        backend: backend,
        locator: _UnreachableLocator(),
        download: downloads.call,
        modelReleases: _smallModel,
        diskSpace: (_) async =>
            const DiskSpaceInfo(volumeId: 'C', freeBytes: 100),
      );
      await repository.enableAndDownload();
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.insufficientDiskSpace,
      );
      expect(downloads.urls, isEmpty);
      expect(backend.installRequests, isEmpty);
      expect(
        File(
          staged(kSemanticImportVectorsFolderName, _segmentName),
        ).readAsStringSync(),
        'damaged',
      );
    });

    test('קובץ חסר נספר לפני הורדה', () async {
      stageAll();
      File(staged(kSemanticImportVectorsFolderName, _segmentName)).deleteSync();
      final downloads = FakeDownloads();
      final repository = buildRepository(
        root: root,
        locator: _UnreachableLocator(),
        download: downloads.call,
        modelReleases: _smallModel,
        diskSpace: (_) async =>
            const DiskSpaceInfo(volumeId: 'C', freeBytes: 100),
      );
      await repository.enableAndDownload();
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.insufficientDiskSpace,
      );
      expect(downloads.urls, isEmpty);
    });

    test('מקור פגום במצב לא מקוון נשאר ללא הורדה', () async {
      stageAll(segment: 'damaged');
      final downloads = FakeDownloads();
      final repository = buildRepository(
        root: root,
        settings: FakeSettingsStore()..isOfflineMode = true,
        download: downloads.call,
        modelReleases: _smallModel,
      );
      await repository.enableAndDownload();
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.offline,
      );
      expect(downloads.urls, isEmpty);
      expect(
        File(
          staged(kSemanticImportVectorsFolderName, _segmentName),
        ).readAsStringSync(),
        'damaged',
      );
    });

    test('קובץ מוכן באותו כונן אינו נספר', () async {
      expect(await run('C'), isNull);
    });

    test('קובץ מוכן בכונן אחר — ההעתקה נספרת', () async {
      expect(await run('D'), SemanticFailureKind.insufficientDiskSpace);
    });
  });
}
