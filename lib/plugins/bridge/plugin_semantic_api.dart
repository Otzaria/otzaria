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

  /// ממיר את הספרים שהסט מכסה לזהויות של ה-SDK. ספר שהאינדקס מכיר והקטלוג
  /// לא (אינדקס שאינו מסונכרן) נספר ב-`unmatched`.
  static Map<String, dynamic> coveredBooksToJson(
    engine.SemanticCoveredBooks covered,
    Map<String, Book> booksByPath,
  ) {
    var unmatched = 0;
    final books = <Map<String, dynamic>>[];
    for (final path in covered.filePaths) {
      final book = booksByPath[path];
      if (book == null) {
        unmatched++;
        continue;
      }
      books.add({
        ...PluginBookIdentity.toJsonWithUid(book),
        'title': book.title,
      });
    }
    return {
      'books': books,
      'unmatched': unmatched,
      'setKey': covered.setKey,
      'generation': covered.generation.toInt(),
      'vectorsLibraryVersion': covered.vectorsLibraryVersion,
    };
  }

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
    return Float32List.fromList([
      for (var offset = 0; offset < bytes.length; offset += 4)
        data.getFloat32(offset, Endian.little),
    ]);
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
  }) {
    _rejectUnknownKeys(args, _nearestKeys);
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

    return engine.SemanticNearestInput(
      points: points,
      topK: k,
      facets: PluginSearchApi.resolveFacets(args, findBook: findBook),
      exclude: _exclude(args['exclude'], findBook),
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
  static Map<String, dynamic> hitToJson(
    engine.SemanticNearestHit hit,
    Map<String, Book> booksByPath, {
    required bool rescored,
  }) {
    final book = BookIdentity.bookForIndexedDocument(
      booksByPath,
      indexedFilePath: hit.filePath,
      indexedTitle: hit.title,
    );
    return {
      if (book != null)
        ...PluginBookIdentity.toJsonWithUid(book)
      else ...{
        'id': null,
        'type': hit.isPdf ? 'pdf' : 'text',
        'bookId': hit.title,
        'source': null,
      },
      'book': hit.title,
      if (book != null) 'categoryPath': FacetHelper.resolveCategoryPath(book),
      'reference': hit.reference,
      'index': hit.segment.toInt(),
      'window': hit.matchedWindow,
      'score': hit.score.isFinite ? hit.score : null,
      'point': hit.point,
      if (rescored)
        'pointScores': [
          for (final score in hit.pointScores) score.isNaN ? null : score,
        ],
    };
  }

  /// ה-chunks של תשובה: השורות בקבוצות, ואחריהן `done`. עד [maxHits] שורות
  /// בכל הרשימות יחד; מה שמעבר נחתך ומסומן ב-`clipped`.
  static List<Map<String, dynamic>> responseChunks(
    engine.SemanticNearestResponse response,
    Map<String, Book> booksByPath, {
    required bool rescored,
  }) {
    final chunks = <Map<String, dynamic>>[];
    var left = maxHits;
    var clipped = false;
    void addList(List<engine.SemanticNearestHit> hits, int? point) {
      final kept = hits.length > left ? hits.sublist(0, left) : hits;
      if (kept.length < hits.length) clipped = true;
      left -= kept.length;
      // גם רשימה ריקה נשלחת, כדי שלכל נקודה תהיה רשימה.
      var start = 0;
      do {
        final end = math.min(start + hitsPerChunk, kept.length);
        chunks.add({
          'type': 'hits',
          'point': ?point,
          'hits': [
            for (final hit in kept.sublist(start, end))
              hitToJson(hit, booksByPath, rescored: rescored),
          ],
        });
        start = end;
      } while (start < kept.length);
    }

    if (response.perPoint.isEmpty) {
      addList(response.hits, null);
    } else {
      for (var i = 0; i < response.perPoint.length; i++) {
        addList(response.perPoint[i].hits, i);
      }
    }
    chunks.add({
      'type': 'done',
      'generation': response.generation.toInt(),
      'vectorsLibraryVersion': response.vectorsLibraryVersion,
      'unresolved': response.unresolved,
      'staleDropped': response.staleDropped,
      'truncated': response.truncated,
      'clipped': clipped,
      'timingMs': {
        'embed': response.embedMs.toInt(),
        'scan': response.scanMs.toInt(),
        'resolve': response.resolveMs.toInt(),
        'rescore': response.rescoreMs.toInt(),
      },
    });
    return chunks;
  }
}
