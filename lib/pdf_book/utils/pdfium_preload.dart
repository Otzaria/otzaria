import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/utils/file/windows_library_preload.dart';
import 'package:pdfrx/pdfrx.dart';

/// ב-Windows כל כניסה ל-pdfrx ממתינה לטעינת pdfium.dll ב-`LoadLibraryW` (FFI, safepoint);
/// `DynamicLibrary.open` של pdfrx אינו safepoint, וסריקת אנטי-וירוס בו עוצרת את ה-GC.
void installPdfiumPreloadGate() {
  if (!Platform.isWindows) return;
  final modulePath = Pdfrx.pdfiumModulePath ?? 'pdfium.dll';
  PdfrxEntryFunctions.instance = PdfiumPreloadGate(
    PdfrxEntryFunctions.instance,
    () => Isolate.run(() => _loadLibrary(modulePath)),
  );
}

void _loadLibrary(String modulePath) {
  if (!preloadWindowsLibrary(modulePath)) {
    throw StateError('LoadLibraryW("$modulePath") failed');
  }
}

/// עוטף את [PdfrxEntryFunctions]: הטעינה רצה פעם אחת, וכשל בה לא חוסם.
@visibleForTesting
class PdfiumPreloadGate implements PdfrxEntryFunctions {
  PdfiumPreloadGate(this._inner, this._preload);

  final PdfrxEntryFunctions _inner;
  final Future<void> Function() _preload;
  Future<void>? _ready;

  Future<void> _waitForPreload() => _ready ??= _preload().catchError((
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('pdfium preload failed: $error\n$stackTrace');
  });

  @override
  Future<void> init() async {
    await _waitForPreload();
    return _inner.init();
  }

  @override
  Future<T> suspendPdfiumWorkerDuringAction<T>(
    FutureOr<T> Function() action,
  ) => _inner.suspendPdfiumWorkerDuringAction(action);

  @override
  Future<R> compute<M, R>(
    FutureOr<R> Function(M message) callback,
    M message,
  ) async {
    await _waitForPreload();
    return _inner.compute(callback, message);
  }

  @override
  Future<void> stopBackgroundWorker() => _inner.stopBackgroundWorker();

  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    await _waitForPreload();
    return _inner.openAsset(
      name,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
    );
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    await _waitForPreload();
    return _inner.openData(
      data,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      sourceName: sourceName,
      allowDataOwnershipTransfer: allowDataOwnershipTransfer,
      useProgressiveLoading: useProgressiveLoading,
      maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
      onDispose: onDispose,
    );
  }

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    await _waitForPreload();
    return _inner.openFile(
      filePath,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
    );
  }

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
    read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    await _waitForPreload();
    return _inner.openCustom(
      read: read,
      fileSize: fileSize,
      sourceName: sourceName,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
      onDispose: onDispose,
    );
  }

  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
    Duration? timeout,
  }) async {
    await _waitForPreload();
    return _inner.openUri(
      uri,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      progressCallback: progressCallback,
      preferRangeAccess: preferRangeAccess,
      headers: headers,
      withCredentials: withCredentials,
      timeout: timeout,
    );
  }

  @override
  Future<PdfDocument> createNew({required String sourceName}) async {
    await _waitForPreload();
    return _inner.createNew(sourceName: sourceName);
  }

  @override
  Future<PdfDocument> createFromJpegData(
    Uint8List jpegData, {
    required double width,
    required double height,
    required String sourceName,
  }) async {
    await _waitForPreload();
    return _inner.createFromJpegData(
      jpegData,
      width: width,
      height: height,
      sourceName: sourceName,
    );
  }

  @override
  Future<void> configureFontEnvironment({
    String? fontCachePath,
    List<String> fontPaths = const [],
  }) async {
    await _waitForPreload();
    return _inner.configureFontEnvironment(
      fontCachePath: fontCachePath,
      fontPaths: fontPaths,
    );
  }

  @override
  Future<void> reloadFonts() async {
    await _waitForPreload();
    return _inner.reloadFonts();
  }

  @override
  Future<void> addFontData({
    required String face,
    required Uint8List data,
    String? resolvedFace,
  }) async {
    await _waitForPreload();
    return _inner.addFontData(
      face: face,
      data: data,
      resolvedFace: resolvedFace,
    );
  }

  @override
  Future<void> addFontFile({
    required String face,
    required String filePath,
    String? resolvedFace,
  }) async {
    await _waitForPreload();
    return _inner.addFontFile(
      face: face,
      filePath: filePath,
      resolvedFace: resolvedFace,
    );
  }

  @override
  Future<void> clearAllFontData() async {
    await _waitForPreload();
    return _inner.clearAllFontData();
  }

  @override
  PdfrxBackendType get backendType => _inner.backendType;
}
