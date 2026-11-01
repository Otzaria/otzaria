import 'package:http/http.dart' as http;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/library_update/services/github_etag_cache.dart';
import 'package:path/path.dart' as p;

/// GitHub דחה את הבקשה כי מכסת ה-API ללא הזדהות (60 לשעה לכל IP) נוצלה.
class GithubRateLimitException implements Exception {
  /// מתי המכסה מתחדשת, או `null` כשהשרת לא ציין.
  final DateTime? resetAt;

  const GithubRateLimitException({this.resetAt});

  /// דקות עד חידוש המכסה (לפחות 1), או `null` כשהמועד אינו ידוע.
  int? minutesUntilReset({DateTime? now}) {
    final reset = resetAt;
    if (reset == null) return null;
    final seconds = reset.difference(now ?? DateTime.now()).inSeconds;
    return seconds <= 0 ? 1 : (seconds / 60).ceil();
  }

  @override
  String toString() => 'GitHub API rate limit exceeded (reset: $resetAt)';
}

/// לקוח HTTP שהופך תשובת חסימת-מכסה של GitHub ל-[GithubRateLimitException],
/// כדי שהמשתמש יראה מתי לנסות שוב במקום "403" גולמי.
///
/// עם [etagCache], בקשות GET ל-api.github.com נשלחות עם `If-None-Match`;
/// תשובת 304 אינה נספרת במכסה והלקוח מחזיר מהמטמון 200 רגיל.
class GithubRateLimitAwareClient extends http.BaseClient {
  final http.Client _inner;
  final GithubEtagCache? _etagCache;

  GithubRateLimitAwareClient([http.Client? inner, GithubEtagCache? etagCache])
    : _inner = inner ?? http.Client(),
      _etagCache = etagCache;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final cache = _etagCache;
    final cacheable =
        cache != null &&
        request.method == 'GET' &&
        request.url.host == 'api.github.com';
    final cached = cacheable ? await cache.read(request.url) : null;
    if (cached != null) request.headers['If-None-Match'] = cached.etag;

    final response = await _inner.send(request);
    final exception = rateLimitExceptionFor(
      response.statusCode,
      response.headers,
    );
    if (exception != null) {
      await response.stream.drain<void>();
      throw exception;
    }
    if (!cacheable) return response;

    if (response.statusCode == 304 && cached != null) {
      await response.stream.drain<void>();
      return http.StreamedResponse(
        Stream.value(cached.body),
        200,
        contentLength: cached.body.length,
        request: request,
        headers: {
          ...response.headers,
          if (cached.contentType != null) 'content-type': cached.contentType!,
        },
      );
    }
    final etag = response.headers['etag'];
    if (response.statusCode != 200 || etag == null) return response;
    final body = await response.stream.toBytes();
    await cache.write(
      request.url,
      GithubEtagEntry(
        etag: etag,
        contentType: response.headers['content-type'],
        body: body,
      ),
    );
    return http.StreamedResponse(
      Stream.value(body),
      200,
      contentLength: body.length,
      request: request,
      headers: response.headers,
    );
  }

  /// מזהה חסימת מכסה לפי הסטטוס והכותרות; `null` כשזו תשובה אחרת.
  static GithubRateLimitException? rateLimitExceptionFor(
    int statusCode,
    Map<String, String> headers, {
    DateTime? now,
  }) {
    if (statusCode != 403 && statusCode != 429) return null;
    final retryAfter = int.tryParse(headers['retry-after'] ?? '');
    if (retryAfter != null) {
      return GithubRateLimitException(
        resetAt: (now ?? DateTime.now()).add(Duration(seconds: retryAfter)),
      );
    }
    if (headers['x-ratelimit-remaining'] != '0') return null;
    final reset = int.tryParse(headers['x-ratelimit-reset'] ?? '');
    return GithubRateLimitException(
      resetAt: reset == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(reset * 1000),
    );
  }

  @override
  void close() => _inner.close();
}

/// לקוח GitHub של האפליקציה: חסימת מכסה כחריגה, ותשובות מותנות במטמון בדיסק.
GithubRateLimitAwareClient githubClientWithEtagCache() =>
    GithubRateLimitAwareClient(
      null,
      GithubEtagCache(
        () async =>
            p.join(await AppPaths.getDataRootPath(), 'github_etag_cache'),
      ),
    );
