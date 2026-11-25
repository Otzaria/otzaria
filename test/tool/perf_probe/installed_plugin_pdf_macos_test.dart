import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/perf_probe/src/installed_pdf_macos_contract.dart';
import '../../../tool/perf_probe/src/installed_pdf_runtime_contract.dart';
import '../../../tool/perf_probe/src/installed_plugin_contract.dart';

const _bundle = '/tmp/profile with spaces/אוצריא.app';
const _executable = '$_bundle/Contents/MacOS/אוצריא';
const _pdfium =
    '$_bundle/Contents/Frameworks/PDFium.framework/Versions/A/PDFium';
const _coreGraphics =
    '/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics';

Map<String, dynamic> _images({bool staticPdfium = false}) {
  final pdfium = staticPdfium ? _executable : _pdfium;
  return {
    'source': installedPdfMacosSource,
    'pid': 173,
    'bundle': _bundle,
    'executable': _executable,
    'configuredPdfrxModule': null,
    'printingBackend': installedPdfMacosPrinting,
    'images': [_executable, pdfium, _coreGraphics],
    'symbols': {
      for (final entry in installedPdfMacosSymbols.entries)
        for (final name in entry.value)
          name: {
            'image': entry.key == 'pdfium' ? pdfium : _coreGraphics,
            'canonicalImage': entry.key == 'pdfium' ? pdfium : _coreGraphics,
            'address': '0x10100',
            'imageBase': '0x10000',
          },
    },
    'bundledFiles': [
      for (final path in {_executable, pdfium})
        {'path': path, 'bytes': 1000, 'sha256': 'a' * 64},
    ],
  };
}

Map<String, dynamic> _report() => {
  'platform': 'macos',
  'status': 'passed',
  'bundlePathsVerified': true,
  'ownedDocumentsRemaining': 0,
  'ownedTabsRemaining': 0,
  'indexingActiveAfter': false,
  'steps': {
    'repeatedLifecycle': jsonDecode(
      File(
        'test/tool/perf_probe/fixtures/installed_pdf_repeated.json',
      ).readAsStringSync(),
    ),
    for (final name in installedPdfRuntimeSteps)
      name: {'status': 'passed', if (name == 'loadedModules') ..._images()},
    'desktopLifecycle': jsonDecode(
      File(
        'test/tool/perf_probe/fixtures/installed_pdf_desktop.json',
      ).readAsStringSync(),
    ),
  },
};

void main() {
  test('accepts loaded framework owners and hashes without Windows DLLs', () {
    expect(installedPdfMacosModuleErrors(_images()), isEmpty);
    expect(
      installedPdfRuntimeErrors(_report(), platform: 'macos'),
      isEmpty,
    );
  });

  test('accepts PDFium linked into the actual app executable', () {
    expect(
      installedPdfMacosModuleErrors(_images(staticPdfium: true)),
      isEmpty,
    );
  });

  test('hashes bundled files while Apple images may live in shared cache', () {
    final images = _images();
    expect(
      (images['bundledFiles'] as List).any(
        (file) => (file as Map)['path'] == _coreGraphics,
      ),
      false,
    );
    expect(installedPdfMacosModuleErrors(images), isEmpty);
  });

  test('a system canonical path cannot hide a foreign printing owner', () {
    final images = _images();
    const foreign = '/tmp/foreign-CoreGraphics';
    (images['images'] as List).add(foreign);
    images['symbols']['CGContextDrawPDFPage']['image'] = foreign;
    expect(installedPdfMacosModuleErrors(images), isNotEmpty);
  });

  for (final name in installedPdfMacosSymbols.values.expand((names) => names)) {
    test('requires the observed owner and native address for $name', () {
      for (final field in ['image', 'canonicalImage', 'address', 'imageBase']) {
        final images = _images();
        (images['symbols'][name] as Map).remove(field);
        expect(installedPdfMacosModuleErrors(images), isNotEmpty);
      }
      final images = _images();
      images['symbols'][name]['address'] = '0x0';
      expect(installedPdfMacosModuleErrors(images), isNotEmpty);
    });
  }

  test('rejects a PDFium cache copy and a canonical path outside the app', () {
    for (final outside in [
      '/tmp/pub-cache/libpdfium_dart.dylib',
      '$_bundle/Contents/Frameworks/../../../outside',
    ]) {
      final images = _images();
      images['symbols']['FPDF_LoadDocument']['canonicalImage'] = outside;
      expect(installedPdfMacosModuleErrors(images), isNotEmpty);
    }
  });

  test('rejects a second PDFium owner even when both files are bundled', () {
    final images = _images();
    images['symbols']['FPDF_RenderPageBitmap']['canonicalImage'] = _executable;
    expect(installedPdfMacosModuleErrors(images), isNotEmpty);
  });

  test('CoreGraphics symbols cannot be supplied by an app or cached shim', () {
    final images = _images();
    images['symbols']['CGPDFDocumentCreateWithProvider']['canonicalImage'] =
        _executable;
    expect(installedPdfMacosModuleErrors(images), isNotEmpty);
  });

  test('every symbol owner must be an observed dyld image', () {
    final images = _images();
    (images['images'] as List).remove(_coreGraphics);
    expect(installedPdfMacosModuleErrors(images), isNotEmpty);
  });

  test('rejects missing, malformed, duplicate and foreign binary hashes', () {
    for (final mutation in [
      (List<dynamic> files) => files.clear(),
      (List<dynamic> files) => files.add(files.first),
      (List<dynamic> files) => files.first['sha256'] = 'not a digest',
      (List<dynamic> files) => files.first['bytes'] = 0,
      (List<dynamic> files) => files.first['path'] = '/tmp/foreign',
    ]) {
      final images = _images();
      mutation(images['bundledFiles'] as List<dynamic>);
      expect(installedPdfMacosModuleErrors(images), isNotEmpty);
    }
  });

  test('requires the default process loader and native backend identity', () {
    for (final field in [
      'source',
      'pid',
      'bundle',
      'executable',
      'configuredPdfrxModule',
      'printingBackend',
      'images',
      'symbols',
      'bundledFiles',
    ]) {
      final images = _images()..remove(field);
      expect(installedPdfMacosModuleErrors(images), isNotEmpty, reason: field);
    }
    final images = _images()..['configuredPdfrxModule'] = '/tmp/override';
    expect(installedPdfMacosModuleErrors(images), isNotEmpty);
  });

  for (final name in installedPdfRuntimeSteps) {
    test('macOS cannot pass when $name was skipped or failed', () {
      for (final status in ['notRun', 'failed']) {
        final report = _report();
        report['steps'][name]['status'] = status;
        expect(
          installedPdfRuntimeErrors(report, platform: 'macos'),
          isNotEmpty,
        );
      }
    });
  }

  test('passed PDF phases still require native loaded-image proof', () {
    final report = jsonDecode(jsonEncode(_report())) as Map<String, dynamic>;
    report['steps']['loadedModules'] = {'status': 'passed'};
    expect(
      installedPdfRuntimeErrors(report, platform: 'macos'),
      isNotEmpty,
    );
  });

  test('the installed-app contract requires the PDF scenario on macOS', () {
    final errors = installedReportErrors({'platform': 'macos', 'phases': []});
    expect(errors, contains('Missing actual-bundle PDF runtime report'));
  });
}
