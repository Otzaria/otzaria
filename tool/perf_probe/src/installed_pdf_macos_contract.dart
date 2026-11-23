import 'package:path/path.dart' as p;

import 'installed_pdf_darwin_contract.dart';

const installedPdfMacosSymbols = installedPdfDarwinSymbols;
const installedPdfMacosSource = installedPdfDarwinSource;
const installedPdfMacosPrinting = installedPdfDarwinPrinting;

/// הבעלות על הסמלים קושרת את הפעולות שנבדקו לספריות הטעונות בפועל.
List<String> installedPdfMacosModuleErrors(Object? value) {
  if (value is! Map) return ['Missing macOS loaded-image evidence'];
  final errors = <String>[];
  bool absolute(Object? path) =>
      path is String &&
      p.posix.isAbsolute(path) &&
      p.posix.normalize(path) == path;
  final bundle = value['bundle'];
  final executable = value['executable'];
  if (value['source'] != installedPdfMacosSource ||
      value['pid'] is! int ||
      (value['pid'] as int) <= 0 ||
      !absolute(bundle) ||
      !(bundle as String).endsWith('.app') ||
      !absolute(executable) ||
      p.posix.dirname(executable as String) !=
          p.posix.join(bundle, 'Contents', 'MacOS') ||
      !value.containsKey('configuredPdfrxModule') ||
      value['configuredPdfrxModule'] != null ||
      value['printingBackend'] != installedPdfMacosPrinting) {
    return ['Invalid macOS app identity, process loader or printing backend'];
  }
  final images = value['images'];
  final symbols = value['symbols'];
  if (images is! List ||
      images.isEmpty ||
      images.any((image) => !absolute(image)) ||
      symbols is! Map) {
    return ['Missing macOS dyld images or resolved symbols'];
  }
  final pdfiumImages = <String>{};
  for (final entry in installedPdfMacosSymbols.entries) {
    for (final name in entry.value) {
      final symbol = symbols[name];
      if (symbol is! Map ||
          !absolute(symbol['image']) ||
          !absolute(symbol['canonicalImage']) ||
          !images.contains(symbol['image']) ||
          symbol['address'] is! String ||
          !RegExp(r'^0x[0-9a-f]*[1-9a-f][0-9a-f]*$').hasMatch(
            symbol['address'] as String,
          ) ||
          symbol['imageBase'] is! String ||
          !RegExp(r'^0x[0-9a-f]*[1-9a-f][0-9a-f]*$').hasMatch(
            symbol['imageBase'] as String,
          )) {
        errors.add('Missing loaded-image owner for $name');
        continue;
      }
      final image = symbol['canonicalImage'] as String;
      if (entry.key == 'pdfium') {
        if (image != executable &&
            !p.posix.isWithin(
              p.posix.join(bundle, 'Contents', 'Frameworks'),
              image,
            )) {
          errors.add('$name is not provided by the actual app bundle: $image');
        }
        pdfiumImages.add(image);
      } else if (symbol['image'] != image ||
          (!p.posix.isWithin('/System/Library/Frameworks', image) &&
              !p.posix.isWithin('/System/Library/PrivateFrameworks', image))) {
        errors.add(
          '$name is not provided by an Apple system framework: $image',
        );
      }
    }
  }
  if (pdfiumImages.length != 1) {
    errors.add('PDFium entry points must come from one loaded app image');
  }
  final expectedFiles = {executable, ...pdfiumImages};
  final files = value['bundledFiles'];
  final observedFiles = <String>{};
  if (files is! List) {
    errors.add('Missing bundled binary hashes');
  } else {
    for (final file in files) {
      if (file is! Map ||
          file['path'] is! String ||
          !expectedFiles.contains(file['path']) ||
          !observedFiles.add(file['path'] as String) ||
          file['bytes'] is! int ||
          (file['bytes'] as int) <= 0 ||
          file['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(file['sha256'] as String)) {
        errors.add('Invalid, duplicate or foreign bundled binary hash');
      }
    }
    if (observedFiles.length != expectedFiles.length ||
        !observedFiles.containsAll(expectedFiles)) {
      errors.add('App executable and PDFium image hashes are required');
    }
  }
  return errors;
}
