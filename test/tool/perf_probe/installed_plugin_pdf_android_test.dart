import 'package:flutter_test/flutter_test.dart';

import '../../../tool/perf_probe/src/installed_pdf_android_contract.dart';
import '../../../tool/perf_probe/src/installed_pdf_runtime_contract.dart';

const _appModule =
    '/data/app/~~install-id/$installedPdfAndroidPackage-package-id/lib/x86_64/libpdfium.so';
const _systemModule = '/system/lib64/libpdfium.so';

Map<String, Object?> _modules() => {
  'status': 'passed',
  'source': '/proc/self/maps',
  'package': installedPdfAndroidPackage,
  'abi': 'x86_64',
  'processId': 123,
  'printingBackend': installedPdfAndroidBackend,
  'configuredPdfrxModule': null,
  'observedModulePaths': [_appModule, _systemModule],
  'executableModulePaths': [_appModule, _systemModule],
  'systemModulePaths': [_systemModule],
  'appModule': {
    'name': 'libpdfium.so',
    'path': _appModule,
    'bytes': 1024,
    'sha256': 'a' * 64,
  },
};

Map<String, Object?> _report() => {
  'platform': 'android',
  'status': 'passed',
  'steps': {
    for (final name in installedPdfRuntimeSteps)
      name: name == 'loadedModules' ? _modules() : {'status': 'passed'},
  },
  'bundlePathsVerified': true,
  'ownedDocumentsRemaining': 0,
  'ownedTabsRemaining': 0,
  'indexingActiveAfter': false,
};

void main() {
  group('Android PDF mappings', () {
    test(
      'reads executable mappings and retains deleted paths for rejection',
      () {
        final maps = [
          '00400000-00401000 r-xp 00000000 00:04 123 $_appModule',
          '00401000-00402000 r--p 00001000 00:04 123 $_appModule',
          '00500000-00501000 r-xp 00000000 00:04 124 $_systemModule',
          '00600000-00601000 r--p 00000000 00:04 125 $_appModule (deleted)',
          '00700000-00701000 rw-p 00000000 00:00 0',
        ].join('\n');
        expect(installedAndroidPdfMappedPaths(maps), {
          _appModule,
          _systemModule,
          '$_appModule (deleted)',
        });
        expect(installedAndroidPdfMappedPaths(maps, executableOnly: true), {
          _appModule,
          _systemModule,
        });
      },
    );

    test('requires the dedicated installation and correct ABI directory', () {
      expect(isInstalledAndroidPdfModule(_appModule), true);
      expect(
        isInstalledAndroidPdfModule(
          _appModule.replaceFirst('~~install-id/', ''),
        ),
        true,
      );
      for (final path in [
        _systemModule,
        '$_appModule (deleted)',
        _appModule.replaceFirst('x86_64', 'arm64'),
        _appModule.replaceFirst(installedPdfAndroidPackage, 'foreign.app'),
        _appModule.replaceFirst('lib/', '../lib/'),
        '/data/local/tmp/libpdfium.so',
      ]) {
        expect(isInstalledAndroidPdfModule(path), false, reason: path);
      }
    });

    test('allows system PdfRenderer with a distinct PDFium mapping', () {
      for (final system in [
        <String>[],
        [_systemModule],
        ['/apex/com.android.mediaprovider/lib64/libpdfium.so'],
      ]) {
        final proof = _modules()
          ..['observedModulePaths'] = [_appModule, ...system]
          ..['executableModulePaths'] = [_appModule, ...system]
          ..['systemModulePaths'] = system;
        expect(installedAndroidPdfModuleErrors(proof), isEmpty);
      }
    });

    test('rejects foreign, duplicate, stale and nonexecuting app mappings', () {
      for (final paths in [
        [_systemModule],
        ['$_appModule (deleted)', _systemModule],
        [_appModule, _appModule],
        [_appModule, '/data/local/tmp/libpdfium.so'],
        [_appModule, '/system/../data/local/tmp/libpdfium.so'],
        [_appModule, '/system/lib64/libpdfium.so (deleted)'],
      ]) {
        final proof = _modules()..['observedModulePaths'] = paths;
        expect(installedAndroidPdfModuleErrors(proof), isNotEmpty);
      }
      expect(
        installedAndroidPdfModuleErrors(
          _modules()..['executableModulePaths'] = [_systemModule],
        ),
        isNotEmpty,
      );
    });

    test(
      'rejects missing identity, altered backend or unproven binary hash',
      () {
        for (final key in [
          'source',
          'package',
          'abi',
          'processId',
          'printingBackend',
          'configuredPdfrxModule',
          'observedModulePaths',
          'executableModulePaths',
          'systemModulePaths',
          'appModule',
        ]) {
          expect(
            installedAndroidPdfModuleErrors(_modules()..remove(key)),
            isNotEmpty,
            reason: key,
          );
        }
        for (final field in ['name', 'path', 'bytes', 'sha256']) {
          final proof = _modules();
          (proof['appModule']! as Map).remove(field);
          expect(installedAndroidPdfModuleErrors(proof), isNotEmpty);
        }
        expect(
          installedAndroidPdfModuleErrors(
            _modules()..['configuredPdfrxModule'] = '/tmp/libpdfium.so',
          ),
          isNotEmpty,
        );
      },
    );
  });

  group('Android installed-app PDF runtime contract', () {
    test('requires the actual runtime and its Android module evidence', () {
      expect(installedPdfRuntimePlatforms, contains('android'));
      expect(
        installedPdfRuntimeErrors(_report(), platform: 'android'),
        isEmpty,
      );
      final proof = _report();
      (proof['steps']! as Map)['loadedModules'] = {'status': 'passed'};
      expect(installedPdfRuntimeErrors(proof, platform: 'android'), isNotEmpty);
    });
    for (final step in installedPdfRuntimeSteps) {
      test('$step cannot silently skip on Android', () {
        for (final status in [
          null,
          'notRun',
          'unsupported',
          'running',
          'failed',
        ]) {
          final report = _report();
          final steps = report['steps']! as Map;
          if (status == null) {
            steps.remove(step);
          } else {
            (steps[step] as Map)['status'] = status;
          }
          expect(
            installedPdfRuntimeErrors(report, platform: 'android'),
            isNotEmpty,
            reason: '$step: $status',
          );
        }
      });
    }
  });
}
