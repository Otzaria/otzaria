import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../tool/perf_probe/src/installed_pdf_darwin_contract.dart';
import '../../tool/perf_probe/src/installed_pdf_ios_contract.dart';
import 'installed_plugin_pdf_darwin.dart';

Future<Map<String, Object?>> collectInstalledPdfIosImages(
  Directory output,
) async {
  if (!Platform.isIOS || !{Abi.iosArm64, Abi.iosX64}.contains(Abi.current())) {
    throw UnsupportedError('The iOS PDF probe requires a 64-bit iOS Simulator');
  }
  final simulator = <String, String>{};
  for (final entry in const {
    'runtimeRoot': 'SIMULATOR_ROOT',
    'udid': 'SIMULATOR_UDID',
    'model': 'SIMULATOR_MODEL_IDENTIFIER',
  }.entries) {
    final observed = Platform.environment[entry.value];
    if (observed != null) {
      simulator[entry.key] = entry.key == 'runtimeRoot'
          ? await Directory(observed).resolveSymbolicLinks()
          : observed;
    }
  }
  final executable = await File(
    Platform.resolvedExecutable,
  ).resolveSymbolicLinks();
  final evidence = collectInstalledPdfDarwinSymbols()
    ..addAll({
      'source': installedPdfDarwinSource,
      'pid': pid,
      'abi': Abi.current().toString(),
      'bundle': p.dirname(executable),
      'executable': executable,
      'simulator': simulator,
      'simulatorEnvironmentSource': installedPdfIosEnvironmentSource,
      'simulatorEnvironmentAvailability': simulator.isEmpty
          ? 'unavailable'
          : simulator.length == 3
          ? 'collected'
          : 'partial',
      'configuredPdfrxModule': Pdfrx.pdfiumModulePath,
      'printingBackend': installedPdfDarwinPrinting,
      'systemImageHashes':
          'Not read: CoreGraphics can reside in the Simulator dyld shared cache. '
          'Loaded symbol owners and the selected runtime root are recorded.',
    });
  final symbols = evidence['symbols'] as Map<String, Map<String, Object?>>;
  final files = <String>{executable};
  for (final entry in installedPdfDarwinSymbols.entries) {
    for (final name in entry.value) {
      final owner = symbols[name]!;
      final path = owner['image'] as String;
      final canonical = entry.key == 'pdfium'
          ? await File(path).resolveSymbolicLinks()
          : p.normalize(path);
      owner['canonicalImage'] = canonical;
      if (entry.key == 'pdfium') files.add(canonical);
    }
  }
  evidence['bundledFiles'] = [
    for (final path in files)
      {
        'path': path,
        'bytes': await File(path).length(),
        'sha256': (await sha256.bind(File(path).openRead()).first).toString(),
      },
  ];
  await File(
    p.join(output.path, 'bundle-runtime-ios-images.json'),
  ).writeAsString(
    const JsonEncoder.withIndent('  ').convert(evidence),
    flush: true,
  );
  final errors = installedPdfIosModuleErrors(evidence);
  if (errors.isNotEmpty) throw StateError(errors.join('\n'));
  return evidence;
}
