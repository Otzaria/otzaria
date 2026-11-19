import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/tools/biographies/data/author_biography_links.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:path/path.dart' as p;

/// Data layer of the biographies tool.
///
/// The bundle comes from the copy the library update downloaded to the data
/// root, or else from the copy packed into the app at build time, so it works
/// offline right after installation. A downloaded copy that cannot be read
/// (corrupt, or a newer format) falls back to the packed one.
class BiographiesRepository {
  /// Like `DictionaryLookupRepository`: a singleton used by the screens, with
  /// a constructor for injecting other sources in tests.
  static final BiographiesRepository instance = BiographiesRepository();

  static const String bundledAssetKey = 'assets/bio/biographies-app.json.gz';

  final Future<String> Function() _updatedPathProvider;
  final Future<ByteData> Function(String key) _loadAsset;

  Future<BiographiesBundle>? _loading;
  Future<Map<String, String>>? _bundledAuthorLinks;

  BiographiesRepository({
    Future<String> Function()? updatedPathProvider,
    Future<ByteData> Function(String key)? loadAsset,
  }) : _updatedPathProvider =
           updatedPathProvider ?? AppPaths.getBiographiesPath,
       _loadAsset = loadAsset ?? rootBundle.load;

  /// Loads the bundle once; repeated (also concurrent) calls share the Future.
  ///
  /// Throws [StateError] when no source has a readable bundle.
  Future<BiographiesBundle> loadBundle() => _loading ??= _load();

  /// All entries, in the bundle's order (by era, then by year).
  Future<List<Biography>> loadAll() async => (await loadBundle()).entries;

  /// Resolves only explicitly mapped names from the official catalog.
  /// A mapping to an entry missing from the installed bundle is ignored.
  Future<Map<String, Biography>> forCatalogAuthors(
    Iterable<String> names,
  ) async {
    final links = await _loadAuthorLinks();
    final ids = {
      for (final name in names)
        if (links[name] case final String id) name: id,
    };
    if (ids.isEmpty) return const {};
    final requestedIds = ids.values.toSet();
    final entries = {
      for (final entry in (await loadBundle()).entries)
        if (requestedIds.contains(entry.id)) entry.id: entry,
    };
    return {
      for (final item in ids.entries)
        if (entries[item.value] case final Biography entry) item.key: entry,
    };
  }

  Future<Map<String, String>> _loadAuthorLinks() async {
    try {
      final path = await _updatedPathProvider();
      final file = File(p.join(p.dirname(path), AuthorBiographyLinks.fileName));
      if (await file.exists()) {
        return AuthorBiographyLinks.decode(await file.readAsString());
      }
    } catch (e) {
      debugPrint('[Biographies] downloaded author mapping unreadable: $e');
    }
    return _bundledAuthorLinks ??= _loadBundledAuthorLinks();
  }

  Future<Map<String, String>> _loadBundledAuthorLinks() async {
    try {
      final data = await _loadAsset(AuthorBiographyLinks.assetKey);
      return AuthorBiographyLinks.decode(
        utf8.decode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    } catch (_) {
      return const {};
    }
  }

  Future<BiographiesBundle> _load() async {
    try {
      final updated = File(await _updatedPathProvider());
      if (await updated.exists()) {
        try {
          return await compute(
            BiographiesCodec.decode,
            await updated.readAsBytes(),
          );
        } catch (e) {
          debugPrint('[Biographies] downloaded bundle unreadable: $e');
        }
      }
      final ByteData data;
      try {
        data = await _loadAsset(bundledAssetKey);
      } catch (_) {
        throw StateError('נתוני הביוגרפיות אינם זמינים');
      }
      return await compute(
        BiographiesCodec.decode,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      // A failure is not cached: the next attempt retries (for example after
      // the update downloaded the file).
      _loading = null;
      rethrow;
    }
  }

  /// Filters and ranks entries by name or by another name they are known by.
  /// Shared by the screen and the plugin API, so both return the same order.
  static List<Biography> filter(List<Biography> entries, String query) {
    query = _normalize(query.trim());
    if (query.isEmpty) return entries;

    // Built once per call, not in every comparison of the sort.
    final wholeWordPattern = RegExp('(^|\\s)${RegExp.escape(query)}(\$|\\s)');
    final titleVariant = _cohenVariantPhrase(query);

    final ranked = <_RankedBiography>[];
    final variants = <_RankedBiography>[];
    for (final bio in entries) {
      final names = _normalizedNames[bio] ??= [
        _normalize(bio.name),
        for (final alias in bio.knownAs) _normalize(alias),
      ];
      // A match on the name ranks before an equal match on another name, but
      // an exact other name ("הרמב"ם") ranks before a partial match on a name.
      var rank =
          _matchRank(names.first, query, wholeWordPattern, titleVariant) * 2;
      for (var i = 1; i < names.length; i++) {
        final aliasRank =
            _matchRank(names[i], query, wholeWordPattern, titleVariant) * 2 + 1;
        if (aliasRank < rank) rank = aliasRank;
      }
      if (rank < _titleVariantRank * 2) {
        ranked.add(_RankedBiography(bio, rank));
      } else if (rank < _noMatch * 2) {
        variants.add(_RankedBiography(bio, rank));
      }
    }

    int compare(_RankedBiography a, _RankedBiography b) {
      final rankCompare = a.rank.compareTo(b.rank);
      if (rankCompare != 0) return rankCompare;
      return a.bio.name.compareTo(b.bio.name);
    }

    // List.sort is unstable for ties. Keep the original matches sorted alone.
    ranked.sort(compare);
    variants.sort(compare);
    return [for (final r in ranked) r.bio, for (final r in variants) r.bio];
  }

  static const int _titleVariantRank = 4;
  static const int _noMatch = 5;

  /// The name and other names after [_normalize], kept between keystrokes.
  static final _normalizedNames = Expando<List<String>>();

  static const _wordSeparator = r'''[^\p{L}\p{M}\p{N}"']''';
  static final _wordSeparators = RegExp('$_wordSeparator+', unicode: true);

  // An explicit הכהן in the query remains specific to that spelling.
  static RegExp? _cohenVariantPhrase(String query) {
    if (!query.contains('כהן')) return null;
    final words = query.split(_wordSeparators).where((word) => word.isNotEmpty);
    if (words.length < 2 || !words.contains('כהן')) return null;
    final phrase = words
        .map((word) => word == 'כהן' ? 'ה?כהן' : RegExp.escape(word))
        .join('$_wordSeparator+');
    return RegExp(
      '(?:^|$_wordSeparator)$phrase(?:\$|$_wordSeparator)',
      unicode: true,
    );
  }

  /// Lower is closer: exact < starts with < whole word < contains < alternate title.
  static int _matchRank(
    String name,
    String query,
    RegExp wholeWordPattern,
    RegExp? titleVariant,
  ) {
    if (name == query) return 0;
    if (name.startsWith(query)) return 1;
    // A whole-word match is also a contains match; most names have neither.
    if (!name.contains(query)) {
      if (titleVariant != null &&
          name.contains('כהן') &&
          titleVariant.hasMatch(name)) {
        return _titleVariantRank;
      }
      return _noMatch;
    }
    return wholeWordPattern.hasMatch(name) ? 2 : 3;
  }

  /// Hebrew geresh and gershayim match their ASCII look-alikes.
  static String _normalize(String text) =>
      text.replaceAll('״', '"').replaceAll('׳', "'");
}

/// An entry with its match rank, computed once before sorting.
class _RankedBiography {
  final Biography bio;
  final int rank;

  const _RankedBiography(this.bio, this.rank);
}
