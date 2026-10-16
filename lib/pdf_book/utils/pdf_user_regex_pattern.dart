import 'package:otzaria/search/utils/user_regex_query.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// `/…/` as the [RegExp] pdfrx's text search requires (no other Pattern);
/// matching is the engine's [UserRegexMatcher] over the page's text layer.
// ignore: deprecated_implement
class PdfUserRegexPattern implements RegExp {
  PdfUserRegexPattern._(this.pattern, this._matcher);

  /// The pattern for [query], or null when it is not a valid `/…/`.
  static PdfUserRegexPattern? tryParse(String query) {
    final raw = query.trim();
    final matcher = UserRegexQuery.matcher(_asPlainPattern(raw));
    return matcher == null ? null : PdfUserRegexPattern._(raw, matcher);
  }

  final UserRegexMatcher _matcher;

  /// The query as typed, which also tells pdfrx whether a search repeats.
  @override
  final String pattern;

  @override
  bool get isCaseSensitive => false;

  @override
  bool get isMultiLine => false;

  @override
  bool get isUnicode => true;

  @override
  bool get isDotAll => false;

  /// The matcher reads HTML; a page's text is plain, so its markup characters
  /// become others of the same length and keep every offset.
  static String _asPlainText(String text) =>
      text.replaceAll('<', '‹').replaceAll('&', '＆');

  /// [_asPlainText] for literal `<`/`&` only: `\<`, `(?<name>`, `(?P<name>`
  /// and `&&` inside a class keep their regex meaning.
  static String _asPlainPattern(String raw) {
    final out = StringBuffer();
    var classDepth = 0;
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      final next = i + 1 < raw.length ? raw[i + 1] : '';
      if (c == '\\') {
        out.write(next == '&' ? _asPlainText(next) : '$c$next');
        i++;
      } else if (c == '&' && next == '&' && classDepth > 0) {
        out.write('&&');
        i++;
      } else if (c == '<' && RegExp(r'\(\?P?$').hasMatch(raw.substring(0, i))) {
        out.write(c);
      } else {
        if (c == '[') classDepth++;
        if (c == ']' && classDepth > 0) classDepth--;
        out.write(_asPlainText(c));
      }
    }
    return out.toString();
  }

  @override
  Iterable<RegExpMatch> allMatches(String input, [int start = 0]) {
    if (start < 0 || start > input.length) {
      throw RangeError.range(start, 0, input.length);
    }
    final text = _asPlainText(input.substring(start));
    return [
      for (final match in _matcher.findMatches(data: text))
        if (match.end > match.start)
          _PdfUserRegexMatch(
            this,
            input,
            start + match.start,
            start + match.end,
          ),
    ];
  }

  @override
  RegExpMatch? firstMatch(String input) {
    final matches = allMatches(input);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  bool hasMatch(String input) => firstMatch(input) != null;

  @override
  String? stringMatch(String input) => firstMatch(input)?.group(0);

  @override
  Match? matchAsPrefix(String string, [int start = 0]) {
    for (final match in allMatches(string, start)) {
      if (match.start == start) return match;
      if (match.start > start) break;
    }
    return null;
  }
}

// ignore: deprecated_implement
class _PdfUserRegexMatch implements RegExpMatch {
  _PdfUserRegexMatch(this.pattern, this.input, this.start, this.end);

  @override
  final PdfUserRegexPattern pattern;

  @override
  final String input;

  @override
  final int start;

  @override
  final int end;

  @override
  int get groupCount => 0;

  @override
  String? group(int group) {
    if (group != 0) throw RangeError.range(group, 0, 0);
    return input.substring(start, end);
  }

  @override
  String? operator [](int group) => this.group(group);

  @override
  List<String?> groups(List<int> groupIndices) => [
    for (final index in groupIndices) group(index),
  ];

  @override
  Iterable<String> get groupNames => const [];

  @override
  String? namedGroup(String name) =>
      throw ArgumentError.value(name, 'name', 'Not a capture group name');
}
