/// Utility class for processing Hebrew text by removing diacritical marks (nikud/niqqud).
///
/// This file provides functions to clean Hebrew text from various diacritical marks including:
/// - Nikud (vowel points)
/// - Teamim (biblical cantillation marks)
/// - Maqaf (Hebrew hyphen)
///
/// Based on the Unicode ranges and character mappings used in Hebrew text processing.
library;

const Map<String, String> _nikudSigns = {
  "HATAF_SEGOL": "ֱ", // U+05B1
  "HATAF_PATAH": "ֲ", // U+05B2
  "HATAF_QAMATZ": "ֳ", // U+05B3
  "HIRIQ": "ִ", // U+05B4
  "TSERE": "ֵ", // U+05B5
  "SEGOL": "ֶ", // U+05B6
  "PATAH": "ַ", // U+05B7
  "QAMATZ": "ָ", // U+05B8
  "SIN_DOT": "ׂ", // U+05C2
  "SHIN_DOT": "ׁ", // U+05C1
  "HOLAM": "ֹ", // U+05B9
  "DAGESH": "ּ", // U+05BC
  "QUBUTZ": "ֻ", // U+05BB
  "SHEVA": "ְ", // U+05B0
  "QAMATZ_QATAN": "ׇ", // U+05C7
};

/// Meteg character (silluq) - U+05BD.
const String _meteg = "ֽ";

/// Regular expression pattern for removing all nikud signs including meteg.
final RegExp _nikudWithMetegRegex = RegExp(
  '[${_nikudSigns.values.join()}$_meteg]',
);

/// Regular expression pattern for removing nikud signs only (excluding meteg).
final RegExp _nikudOnlyRegex = RegExp('[${_nikudSigns.values.join()}]');

/// Regular expression pattern for biblical cantillation marks (teamim).
/// Covers Unicode range U+0591 to U+05AF.
final RegExp _teamimRegex = RegExp('[\u0591-\u05AF]');

/// Hebrew maqaf character (hyphen) - U+05BE.
const String _maqafChar = "־";

/// Removes all nikud (vowel points) from Hebrew text.
///
/// [text]: The Hebrew text containing nikud marks, or null.
/// [includeMeteg]: Whether to also remove meteg marks (default: true).
/// Returns the text with nikud removed, or empty string if input is null/empty.
String removeNikud(String? text, {bool includeMeteg = true}) {
  if (text == null || text.isEmpty) return "";

  return text.replaceAll(
    includeMeteg ? _nikudWithMetegRegex : _nikudOnlyRegex,
    '',
  );
}

/// Removes biblical cantillation marks (teamim) from Hebrew text.
///
/// [text]: The Hebrew text containing teamim, or null.
/// Returns the text with teamim removed, or empty string if input is null/empty.
String removeTeamim(String? text) {
  if (text == null || text.isEmpty) return "";
  return text.replaceAll(_teamimRegex, '');
}

/// Removes all diacritical marks from Hebrew text (nikud and teamim).
///
/// [text]: The Hebrew text containing diacritical marks, or null.
/// Returns the text with all diacritical marks removed, or empty string if input is null/empty.
String removeAllDiacritics(String? text) {
  if (text == null || text.isEmpty) return "";
  return removeTeamim(removeNikud(text, includeMeteg: true));
}

/// Checks whether the given text contains nikud marks.
///
/// [text]: The text to examine, or null.
/// Returns `true` if the text contains any nikud marks, `false` otherwise.
bool containsNikud(String? text) {
  if (text == null || text.isEmpty) return false;
  return _nikudWithMetegRegex.hasMatch(text);
}

/// Checks whether the given text contains teamim (cantillation marks).
///
// [text]: The text to examine, or null.
/// Returns `true` if the text contains any teamim, `false` otherwise.
bool containsTeamim(String? text) {
  if (text == null || text.isEmpty) return false;
  return _teamimRegex.hasMatch(text);
}

/// Checks whether the given text contains maqaf (Hebrew hyphen).
///
/// [text]: The text to examine, or null.
/// Returns `true` if the text contains any maqaf characters, `false` otherwise.
bool containsMaqaf(String? text) {
  if (text == null || text.isEmpty) return false;
  return text.contains(_maqafChar);
}

/// Replaces Hebrew maqaf characters with a specified replacement string.
///
/// [text]: The text containing maqaf characters, or null.
/// [replacement]: The string to replace maqaf with (default: single space).
/// Returns the text with maqaf characters replaced, or empty string if input is null/empty.
String replaceMaqaf(String? text, {String replacement = ' '}) {
  if (text == null || text.isEmpty) return "";
  return text.replaceAll(_maqafChar, replacement);
}
