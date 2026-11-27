import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/bridge/plugin_search_api.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

/// תרגום פרמטרי `semantic.*` של ה-Plugin SDK לטיפוסי המנוע, והתשובות חזרה
/// ל-JSON. הטקסט של השורות אינו בתשובות: תוסף קורא אותו בהרשאת התוכן שלו.
class PluginSemanticApi {
  PluginSemanticApi._();

  /// כמו במנוע (`MAX_NEAREST_POINTS`, `MAX_NEAREST_TOP_K`,
  /// `MAX_NEAREST_CANDIDATES`, `MAX_QUERY_TOKEN_TEXTS`).
  static const int maxPoints = 64;
  static const int maxK = 2000;
  static const int maxCandidates = 5000;
  static const int maxTokenTexts = 5000;

  static const int defaultK = 50;
  static const int defaultMaxCandidates = 1000;

  /// תקרת השורות בתשובה אחת, בכל הרשימות יחד: כך גם 64 רשימות עוברות בגשר.
  static const int maxHits = 20000;
  static const int hitsPerChunk = 500;
  static const int maxExcludeSpans = 1000;
  static const int maxPointTextLength = 20000;
  static const int maxTokenTextsLength = 2000000;
  static const int maxScopeEntries = 128;

  static Map<String, dynamic> describeLimits() => {
    'maxPoints': maxPoints,
    'maxK': maxK,
    'defaultK': defaultK,
    'maxCandidates': maxCandidates,
    'defaultMaxCandidates': defaultMaxCandidates,
    'maxHits': maxHits,
    'maxExcludeSpans': maxExcludeSpans,
    'maxPointTextLength': maxPointTextLength,
    'maxTokenTexts': maxTokenTexts,
    'maxTokenTextsLength': maxTokenTextsLength,
    'maxScopeEntries': maxScopeEntries,
  };

  static Never _invalid(String detail) =>
      throw Exception('error.invalid_params: $detail');

  /// השלב כפי שתוסף רואה אותו: `ready` רק כשאפשר לחפש.
  static String phaseOf(SemanticAvailability availability) {
    if (availability.isUsable) return 'ready';
    if (!availability.consentGranted &&
        availability.phase != SemanticAvailabilityPhase.hidden) {
      return 'consentRequired';
    }
    return availability.phase.name;
  }

  static Map<String, dynamic> statusToJson(
    SemanticAvailability availability, {
    SemanticVectorsSummary? vectors,
    String? modelFamilyId,
    int? dim,
    String? vectorsReleaseTag,
  }) {
    final progress = availability.progress;
    final installed = vectors != null && vectors.present ? vectors : null;
    return {
      'phase': phaseOf(availability),
      if (availability.hiddenReason case final reason?)
        'hiddenReason': reason.name,
      if (availability.failure case final failure?)
        'failure': failure.kind.name,
      if (progress != null)
        'progress': {'item': progress.item.name, 'fraction': progress.fraction},
      'modelFamilyId': modelFamilyId,
      'dim': dim,
      'vectorsReleaseTag': vectorsReleaseTag,
      'vectorsLibraryVersion': installed?.libraryVersion,
      'generation': installed?.generation,
      'limits': describeLimits(),
    };
  }

