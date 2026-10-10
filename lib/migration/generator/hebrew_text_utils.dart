/// Utility class for processing Hebrew text by removing diacritical marks (nikud/niqqud).
///
/// This file provides functions to clean Hebrew text from various diacritical marks including:
/// - Nikud (vowel points)
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
