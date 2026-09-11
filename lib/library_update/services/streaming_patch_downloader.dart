import 'dart:io';
import 'dart:isolate';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

/// פונקציית חילוץ `.zst` מקובץ לקובץ בזרימה (ללא טעינה ל-RAM).
typedef StreamingZstdExtractor =
    Future<void> Function(String archivePath, String outputPath);

/// שם הקובץ המחולץ מארכיון patch — זהה למימוש הבסיסי: הסרת סיומת `.zst`.
String extractedPatchFileName(String archiveFileName) =>
    archiveFileName.endsWith('.zst')
    ? archiveFileName.substring(0, archiveFileName.length - 4)
    : '$archiveFileName.db';

/// [PatchDownloader] שמוריד ומחלץ קובצי patch **בזרימה לדיסק**, במקום דרך
/// הזיכרון.
///
/// המימוש המקורי טוען את ה-patch הדחוס ל-RAM ופורס אותו עם `Zstandard().decompress`.
/// כש-patch של ~560MB נדחס בזרימה בלי שדה גודל בכותרת ה-frame, הספרייה מקצה
/// "גודל דחוס × 20" בבלוק אחד — כ-11GB — והמשתמש רואה
/// `Could not allocate 11694234840 bytes`. גם עם שדה גודל, patch של כמה GB
/// פרוסים לא צריך לשבת בזיכרון.
///
/// הזרימה: [downloadToFile] (עם resume ואימות sha256 של הדחוס) → חילוץ זורם
/// ([ZstdStreamExtractor], אותו מנוע שמשמש להורדה המלאה) → אימות גודל ו-sha256
/// של הקובץ המחולץ מהדיסק. הקובץ הדחוס נמחק בסיום; בכשל נמחקים שניהם.
class StreamingPatchDownloader extends PatchDownloader {
  StreamingPatchDownloader({
    StreamingZstdExtractor? extractor,
    super.httpClient,
    super.connectTimeout,
    super.stallTimeout,
  }) : _extractor = extractor ?? ZstdStreamExtractor.extractToFile,
       // decompress בזיכרון אינו בשימוש במסלול הזה, אך המחלקה הבסיסית דורשת אותו.
       super(decompress: (_) async => null);

  final StreamingZstdExtractor _extractor;

  /// מחזיר נתיב של patch מחולץ רק לאחר אימות גודל ו-sha256.
  Future<String?> findReusableExtracted({
    required PatchFileEntry patchFile,
    required Directory destDir,
    void Function(int bytesDone, int bytesTotal)? onVerifyProgress,
    bool Function()? isCancelled,
  }) async {
    final extractedPath = p.join(
      destDir.path,
      extractedPatchFileName(patchFile.file),
    );
    final reusable = await _reuseExtracted(
      patchFile,
      extractedPath,
      onVerifyProgress: onVerifyProgress,
      isCancelled: isCancelled,
    );
    if (!reusable) return null;
    final compressedPath = p.join(destDir.path, patchFile.file);
    _deleteQuietly(compressedPath);
    _deleteQuietly(PatchDownloader.resumeSidecarPath(compressedPath));
    return extractedPath;
  }

  @override
  Future<String> downloadAndExtract({
    required PatchFileEntry patchFile,
    required String downloadUrl,
    required Directory destDir,
    void Function(int downloaded, int? total)? onProgress,
    void Function(int bytesDone, int bytesTotal)? onVerifyProgress,
    bool Function()? isCancelled,
  }) async {
    if (!destDir.existsSync()) destDir.createSync(recursive: true);

    final compressedPath = p.join(destDir.path, patchFile.file);
    final extractedPath = p.join(
      destDir.path,
      extractedPatchFileName(patchFile.file),
    );

    // patch מחולץ ומאומת שנשאר מריצה שנקטעה באמצע ה-apply — שימוש חוזר בו
    // חוסך הורדה של מאות MB וחילוץ של כמה GB.
    final reused = await _reuseExtracted(
      patchFile,
      extractedPath,
      onVerifyProgress: onVerifyProgress,
      isCancelled: isCancelled,
    );
    if (reused) {
      onProgress?.call(patchFile.size, patchFile.size);
      _deleteQuietly(compressedPath);
      _deleteQuietly(PatchDownloader.resumeSidecarPath(compressedPath));
      return extractedPath;
    }

    try {
      // ה-sha256 של הדחוס הוא זהות יציבה של הנכס — מאפשר המשך הורדה שנקטעה.
      await downloadToFile(
        url: downloadUrl,
        destPath: compressedPath,
        expectedSize: patchFile.size,
        expectedSha256: patchFile.sha256,
        resumeToken: patchFile.sha256,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );

      if (isCancelled != null && isCancelled()) {
        throw const PatchDownloadCancelled();
      }

      _deleteQuietly(extractedPath);
      await _extractor(compressedPath, extractedPath);

      final extracted = File(extractedPath);
      if (!extracted.existsSync()) {
        throw const PatchDownloadException('חילוץ ה-patch נכשל או החזיר ריק');
      }
      final actualSize = extracted.lengthSync();
      if (actualSize != patchFile.uncompressedSize) {
        throw PatchDownloadException(
          'גודל הקובץ המחולץ אינו תואם (צפוי ${patchFile.uncompressedSize}, '
          'בפועל $actualSize)',
        );
      }

      final actualHash = await _sha256OfFile(
        extractedPath,
        onProgress: onVerifyProgress,
        isCancelled: isCancelled,
      );
      if (actualHash != patchFile.uncompressedSha256.toLowerCase()) {
        throw const PatchDownloadException('sha256 של הקובץ המחולץ אינו תואם');
      }

      // הדחוס מילא את תפקידו; יחד איתו נמחק קובץ הצד של ה-resume.
      _deleteQuietly(compressedPath);
      _deleteQuietly(PatchDownloader.resumeSidecarPath(compressedPath));
      return extractedPath;
    } catch (e) {
      _deleteQuietly(extractedPath);
      // ביטול/כשל רשת משאירים את הדחוס להמשך הורדה (downloadToFile מנהל זאת);
      // כשל אימות של המחולץ מעיד על נכס פגום — מוחקים כדי לא להמשיך זבל.
      if (e is PatchDownloadException) {
        _deleteQuietly(compressedPath);
        _deleteQuietly(PatchDownloader.resumeSidecarPath(compressedPath));
      }
      rethrow;
    }
  }

