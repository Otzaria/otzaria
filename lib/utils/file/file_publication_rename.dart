import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:posix/posix.dart' as posix;
import 'package:win32/win32.dart' as win32;

Future<void> renamePublicationWithoutReplacing(String from, String to) =>
    Isolate.run(() => _renameWithoutReplacing(from, to));

void _renameWithoutReplacing(String from, String to) {
  using((arena) {
    if (Platform.isWindows) {
      final source = windowsPublicationPath(
        from,
      ).toNativeUtf16(allocator: arena);
      final destination = windowsPublicationPath(
        to,
      ).toNativeUtf16(allocator: arena);
      final result = win32.MoveFileEx(
        win32.PCWSTR(source),
        win32.PCWSTR(destination),
        const win32.MOVE_FILE_FLAGS(0),
      );
      if (!result.value) _renameFailed(to, result.error);
      return;
    }
    final source = from.toNativeUtf8(allocator: arena);
    final destination = to.toNativeUtf8(allocator: arena);
    if (Platform.isMacOS && _process.providesSymbol('renamex_np')) {
      posix.clearErrno();
      if (_renamex(source, destination, _renameExclusive) != 0) {
        _renameFailed(to, posix.errno());
      }
      return;
    }
    if (Platform.isLinux && _process.providesSymbol('renameat2')) {
      posix.clearErrno();
      if (_renameat2(_cwd, source, _cwd, destination, _renameNoReplace) != 0) {
        _renameFailed(to, posix.errno());
      }
      return;
    }
    throw FileSystemException('Exclusive file publication is unavailable', to);
  });
}

Never _renameFailed(String path, int code) => throw FileSystemException(
  'Cannot publish without replacing the target',
  path,
  OSError('', code),
);

const _renameExclusive = 4;
const _renameNoReplace = 1;
const _cwd = -100; // Linux AT_FDCWD. Both paths are absolute.
final _process = DynamicLibrary.process();
final _renamex = _process
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, Pointer<Utf8>, int)
    >('renamex_np');
final _renameat2 = _process
    .lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Uint32),
      int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)
    >('renameat2');

String windowsPublicationPath(String path) {
  if (path.startsWith(r'\\?\') || path.startsWith(r'\\.\')) return path;
  final absolute = p.normalize(p.absolute(path));
  if (absolute.length < 260) return absolute;
  return absolute.startsWith(r'\\')
      ? r'\\?\UNC\' + absolute.substring(2)
      : r'\\?\' + absolute;
}
