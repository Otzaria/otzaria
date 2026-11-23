import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../tool/perf_probe/src/installed_pdf_android_contract.dart';

/// אוסף את הספרייה הממופה; ה־host משווה את הגיבוב ל־APK שבנה והתקין.
Future<Map<String, Object?>> installedAndroidPdfModules(
  Directory output,
) async {
  if (!Platform.isAndroid || Abi.current() != Abi.androidX64) {
    throw StateError('The Android PDF probe requires its x86_64 emulator');
  }
  final maps = await File('/proc/self/maps').readAsString();
  await File(
    p.join(output.path, 'bundle-runtime-maps.txt'),
  ).writeAsString(maps, flush: true);
  final observed = installedAndroidPdfMappedPaths(maps);
  final candidates = observed.where(isInstalledAndroidPdfModule).toList();
  if (candidates.length != 1) {
    throw StateError('Expected one installed app PDFium mapping: $candidates');
  }
  final file = File(candidates.single);
  if (await file.resolveSymbolicLinks() != file.path) {
    throw StateError('Installed PDFium mapping cannot be a symbolic link');
  }
  final result = <String, Object?>{
    'source': '/proc/self/maps',
    'package': installedPdfAndroidPackage,
    'abi': 'x86_64',
    'processId': pid,
    'printingBackend': installedPdfAndroidBackend,
    'configuredPdfrxModule': Pdfrx.pdfiumModulePath,
    'observedModulePaths': observed.toList()..sort(),
    'executableModulePaths': installedAndroidPdfMappedPaths(
      maps,
      executableOnly: true,
    ).toList()..sort(),
    'systemModulePaths': observed.where(isAndroidSystemPdfModule).toList()
      ..sort(),
    'appModule': {
      'name': 'libpdfium.so',
      'path': file.path,
      'bytes': await file.length(),
      'sha256': (await sha256.bind(file.openRead()).first).toString(),
    },
  };
  final errors = installedAndroidPdfModuleErrors(result);
  if (errors.isNotEmpty) throw StateError(errors.join('\n'));
  return result;
}