  /// האם [extractedPath] הוא בדיוק ה-patch המצופה. אינו תואם — נמחק.
  /// ביטול באמצע האימות משאיר את הקובץ — ייבדק שוב בריצה הבאה.
  static Future<bool> _reuseExtracted(
    PatchFileEntry patchFile,
    String extractedPath, {
    void Function(int bytesDone, int bytesTotal)? onVerifyProgress,
    bool Function()? isCancelled,
  }) async {
    final extracted = File(extractedPath);
    if (!extracted.existsSync()) return false;
    if (extracted.lengthSync() == patchFile.uncompressedSize) {
      final hash = await _sha256OfFile(
        extractedPath,
        onProgress: onVerifyProgress,
        isCancelled: isCancelled,
      );
      if (hash == patchFile.uncompressedSha256.toLowerCase()) return true;
    }
    _deleteQuietly(extractedPath);
    return false;
  }

  static void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

/// כל כמה בייטים ה-isolate מדווח התקדמות ובודק אם התבקש ביטול.
const int _kVerifyReportEvery = 8 << 20;

/// sha256 של קובץ בזרימה — רץ ב-isolate כדי לא לחסום את ה-UI על קבצים גדולים.
/// [onProgress] מקבל (בייטים שנקראו, גודל הקובץ); ביטול זורק
/// [PatchDownloadCancelled] בתוך שניות גם על קובץ של כמה GB.
Future<String> _sha256OfFile(
  String path, {
  void Function(int bytesDone, int bytesTotal)? onProgress,
  bool Function()? isCancelled,
}) async {
  final total = File(path).lengthSync();
  onProgress?.call(0, total);
  final progressPort = ReceivePort();
  SendPort? cancelPort;
  final sub = progressPort.listen((msg) {
    if (msg is SendPort) {
      cancelPort = msg;
      return;
    }
    final done = msg as int;
    onProgress?.call(done, total);
    if (isCancelled != null && isCancelled()) cancelPort?.send(null);
  });
  try {
    final hash = await _hashInIsolate(path, progressPort.sendPort);
    // קובץ קטן מסתיים לפני דיווח הביניים הראשון — הביטול נבדק גם בסיום.
    if (hash == null || (isCancelled != null && isCancelled())) {
      throw const PatchDownloadCancelled();
    }
    onProgress?.call(total, total);
    return hash;
  } finally {
    await sub.cancel();
    progressPort.close();
  }
}

// מבודד מ-[_sha256OfFile]: הסגור לוכד את כל ה-scope של המתודה, ושם
// onProgress/isCancelled גוררים את ה-bloc הלא-sendable ל-spawn.
Future<String?> _hashInIsolate(String path, SendPort progress) =>
    Isolate.run(() => _hashWorker(path, progress));

/// גוף ה-isolate: מחשב sha256, מדווח כל [_kVerifyReportEvery] בייטים, ועוצר
/// (מחזיר null) כשמגיעה הודעת ביטול על ה-port שהוא שולח בתחילה.
Future<String?> _hashWorker(String path, SendPort progress) async {
  final cancelPort = ReceivePort();
  var cancelled = false;
  cancelPort.listen((_) => cancelled = true);
  progress.send(cancelPort.sendPort);
  try {
    final digestSink = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(digestSink);
    var done = 0;
    var sinceReport = 0;
    await for (final chunk in File(path).openRead()) {
      if (cancelled) return null;
      input.add(chunk);
      done += chunk.length;
      sinceReport += chunk.length;
      if (sinceReport >= _kVerifyReportEvery) {
        sinceReport = 0;
        progress.send(done);
      }
    }
    input.close();
    return digestSink.events.single.toString();
  } finally {
    cancelPort.close();
  }
}
