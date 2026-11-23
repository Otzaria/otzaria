import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../tool/perf_probe/src/installed_pdf_macos_contract.dart';

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
  final evidence = _loadedImageEvidence()
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

Map<String, Object?> _loadedImageEvidence() => using((arena) {
  final process = DynamicLibrary.process();
  final imageCount = process.lookupFunction<Uint32 Function(), int Function()>(
    '_dyld_image_count',
  );
  final imageName = process
      .lookupFunction<
        Pointer<Utf8> Function(Uint32),
        Pointer<Utf8> Function(int)
      >(
        '_dyld_get_image_name',
      );
  final dladdr = process
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<_DlInfo>),
        int Function(Pointer<Void>, Pointer<_DlInfo>)
      >('dladdr');
  final count = imageCount();
  if (count <= 0 || count > 16384) {
    throw StateError('Invalid dyld image count: $count');
  }
  final images = <String>{};
  var disappeared = 0;
  for (var i = 0; i < count; i++) {
    final name = imageName(i);
    if (name == nullptr) {
      disappeared++;
    } else {
      images.add(name.toDartString());
    }
  }
  final symbols = <String, Map<String, Object?>>{};
  for (final names in installedPdfMacosSymbols.values) {
    for (final name in names) {
      final address = process.lookup<Void>(name);
      final info = arena<_DlInfo>();
      if (dladdr(address, info) == 0 ||
          info.ref.imageName == nullptr ||
          info.ref.imageBase == nullptr) {
        throw StateError('dyld did not identify the loaded image for $name');
      }
      final owner = info.ref.imageName.toDartString();
      // הרשימה אינה אטומית; dladdr הוא הראיה המחייבת לסמלים שבשימוש.
      images.add(owner);
      symbols[name] = {
        'image': owner,
        'address': '0x${address.address.toRadixString(16)}',
        'imageBase': '0x${info.ref.imageBase.address.toRadixString(16)}',
        'nearestSymbol': info.ref.symbolName == nullptr
            ? null
            : info.ref.symbolName.toDartString(),
      };
    }
  }
  return {
    'images': images.toList()..sort(),
    'enumeratedImageCount': count,
    'disappearedDuringEnumeration': disappeared,
    'symbols': symbols,
  };
});

final class _DlInfo extends Struct {
  external Pointer<Utf8> imageName;
  external Pointer<Void> imageBase;
  external Pointer<Utf8> symbolName;
  external Pointer<Void> symbolAddress;
}
