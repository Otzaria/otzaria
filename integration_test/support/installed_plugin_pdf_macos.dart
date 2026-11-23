import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../tool/perf_probe/src/installed_pdf_macos_contract.dart';
import 'installed_plugin_pdf_darwin.dart';

/// תצלום אחרי רסטר ההדפסה; אין פתיחה נוספת של PDFium או החלפת loader.
Future<Map<String, Object?>> collectInstalledPdfMacosImages(
  Directory output,
) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('macOS loaded-image collection requires macOS');
  }
  final executable = await File(
    Platform.resolvedExecutable,
  ).resolveSymbolicLinks();
  final bundle = p.dirname(p.dirname(p.dirname(executable)));
  final evidence = collectInstalledPdfDarwinSymbols()
    ..addAll({
      'source': installedPdfMacosSource,
      'pid': pid,
      'bundle': bundle,
      'executable': executable,
      'configuredPdfrxModule': Pdfrx.pdfiumModulePath,
      'printingBackend': installedPdfMacosPrinting,
      'systemImageHashes':
          'Not read: Apple frameworks may be mapped from the dyld shared cache. '
          'Their symbol owners and loaded image paths are recorded.',
    });
  final symbols = evidence['symbols'] as Map<String, Map<String, Object?>>;
  final bundledPaths = <String>{executable};
  for (final entry in installedPdfMacosSymbols.entries) {
    for (final name in entry.value) {
      final owner = symbols[name]!;
      final path = owner['image'] as String;
      final canonical = entry.key == 'pdfium'
          ? await File(path).resolveSymbolicLinks()
          : p.normalize(path);
      owner['canonicalImage'] = canonical;
      if (entry.key == 'pdfium') bundledPaths.add(canonical);
    }
  }
  evidence['bundledFiles'] = [
    for (final path in bundledPaths)
      {
        'path': path,
        'bytes': await File(path).length(),
        'sha256': (await sha256.bind(File(path).openRead()).first).toString(),
      },
  ];
  await File(
    p.join(output.path, 'bundle-runtime-macos-images.json'),
  ).writeAsString(
    const JsonEncoder.withIndent('  ').convert(evidence),
    flush: true,
  );
  final errors = installedPdfMacosModuleErrors(evidence);
  if (errors.isNotEmpty) throw StateError(errors.join('\n'));
  return evidence;
}
