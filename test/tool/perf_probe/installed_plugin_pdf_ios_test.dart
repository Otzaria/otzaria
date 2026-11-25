import 'dart:convert';

import 'package:test/test.dart';

import '../../../tool/perf_probe/src/installed_pdf_darwin_contract.dart';
import '../../../tool/perf_probe/src/installed_pdf_ios_contract.dart';
import '../../../tool/perf_probe/src/installed_pdf_runtime_contract.dart';

const _bundle =
    '/Simulator/Devices/ABC/data/Containers/Bundle/Application/DEF/אוצריא.app';
const _executable = '$_bundle/Runner';
const _pdfium = '$_bundle/Frameworks/PDFium.framework/PDFium';
const _runtimeRoot =
    '/Library/Developer/CoreSimulator/iOS 26.1.simruntime/Contents/Resources/RuntimeRoot';
const _coreGraphics =
    '$_runtimeRoot/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics';

Map<String, dynamic> _images() => {
  'source': installedPdfDarwinSource,
  'pid': 173,
  'abi': 'ios_arm64',
  'bundle': _bundle,
  'executable': _executable,
  'configuredPdfrxModule': null,
  'printingBackend': installedPdfDarwinPrinting,
  'simulatorEnvironmentSource': installedPdfIosEnvironmentSource,
  'simulatorEnvironmentAvailability': 'collected',
  'simulator': {
    'udid': 'A916179E-C19B-44CD-B606-25F904E6B567',
    'model': 'iPhone18,1',
    'runtimeRoot': _runtimeRoot,
  },
  'images': [_executable, _pdfium, _coreGraphics],
  'symbols': {
    for (final role in installedPdfDarwinSymbols.entries)
      for (final name in role.value)
        name: {
          'image': role.key == 'pdfium' ? _pdfium : _coreGraphics,
          'canonicalImage': role.key == 'pdfium' ? _pdfium : _coreGraphics,
          'address': '0x10100',
          'imageBase': '0x10000',
        },
  },
  'bundledFiles': [
    for (final path in [_executable, _pdfium])
      {'path': path, 'bytes': 1024, 'sha256': 'a' * 64},
  ],
};

Map<String, dynamic> _report() => {
  'status': 'passed',
  'platform': 'ios',
  'bundlePathsVerified': true,
  'ownedDocumentsRemaining': 0,
  'ownedTabsRemaining': 0,
  'indexingActiveAfter': false,
  'steps': {
    for (final name in installedPdfRuntimeSteps)
      name: {
        'status': 'passed',
        if (name == 'loadedModules') ..._images(),
      },
  },
};

