import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'dart:math';
import 'package:flutter/material.dart';

class TextBookSearcher {
  final String _markdownData;
  final List<TextSearchResult> searchResults = [];
  int searchSession = 0;
  bool isSearching = false;
  double searchProgress = 0.0;

  TextBookSearcher(this._markdownData);

  void startTextSearch(String query) {
    if (query.isEmpty) {
      searchResults.clear();
      isSearching = false;
      searchProgress = 0.0;
      searchSession++;
      notifyListeners();
      return;
    }

    isSearching = true;
    searchProgress = 0.0; // Reset progress for new search

    // Perform search asynchronously to avoid blocking the main thread
    Future(() async {
      searchResults.clear();
      var matches = await _findAllMatches(_markdownData, query);
      searchResults.addAll(matches);

      // Update search session and mark search as complete
      searchSession++;
      isSearching = false;
      searchProgress = 1.0;
      notifyListeners();
    });
  }

  Future<List<TextSearchResult>> _findAllMatches(
      String data, String query) async {
    List<String> sections = data.split('\n');
    List<TextSearchResult> results = [];
    List<String> address = [];
    for (int sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      // get the address from html content
      if (sections[sectionIndex].startsWith('<h')) {
        if (address.isNotEmpty &&
            address.any((element) =>
                element.substring(0, 4) ==
                sections[sectionIndex].substring(0, 4))) {
          address.removeRange(
              address.indexWhere((element) =>
                  element.substring(0, 4) ==
                  sections[sectionIndex].substring(0, 4)),
              address.length);
        }
        address.add(sections[sectionIndex]);
      }
      // get results from clean text
      String section = removeVolwels(stripHtmlIfNeeded(sections[sectionIndex]));

      int index = section.indexOf(query);
      if (index >= 0) {
        // if there is a match
        // מסנן את רמה 1 (<h1>) - שם הספר
        final filteredAddress =
            address.where((h) => !h.startsWith('<h1')).toList();

        // Calculate start and end indices with word boundaries
        int start = max(0, index - 40);
        int end = min(section.length, index + query.length + 40);

        // Adjust start to beginning of word
        if (start > 0) {
          int spaceIndex = section.lastIndexOf(' ', start);
          if (spaceIndex != -1) {
            start = spaceIndex + 1;
          } else {
            start = 0;
          }
        }

        // Adjust end to end of word
        if (end < section.length) {
          int spaceIndex = section.indexOf(' ', end);
          if (spaceIndex != -1) {
            end = spaceIndex;
          } else {
            end = section.length;
          }
        }

        results.add(TextSearchResult(
            snippet: section.substring(start, end),
            index: sectionIndex,
            query: query,
            address:
                removeVolwels(stripHtmlIfNeeded(filteredAddress.join(', ')))));
      }
    }
    return results;
  }

  final List<VoidCallback> _listeners = [];

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}
