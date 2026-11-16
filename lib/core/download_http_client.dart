import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:otzaria/core/download_network_policy.dart';

/// לקוחות נפרדים נשארים בבעלות הקוראים; אין client גלובלי שנסגר בטעות.
http.Client createDownloadClient([http.Client? inner]) {
  final client = inner ?? http.Client();
  final policy = DownloadNetworkPolicy.instance;
  return policy.isSupported
      ? DownloadHttpClient(client, policy: policy)
      : client;
}

/// אוכף גם בקשות חוזרות ומפסיק גוף פתוח כשהרשת כבר אינה מותרת.
/// במעקב redirects אוטומטי נדרש client ייעודי שהקורא סוגר בסיום הבקשה.
class DownloadHttpClient extends http.BaseClient {
  DownloadHttpClient(this._inner, {DownloadNetworkPolicy? policy})
    : _policy = policy ?? DownloadNetworkPolicy.instance;

  final http.Client _inner;
  final DownloadNetworkPolicy _policy;
  final _releases = <void Function()>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _policy.requireAccess();
    final abort = Completer<void>();
    DownloadNetworkStatus? denied;
    final subscription = _policy.changes.listen((status) {
      if (status != DownloadNetworkStatus.allowed) {
        denied = status;
        if (!abort.isCompleted) abort.complete();
      }
    });
    void release() {
      _releases.remove(release);
      unawaited(subscription.cancel());
    }

    _releases.add(release);
    final originalAbort = request is http.Abortable
        ? request.abortTrigger
        : null;
    final guarded = _PolicyRequest(
      request,
      originalAbort == null
          ? abort.future
          : Future.any([abort.future, originalAbort]),
    );
    try {
      if (_policy.status != DownloadNetworkStatus.allowed) {
        throw DownloadNetworkPaused(_policy.status);
      }
      final response = await _inner.send(guarded);
      StreamSubscription<List<int>>? upstream;
      late final StreamController<List<int>> body;
      // ביטול IOClient אינו סוגר תגובה שטרם האזינו לה; נרשמים לפני צריכת הגוף.
      body = StreamController<List<int>>(
        sync: true,
        onListen: () => upstream?.resume(),
        onPause: () => upstream?.pause(),
        onResume: () => upstream?.resume(),
        onCancel: () {
          release();
          return upstream?.cancel();
        },
      );
      upstream = response.stream.listen(
        (chunk) {
          if (denied == null) {
            body.add(chunk);
          } else {
            body.addError(DownloadNetworkPaused(denied!));
            unawaited(upstream?.cancel());
            release();
            unawaited(body.close());
          }
        },
        onError: (Object error, StackTrace stack) {
          body.addError(
            denied != null && error is http.RequestAbortedException
                ? DownloadNetworkPaused(denied!)
                : error,
            stack,
          );
        },
        onDone: () {
          release();
          unawaited(body.close());
        },
      )..pause();

      return http.StreamedResponse(
        body.stream,
        response.statusCode,
        headers: response.headers,
        contentLength: response.contentLength,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        request: request,
      );
    } on http.RequestAbortedException {
      release();
      if (denied != null) throw DownloadNetworkPaused(denied!);
      rethrow;
    } catch (_) {
      release();
      rethrow;
    }
  }

  @override
  void close() {
    for (final release in _releases.toList()) {
      release();
    }
    _inner.close();
  }
}

class _PolicyRequest extends http.BaseRequest with http.Abortable {
  _PolicyRequest(this.original, this.abortTrigger)
    : super(original.method, original.url) {
    contentLength = original.contentLength;
    followRedirects = original.followRedirects;
    headers.addAll(original.headers);
    maxRedirects = original.maxRedirects;
    persistentConnection = original.persistentConnection;
  }

  final http.BaseRequest original;
  @override
  final Future<void> abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return original.finalize();
  }
}
