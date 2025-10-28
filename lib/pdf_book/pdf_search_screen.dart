// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:otzaria/widgets/search_pane_base.dart';

//
// Simple Text Search View for Syncfusion PDF Viewer
// Note: Syncfusion provides automatic highlighting but doesn't expose match details
// This is a simplified version that shows count and navigation
//
class PdfBookSearchView extends StatefulWidget {
  const PdfBookSearchView({
    required this.pdfController,
    required this.searchController,
    required this.focusNode,
    this.outline,
    this.bookTitle,
    this.initialSearchText = '',
    this.onSearchResultNavigated,
    super.key,
  });

  final PdfViewerController pdfController;
  final TextEditingController searchController;
  final FocusNode focusNode;
  final List<PdfBookmark>? outline;
  final String? bookTitle;
  final String initialSearchText;
  final VoidCallback? onSearchResultNavigated;

  @override
  State<PdfBookSearchView> createState() => _PdfBookSearchViewState();
}

class _PdfBookSearchViewState extends State<PdfBookSearchView> {
  PdfTextSearchResult? _searchResult;
  bool _isSearching = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_searchTextUpdated);

    // If there's initial search text, perform the search
    if (widget.searchController.text.isNotEmpty) {
      _performSearch(widget.searchController.text);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult?.clear();
    widget.searchController.removeListener(_searchTextUpdated);
    super.dispose();
  }

  void _searchTextUpdated() {
    // Cancel previous timer
    _debounceTimer?.cancel();

    final query = widget.searchController.text.trim();
    if (query.isEmpty) {
      _clearSearch();
      return;
    }

    // Wait 300ms before searching (reduced from 500ms)
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  void _onSearchResultChanged() {
    // This is called when search progresses (page by page on mobile/desktop)
    if (mounted && _searchResult != null && _searchResult!.hasResult) {
      setState(() {
        // Update UI with new results
        _isSearching = !_searchResult!.isSearchCompleted;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      // Clear previous search and remove its listener
      _searchResult?.removeListener(_onSearchResultChanged);
      _searchResult?.clear();

      // Start new search - this returns immediately
      final result = widget.pdfController.searchText(query);
      _searchResult = result;

      // Add listener to get updates as search progresses
      // On mobile/desktop, search is async and results come page by page
      _searchResult!.addListener(_onSearchResultChanged);

      // Initial state update
      if (mounted) {
        setState(() {
          // Search is now in progress
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _clearSearch() {
    _searchResult?.clear();
    setState(() {
      _searchResult = null;
    });
  }

  void _goToNextMatch() {
    if (_searchResult != null && _searchResult!.hasResult) {
      _searchResult!.nextInstance();
      widget.onSearchResultNavigated?.call();
      setState(() {});
    }
  }

  void _goToPreviousMatch() {
    if (_searchResult != null && _searchResult!.hasResult) {
      _searchResult!.previousInstance();
      widget.onSearchResultNavigated?.call();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _searchResult != null && _searchResult!.hasResult;
    final totalCount = _searchResult?.totalInstanceCount ?? 0;
    final currentIndex = _searchResult?.currentInstanceIndex ?? 0;

    return SearchPaneBase(
      searchController: widget.searchController,
      focusNode: widget.focusNode,
      progressWidget:
          _isSearching ? const LinearProgressIndicator(minHeight: 4) : null,
      resultCountString: hasResults
          ? 'נמצאו $totalCount תוצאות (${currentIndex + 1}/$totalCount)'
          : null,
      resultsWidget: hasResults
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_upward),
                        tooltip: 'תוצאה קודמת',
                        onPressed: _goToPreviousMatch,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${currentIndex + 1} / $totalCount',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward),
                        tooltip: 'תוצאה הבאה',
                        onPressed: _goToNextMatch,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'השתמש בחצים לניווט בין התוצאות',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'התוצאות מסומנות במסמך',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Text(
                'הזן טקסט לחיפוש',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
      isNoResults: widget.searchController.text.isNotEmpty &&
          !_isSearching &&
          (_searchResult == null || !_searchResult!.hasResult),
      onSearchTextChanged: (_) => _searchTextUpdated(),
      resetSearchCallback: _clearSearch,
      hintText: 'חפש כאן..',
    );
  }
}