void main() {
  test(
    'iOS requires completed real PDF runtime and Simulator image evidence',
    () {
      expect(installedPdfRuntimeErrors(_report(), platform: 'ios'), isEmpty);
      for (final value in [
        null,
        {},
        {'status': 'notRun'},
      ]) {
        expect(installedPdfRuntimeErrors(value, platform: 'ios'), isNotEmpty);
      }
    },
  );

  for (final name in installedPdfRuntimeSteps) {
    test('$name cannot be skipped in an iOS PDF pass', () {
      final report = _report();
      (report['steps'] as Map)[name] = {'status': 'notRun'};
      expect(installedPdfRuntimeErrors(report, platform: 'ios'), isNotEmpty);
    });
  }

  test(
    'a 64-bit Simulator records its actual loaded owners and binary hashes',
    () {
      expect(installedPdfIosModuleErrors(_images()), isEmpty);
      expect(
        installedPdfIosModuleErrors(_images()..['abi'] = 'ios_x64'),
        isEmpty,
      );
    },
  );

  test('static PDFium and Xcode debug dylib stay inside the same app', () {
    for (final image in [_executable, '$_executable.debug.dylib']) {
      final record = _images();
      (record['images'] as List).add(image);
      record['images'] = (record['images'] as List).toSet().toList();
      for (final name in installedPdfDarwinSymbols['pdfium']!) {
        (record['symbols'] as Map)[name] = {
          'image': image,
          'canonicalImage': image,
          'address': '0x10100',
          'imageBase': '0x10000',
        };
      }
      record['bundledFiles'] = [
        for (final path in {_executable, image})
          {'path': path, 'bytes': 1024, 'sha256': 'a' * 64},
      ];
      expect(installedPdfIosModuleErrors(record), isEmpty);
    }
  });

  test(
    'CoreGraphics in the Simulator dyld shared cache needs symbol owners',
    () {
      final record = _images();
      const image =
          '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics';
      (record['images'] as List).add(image);
      for (final name in installedPdfDarwinSymbols['printing']!) {
        (record['symbols'] as Map)[name] = {
          'image': image,
          'canonicalImage': image,
          'address': '0x10100',
          'imageBase': '0x10000',
        };
      }
      expect(installedPdfIosModuleErrors(record), isEmpty);
    },
  );

  test('malformed optional environment and foreign ABI cannot pass', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (record) => record['simulator'] = null,
      (record) => record['simulator']['udid'] = '',
      (record) => record['simulator']['model'] = 'MacBookPro',
      (record) => record['simulator']['runtimeRoot'] = '/cache',
      (record) => record['abi'] = 'macos_arm64',
      (record) => record['configuredPdfrxModule'] = '/cache/PDFium',
      (record) => record['printingBackend'] = 'mock',
      (record) => record['pid'] = false,
    ]) {
      final record = _images();
      change(record);
      expect(installedPdfIosModuleErrors(record), isNotEmpty);
    }
  });

  test('unavailable environment keeps native image and hash proof mandatory', () {
    final record = _images()
      ..['simulator'] = <String, Object?>{}
      ..['simulatorEnvironmentAvailability'] = 'unavailable';
    expect(installedPdfIosModuleErrors(record), isEmpty);
    (record['bundledFiles'] as List).removeLast();
    expect(installedPdfIosModuleErrors(record), isNotEmpty);
  });

  test('partial environment is recorded without inventing missing fields', () {
    final record = _images()
      ..['simulator'] = {'udid': 'A916179E-C19B-44CD-B606-25F904E6B567'}
      ..['simulatorEnvironmentAvailability'] = 'partial';
    expect(installedPdfIosModuleErrors(record), isEmpty);
    record['simulatorEnvironmentAvailability'] = 'unavailable';
    expect(installedPdfIosModuleErrors(record), isNotEmpty);
  });

  test('environment source and availability cannot contradict the values', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (record) => record.remove('simulatorEnvironmentSource'),
      (record) => record['simulatorEnvironmentSource'] = 'host override',
      (record) => record.remove('simulatorEnvironmentAvailability'),
      (record) => record['simulatorEnvironmentAvailability'] = 'unavailable',
      (record) => record['simulator']['foreign'] = 'value',
    ]) {
      final record = _images();
      change(record);
      expect(installedPdfIosModuleErrors(record), isNotEmpty);
    }
  });

  test('every native symbol needs an executable owner and nonzero address', () {
    for (final symbol in installedPdfDarwinSymbols.values.expand(
      (names) => names,
    )) {
      for (final key in ['image', 'canonicalImage', 'address', 'imageBase']) {
        final record = _images();
        (record['symbols'][symbol] as Map).remove(key);
        expect(installedPdfIosModuleErrors(record), isNotEmpty);
      }
    }
    final record = _images();
    record['symbols']['FPDF_LoadDocument']['address'] = '0x0';
    expect(installedPdfIosModuleErrors(record), isNotEmpty);
  });

  test('cache PDFium, another app and a foreign CoreGraphics owner fail', () {
    for (final symbol in ['FPDF_LoadDocument', 'CGContextDrawPDFPage']) {
      final record = _images();
      const path = '/foreign/binary';
      (record['images'] as List).add(path);
      record['symbols'][symbol]['image'] = path;
      record['symbols'][symbol]['canonicalImage'] = path;
      expect(installedPdfIosModuleErrors(record), isNotEmpty);
    }
  });

  test('a system canonical path cannot hide a foreign printing owner', () {
    final record = _images();
    const foreign = '/tmp/foreign-CoreGraphics';
    (record['images'] as List).add(foreign);
    record['symbols']['CGContextDrawPDFPage']['image'] = foreign;
    expect(installedPdfIosModuleErrors(record), isNotEmpty);
  });

  test('every owned binary must have one complete hash record', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (record) => (record['bundledFiles'] as List).removeLast(),
      (record) =>
          (record['bundledFiles'] as List).add(record['bundledFiles'][0]),
      (record) => record['bundledFiles'][0]['sha256'] = 'bad',
      (record) => record['bundledFiles'][0]['bytes'] = false,
      (record) => record['bundledFiles'][0]['path'] = '/foreign/binary',
      (record) => (record['images'] as List).add(record['images'][0]),
    ]) {
      final record = jsonDecode(jsonEncode(_images())) as Map<String, dynamic>;
      change(record);
      expect(installedPdfIosModuleErrors(record), isNotEmpty);
    }
  });
}
