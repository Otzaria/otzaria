import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria/search_feedback/search_feedback_identity.dart';

/// מה לעשות עם אצווה אחרי תשובת השרת (טבלת השגיאות של הפרוטוקול).
enum SearchFeedbackOutcomeKind {
  /// התקבלה — למחוק.
  accepted,

  /// פגומה לצמיתות — לוותר עליה.
  drop,

  /// המפתח אינו מוכר — לרשום מחדש ולנסות פעם אחת.
  unknownKey,

  /// המפתח נחסם — לעצור, לרוקן את התור ולהפסיק לאסוף.
  keyBlocked,

  /// גדולה מדי — לפצל.
  tooLarge,

  /// תקלה זמנית — לנסות מאוחר יותר.
  retryLater,
}

/// תוצאת בקשה אחת לשרת.
/// סוג כשל שנספר לאורך ניסיונות, כדי שאצווה תקועה לא תחסום את התור לנצח.
enum SearchFeedbackStrike {
  /// אין מה לספור (הצלחה, שגיאת רשת, שבת/השבתה, הגבלת קצב).
  none,

  /// 5xx מהשרת שאינו שבת/השבתה.
  serverError,

  /// 4xx בלי קוד פרוטוקול — כנראה דף חסימה של מסנן.
  filtered,
}

class SearchFeedbackOutcome {
  const SearchFeedbackOutcome(
    this.kind, {
    this.retryAfter,
    this.keyId,
    this.strike = SearchFeedbackStrike.none,
    this.rejected = 0,
  });

  final SearchFeedbackOutcomeKind kind;

  /// ערך Retry-After מהשרת, אם נשלח.
  final Duration? retryAfter;

  /// ה-keyId שהשרת החזיר ברישום.
  final String? keyId;

  final SearchFeedbackStrike strike;

  /// אירועים שהשרת דילג עליהם בתוך אצווה שהתקבלה (Amendment B).
  final int rejected;

  static const SearchFeedbackOutcome network = SearchFeedbackOutcome(
    SearchFeedbackOutcomeKind.retryLater,
  );
}

/// לקוח HTTP של ערוץ המשוב: חתימה, כותרות וסיווג התשובות.
class SearchFeedbackSender {
  SearchFeedbackSender({
    required this._client,
    required this._baseUrl,
    required this._clock,
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client Function() _client;
  final Uri _baseUrl;
  final DateTime Function() _clock;
  final Duration timeout;

  Future<SearchFeedbackOutcome> register({
    required SearchFeedbackIdentity identity,
    required String body,
    required String appVersion,
  }) => _post(
    '/api/search-feedback/register',
    identity: identity,
    body: body,
    appVersion: appVersion,
    includeKeyId: false,
  );

  Future<SearchFeedbackOutcome> sendEvents({
    required SearchFeedbackIdentity identity,
    required String body,
    required String appVersion,
  }) => _post(
    '/api/search-feedback/events',
    identity: identity,
    body: body,
    appVersion: appVersion,
    includeKeyId: true,
  );

  Future<SearchFeedbackOutcome> _post(
    String path, {
    required SearchFeedbackIdentity identity,
    required String body,
    required String appVersion,
    required bool includeKeyId,
  }) async {
    final bytes = utf8.encode(body);
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'X-Otzaria-Signature': identity.sign(bytes),
      if (includeKeyId) 'X-Otzaria-Key-Id': identity.keyId,
      'User-Agent': 'otzaria-search-feedback/$appVersion',
    };
    try {
      final response = await _client()
          .post(_baseUrl.resolve(path), headers: headers, body: bytes)
          .timeout(timeout);
      return classify(
        response.statusCode,
        response.body,
        response.headers,
        now: _clock(),
      );
    } on TimeoutException {
      return SearchFeedbackOutcome.network;
    } on SocketException {
      return SearchFeedbackOutcome.network;
    } on http.ClientException {
      return SearchFeedbackOutcome.network;
    } on HandshakeException {
      return SearchFeedbackOutcome.network;
    }
  }

  /// מסווג תשובה: קודם לפי קוד ה-`error` בגוף, ורק אחר כך לפי הסטטוס.
  static SearchFeedbackOutcome classify(
    int status,
    String body,
    Map<String, String> headers, {
    required DateTime now,
  }) {
    final json = _tryDecode(body);
    final error = json?['error'];
    final retryAfter = parseRetryAfter(headers['retry-after'], now: now);
    final byCode = switch (error) {
      'invalid_json' ||
      'bad_signature' ||
      'invalid_payload' => SearchFeedbackOutcomeKind.drop,
      'unknown_key' => SearchFeedbackOutcomeKind.unknownKey,
      'key_blocked' => SearchFeedbackOutcomeKind.keyBlocked,
      'too_large' => SearchFeedbackOutcomeKind.tooLarge,
      'rate_limited' ||
      'shabbat' ||
      'disabled' => SearchFeedbackOutcomeKind.retryLater,
      _ => null,
    };
    final expected = error == 'shabbat' || error == 'disabled';
    final strike = status >= 500 && !expected
        ? SearchFeedbackStrike.serverError
        : SearchFeedbackStrike.none;
    if (byCode != null) {
      return SearchFeedbackOutcome(
        byCode,
        retryAfter: retryAfter,
        strike: strike,
      );
    }
    if (status >= 200 && status < 300) {
      final keyId = json?['keyId'];
      final rejected = json?['rejected'];
      return SearchFeedbackOutcome(
        SearchFeedbackOutcomeKind.accepted,
        keyId: keyId is String ? keyId : null,
        rejected: rejected is int ? rejected : 0,
      );
    }
    final kind = switch (status) {
      400 || 401 || 422 => SearchFeedbackOutcomeKind.drop,
      413 => SearchFeedbackOutcomeKind.tooLarge,
      _ => SearchFeedbackOutcomeKind.retryLater,
    };
    final filtered =
        error is! String &&
        kind == SearchFeedbackOutcomeKind.retryLater &&
        status >= 400 &&
        status < 500 &&
        status != 408 &&
        status != 429;
    // 403 בלי קוד אינו חסימת מפתח — מסנני רשת מחזירים 403/418 משלהם.
    return SearchFeedbackOutcome(
      kind,
      retryAfter: retryAfter,
      strike: filtered ? SearchFeedbackStrike.filtered : strike,
    );
  }

  static Map<String, Object?>? _tryDecode(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// Retry-After בשניות או כתאריך HTTP.
  static Duration? parseRetryAfter(String? value, {required DateTime now}) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return seconds < 0 ? null : Duration(seconds: seconds);
    try {
      final at = HttpDate.parse(value.trim());
      final diff = at.difference(now);
      return diff.isNegative ? Duration.zero : diff;
    } on FormatException {
      return null;
    } on HttpException {
      return null;
    }
  }
}
