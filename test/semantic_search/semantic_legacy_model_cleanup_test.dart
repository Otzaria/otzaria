import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/repository/semantic_data_ownership.dart';
import 'package:path/path.dart' as p;

import 'semantic_test_support.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_legacy_'));
  tearDown(() => root.deleteSync(recursive: true));

  SemanticPaths paths() => SemanticPaths(p.join(root.path, 'otzaria'));

  /// תיקיית מודל של גרסה קודמת, עם סימון הבעלות או בלעדיו.
  Directory legacyModel({required bool owned}) {
    final dir = Directory(paths().legacyModelDirectories.first);
    File(p.join(dir.path, 'model.onnx')).createSync(recursive: true);
    if (owned) File(p.join(dir.path, kSemanticOwnerMarker)).createSync();
    return dir;
  }

  test('יש תיקיית מודל ישנה לבדוק', () {
    expect(
      kLegacySemanticModelFolderNames,
      isNot(contains(kSemanticModelFolderName)),
    );
    expect(kLegacySemanticModelFolderNames, contains('meivin-round2-onnx'));
  });

  group('אחרי התקנה מוצלחת של המודל', () {
    test('תיקיית מודל ישנה שלנו נמחקת', () async {
      final legacy = legacyModel(owned: true);
      final repository = buildRepository(
        root: root,
        locator: FakeLocator(releaseV30()),
      );

      await repository.enableAndDownload();

      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
      expect(legacy.existsSync(), isFalse);
      expect(Directory(paths().modelDirectory).existsSync(), isTrue);
    });

    test('תיקייה זרה באותו שם נשארת', () async {
      final legacy = legacyModel(owned: false);
      final repository = buildRepository(
        root: root,
        locator: FakeLocator(releaseV30()),
      );

      await repository.enableAndDownload();

      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
      expect(legacy.existsSync(), isTrue);
    });

    test('הורדת מודל שנכשלה אינה מוחקת את הישן', () async {
      final legacy = legacyModel(owned: true);
      final service = CompanionAssetsService(
        clientFactory: () =>
            MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
      );
      final repository = buildRepository(
        root: root,
        download: service.downloadVerifiedFile,
        locator: FakeLocator(releaseV30()),
      );

      await repository.enableAndDownload();

      expect(repository.availability.phase, SemanticAvailabilityPhase.failed);
      expect(legacy.existsSync(), isTrue);
    });
  });

  group('מחיקת הנתונים', () {
    test('מוחקת תיקיית מודל ישנה שלנו', () async {
      installModelFiles(root);
      final legacy = legacyModel(owned: true);
      final repository = buildRepository(root: root);

      await repository.removeData();

      expect(legacy.existsSync(), isFalse);
      expect(Directory(paths().modelDirectory).existsSync(), isFalse);
    });

    test('אינה נוגעת בתיקייה זרה באותו שם', () async {
      installModelFiles(root);
      final legacy = legacyModel(owned: false);
      final repository = buildRepository(root: root);

      await repository.removeData();

      expect(legacy.existsSync(), isTrue);
      expect(Directory(paths().modelDirectory).existsSync(), isFalse);
    });
  });
}
