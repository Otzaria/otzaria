import 'dart:typed_data';

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