  /// `semantic.countTokens({texts})`.
  static List<String> parseTokenTexts(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {'texts'});
    final raw = args['texts'];
    if (raw is! List || raw.any((text) => text is! String)) {
      _invalid('texts must be an array of strings');
    }
    if (raw.isEmpty || raw.length > maxTokenTexts) {
      _invalid('texts must hold 1 to $maxTokenTexts strings');
    }
    final texts = raw.cast<String>();
    if (texts.any((text) => text.length > maxPointTextLength)) {
      _invalid('each text must not exceed $maxPointTextLength characters');
    }
    final length = texts.fold<int>(0, (sum, text) => sum + text.length);
    if (length > maxTokenTextsLength) {
      _invalid('texts must not exceed $maxTokenTextsLength characters');
    }
    return texts;
  }

  static Map<String, dynamic> tokensToJson(engine.SemanticQueryTokens tokens) =>
      {
        'counts': tokens.counts.toList(),
        'queryMaxTokens': tokens.queryMaxTokens,
        'overheadTokens': tokens.overheadTokens,
      };

  /// מחזיר רק ספרים רשמיים שעדיין קיימים בקטלוג.
  static Map<String, dynamic> coveredBooksToJson(
    Set<String> paths,
    Map<String, Book> booksByPath,
  ) => {
    'books': [
      for (final path in paths)
        if (booksByPath[path] case final book?
            when book.hasOfficialSemanticIdentity)
          {...PluginBookIdentity.toJsonWithUid(book), 'title': book.title},
    ],
  };

  static void _rejectUnknownKeys(
    Map<String, dynamic> args,
    Set<String> allowed,
  ) {
    for (final key in args.keys) {
      if (!allowed.contains(key)) _invalid('unknown parameter "$key"');
    }
  }

  static int _intArg(
    Object? raw,
    String name, {
    required int fallback,
    required int min,
    required int max,
  }) {
    if (raw == null) return fallback;
    if (raw is! num || !raw.isFinite || raw != raw.truncate()) {
      _invalid('$name must be a whole number');
    }
    final value = raw.toInt();
    if (value < min || value > max) {
      _invalid('$name must be between $min and $max (got $value)');
    }
    return value;
  }

  static engine.SemanticPoint _point(Object? raw, int index) {
    if (raw is! Map) _invalid('from[$index] must be an object');
    final point = Map<String, dynamic>.from(raw);
    final text = point['text'];
    final vector = point['vector'];
    if ((text == null) == (vector == null)) {
      _invalid('from[$index] must have exactly one of text and vector');
    }
    if (text != null) {
      _rejectUnknownKeys(point, const {'text', 'as'});
      if (text is! String || text.trim().isEmpty) {
        _invalid('from[$index].text must be a non-empty string');
      }
      if (text.length > maxPointTextLength) {
        _invalid(
          'from[$index].text must not exceed $maxPointTextLength characters',
        );
      }
      final role = point['as'] ?? 'query';
      if (role != 'query' && role != 'passage') {
        _invalid('from[$index].as must be "query" or "passage"');
      }
      return engine.SemanticPoint(text: text, asPassage: role == 'passage');
    }
    _rejectUnknownKeys(point, const {'vector'});
    if (vector is! String) {
      _invalid('from[$index].vector must be a base64 string of float32 values');
    }
    return engine.SemanticPoint(
      asPassage: false,
      vector: decodeVector(vector, 'from[$index].vector'),
    );
  }

  /// base64 של float32 בסדר little-endian. הרוחב נבדק מול הסט במנוע.
  static Float32List decodeVector(String encoded, String name) {
    if (encoded.length > 22000) _invalid('$name is too long');
    final Uint8List bytes;
    try {
      bytes = base64.decode(encoded);
    } on FormatException {
      _invalid('$name is not valid base64');
    }
    if (bytes.isEmpty || bytes.length % 4 != 0) {
      _invalid('$name must hold whole float32 values');
    }
    final data = ByteData.sublistView(bytes);
    final vector = Float32List(bytes.length ~/ 4);
    for (var i = 0; i < vector.length; i++) {
      final value = data.getFloat32(i * 4, Endian.little);
      if (!value.isFinite) _invalid('$name must hold finite values');
      vector[i] = value;
    }
    return vector;
  }

  static const Set<String> _nearestKeys = {
    'from',
    'k',
    'minScore',
    'pool',
    'maxCandidates',
    'rescore',
    'exclude',
    // ההיקף, כמו ב-search.query.
    'facets',
    'categories',
    'books',
    'authors',
    'eras',
    'baseBooksOnly',
  };

  /// `semantic.nearest`. [findBook] מאתר ספר לפי זהות ה-SDK, כמו ב-`search.query`.
  static engine.SemanticNearestInput parseNearest(
    Map<String, dynamic> args, {
    required Book? Function(Map<String, dynamic> identity) findBook,
    required List<String> bookPaths,
  }) {
    _rejectUnknownKeys(args, _nearestKeys);
    for (final key in const [
      'facets',
      'categories',
      'books',
      'authors',
      'eras',
    ]) {
      if (args[key] case final List<dynamic> list
          when list.length > maxScopeEntries) {
        _invalid('$key must hold at most $maxScopeEntries entries');
      }
    }
    final rawPoints = args['from'];
    if (rawPoints is! List || rawPoints.isEmpty) {
      _invalid('from must be a non-empty array of points');
    }
    if (rawPoints.length > maxPoints) {
      _invalid('from must hold at most $maxPoints points');
    }
    final points = [
      for (var i = 0; i < rawPoints.length; i++) _point(rawPoints[i], i),
    ];

    final pool = switch (args['pool'] ?? 'best') {
      'best' => engine.SemanticPool.best,
      'perPoint' => engine.SemanticPool.perPoint,
      _ => _invalid('pool must be "best" or "perPoint"'),
    };
    final best = pool == engine.SemanticPool.best;
    final k = _intArg(args['k'], 'k', fallback: defaultK, min: 1, max: maxK);
    if (!best && points.length * k > maxHits) {
      _invalid('perPoint: points × k must not exceed $maxHits');
    }
    if (!best && args['maxCandidates'] != null) {
      _invalid('maxCandidates applies to pool "best" only');
    }
    final candidates = _intArg(
      args['maxCandidates'],
      'maxCandidates',
      fallback: defaultMaxCandidates,
      min: 1,
      max: maxCandidates,
    );
    final rescore = args['rescore'] ?? false;
    if (rescore is! bool) _invalid('rescore must be a boolean');
    if (rescore && !best) _invalid('rescore applies to pool "best" only');

    final rawMinScore = args['minScore'];
    if (rawMinScore != null && (rawMinScore is! num || !rawMinScore.isFinite)) {
      _invalid('minScore must be a finite number');
    }

    Book? findOfficialBook(Map<String, dynamic> identity) {
      final book = findBook(identity);
      return book?.hasOfficialSemanticIdentity == true ? book : null;
    }

    return engine.SemanticNearestInput(
      points: points,
      topK: k,
      facets: PluginSearchApi.resolveFacets(args, findBook: findOfficialBook),
      bookPaths: bookPaths,
      exclude: _exclude(args['exclude'], findOfficialBook),
      minScore: (rawMinScore as num?)?.toDouble(),
      pool: pool,
      maxCandidates: candidates,
      rescore: rescore,
    );
  }

  static List<engine.SemanticLineSpan> _exclude(
    Object? raw,
    Book? Function(Map<String, dynamic> identity) findBook,
  ) {
    if (raw == null) return const [];
    if (raw is! List) _invalid('exclude must be an array');
    if (raw.length > maxExcludeSpans) {
      _invalid('exclude must hold at most $maxExcludeSpans spans');
    }
    return [for (var i = 0; i < raw.length; i++) _span(raw[i], i, findBook)];
  }

  static engine.SemanticLineSpan _span(
    Object? raw,
    int index,
    Book? Function(Map<String, dynamic> identity) findBook,
  ) {
    if (raw is! Map) _invalid('exclude[$index] must be an object');
    final identity = Map<String, dynamic>.from(raw);
    final from = _intArg(
      identity.remove('from'),
      'exclude[$index].from',
      fallback: -1,
      min: 0,
      max: 0x7fffffff,
    );
    final to = _intArg(
      identity.remove('to'),
      'exclude[$index].to',
      fallback: -1,
      min: 0,
      max: 0x7fffffff,
    );
    if (from < 0 || to < 0) _invalid('exclude[$index] needs from and to');
    if (from > to) _invalid('exclude[$index].from must not exceed to');
    PluginSearchApi.validateBookIdentity(identity);
    final book = findBook(identity);
    if (book == null) {
      throw Exception(
        'error.not_found: book not found for exclude[$index] '
        '(${identity['bookId'] ?? identity['id'] ?? identity['bookUid']})',
      );
    }
    return engine.SemanticLineSpan(
      filePath: BookIdentity.indexedFilePath(book),
      fromSegment: BigInt.from(from),
      toSegment: BigInt.from(to),
    );
  }

  /// שורה שנמצאה, בזהות ספר של ה-SDK. ציון שאין לו וקטור (NaN) הוא `null`.
  static Map<String, dynamic>? hitToJson(
    engine.SemanticNearestHit hit,
    Map<String, Book> booksByPath, {
    required bool rescored,
  }) {
    final book = BookIdentity.validatedIndexedBook(
      booksByPath[hit.filePath],
      indexedTitle: hit.title,
    );
    if (book == null || !book.hasOfficialSemanticIdentity) return null;
    return {
      ...PluginBookIdentity.toJsonWithUid(book),
      'book': book.title,
      'categoryPath': FacetHelper.resolveCategoryPath(book),
      'reference': hit.reference,
      'index': hit.segment.toInt(),
      'window': hit.matchedWindow,
      'score': hit.score.isFinite ? hit.score : null,
      'point': hit.point,
      if (rescored)
        'pointScores': [
          for (final score in hit.pointScores) score.isFinite ? score : null,
        ],
    };
  }

  /// ה-chunks של תשובה: השורות בקבוצות, ואחריהן `done`. עד [maxHits] שורות
  /// בכל הרשימות יחד; מה שמעבר נחתך ומסומן ב-`clipped`.
  static Iterable<Map<String, dynamic>> responseChunks(
    engine.SemanticNearestResponse response,
    Map<String, Book> booksByPath, {
    required bool rescored,
  }) sync* {
    var left = maxHits;
    var clipped = false;
    Iterable<Map<String, dynamic>> chunksFor(
      List<engine.SemanticNearestHit> hits,
      int? point,
    ) sync* {
      final kept = <Map<String, dynamic>>[];
      for (final hit in hits) {
        final json = hitToJson(hit, booksByPath, rescored: rescored);
        if (json == null) continue;
        if (left == 0) {
          clipped = true;
          break;
        }
        kept.add(json);
        left--;
      }
      // גם רשימה ריקה נשלחת, כדי שלכל נקודה תהיה רשימה.
      var start = 0;
      do {
        final end = math.min(start + hitsPerChunk, kept.length);
        yield {
          'type': 'hits',
          'point': ?point,
          'hits': kept.sublist(start, end),
        };
        start = end;
      } while (start < kept.length);
    }

    if (response.perPoint.isEmpty) {
      yield* chunksFor(response.hits, null);
    } else {
      for (var i = 0; i < response.perPoint.length; i++) {
        yield* chunksFor(response.perPoint[i].hits, i);
      }
    }
    yield {
      'type': 'done',
      'generation': response.generation.toInt(),
      'vectorsLibraryVersion': response.vectorsLibraryVersion,
      'clipped': clipped,
    };
  }
}
