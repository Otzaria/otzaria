import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';

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

    final ranked = <_RankedBiography>[];
    for (final bio in entries) {
      final names = _normalizedNames[bio] ??= [
        _normalize(bio.name),
        for (final alias in bio.knownAs) _normalize(alias),
      ];
      // A match on the name ranks before an equal match on another name, but
      // an exact other name ("הרמב"ם") ranks before a partial match on a name.
      var rank = _matchRank(names.first, query, wholeWordPattern) * 2;
      for (var i = 1; i < names.length; i++) {
        final aliasRank = _matchRank(names[i], query, wholeWordPattern) * 2 + 1;
        if (aliasRank < rank) rank = aliasRank;
      }
      if (rank < _noMatch * 2) ranked.add(_RankedBiography(bio, rank));
    }

    ranked.sort((a, b) {
      final rankCompare = a.rank.compareTo(b.rank);
      if (rankCompare != 0) return rankCompare;
      return a.bio.name.compareTo(b.bio.name);
    });

    return ranked.map((r) => r.bio).toList();
  }

  static const int _noMatch = 4;

  /// The name and other names after [_normalize], kept between keystrokes.
  static final _normalizedNames = Expando<List<String>>();

  /// Lower is closer: exact < starts with < whole word < contains.
  static int _matchRank(String name, String query, RegExp wholeWordPattern) {
    if (name == query) return 0;
    if (name.startsWith(query)) return 1;
    // A whole-word match is also a contains match; most names have neither.
    if (!name.contains(query)) return _noMatch;
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
