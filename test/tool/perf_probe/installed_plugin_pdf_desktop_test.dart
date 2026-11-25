import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/perf_probe/src/installed_pdf_desktop_contract.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(
          File(
            'test/tool/perf_probe/fixtures/installed_pdf_desktop.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test('accepts all native transitions with two retained PDF documents', () {
    expect(installedPdfDesktopErrors(fixture()), isEmpty);
  });

  test('missing, skipped and malformed lifecycle evidence fails closed', () {
    for (final value in [
      null,
      [],
      {},
      {'status': 'notRun'},
      {'status': 'passed'},
    ]) {
      expect(installedPdfDesktopErrors(value), isNotEmpty);
    }
  });

  test('restoration requires native geometry and every original flag', () {
    for (final field in ['visible', 'minimized', 'maximized', 'fullScreen']) {
      final proof = fixture();
      proof['restoredWindow'][field] = !proof['originalWindow'][field];
      expect(installedPdfDesktopErrors(proof), isNotEmpty, reason: field);
    }
    for (final size in [null, '1000', double.nan, double.infinity, 0, 1003]) {
      final proof = fixture();
      proof['restoredWindow']['logicalBounds']['width'] = size;
      expect(installedPdfDesktopErrors(proof), isNotEmpty, reason: '$size');
    }
    final rounded = fixture();
    rounded['restoredWindow']['logicalBounds']['width'] = 1002;
    expect(installedPdfDesktopErrors(rounded), isEmpty);
  });

  test(
    'a replacement document or corrective navigation cannot prove retention',
    () {
      for (final name in installedPdfDesktopActions) {
        for (final entry in {
          'documentUnchanged': false,
          'navigationIssued': true,
          'targetCenterVisible': false,
          'visibleRenderState': 'loading',
          'targetPage': 4,
          'path': '/another/document.pdf',
          'viewWidth': 0,
        }.entries) {
          final proof = fixture();
          final action = (proof['actions'] as List).singleWhere(
            (item) => item['name'] == name,
          );
          action['reader'][entry.key] = entry.value;
          expect(
            installedPdfDesktopErrors(proof),
            isNotEmpty,
            reason: '$name ${entry.key}',
          );
        }
      }
    },
  );

  test(
    'native hide and minimize acknowledgements cannot be fabricated from ready',
    () {
      for (final name in ['hide', 'minimize']) {
        final proof = fixture();
        final action = (proof['actions'] as List).singleWhere(
          (item) => item['name'] == name,
        );
        action['nativeAcknowledgement'] = action['afterWindow'];
        expect(installedPdfDesktopErrors(proof), isNotEmpty, reason: name);
      }
    },
  );

  test(
    'resize requires a real changed size and the requested native bounds',
    () {
      for (final replacement in [
        null,
        'invalid',
        {},
        fixture()['originalWindow'],
      ]) {
        final proof = fixture();
        proof['actions'][2]['nativeAcknowledgement'] = replacement;
        expect(installedPdfDesktopErrors(proof), isNotEmpty);
      }
      final proof = fixture();
      proof['actions'][2]['requestedBounds'] =
          proof['originalWindow']['logicalBounds'];
      proof['actions'][2]['nativeAcknowledgement'] = proof['originalWindow'];
      expect(installedPdfDesktopErrors(proof), isNotEmpty);
    },
  );

  test(
    'every transition requires overlapping real raster work and valid pixels',
    () {
      for (final index in List.generate(
        installedPdfDesktopActions.length,
        (i) => i,
      )) {
        for (final change in [
          (Map proof) => proof['actions'][index]['activity'] = null,
          (Map proof) => proof['actions'][index]['activity']['endUs'] = 0,
          (Map proof) =>
              proof['actions'][index]['activity']['raster']['contentPixelsVerified'] =
                  false,
          (Map proof) =>
              proof['actions'][index]['activity']['raster']['pixelSha256'] =
                  'not-a-hash',
        ]) {
          final proof = fixture();
          change(proof);
          expect(installedPdfDesktopErrors(proof), isNotEmpty);
        }
      }
    },
  );

  test('both documents and final native close are required', () {
    for (final entry in {
      'secondaryPath': fixture()['primaryPath'],
      'distinctDocuments': false,
      'secondaryNativeCloseCompleted': false,
      'windowRestored': false,
      'restoredReader': null,
    }.entries) {
      final proof = fixture()..[entry.key] = entry.value;
      expect(installedPdfDesktopErrors(proof), isNotEmpty, reason: entry.key);
    }
    final proof = fixture();
    (proof['actions'] as List).removeAt(3);
    expect(installedPdfDesktopErrors(proof), isNotEmpty);
  });

  test('cohorts must include 1, 5 and 10 distinct live PDF documents', () {
    for (final change in [
      (Map proof) => proof['tabCohorts'] = null,
      (Map proof) => proof['tabCohorts'][2]['nativeDocumentCount'] = 9,
      (Map proof) => proof['tabCohorts'][1]['paths'][1] = proof['primaryPath'],
      (Map proof) => proof['additionalNativeCloses'] = 8,
      (Map proof) => proof['memoryPressureSource'] = 'physical OS pressure',
      (Map proof) => proof['memoryPressureAcknowledged'] = null,
      (Map proof) => proof['memoryPressureAcknowledged'] = false,
      (Map proof) => proof['memoryPressureAcknowledged'] = 1,
      (Map proof) => proof['documentsRetainedAfterPressure'] = 9,
    ]) {
      final proof = fixture();
      change(proof);
      expect(installedPdfDesktopErrors(proof), isNotEmpty);
    }
  });

  Map<String, dynamic> cycles() =>
      jsonDecode(
            File(
              'test/tool/perf_probe/fixtures/installed_pdf_repeated.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test(
    'all fifty cycles require the real target and completed native close',
    () {
      expect(installedPdfRepeatedLifecycleErrors(cycles()), isEmpty);
      for (var index = 0; index < 50; index++) {
        for (final entry in {
          'differentDocument': false,
          'targetCenterVisible': false,
          'visibleRenderState': 'loading',
          'nativeCloseCompleted': false,
          'ownedTabsRemaining': 1,
          'raster': null,
        }.entries) {
          final proof = cycles();
          proof['cycles'][index][entry.key] = entry.value;
          expect(
            installedPdfRepeatedLifecycleErrors(proof),
            isNotEmpty,
            reason: '${index + 1} ${entry.key}',
          );
        }
      }
      final proof = cycles();
      (proof['cycles'] as List).removeLast();
      expect(installedPdfRepeatedLifecycleErrors(proof), isNotEmpty);
    },
  );
  test('native counts and page numbers cannot be booleans or fractions', () {
    for (final invalid in [true, 1.0]) {
      final cohort = fixture();
      cohort['tabCohorts'][0]['tabCount'] = invalid;
      expect(installedPdfDesktopErrors(cohort), isNotEmpty);
      final raster = fixture();
      raster['actions'][0]['activity']['raster']['page'] = invalid;
      expect(installedPdfDesktopErrors(raster), isNotEmpty);
      for (final key in ['cycle', 'targetPage']) {
        final proof = cycles();
        proof['cycles'][0][key] = invalid;
        expect(installedPdfRepeatedLifecycleErrors(proof), isNotEmpty);
      }
    }
  });
  test('the final native close must complete before the cycle deadline', () {
    for (final elapsed in [null, -1, 600000, 600001]) {
      final proof = cycles()..['cyclesElapsedMs'] = elapsed;
      expect(installedPdfRepeatedLifecycleErrors(proof), isNotEmpty);
    }
  });
  test(
    'fifty slower software-rendered cycles retain every acceptance check',
    () {
      final proof = cycles()..['cyclesElapsedMs'] = 322000;
      for (final cycle in proof['cycles'] as List) {
        cycle['durationMs'] = 6400;
        cycle['stageDurationMs'] = {
          'openAndReady': 5100,
          'nativeProof': 100,
          'close': 1200,
        };
      }
      expect(installedPdfRepeatedLifecycleErrors(proof), isEmpty);
      proof['cycles'][49]['nativeCloseCompleted'] = false;
      expect(installedPdfRepeatedLifecycleErrors(proof), isNotEmpty);
    },
  );
  test(
    'each cycle records finite, nonnegative stage times within its duration',
    () {
      for (final stage in installedPdfRepeatedLifecycleStages) {
        for (final invalid in [
          null,
          -1,
          true,
          double.nan,
          double.infinity,
          801,
        ]) {
          final proof = cycles();
          proof['cycles'][0]['stageDurationMs'][stage] = invalid;
          expect(installedPdfRepeatedLifecycleErrors(proof), isNotEmpty);
        }
      }
      final missing = cycles();
      missing['cycles'][49].remove('stageDurationMs');
      expect(installedPdfRepeatedLifecycleErrors(missing), isNotEmpty);
      final inconsistent = cycles()..['cyclesElapsedMs'] = 39999;
      expect(installedPdfRepeatedLifecycleErrors(inconsistent), isNotEmpty);
    },
  );
}
