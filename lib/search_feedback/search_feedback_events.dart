import 'dart:convert';
import 'dart:math';

import 'package:otzaria/search_feedback/search_feedback_api.dart';

/// מגבלות הפרוטוקול (v1) שנאכפות בצד הלקוח לפני הכנסה לתור.
abstract final class SearchFeedbackLimits {
  static const int query = 500;
  static const int title = 300;
  static const int reference = 300;
  static const int snippetText = 2000;
  static const int passageText = 20000;
  static const int matchedTextItems = 50;
  static const int matchedTextItemLength = 200;
  static const int resultsPerEvent = 100;
  static const int fallbackKind = 64;
  static const int maxFuzzyDistance = 10;
  static const int maxPageSize = 1000;
  static const int rankingKeys = 40;
  static const int eventsPerBatch = 100;
  static const int batchBytes = 512 * 1024;

  /// מרווח לעטיפת ה-batch (context, מזהים) מתוך [batchBytes].
  static const int batchEnvelopeReserve = 16 * 1024;

  /// אירוע בודד גדול מזה מכווץ (קטעי טקסט) כדי שייכנס ל-batch.
  static const int eventBytes = 256 * 1024;

  /// שדות חופשיים שאין להם מגבלה בפרוטוקול (מצבים, שמות מודל, פאסטות).
  static const int shortField = 64;
  static const int mediumField = 300;
  static const int facets = 50;
  static const Duration maxDwell = Duration(minutes: 30);
}

/// JSON שבו כל תו שאינו ASCII מקודד כ-`\uXXXX` — תקני, אך מסנני רשת
/// שסורקים את גוף הבקשה (נטפרי) אינם חוסמים בו טקסט תורני.
String searchFeedbackJsonEncode(Object? value) {
  final raw = jsonEncode(value);
  final out = StringBuffer();
  for (final unit in raw.codeUnits) {
    if (unit < 0x80) {
      out.writeCharCode(unit);
    } else {
      out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    }
  }
  return out.toString();
}

final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

/// האם [id] תקין לפי הפרוטוקול (batchId / eventId / searchSessionId / openId).
bool isValidSearchFeedbackId(String id) => _idPattern.hasMatch(id);

