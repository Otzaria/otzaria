import 'dart:typed_data';

import 'library_zdb_types.dart';

const int? libraryZdbCacheBytesPerFile = null;

({Object error, StackTrace stackTrace})? get libraryVfsRegistrationFailure =>
    null;

bool ensureLibraryVfs() => false;

bool isLibraryZdb(String path) => false;

bool isLibraryDbOpenInProcess(String path) => false;

Uint8List readLibraryZdbBytes(String path, int offset, int length) =>
    throw UnsupportedError('zvfs אינו זמין בפלטפורמה זו');

int libraryZdbLogicalSize(String path) =>
    throw UnsupportedError('zvfs אינו זמין בפלטפורמה זו');

int libraryDbLogicalSizeOf(String path) =>
    throw UnsupportedError('zvfs אינו זמין בפלטפורמה זו');

LibraryZdbHeader readLibraryZdbHeader(String path) =>
    throw UnsupportedError('zvfs אינו זמין בפלטפורמה זו');

Future<void> verifyLibraryZdbFrames(
  String path, {
  void Function(int bytesDone, int totalBytes)? onProgress,
}) => throw UnsupportedError('zvfs אינו זמין בפלטפורמה זו');

Future<void> installLibraryZdb(
  String path,
  String candidatePath, {
  bool verify = true,
}) => throw UnsupportedError('zvfs אינו זמין בפלטפורמה זו');

Future<void> compactLibraryZdb(
  String path, {
  void Function(int bytesDone, int totalBytes)? onProgress,
}) => throw UnsupportedError('zvfs אינו זמין בפלטפורמה זו');
