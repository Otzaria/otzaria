import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/perf_probe/src/installed_pdf_runtime_contract.dart';

Map<String, Object?> _completePdfReport(String platform) => {
  'platform': platform,
  'status': 'passed',
  'steps': {
    'repeatedLifecycle': jsonDecode(
      File(
        'test/tool/perf_probe/fixtures/installed_pdf_repeated.json',
      ).readAsStringSync(),
    ),
    for (final name in installedPdfRuntimeSteps) name: {'status': 'passed'},
    'desktopLifecycle': jsonDecode(
      File(
        'test/tool/perf_probe/fixtures/installed_pdf_desktop.json',
      ).readAsStringSync(),
    ),
  },
  'bundlePathsVerified': true,
  'ownedDocumentsRemaining': 0,
  'ownedTabsRemaining': 0,
  'indexingActiveAfter': false,
};

void main() {
  const bundleDirectory = '/tmp/app with spaces/bundle';
  const bundle = '$bundleDirectory/lib';
  final expected = {
    for (final name in installedPdfRuntimeModules['linux']!)
      name: '$bundle/$name',
  };

  group('loaded PDFium paths', () {
    test(
      'reads actual mapped paths, retaining spaces and deduplicating segments',
      () {
        final maps = [
          '00400000-00401000 r-xp 00000000 00:04 123 $bundle/libpdfium.so',
          '00401000-00402000 r--p 00001000 00:04 123 $bundle/libpdfium.so',
          '00500000-00501000 r-xp 00000000 00:04 124 $bundle/libpdfium_printing.so',
          '00600000-00601000 r-xp 00000000 00:04 125 $bundle/libprinting_plugin.so',
          '00700000-00701000 rw-p 00000000 00:00 0',
          '00800000-00801000 r-xp 00000000 00:00 0 [vdso]',
        ].join('\n');
        final paths = installedPdfMappedPaths(maps);
        expect(paths, expected.values.toSet());
        expect(
          installedPdfModuleErrors(
            platform: 'linux',
            bundleDirectory: bundleDirectory,
            mappedPaths: paths,
            expectedPaths: expected,
          ),
          isEmpty,
        );
      },
    );

    for (final name in installedPdfRuntimeModules['linux']!) {
      test('rejects missing $name even when the bundle file exists', () {
        final paths = expected.values.toSet()..remove(expected[name]);
        expect(
          installedPdfModuleErrors(
            platform: 'linux',
            bundleDirectory: bundleDirectory,
            mappedPaths: paths,
            expectedPaths: expected,
          ),
          hasLength(1),
        );
      });
      test('rejects a cached or second $name outside the bundle', () {
        for (final replace in [true, false]) {
          final paths = expected.values.toSet();
          if (replace) paths.remove(expected[name]);
          paths.add('/tmp/pub-cache/$name');
          expect(
            installedPdfModuleErrors(
              platform: 'linux',
              bundleDirectory: bundleDirectory,
              mappedPaths: paths,
              expectedPaths: expected,
            ),
            hasLength(1),
          );
        }
      });
    }
    test('rejects a module reached through a bundle link to pub cache', () {
      final resolved = {
        ...expected,
        'libpdfium.so': '/tmp/pub-cache/libpdfium.so',
      };
      expect(
        installedPdfModuleErrors(
          platform: 'linux',
          bundleDirectory: bundleDirectory,
          mappedPaths: resolved.values.toSet(),
          expectedPaths: resolved,
        ),
        hasLength(1),
      );
    });
    test('a deleted mapping cannot prove which binary is executing', () {
      final paths = expected.values.toSet()
        ..remove(expected['libpdfium.so'])
        ..add('${expected['libpdfium.so']} (deleted)');
      expect(
        installedPdfModuleErrors(
          platform: 'linux',
          bundleDirectory: bundleDirectory,
          mappedPaths: paths,
          expectedPaths: expected,
        ),
        hasLength(1),
      );
    });
  });

  group('loaded Windows PDFium paths', () {
    const directory = r'C:\app with spaces\runner\Profile';
    final expected = {
      for (final name in installedPdfRuntimeModules['windows']!)
        name: '$directory\\$name',
    };
    test('accepts canonical bundle paths with Windows spelling variants', () {
      for (final paths in [
        expected.values.toSet(),
        expected.values.map((path) => path.toUpperCase()).toSet(),
        expected.values.map((path) => r'\\?\' + path).toSet(),
      ]) {
        expect(
          installedPdfModuleErrors(
            platform: 'windows',
            bundleDirectory: directory,
            mappedPaths: paths,
            expectedPaths: expected,
          ),
          isEmpty,
        );
      }
    });
    for (final name in installedPdfRuntimeModules['windows']!) {
      test('rejects missing $name even when the bundle file exists', () {
        expect(
          installedPdfModuleErrors(
            platform: 'windows',
            bundleDirectory: directory,
            mappedPaths: expected.values.toSet()..remove(expected[name]),
            expectedPaths: expected,
          ),
          hasLength(1),
        );
      });
      test(
        'rejects a cached or additional $name regardless of filename case',
        () {
          for (final replace in [true, false]) {
            final paths = expected.values.toSet();
            if (replace) paths.remove(expected[name]);
            paths.add('C:\\pub-cache\\${name.toUpperCase()}');
            expect(
              installedPdfModuleErrors(
                platform: 'windows',
                bundleDirectory: directory,
                mappedPaths: paths,
                expectedPaths: expected,
              ),
              hasLength(1),
            );
          }
        },
      );
    }
    test('does not accept a relative expected path as a bundle location', () {
      final relative = {
        for (final name in installedPdfRuntimeModules['windows']!) name: name,
      };
      expect(
        installedPdfModuleErrors(
          platform: 'windows',
          bundleDirectory: directory,
          mappedPaths: relative.values.toSet(),
          expectedPaths: relative,
        ),
        hasLength(3),
      );
    });
  });

  for (final platform in installedPdfRuntimeModules.keys) {
    group('$platform actual bundle PDF evidence', () {
      test('a plugin lifecycle pass cannot replace PDF lifecycle evidence', () {
        final report = _completePdfReport(platform);
        (report['steps']! as Map).remove('desktopLifecycle');
        expect(
          installedPdfRuntimeErrors(report, platform: platform),
          isNotEmpty,
        );
      });

      test('requires all runtime phases and completed teardown', () {
        expect(
          installedPdfRuntimeErrors(
            _completePdfReport(platform),
            platform: platform,
          ),
          isEmpty,
        );
        for (final value in [
          null,
          {},
          {'status': 'notRun'},
        ]) {
          expect(
            installedPdfRuntimeErrors(value, platform: platform),
            isNotEmpty,
          );
        }
      });
      for (final name in installedPdfRuntimeSteps) {
        test('$name cannot silently become missing, skipped or failed', () {
          for (final status in [
            null,
            'notRun',
            'unsupported',
            'running',
            'failed',
          ]) {
            final report = _completePdfReport(platform);
            final steps = report['steps']! as Map;
            if (status == null) {
              steps.remove(name);
            } else {
              steps[name] = {'status': status};
            }
            expect(
              installedPdfRuntimeErrors(report, platform: platform),
              isNotEmpty,
              reason: '$name: $status',
            );
          }
        });
      }
      test(
        'a resource still owned, foreign platform or unverified loader fails',
        () {
          for (final entry in {
            'platform': platform == 'linux' ? 'windows' : 'linux',
            'status': 'failed',
            'bundlePathsVerified': false,
            'ownedDocumentsRemaining': 1,
            'ownedTabsRemaining': 1,
            'indexingActiveAfter': true,
          }.entries) {
            final report = _completePdfReport(platform)
              ..[entry.key] = entry.value;
            expect(
              installedPdfRuntimeErrors(report, platform: platform),
              isNotEmpty,
              reason: entry.key,
            );
            report.remove(entry.key);
            expect(
              installedPdfRuntimeErrors(report, platform: platform),
              isNotEmpty,
              reason: 'missing ${entry.key}',
            );
          }
        },
      );
    });
  }
}