/// מזהה אקראי של 128 ביט ב-base64url בלי ריפוד (22 תווים).
String newSearchFeedbackId([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// חותמת זמן UTC בפורמט ISO עם אלפיות בדיוק (`...T10:00:00.000Z`).
String searchFeedbackIsoTime(DateTime time) {
  final utc = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = utc.millisecond.toString().padLeft(3, '0');
  final year = utc.year.toString().padLeft(4, '0');
  return '$year-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:'
      '${two(utc.minute)}:${two(utc.second)}.${ms}Z';
}

/// מקצר ל-[max] יחידות UTF-16 בלי לחתוך זוג surrogate באמצע.
String truncateForSearchFeedback(String value, int max) {
  if (value.length <= max) return value;
  var end = max;
  final last = value.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return value.substring(0, end);
}

String? _optional(String? value, int max) =>
    value == null ? null : truncateForSearchFeedback(value, max);

double? _finite(double? value) =>
    value == null || !value.isFinite ? null : value;

/// ערכי ה-enum שהשרת מקבל; ערך אחר פוסל את השדה ולא את כל האצווה.
abstract final class SearchFeedbackEnums {
  static const retrievalMode = {'hybrid', 'semanticOnly', 'lexicalOnly'};
  static const lexicalMode = {'exact', 'fuzzy'};
  static const grouping = {'sameSection', 'identicalText'};
  static const executedMode = {
    'disabled',
    'hybrid',
    'semanticOnly',
    'lexicalOnly',
  };
  static const source = {'lexical', 'semantic', 'both'};
  static const passageTextSource = {'line', 'snippet'};
}

final RegExp _rankingKeyPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$');
final RegExp _checksumPattern = RegExp(r'^[0-9a-f]{64}$');

/// תוצאה שאפשר לשלוח: לא מספר אישי, עם מקור מוכר ו-segment תקין.
bool _isSendable(SemanticResultSnapshot result) =>
    !result.isUserBook &&
    result.segment >= 0 &&
    SearchFeedbackEnums.source.contains(result.source);

/// בונה את גופי האירועים של הפרוטוקול מהתמונות שהממשק מוסר.
/// `null` = אין מה לשלוח (למשל תוצאה מספר אישי).
class SearchFeedbackEventBuilder {
  SearchFeedbackEventBuilder({required this.clock, required this.newId});

  final DateTime Function() clock;
  final String Function() newId;

  Map<String, Object?>? search(SemanticSearchContext context) {
    final query = truncateForSearchFeedback(
      context.query,
      SearchFeedbackLimits.query,
    );
    final params = context.params;
    final response = context.response;
    if (!SearchFeedbackEnums.retrievalMode.contains(params.retrievalMode) ||
        !SearchFeedbackEnums.lexicalMode.contains(params.lexicalMode) ||
        !SearchFeedbackEnums.executedMode.contains(response.executedMode)) {
      return null;
    }
    final grouping = params.grouping;
    return _event(context, 'search', {
      'query': query,
      'queryLength': query.length,
      'queryWordCount': query
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length,
      'params': {
        'retrievalMode': params.retrievalMode,
        'lexicalMode': params.lexicalMode,
        'fuzzyMaxDistance': params.fuzzyMaxDistance.clamp(
          0,
          SearchFeedbackLimits.maxFuzzyDistance,
        ),
        'grouping': SearchFeedbackEnums.grouping.contains(grouping)
            ? grouping
            : null,
        'matchNikud': params.matchNikud,
        'matchTaamim': params.matchTaamim,
        'scope': {
          'facets': [
            for (final facet in params.facets.take(SearchFeedbackLimits.facets))
              truncateForSearchFeedback(
                facet,
                SearchFeedbackLimits.mediumField,
              ),
          ],
          'allLibrary': params.allLibrary,
        },
        'pageSize': params.pageSize.clamp(1, SearchFeedbackLimits.maxPageSize),
        'ranking': sanitizeRanking(params.ranking),
      },
      'response': {
        'executedMode': response.executedMode,
        'semanticAvailable': response.semanticAvailable,
        'fallbackReason': _optional(
          response.fallbackReason,
          SearchFeedbackLimits.mediumField,
        ),
        'fallbackKind': _optional(
          response.fallbackKind,
          SearchFeedbackLimits.fallbackKind,
        ),
        'latencyMs': response.latencyMs,
        'totalCount': response.totalCount,
        'lexicalTotalCount': response.lexicalTotalCount,
        'groupCount': response.groupCount,
        'countsAreExact': response.countsAreExact,
        'truncated': response.truncated,
        'candidateWindowTruncated': response.candidateWindowTruncated,
      },
    });
  }

  /// דף שהוצג. דף שכל תוצאותיו מספרים אישיים אינו נשלח כלל.
  Map<String, Object?>? resultsShown(
    SemanticSearchContext context,
    int offset,
    List<SemanticResultSnapshot> results,
  ) {
    final allowed = results.where(_isSendable).toList();
    if (allowed.isEmpty && results.isNotEmpty) return null;
    final header = _header(context, 'results_shown');
    if (header == null) return null;
    final page = allowed.take(SearchFeedbackLimits.resultsPerEvent).toList();
    // דף מלא בקטעים ארוכים עלול לחרוג מה-batch — מקצרים קטעים עד שנכנס.
    for (
      var snippetMax = SearchFeedbackLimits.snippetText;
      snippetMax >= 50;
      snippetMax ~/= 2
    ) {
      final event = {
        ...header,
        'offset': max(0, offset),
        'results': [
          for (final result in page) resultRef(result, snippetMax: snippetMax),
        ],
      };
      if (searchFeedbackJsonEncode(event).length <=
          SearchFeedbackLimits.eventBytes) {
        return event;
      }
    }
    return null;
  }

  Map<String, Object?>? open(
    SemanticSearchContext context,
    SemanticResultSnapshot result,
    SearchFeedbackOpenVia via,
    String openId,
  ) {
    if (!_isSendable(result)) return null;
    return _event(context, 'open', {
      'openId': openId,
      'via': via.name,
      'result': resultFull(result),
    });
  }

  Map<String, Object?>? dwell(
    SemanticSearchContext context,
    String openId,
    Duration dwell,
    SearchFeedbackDwellEnd end,
  ) {
    if (!isValidSearchFeedbackId(openId)) return null;
    var reason = end;
    var ms = max(0, dwell.inMilliseconds);
    if (ms > SearchFeedbackLimits.maxDwell.inMilliseconds) {
      ms = SearchFeedbackLimits.maxDwell.inMilliseconds;
      reason = SearchFeedbackDwellEnd.capped;
    }
    return _event(context, 'dwell', {
      'openId': openId,
      'dwellMs': ms,
      'endReason': dwellEndWireName(reason),
    });
  }

  Map<String, Object?>? vote(
    SemanticSearchContext context,
    SemanticResultSnapshot result,
    SearchFeedbackVote vote,
  ) {
    if (!_isSendable(result)) return null;
    return _event(context, 'vote', {
      'vote': vote.name,
      'result': resultFull(result),
    });
  }

  /// ResultRef של הפרוטוקול.
  static Map<String, Object?> resultRef(
    SemanticResultSnapshot result, {
    int snippetMax = SearchFeedbackLimits.snippetText,
  }) => {
    'rank': result.rank,
    'title': truncateForSearchFeedback(
      result.title,
      SearchFeedbackLimits.title,
    ),
    'reference': truncateForSearchFeedback(
      result.reference,
      SearchFeedbackLimits.reference,
    ),
    'segment': result.segment,
    'isPdf': result.isPdf,
    'source': result.source,
    'lexicalScore': _finite(result.lexicalScore),
    'semanticScore': _finite(result.semanticScore),
    'fusedScore': _finite(result.fusedScore),
    'mergedCount': result.mergedCount,
    'snippetText': truncateForSearchFeedback(result.snippetText, snippetMax),
  };

  /// ResultFull: כשאין פסקה מלאה, הקטע המקוצר משמש כטקסט עם מקור `snippet`.
  static Map<String, Object?> resultFull(SemanticResultSnapshot result) {
    final passage = result.passageText;
    return {
      ...resultRef(result),
      'passageText': truncateForSearchFeedback(
        passage ?? result.snippetText,
        SearchFeedbackLimits.passageText,
      ),
      'passageTextSource': passage == null
          ? 'snippet'
          : SearchFeedbackEnums.passageTextSource.contains(
              result.passageTextSource,
            )
          ? result.passageTextSource
          : 'line',
      'matchedText': [
        for (final text in result.matchedText.take(
          SearchFeedbackLimits.matchedTextItems,
        ))
          truncateForSearchFeedback(
            text,
            SearchFeedbackLimits.matchedTextItemLength,
          ),
      ],
    };
  }

  /// מנקה את מפת הדירוג: עד 40 מפתחות תקינים, ערכים סקלריים או קינון אחד.
  /// מפתח שאינו תואם את תבנית הפרוטוקול מושמט.
  static Map<String, Object?>? sanitizeRanking(Map<String, Object?>? ranking) {
    if (ranking == null) return null;
    Object? scalar(Object? value) => switch (value) {
      null => null,
      bool() => value,
      int() => value,
      double() => _finite(value),
      String() => truncateForSearchFeedback(
        value,
        SearchFeedbackLimits.mediumField,
      ),
      _ => truncateForSearchFeedback(
        value.toString(),
        SearchFeedbackLimits.mediumField,
      ),
    };
    bool validKey(Object? key) =>
        key is String && _rankingKeyPattern.hasMatch(key);
    final result = <String, Object?>{};
    for (final entry
        in ranking.entries
            .where((e) => validKey(e.key))
            .take(SearchFeedbackLimits.rankingKeys)) {
      final value = entry.value;
      result[entry.key] = value is Map
          ? {
              for (final nested
                  in value.entries
                      .where((e) => validKey(e.key))
                      .take(SearchFeedbackLimits.rankingKeys))
                nested.key as String: scalar(nested.value),
            }
          : scalar(value);
    }
    return result;
  }

  static String dwellEndWireName(SearchFeedbackDwellEnd end) => switch (end) {
    SearchFeedbackDwellEnd.tabClosed => 'tab_closed',
    SearchFeedbackDwellEnd.tabSwitched => 'tab_switched',
    SearchFeedbackDwellEnd.returnedToResults => 'returned_to_results',
    SearchFeedbackDwellEnd.appExit => 'app_exit',
    SearchFeedbackDwellEnd.capped => 'capped',
  };

  Map<String, Object?>? _event(
    SemanticSearchContext context,
    String type,
    Map<String, Object?> payload,
  ) {
    final header = _header(context, type);
    return header == null ? null : {...header, ...payload};
  }

  Map<String, Object?>? _header(SemanticSearchContext context, String type) {
    if (!isValidSearchFeedbackId(context.searchSessionId)) return null;
    final now = clock();
    return {
      'eventId': newId(),
      'type': type,
      'clientTime': searchFeedbackIsoTime(now),
      'searchSessionId': context.searchSessionId,
      'msSinceSearch': max(0, now.difference(context.startedAt).inMilliseconds),
    };
  }
}

/// ה-engine של ClientContext לפי Amendment A.
Map<String, Object?> searchFeedbackEngineJson(SemanticEngineSnapshot engine) {
  String? field(String? value, int max) => _optional(value, max);
  return {
    'state': field(engine.state, SearchFeedbackLimits.shortField),
    'modelFamilyId': field(
      engine.modelFamilyId,
      SearchFeedbackLimits.mediumField,
    ),
    'modelQuantization': field(
      engine.modelQuantization,
      SearchFeedbackLimits.shortField,
    ),
    'modelPackageChecksum': _checksum(engine.modelPackageChecksum),
    'embeddingDim': (engine.embeddingDim ?? 0) >= 1
        ? engine.embeddingDim
        : null,
    'vectorsReleaseTag': field(
      engine.vectorsReleaseTag,
      SearchFeedbackLimits.mediumField,
    ),
    'vectorsLibraryVersion': engine.vectorsLibraryVersion,
    'vectorSegments': engine.vectorSegments,
  };
}

/// SHA-256 בהקס קטן (64 תווים); כל ערך אחר נשלח כ-null.
String? _checksum(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized != null && _checksumPattern.hasMatch(normalized)
      ? normalized
      : null;
}

/// גרסת מערכת ההפעלה כמספר בלבד — לעולם לא שם מחשב/משתמש.
/// כשאין מספר גרסה מזוהה מוחזר `unknown`.
String coarseOsVersion(String raw) {
  final version = RegExp(r'\d+(?:\.\d+)+').firstMatch(raw)?.group(0);
  if (version == null) return 'unknown';
  final build = RegExp(r'Build (\d+)').firstMatch(raw)?.group(1);
  final result = build != null && version.split('.').length == 2
      ? '$version.$build'
      : version;
  return truncateForSearchFeedback(result, 32);
}
