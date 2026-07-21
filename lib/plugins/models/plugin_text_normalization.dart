import 'package:characters/characters.dart';

enum PluginNormalizationProfile {
  strict,
  display,
  search,
  lenient;

  static PluginNormalizationProfile parse(Object? value) {
    return switch (value) {
      null || 'strict' => strict,
      'display' => display,
      'search' => search,
      'lenient' => lenient,
      _ => throw const FormatException('unsupported normalization profile'),
    };
  }
}

class PluginNormalizeOptions {
  final PluginNormalizationProfile profile;
  final bool ignoreNikud;
  final bool ignoreTeamim;
  final bool ignorePunctuation;
  final bool normalizeWhitespace;
  final bool normalizeFinalLetters;

  const PluginNormalizeOptions({
    required this.profile,
    required this.ignoreNikud,
    required this.ignoreTeamim,
    required this.ignorePunctuation,
    required this.normalizeWhitespace,
    required this.normalizeFinalLetters,
  });

  factory PluginNormalizeOptions.forProfile(
    PluginNormalizationProfile profile, {
    bool displayIgnoreNikud = false,
    bool displayIgnoreTeamim = false,
    Map<String, dynamic> overrides = const {},
  }) {
    final defaults = switch (profile) {
      PluginNormalizationProfile.strict => const (
        ignoreNikud: false,
        ignoreTeamim: false,
        ignorePunctuation: false,
        normalizeWhitespace: false,
        normalizeFinalLetters: false,
      ),
      PluginNormalizationProfile.display => (
        ignoreNikud: displayIgnoreNikud,
        ignoreTeamim: displayIgnoreTeamim,
        ignorePunctuation: false,
        normalizeWhitespace: true,
        normalizeFinalLetters: false,
      ),
      PluginNormalizationProfile.search => const (
        ignoreNikud: true,
        ignoreTeamim: true,
        ignorePunctuation: false,
        normalizeWhitespace: true,
        normalizeFinalLetters: false,
      ),
      PluginNormalizationProfile.lenient => const (
        ignoreNikud: true,
        ignoreTeamim: true,
        ignorePunctuation: true,
        normalizeWhitespace: true,
        normalizeFinalLetters: true,
      ),
    };
    bool resolve(String key, bool fallback) {
      final value = overrides[key];
      if (value == null) return fallback;
      if (value is! bool) throw FormatException('$key must be a boolean');
      return value;
    }

    return PluginNormalizeOptions(
      profile: profile,
      ignoreNikud: resolve('ignoreNikud', defaults.ignoreNikud),
      ignoreTeamim: resolve('ignoreTeamim', defaults.ignoreTeamim),
      ignorePunctuation: resolve(
        'ignorePunctuation',
        defaults.ignorePunctuation,
      ),
      normalizeWhitespace: resolve(
        'normalizeWhitespace',
        defaults.normalizeWhitespace,
      ),
      normalizeFinalLetters: resolve(
        'normalizeFinalLetters',
        defaults.normalizeFinalLetters,
      ),
    );
  }
}

class PluginNormalizedText {
  final String text;
  final List<int> sourceBoundaryByNormalizedGrapheme;

  /// sourceEnd של כל grapheme מנורמל — נפרד מגבולות ההתחלה, כי גרפמות
  /// שהוסרו בין שכנים יוצרות פער (end של הקודם ≠ start של הבא).
  final List<int> sourceEndByNormalizedGrapheme;

  const PluginNormalizedText({
    required this.text,
    required this.sourceBoundaryByNormalizedGrapheme,
    required this.sourceEndByNormalizedGrapheme,
  });

  /// גבול הסיום במקור של טווח מנורמל שמסתיים ב-[normalizedEnd] (בלעדי).
  /// בשונה מ-[sourceBoundary], אינו בולע תווים שהוסרו אחרי הטווח.
  int sourceEndBoundary(int normalizedEnd) {
    if (normalizedEnd <= 0) return sourceBoundary(0);
    return sourceEndByNormalizedGrapheme[normalizedEnd - 1];
  }

  int sourceBoundary(int normalizedGrapheme) {
    if (normalizedGrapheme < 0 ||
        normalizedGrapheme >= sourceBoundaryByNormalizedGrapheme.length) {
      throw RangeError.range(
        normalizedGrapheme,
        0,
        sourceBoundaryByNormalizedGrapheme.length - 1,
      );
    }
    return sourceBoundaryByNormalizedGrapheme[normalizedGrapheme];
  }
}

