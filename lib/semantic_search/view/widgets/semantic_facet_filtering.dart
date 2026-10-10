import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';

/// עץ הקטגוריות של החיפוש החכם — אותו עץ של החיפוש הרגיל, עם ספירת
/// התוצאות שמוצגות כעת.
class SemanticFacetFiltering extends StatefulWidget {
  const SemanticFacetFiltering({
    super.key,
    required this.facetCounts,
    required this.selectedFacets,
    required this.isLoading,
    required this.hasResults,
    required this.onSetFacet,
    required this.onToggleFacet,
    required this.onClearAll,
    required this.onToggleDimension,
  });

  final Map<String, int> facetCounts;
  final List<String> selectedFacets;
  final bool isLoading;
  final bool hasResults;
  final ValueChanged<String> onSetFacet;
  final ValueChanged<String> onToggleFacet;
  final VoidCallback onClearAll;
  final ValueChanged<String> onToggleDimension;

  @override
  State<SemanticFacetFiltering> createState() => _SemanticFacetFilteringState();
}

class _SemanticFacetFilteringState extends State<SemanticFacetFiltering>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _filterQuery = TextEditingController();
  final Map<String, bool> _expansionState = {};

  @override
  void dispose() {
    _filterQuery.dispose();
    super.dispose();
  }

  /// ב-Mac המוסכמה לריבוי בחירה היא Cmd+Click, בשאר הפלטפורמות Ctrl+Click.
  bool _isMultiSelectModifierPressed() {
    final keyboard = HardwareKeyboard.instance;
    if (Platform.isMacOS) {
      return keyboard.isMetaPressed || keyboard.isControlPressed;
    }
    return keyboard.isControlPressed;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NavPanelCollapsibleSearch(
      delegate: NavPanelSearchDelegate(
        controller: _filterQuery,
        hintText: 'איתור ספר…',
        onChanged: (_) => setState(() {}),
        onClear: () => setState(_filterQuery.clear),
      ),
      child: BlocBuilder<LibraryBloc, LibraryState>(
        builder: (context, libraryState) {
          if (libraryState.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (libraryState.error != null) {
            return Center(child: Text('Error: ${libraryState.error}'));
          }
          final library = libraryState.library;
          if (library == null) {
            return const Center(child: Text('No library data available'));
          }
          return SearchNavigationTree(
            library: library,
            facetCounts: widget.facetCounts,
            selectedFacets: widget.selectedFacets,
            expansion: _expansionState,
            filterQuery: _filterQuery.text,
            isLoading: widget.isLoading,
            hasResults: widget.hasResults,
            onSetFacet: widget.onSetFacet,
            onToggleFacet: widget.onToggleFacet,
            onToggleExpand: (path, isExpanded) =>
                setState(() => _expansionState[path] = !isExpanded),
            isMultiSelectPressed: _isMultiSelectModifierPressed,
            onClearAll: widget.onClearAll,
            rootHeaderAction: SearchDimensionFilterButton(
              selectedFacets: widget.selectedFacets,
              onToggle: widget.onToggleDimension,
            ),
          );
        },
      ),
    );
  }
}
