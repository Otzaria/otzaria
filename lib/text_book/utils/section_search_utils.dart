import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

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

/// Represents section boundaries (start and end line indices, inclusive)
class SectionBounds {
  final int start;
  final int end;

  const SectionBounds({required this.start, required this.end});

  bool contains(int index) => index >= start && index <= end;
  int get length => end - start + 1;

  @override
  String toString() => 'SectionBounds($start-$end)';

  @override
  bool operator ==(Object other) =>
      other is SectionBounds && start == other.start && end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}

/// Detects current section boundaries based on visible content
SectionBounds detectCurrentSection({
  required List<String> content,
  required List<int> visibleIndices,
}) {
  if (content.isEmpty) return const SectionBounds(start: 0, end: 0);

  final currentIndex = (visibleIndices.isNotEmpty ? visibleIndices.first : 0)
      .clamp(0, content.length - 1);

  // Find section header (h2/h3) before current position
  int? headerIndex;
  for (int i = currentIndex; i >= 0; i--) {
    if (content[i].contains('<h2') || content[i].contains('<h3')) {
      headerIndex = i;
      break;
    }
  }

  // Determine section start
  int startIndex;
  if (headerIndex != null) {
    startIndex = headerIndex + 1;
  } else {
    // If no h2/h3 found, search for h1
    int? h1Index;
    for (int i = currentIndex; i >= 0; i--) {
      if (content[i].contains('<h1')) {
        h1Index = i;
        break;
      }
    }
    startIndex = h1Index != null ? h1Index + 1 : 0;
  }

  // Find section end (next h2/h3)
  int? sectionEnd;
  for (int i = startIndex; i < content.length; i++) {
    if (content[i].contains('<h2') || content[i].contains('<h3')) {
      sectionEnd = i - 1;
      break;
    }
  }

  return SectionBounds(
    start: startIndex,
    end: sectionEnd ?? content.length - 1,
  );
}

/// Search logic executed in isolate for better performance
List<TextSearchResult> _searchIsolate(Map<String, dynamic> args) {
  final List<String> content = args['content'] as List<String>;
  final String query = args['query'] as String;
  final SectionBounds? bounds = args['bounds'] as SectionBounds?;

  final results = <TextSearchResult>[];
  final searchStart = bounds?.start ?? 0;
  final searchEnd = bounds?.end ?? content.length - 1;

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
    if (cleanLine.contains(query)) {
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

/// Performs search within specified content range
Future<List<TextSearchResult>> searchInContent({
  required List<String> content,
  required String query,
  required SectionBounds? bounds,
}) async {
  if (query.isEmpty || content.isEmpty) return [];

  // Validate bounds
  if (bounds != null &&
      (bounds.start > bounds.end ||
          bounds.start < 0 ||
          bounds.end >= content.length)) {
    return [];
  }

  return compute(_searchIsolate, {
    'content': content,
    'query': query,
    'bounds': bounds,
  });
}
