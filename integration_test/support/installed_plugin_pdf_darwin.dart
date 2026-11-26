import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../tool/perf_probe/src/installed_pdf_darwin_contract.dart';

/// בודק את בעלי הסמלים שכבר נטענו; אינו פותח ספרייה נוספת.
Map<String, Object?> collectInstalledPdfDarwinSymbols() => using((arena) {
  final process = DynamicLibrary.process();
  final imageCount = process.lookupFunction<Uint32 Function(), int Function()>(
    '_dyld_image_count',
  );
  final imageName = process
      .lookupFunction<
        Pointer<Utf8> Function(Uint32),
        Pointer<Utf8> Function(int)
      >('_dyld_get_image_name');
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
  for (final names in installedPdfDarwinSymbols.values) {
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
