import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:posix/posix.dart' as posix;

import 'file_publication_rename.dart';

void makeFilePublicationPrivate(String path) {
  if (Platform.isLinux || Platform.isMacOS) _setPosixMode(path, 0x180);
}

Future<void> preserveFilePublicationPermissions(
  String destination,
  String staging,
) async {
  final type = await FileSystemEntity.type(destination, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.file) {
    throw FileSystemException(
      'Only regular files can be replaced',
      destination,
    );
  }
  if (Platform.isWindows) {
    _copyWindowsDacl(destination, staging);
  } else if (Platform.isLinux || Platform.isMacOS) {
    final stat = await FileStat.stat(destination);
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Cannot read target permissions', destination);
    }
    _setPosixMode(staging, stat.mode & 0xFFF);
  }
}

void _setPosixMode(String path, int mode) {
  try {
    posix.chmod(path, mode.toRadixString(8));
  } on posix.PosixException catch (error) {
    throw FileSystemException(
      'Cannot preserve file permissions',
      path,
      OSError(error.message, error.code),
    );
  }
}

const _fileObject = 1;
const _daclInformation = 0x00000004;
const _daclProtected = 0x1000;
const _protectedDaclInformation = 0x80000000;
const _unprotectedDaclInformation = 0x20000000;

void _copyWindowsDacl(String source, String destination) {
  using((arena) {
    final descriptor = arena<Pointer<Void>>();
    final dacl = arena<Pointer<Void>>();
    final control = arena<Uint16>();
    final revision = arena<Uint32>();
    final sourceName = windowsPublicationPath(
      source,
    ).toNativeUtf16(allocator: arena);
    final destinationName = windowsPublicationPath(destination).toNativeUtf16(
      allocator: arena,
    );
    try {
      final read = _getNamedSecurityInfo(
        sourceName,
        _fileObject,
        _daclInformation,
        nullptr,
        nullptr,
        dacl,
        nullptr,
        descriptor,
      );
      if (read != 0) {
        throw FileSystemException(
          'Read file permissions',
          source,
          OSError('', read),
        );
      }
      if (_getSecurityDescriptorControl(descriptor.value, control, revision) ==
          0) {
        throw FileSystemException('Read file permission flags', source);
      }
      final protection = (control.value & _daclProtected) != 0
          ? _protectedDaclInformation
          : _unprotectedDaclInformation;
      // A successful read may return a NULL DACL. Preserve that distinction;
      // never replace a failed read with unrestricted access.
      final written = _setNamedSecurityInfo(
        destinationName,
        _fileObject,
        _daclInformation | protection,
        nullptr,
        nullptr,
        dacl.value,
        nullptr,
      );
      if (written != 0) {
        throw FileSystemException(
          'Write file permissions',
          destination,
          OSError('', written),
        );
      }
    } finally {
      if (descriptor.value != nullptr) _localFree(descriptor.value);
    }
  });
}

final _security = DynamicLibrary.open('advapi32.dll');
final _getNamedSecurityInfo = _security
    .lookupFunction<
      Uint32 Function(
        Pointer<Utf16>,
        Int32,
        Uint32,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
      ),
      int Function(
        Pointer<Utf16>,
        int,
        int,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
      )
    >('GetNamedSecurityInfoW');
final _setNamedSecurityInfo = _security
    .lookupFunction<
      Uint32 Function(
        Pointer<Utf16>,
        Int32,
        Uint32,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        Pointer<Utf16>,
        int,
        int,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('SetNamedSecurityInfoW');
final _getSecurityDescriptorControl = _security
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint16>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint16>, Pointer<Uint32>)
    >('GetSecurityDescriptorControl');
final _localFree = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree');