class PluginTextNormalizationService {
  const PluginTextNormalizationService();

  PluginNormalizedText normalize(
    String source,
    PluginNormalizeOptions options,
  ) {
    final output = <String>[];
    final boundaries = <int>[0];
    final ends = <int>[];
    final sourceGraphemes = source.characters.toList(growable: false);
    var pendingWhitespaceStart = -1;
    var pendingWhitespaceEnd = -1;

    void append(String value, int sourceStart, int sourceEnd) {
      for (final grapheme in value.characters) {
        output.add(grapheme);
        boundaries
          ..[boundaries.length - 1] = sourceStart
          ..add(sourceEnd);
        ends.add(sourceEnd);
      }
    }

    void flushWhitespace() {
      if (pendingWhitespaceStart < 0 || output.isEmpty) {
        pendingWhitespaceStart = -1;
        pendingWhitespaceEnd = -1;
        return;
      }
      append(' ', pendingWhitespaceStart, pendingWhitespaceEnd);
      pendingWhitespaceStart = -1;
      pendingWhitespaceEnd = -1;
    }

    for (var index = 0; index < sourceGraphemes.length; index++) {
      final transformed = _transform(sourceGraphemes[index], options);
      if (transformed.isEmpty) continue;
      if (options.normalizeWhitespace && _isWhitespace(transformed)) {
        pendingWhitespaceStart = pendingWhitespaceStart < 0
            ? index
            : pendingWhitespaceStart;
        pendingWhitespaceEnd = index + 1;
        continue;
      }
      flushWhitespace();
      append(transformed, index, index + 1);
    }

    return PluginNormalizedText(
      text: output.join(),
      sourceBoundaryByNormalizedGrapheme: List.unmodifiable(boundaries),
      sourceEndByNormalizedGrapheme: List.unmodifiable(ends),
    );
  }

  String _transform(String grapheme, PluginNormalizeOptions options) {
    if (options.normalizeWhitespace && _isWhitespace(grapheme)) return ' ';
    final buffer = StringBuffer();
    for (final rune in grapheme.runes) {
      if (options.ignoreTeamim && _isTeamim(rune)) continue;
      if (options.ignoreNikud && _isNikud(rune)) continue;
      if (options.ignorePunctuation && _isPunctuation(rune)) continue;
      buffer.writeCharCode(
        options.normalizeFinalLetters ? _normalizeFinalLetter(rune) : rune,
      );
    }
    return buffer.toString();
  }

  bool _isWhitespace(String value) =>
      value.runes.every((rune) => _whitespaceRunes.contains(rune));

  bool _isTeamim(int rune) => rune >= 0x0591 && rune <= 0x05AF;

  bool _isNikud(int rune) =>
      (rune >= 0x05B0 && rune <= 0x05BD) ||
      rune == 0x05BF ||
      rune == 0x05C1 ||
      rune == 0x05C2 ||
      rune == 0x05C4 ||
      rune == 0x05C5 ||
      rune == 0x05C7;

  bool _isPunctuation(int rune) =>
      (rune >= 0x21 && rune <= 0x2F) ||
      (rune >= 0x3A && rune <= 0x40) ||
      (rune >= 0x5B && rune <= 0x60) ||
      (rune >= 0x7B && rune <= 0x7E) ||
      rune == 0x05BE ||
      rune == 0x05C0 ||
      rune == 0x05C3 ||
      rune == 0x05C6 ||
      rune == 0x05F3 ||
      rune == 0x05F4 ||
      (rune >= 0x2000 && rune <= 0x206F);

  int _normalizeFinalLetter(int rune) => switch (rune) {
    0x05DA => 0x05DB,
    0x05DD => 0x05DE,
    0x05DF => 0x05E0,
    0x05E3 => 0x05E4,
    0x05E5 => 0x05E6,
    _ => rune,
  };
}

const _whitespaceRunes = {
  0x0009,
  0x000A,
  0x000B,
  0x000C,
  0x000D,
  0x0020,
  0x0085,
  0x00A0,
  0x1680,
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200A,
  0x2028,
  0x2029,
  0x202F,
  0x205F,
  0x3000,
};
