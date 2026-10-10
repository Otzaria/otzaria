import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';

/// ביטול הורדה מבחוץ (כפתור "ביטול" בכרטיס).
class AttachedUpdateCancelToken {
  final _listeners = <void Function()>[];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  /// Registers [listener]; returns the function that unregisters it.
  void Function() onCancel(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

class AttachedUpdateCancelled implements Exception {
  const AttachedUpdateCancelled();
}

/// כשל רשת או תגובה לא צפויה. אינו כולל דחיית מדיניות
/// ([AttachedUpdateHostRejected]) וסטיית תוכן ([AttachedUpdatePartMismatch]).
class AttachedUpdateNetworkException implements Exception {
  final String message;
  const AttachedUpdateNetworkException(this.message);

  @override
  String toString() => 'AttachedUpdateNetworkException: $message';
}

/// תגובת HTTP שנכשלה, עם קוד זמין להבחנה בין קובץ חסר לניתוק.
class AttachedUpdateHttpException extends AttachedUpdateNetworkException {
  final int statusCode;
  const AttachedUpdateHttpException(this.statusCode)
    : super('HTTP $statusCode');
}

/// חלק שהורד אינו תואם ל-sha256 שבמניפסט. הבתים שלו נמחקו מהקובץ.
class AttachedUpdatePartMismatch implements Exception {
  final int partIndex;
  const AttachedUpdatePartMismatch(this.partIndex);

  @override
  String toString() => 'AttachedUpdatePartMismatch: part $partIndex';
}

/// לקוח ה-HTTP של עדכוני המסדים המצורפים. כל חיבור — גם אחרי הפניה — עובר
/// ב-[policy], והחיבור נעשה לכתובות שנבדקו בדיוק. תעודות: ה-SecurityContext
/// הגלובלי, שאליו נטענות תעודות נטפרי בעלייה (כמו בעדכון הספרייה הרשמי).
/// dart:io בלבד — אפשר להריצו ב-isolate.
class AttachedUpdateFetcher {
  AttachedUpdateFetcher({
    this.policy = const AttachedUpdateHostPolicy(),
    this.connectTimeout = const Duration(seconds: 15),
    this.readTimeout = const Duration(seconds: 30),
    this.maxRedirects = 5,
    this.findProxy = HttpClient.findProxyFromEnvironment,
  });

  final AttachedUpdateHostPolicy policy;
  final Duration connectTimeout;

  /// זמן מרבי בלי אף בית — לכותרות התגובה ובין נתחי הגוף.
  final Duration readTimeout;
  final int maxRedirects;

  /// Same proxy resolution as the official library updater (`http.Client`).
  final String Function(Uri uri) findProxy;

  static const _userAgent = 'Otzaria-attached-library-updater';

  /// כתובת החתימה: נתיב המניפסט עם `.sig` (שאילתה, אם יש, נשמרת).
  static Uri signatureUriFor(Uri manifest) =>
      manifest.replace(path: '${manifest.path}.sig');

  /// מוריד את המניפסט ואת חתימתו. האימות — אצל הקורא, עם המפתח הנעוץ.
  Future<({Uint8List manifest, Uint8List signature})> fetchSignedManifest(
    String manifestUrl, {
    AttachedUpdateCancelToken? cancel,
  }) async {
    final uri = Uri.parse(manifestUrl);
    final manifest = await fetchBytes(
      uri,
      maxBytes: AttachedUpdateManifest.maxManifestBytes,
      cancel: cancel,
    );
    final signature = await fetchBytes(
      signatureUriFor(uri),
      maxBytes: AttachedUpdateManifest.maxSignatureBytes,
      cancel: cancel,
    );
    return (manifest: manifest, signature: signature);
  }

  /// גוף תגובת 200 כולו, עד [maxBytes].
  Future<Uint8List> fetchBytes(
    Uri uri, {
    required int maxBytes,
    AttachedUpdateCancelToken? cancel,
  }) => _withClient(cancel, (client) async {
    final response = await _open(client, uri, cancel: cancel);
    if (response.statusCode != HttpStatus.ok) {
      throw AttachedUpdateHttpException(response.statusCode);
    }
    if (response.contentLength > maxBytes) {
      throw const AttachedUpdateNetworkException('response too large');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in _body(response, cancel)) {
      if (builder.length + chunk.length > maxBytes) {
        throw const AttachedUpdateNetworkException('response too large');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  });

  /// מוריד את [parts] לפי הסדר ומשרשר אותם ל-[targetPath], עם sha256 לכל
  /// חלק. קובץ חלקי קיים ממשיך מאותה נקודה (Range) אחרי אימות מה שכבר בו;
  /// חלק שאינו תואם נחתך מהקובץ וזורק [AttachedUpdatePartMismatch].
  Future<void> downloadParts(
    List<AttachedUpdatePart> parts,
    String targetPath, {
    void Function(int received, int total)? onProgress,
    AttachedUpdateCancelToken? cancel,
  }) async {
    final total = parts.fold<int>(0, (sum, part) => sum + part.size);
    final file = File(targetPath);
    var existing = await file.exists() ? await file.length() : 0;
    if (existing > total) existing = 0;

    // אימות מה שכבר בדיסק: חלקים שלמים נבדקים, והחלקי ממשיך מהגיבוב שלו.
    var index = 0;
    var start = 0;
    var resumeSink = _DigestSink();
    ByteConversionSink? resumeHash;
    var resumeHave = 0;
    while (index < parts.length) {
      final part = parts[index];
      final have = (existing - start).clamp(0, part.size);
      if (have == 0) break;
      resumeSink = _DigestSink();
      resumeHash = sha256.startChunkedConversion(resumeSink);
      await for (final chunk in file.openRead(start, start + have)) {
        resumeHash.add(chunk);
      }
      if (have < part.size) {
        resumeHave = have;
        break;
      }
      resumeHash.close();
      if (resumeSink.value.toString() != part.sha256) {
        resumeHash = null;
        break;
      }
      resumeHash = null;
      start += part.size;
      index++;
    }
    final raf = await file.open(mode: FileMode.append);
    try {
      await _truncate(raf, start + resumeHave);
      var received = start + resumeHave;
      onProgress?.call(received, total);
      void onBytes(int n) {
        received += n;
        onProgress?.call(received, total);
      }

      for (; index < parts.length; index++) {
        final part = parts[index];
        final have = resumeHave;
        resumeHave = 0;
        var sink = have > 0 ? resumeSink : _DigestSink();
        var hash = have > 0 ? resumeHash! : sha256.startChunkedConversion(sink);
        try {
          await _downloadPart(part, have, raf, hash, onBytes, cancel);
        } on _RestartPart {
          await _truncate(raf, start);
          received = start;
          sink = _DigestSink();
          hash = sha256.startChunkedConversion(sink);
          await _downloadPart(part, 0, raf, hash, onBytes, cancel);
        }
        hash.close();
        if (sink.value.toString() != part.sha256) {
          await _truncate(raf, start);
          throw AttachedUpdatePartMismatch(index);
        }
        start += part.size;
      }
    } finally {
      await raf.close();
    }
  }

  // המיקום נקבע במפורש: FileMode.append אינו מבטיח כתיבה לסוף אחרי חיתוך.
  static Future<void> _truncate(RandomAccessFile raf, int length) async {
    await raf.truncate(length);
    await raf.setPosition(length);
  }

  /// כותב את המשך החלק מבית [have]. שרת שהתעלם מ-Range זורק [_RestartPart]
  /// לפני כתיבה כלשהי — הקורא מתחיל את החלק מאפס.
  Future<void> _downloadPart(
    AttachedUpdatePart part,
    int have,
    RandomAccessFile raf,
    ByteConversionSink hash,
    void Function(int bytes) onBytes,
    AttachedUpdateCancelToken? cancel,
  ) => _withClient(cancel, (client) async {
    final response = await _open(
      client,
      Uri.parse(part.url),
      cancel: cancel,
      headers: {
        if (have > 0) HttpHeaders.rangeHeader: 'bytes=$have-${part.size - 1}',
      },
    );
    var written = have;
    if (have > 0 && response.statusCode == HttpStatus.partialContent) {
      final range = response.headers.value(HttpHeaders.contentRangeHeader);
      if (range == null || !range.startsWith('bytes $have-')) {
        throw const AttachedUpdateNetworkException('unexpected Content-Range');
      }
    } else if (response.statusCode == HttpStatus.ok) {
      if (have > 0) throw const _RestartPart();
    } else {
      throw AttachedUpdateHttpException(response.statusCode);
    }
    await for (final chunk in _body(response, cancel)) {
      if (written + chunk.length > part.size) {
        throw const AttachedUpdateNetworkException('part larger than declared');
      }
      await raf.writeFrom(chunk);
      hash.add(chunk);
      written += chunk.length;
      onBytes(chunk.length);
    }
    if (written != part.size) {
      throw const AttachedUpdateNetworkException('connection closed early');
    }
  });

  /// גוף התגובה עם [readTimeout] בין נתחים, ונקטע מיד בביטול — סגירת הלקוח
  /// לבדה אינה מבטיחה שזרם תקוע יסתיים.
  Stream<List<int>> _body(
    HttpClientResponse response,
    AttachedUpdateCancelToken? cancel,
  ) {
    final body = response.timeout(readTimeout);
    if (cancel == null) return body;
    StreamSubscription<List<int>>? subscription;
    void Function()? unsubscribe;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        subscription = body.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            unsubscribe?.call();
            controller.close();
          },
        );
        unsubscribe = cancel.onCancel(() {
          subscription?.cancel();
          controller
            ..addError(const AttachedUpdateCancelled())
            ..close();
        });
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        unsubscribe?.call();
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<T> _withClient<T>(
    AttachedUpdateCancelToken? cancel,
    Future<T> Function(HttpClient client) body,
  ) async {
    if (cancel?.isCancelled ?? false) throw const AttachedUpdateCancelled();
    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..idleTimeout = const Duration(seconds: 5)
      ..autoUncompress = false
      ..userAgent = _userAgent
      ..findProxy = findProxy
      ..connectionFactory = _connect;
    // גם המתנה לחיבור או לכותרות נקטעת בביטול, לא רק קריאת הגוף.
    final cancelled = Completer<T>();
    final unsubscribe = cancel?.onCancel(() {
      client.close(force: true);
      if (!cancelled.isCompleted) {
        cancelled.completeError(const AttachedUpdateCancelled());
      }
    });
    try {
      return await Future.any([body(client), cancelled.future]);
    } on AttachedUpdateHostRejected {
      rethrow;
    } catch (e) {
      if (cancel?.isCancelled ?? false) throw const AttachedUpdateCancelled();
      if (e is AttachedUpdateNetworkException || e is _RestartPart) rethrow;
      if (e is SocketException ||
          e is HttpException ||
          e is TlsException ||
          e is TimeoutException) {
        throw AttachedUpdateNetworkException(e.toString());
      }
      rethrow;
    } finally {
      unsubscribe?.call();
      client.close(force: true);
    }
  }

  /// מתחבר לכתובת שהמדיניות אישרה, ומקים TLS מול שם המארח המקורי.
  Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (proxyHost != null && proxyPort != null) {
      // The proxy resolves the host; reject only a locally private address.
      await policy.checkNotPrivate(uri);
      return Socket.startConnect(proxyHost, proxyPort);
    }
    final addresses = await policy.resolve(uri);
    Socket? raw;
    Object? lastError;
    for (final address in addresses) {
      try {
        raw = await Socket.connect(address, uri.port, timeout: connectTimeout);
        break;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    if (raw == null) {
      throw lastError ?? const SocketException('connection failed');
    }
    final socket = uri.scheme == 'https'
        ? SecureSocket.secure(raw, host: uri.host)
        : Future<Socket>.value(raw);
    return ConnectionTask.fromSocket(socket, raw.destroy);
  }

  /// פותח בקשת GET ועוקב אחרי הפניות ידנית — כל יעד נבדק במדיניות.
  Future<HttpClientResponse> _open(
    HttpClient client,
    Uri uri, {
    AttachedUpdateCancelToken? cancel,
    Map<String, String> headers = const {},
  }) async {
    var current = uri;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      policy.checkUri(current);
      final request = await client
          .getUrl(current)
          .timeout(connectTimeout + policy.lookupTimeout);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(readTimeout);
      if (!response.isRedirect) return response;
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.listen(null).cancel();
      if (location == null) {
        throw const AttachedUpdateNetworkException('redirect without Location');
      }
      current = current.resolve(location);
    }
    throw const AttachedUpdateNetworkException('too many redirects');
  }
}

class _RestartPart implements Exception {
  const _RestartPart();
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;
  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
