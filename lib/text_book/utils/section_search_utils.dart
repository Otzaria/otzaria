import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// Maximum number of search results to return
const int _maxSearchResults = 1000;

/// Updates the address list with a new header line
void _updateAddress(List<String> address, String line) {
  if (line.length < 4) {
    address.add(line);
    return;
  }

  final index = address.indexWhere(
      (e) => e.length >= 4 && e.substring(0, 4) == line.substring(0, 4));

  if (index != -1) {
    address.removeRange(index, address.length);
  }
  address.add(line);
}

bool _isHebrewLetter(int codeUnit) {
  return (codeUnit >= 0x05D0 && codeUnit <= 0x05EA) ||
      (codeUnit >= 0x05F0 && codeUnit <= 0x05F4) ||
      (codeUnit >= 0xFB1D && codeUnit <= 0xFBB1);
}

/// Returns true only if [query] appears as a whole word in [text]
/// (not surrounded by Hebrew letters on either side).
bool _containsWholeWord(String text, String query) {
  if (!text.contains(query)) return false;

  int idx = text.indexOf(query);
  while (idx != -1) {
    final before = idx > 0 ? text.codeUnitAt(idx - 1) : -1;
    final after = idx + query.length < text.length
        ? text.codeUnitAt(idx + query.length)
        : -1;

    if (!_isHebrewLetter(before) && !_isHebrewLetter(after)) return true;

    idx = text.indexOf(query, idx + 1);
  }
  return false;
}

/// Search logic executed in isolate for better performance
List<TextSearchResult> _searchIsolate(Map<String, dynamic> args) {
  final List<String> content = args['content'] as List<String>;
  final String query = args['query'] as String;

  final results = <TextSearchResult>[];
  const searchStart = 0;
  final searchEnd = content.length - 1;

  final address = <String>[];
  for (int i = 0; i <= searchStart && i < content.length; i++) {
    final line = content[i];
    if (line.contains('<h') && !line.startsWith('<h1')) {
      _updateAddress(address, line);
    }
  }

  for (int i = searchStart; i <= searchEnd && i < content.length; i++) {
    final line = content[i];

    if (line.contains('<h') && !line.startsWith('<h1')) {
      _updateAddress(address, line);
    }

    final cleanLine = utils.removeVolwels(utils.stripHtmlIfNeeded(line));
    if (_containsWholeWord(cleanLine, query)) {
      results.add(TextSearchResult(
        index: i,
        snippet: cleanLine,
        address:
            utils.removeVolwels(utils.stripHtmlIfNeeded(address.join(', '))),
        query: query,
      ));
      if (results.length >= _maxSearchResults) break;
    }
  }

  return results;
}

/// Performs search within the provided content
Future<List<TextSearchResult>> searchInContent({
  required List<String> content,
  required String query,
}) async {
  if (query.isEmpty || content.isEmpty) return [];

  return compute(_searchIsolate, {
    'content': content,
    'query': query,
  });
}
