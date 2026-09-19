import 'package:http/http.dart' as http;

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
class GithubRateLimitAwareClient extends http.BaseClient {
  final http.Client _inner;

  GithubRateLimitAwareClient([http.Client? inner])
    : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final exception = rateLimitExceptionFor(
      response.statusCode,
      response.headers,
    );
    if (exception == null) return response;
    await response.stream.drain<void>();
    throw exception;
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
