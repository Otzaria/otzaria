import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/search_feedback/search_feedback_events.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/repository/semantic_data_ownership.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:path/path.dart' as p;

import 'semantic_test_support.dart';

void main() {
  group('SemanticPaths', () {
    test('המודל ליד seforim.db, הוקטורים ב-<root>/vectors', () {
      final root = p.join('D:', 'lib');
      final paths = SemanticPaths(p.join(root, 'otzaria'));

      expect(paths.root, root);
      expect(
        paths.modelDirectory,
        p.join(root, 'otzaria', 'meivin-round2-onnx'),
      );
      expect(
        paths.modelFile(SemanticQuantization.int8),
        p.join(paths.modelDirectory, 'seforim-embed-round2-int8.onnx'),
      );
      expect(
        paths.modelFile(SemanticQuantization.fp32),
        p.join(paths.modelDirectory, 'seforim-embed-round2-fp32.onnx'),
      );
      expect(
        paths.tokenizerFile,
        p.join(paths.modelDirectory, 'tokenizer.json'),
      );
      expect(paths.identityFile, p.join(paths.modelDirectory, 'model.json'));
      expect(paths.vectorsDirectory, p.join(root, 'vectors'));
      expect(paths.vectorsDownloadDirectory, p.join(root, 'vectors-download'));
    });
  });

  group('SemanticModelIdentity', () {
    test('מפענח את model.json המצורף', () {
      final identity = SemanticModelIdentity.parse(bundledModelJson());

      expect(
        identity.familyId,
        'ArieLLL123/judaic-semantic-round2-onnx-zayit@'
        '1ec8dc68888bcea774ae9f735b2fe7cd9dc7f3ca',
      );
      expect(identity.embeddingDim, 256);
      expect(
        identity.packageFor(SemanticQuantization.int8)?.checksum,
        '9e408407922b4aab26dd148cbe4b9a0e573c65591cfc799ba28e991d77d9d065',
      );
      expect(
        identity.packageFor(SemanticQuantization.fp32)?.checksum,
        '4a4a2ae88a86f15ffe6069bfcefc3abd13c207cec5d7aaef52c0c59d752ade46',
      );
      expect(identity.rawJson, bundledModelJson());
    });

    test('שדה חובה חסר הוא FormatException', () {
      expect(
        () => SemanticModelIdentity.parse('{"family_id":"x"}'),
        throwsFormatException,
      );
    });

    test('ערך הגדרה לא מוכר חוזר ל-int8', () {
      expect(SemanticQuantization.parse('fp32'), SemanticQuantization.fp32);
      expect(SemanticQuantization.parse(null), SemanticQuantization.int8);
      expect(SemanticQuantization.parse('q4'), SemanticQuantization.int8);
    });
  });

  group('סבב תיקונים: מודלים', () {
    test('סוג של האפליקציה אינו מתאים לשם של המנוע', () {
      expect(
        SemanticFailureKind.fromEngineName('consentRequired'),
        SemanticFailureKind.internal,
      );
      expect(
        SemanticFailureKind.fromEngineName('vectorsBusy'),
        SemanticFailureKind.vectorsBusy,
      );
      expect(SemanticFailureKind.vectorsBusy.isEngineKind, isTrue);
      expect(SemanticFailureKind.offline.isEngineKind, isFalse);
    });

    test('alphaByQueryType נשמר כמפה מקוננת אחרי הניקוי של הטלמטריה', () {
      final map = const SemanticRankingConfig().toSnapshotMap();
      expect(map.keys.where((k) => k.contains('.')), isEmpty);

      final sanitized = SearchFeedbackEventBuilder.sanitizeRanking(map)!;

      expect(sanitized['alphaByQueryType'], {
        'quotedPhrase': 1.0,
        'exactReference': 0.85,
        'short': 0.7,
        'mixed': 0.5,
        'conceptual': 0.3,
        'unknown': 0.5,
      });
      expect(sanitized['fusionStrategy'], 'rrf');
    });

    test('ברירות המחדל של הדירוג הן של המנוע, וכולן נרשמות בטלמטריה', () {
      const config = SemanticRankingConfig();
      expect(config.fusion, SemanticFusion.rrf);
      expect(config.semanticThreshold, 0.55);
      expect(config.foundationalBonus, 0.002);
      expect(config.foundationalCandidateShare, 0.5);

      final sanitized = SearchFeedbackEventBuilder.sanitizeRanking(
        config.toSnapshotMap(),
      )!;
      expect(sanitized['fusionStrategy'], 'rrf');
      expect(sanitized['semanticThreshold'], 0.55);
      expect(sanitized['foundationalBonus'], 0.002);
      expect(sanitized['foundationalCandidateShare'], 0.5);
      // כל מפתח עובר את בדיקת השרת, ואף אחד לא נשמט בניקוי.
      final keyPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$');
      expect(sanitized.keys, config.toSnapshotMap().keys);
      expect(sanitized.length, lessThanOrEqualTo(40));
      for (final entry in sanitized.entries) {
        expect(keyPattern.hasMatch(entry.key), isTrue, reason: entry.key);
        if (entry.value is Map) {
          for (final nested in (entry.value as Map).entries) {
            expect(keyPattern.hasMatch(nested.key as String), isTrue);
            expect(nested.value, isA<num>());
          }
        } else {
          expect(
            entry.value == null ||
                entry.value is num ||
                entry.value is bool ||
                entry.value is String,
            isTrue,
            reason: entry.key,
          );
        }
      }
    });

    test('שינוי בשדה חדש של הדירוג משנה את השוויון', () {
      expect(
        const SemanticRankingConfig(foundationalBonus: 0),
        isNot(const SemanticRankingConfig()),
      );
      expect(
        const SemanticRankingConfig(foundationalCandidateShare: 0),
        isNot(const SemanticRankingConfig()),
      );
    });

    test('מחיקה רק של תיקייה שלנו', () async {
      final root = Directory.systemTemp.createTempSync('semantic_owner_');
      addTearDown(() => root.deleteSync(recursive: true));
      final ours = p.join(root.path, 'vectors-download');
      final engineSet = p.join(root.path, 'vectors');
      final foreign = p.join(root.path, 'other');
      await markSemanticDirectory(ours);
      File(p.join(engineSet, 'CURRENT')).createSync(recursive: true);
      File(p.join(foreign, 'file.txt')).createSync(recursive: true);

      expect(await deleteSemanticOwnedDirectory(ours), isTrue);
      expect(await deleteSemanticOwnedDirectory(engineSet), isTrue);
      expect(await deleteSemanticOwnedDirectory(foreign), isFalse);
      expect(Directory(foreign).existsSync(), isTrue);
    });

    test('<root> נקבע לפי תיקיית הספרייה כשהיא ניתנת', () {
      final paths = SemanticPaths(
        p.join('D:', 'lib', 'otzaria', 'db'),
        root: p.join('D:', 'lib'),
      );
      expect(paths.vectorsDirectory, p.join('D:', 'lib', 'vectors'));
      expect(
        paths.modelDirectory,
        p.join('D:', 'lib', 'otzaria', 'db', 'meivin-round2-onnx'),
      );
    });

    test('הודעות הממשק אינן מזכירות מודל או וקטורים', () {
      for (final message in SemanticSearchMessages.allFailureMessages) {
        expect(message, isNot(contains('מודל')));
        expect(message, isNot(contains('וקטור')));
      }
    });
  });

  group('SemanticFailureKind', () {
    test('ממפה לפי שם את סוגי המנוע, ושם לא מוכר הוא internal', () {
      expect(
        SemanticFailureKind.fromEngineName('insufficientDiskSpace'),
        SemanticFailureKind.insufficientDiskSpace,
      );
      expect(
        SemanticFailureKind.fromEngineName('onnxRuntimeMissing'),
        SemanticFailureKind.onnxRuntimeMissing,
      );
      expect(
        SemanticFailureKind.fromEngineName('someFutureKind'),
        SemanticFailureKind.internal,
      );
    });

    test('לכל סוג יש הודעה בעברית', () {
      for (final kind in SemanticFailureKind.values) {
        expect(SemanticSearchMessages.failure(kind), isNotEmpty);
      }
      expect(
        SemanticSearchMessages.failure(SemanticFailureKind.artifactCorrupt),
        SemanticSearchMessages.corruptOrIncompatible,
      );
      expect(
        SemanticSearchMessages.failure(
          SemanticFailureKind.insufficientDiskSpace,
        ),
        SemanticSearchMessages.insufficientDiskSpace,
      );
    });
  });

  group('platform support', () {
    test('מחשבים בלבד; macOS רק arm64 מגרסה 14', () {
      expect(isSemanticSearchPlatformSupported(abi: Abi.windowsX64), isTrue);
      expect(isSemanticSearchPlatformSupported(abi: Abi.linuxArm64), isTrue);
      expect(isSemanticSearchPlatformSupported(abi: Abi.androidArm64), isFalse);
      expect(isSemanticSearchPlatformSupported(abi: Abi.iosArm64), isFalse);
      expect(
        isSemanticSearchPlatformSupported(
          abi: Abi.macosArm64,
          macOsVersion: 'Version 14.2 (Build 23C64)',
        ),
        isTrue,
      );
      expect(
        isSemanticSearchPlatformSupported(
          abi: Abi.macosArm64,
          macOsVersion: 'Version 13.6 (Build 22G120)',
        ),
        isFalse,
      );
      expect(
        isSemanticSearchPlatformSupported(
          abi: Abi.macosX64,
          macOsVersion: 'Version 15.0',
        ),
        isFalse,
      );
    });
  });

  group('SemanticAvailability', () {
    test('מבדיל בין חסר מנוע/נתונים לבין חסרה הסכמה', () {
      const engineMissing = SemanticAvailability(
        phase: SemanticAvailabilityPhase.hidden,
        consentGranted: true,
        hiddenReason: SemanticHiddenReason.engineNotInBuild,
      );
      const platform = SemanticAvailability(
        phase: SemanticAvailabilityPhase.hidden,
        consentGranted: true,
        hiddenReason: SemanticHiddenReason.unsupportedPlatform,
      );
      const consent = SemanticAvailability(
        phase: SemanticAvailabilityPhase.consentRequired,
        consentGranted: false,
      );
      const download = SemanticAvailability(
        phase: SemanticAvailabilityPhase.needsDownload,
        consentGranted: true,
      );

      expect(engineMissing.isMissingEngineOrData, isTrue);
      expect(download.isMissingEngineOrData, isTrue);
      expect(platform.isMissingEngineOrData, isFalse);
      expect(consent.isMissingEngineOrData, isFalse);
      expect(download.isUsable, isFalse);
    });

    test('אחוז ההורדה', () {
      const progress = SemanticDownloadProgress(
        item: SemanticDownloadItem.vectors,
        receivedBytes: 50,
        totalBytes: 200,
      );
      expect(progress.fraction, 0.25);
      expect(
        const SemanticDownloadProgress(
          item: SemanticDownloadItem.model,
          receivedBytes: 5,
        ).fraction,
        isNull,
      );
    });
  });
}
