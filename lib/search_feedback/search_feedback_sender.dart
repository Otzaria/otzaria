import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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

/// סוג הכשל של ניסיון שליחה, לצורך השהיה או ויתור על אצווה.
enum SearchFeedbackStrike {
  /// אין מה לספור (הצלחה, שגיאת רשת, שבת/השבתה, הגבלת קצב).
  none,

  /// 5xx מהשרת שאינו שבת/השבתה.
  serverError,

  /// תשובה שאינה של הפרוטוקול (דף חסימה של ספק/מסנן) — משהים, לא מוותרים.
  filtered,
}

/// תוצאת בקשה אחת לשרת.
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
    bool Function()? canSend,
  }) => _post(
    '/api/search-feedback/register',
    identity: identity,
    body: body,
    appVersion: appVersion,
    canSend: canSend,
    includeKeyId: false,
  );

  Future<SearchFeedbackOutcome> sendEvents({
    required SearchFeedbackIdentity identity,
    required String body,
    required String appVersion,
    bool Function()? canSend,
  }) => _post(
    '/api/search-feedback/events',
    identity: identity,
    body: body,
    appVersion: appVersion,
    canSend: canSend,
    includeKeyId: true,
  );

  Future<SearchFeedbackOutcome> _post(
    String path, {
    required SearchFeedbackIdentity identity,
    required String body,
    required String appVersion,
    required bool includeKeyId,
    bool Function()? canSend,
  }) async {
    if (canSend != null && !canSend()) return SearchFeedbackOutcome.network;
    final signed = await _signBody(identity, body);
    if (canSend != null && !canSend()) return SearchFeedbackOutcome.network;
    final bytes = signed.bytes;
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'X-Otzaria-Signature': signed.signature,
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
    final isProtocolSuccess =
        json != null &&
        (json.containsKey('accepted') || json.containsKey('keyId'));
    if (status >= 200 && status < 300 && isProtocolSuccess) {
      final keyId = json['keyId'];
      final rejected = json['rejected'];
      return SearchFeedbackOutcome(
        SearchFeedbackOutcomeKind.accepted,
        keyId: keyId is String ? keyId : null,
        rejected: rejected is int ? rejected : 0,
      );
    }
    if (error is String) {
      return SearchFeedbackOutcome(
        switch (status) {
          400 || 401 || 422 => SearchFeedbackOutcomeKind.drop,
          413 => SearchFeedbackOutcomeKind.tooLarge,
          _ => SearchFeedbackOutcomeKind.retryLater,
        },
        retryAfter: retryAfter,
        strike: strike,
      );
    }
    if (status == 413) {
      return SearchFeedbackOutcome(
        SearchFeedbackOutcomeKind.tooLarge,
        retryAfter: retryAfter,
        strike: strike,
      );
    }
    // בלי קוד פרוטוקול (גם 200 של דף HTML): ספק או מסנן חוסם — אסור למחוק נתונים.
    final transient = status >= 500 || status == 408 || status == 429;
    return SearchFeedbackOutcome(
      SearchFeedbackOutcomeKind.retryLater,
      retryAfter: retryAfter,
      strike: transient ? strike : SearchFeedbackStrike.filtered,
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

Future<({List<int> bytes, String signature})> _signBody(
  SearchFeedbackIdentity identity,
  String body,
) => Isolate.run(() {
  final bytes = utf8.encode(body);
  return (bytes: bytes, signature: identity.sign(bytes));
});
