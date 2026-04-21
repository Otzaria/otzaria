import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/search/view/category_tree_selector.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

/// פאנל עריכת חיפוש - מופיע מתחת לשורת "מוצגות תוצאות של..."
/// מאפשר עריכת החיפוש הנוכחי ללא יצירת כרטיסייה חדשה
class SearchEditPanel extends StatefulWidget {
  final SearchingTab tab;
  final VoidCallback onClose;

  const SearchEditPanel({
    super.key,
    required this.tab,
    required this.onClose,
  });

  @override
  State<SearchEditPanel> createState() => _SearchEditPanelState();
}

class _SearchEditPanelState extends State<SearchEditPanel> {
  late final TextEditingController _distanceController;
  late Set<String> _selectedCategoryFacets;

  @override
  void initState() {
    super.initState();
    final searchState = widget.tab.searchBloc.state;
    _distanceController =
        TextEditingController(text: searchState.distance.toString());
    _selectedCategoryFacets = searchState.searchScopeFacets.toSet();
  }

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  void _performSearch(BuildContext context) {
    final query = widget.tab.queryController.text.trim();

    if (query.isEmpty) {
      UiSnack.show('נא להזין טקסט לחיפוש');
      return;
    }

    final facetsToSearch = _selectedCategoryFacets.toList();

    widget.tab.updateTitleFromAppliedQuery(query);
    widget.tab.searchBloc.add(SetFacetsWithoutSearch(facetsToSearch));
    widget.tab.searchBloc.add(
      UpdateSearchQuery(
        query,
        customSpacing: widget.tab.spacingValues,
        alternativeWords: widget.tab.alternativeWords,
        searchOptions: widget.tab.searchOptions,
      ),
    );

    widget.onClose();
  }

  Widget _buildSearchModeToggle(SearchState state) {
    final modes = [
      ('מתקדם', SearchMode.advanced),
      ('מדויק', SearchMode.exact),
      ('מקורב', SearchMode.fuzzy),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, mode) in modes)
          ChoiceChip(
            label: Text(label, textDirection: TextDirection.rtl),
            selected: state.configuration.searchMode == mode,
            onSelected: (selected) {
              if (selected) {
                widget.tab.searchBloc.add(SetSearchMode(mode));
              }
            },
          ),
      ],
    );
  }

  Widget _buildDistanceField(BuildContext context, SearchState state) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    if (_distanceController.text != state.distance.toString()) {
      _distanceController.text = state.distance.toString();
      _distanceController.selection = TextSelection.collapsed(
        offset: _distanceController.text.length,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'מרווח כללי בין מילים:',
          style: TextStyle(
            fontSize: 14,
            color: onSurface.withValues(alpha: 0.7),
          ),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: RtlTextField(
            controller: _distanceController,
            decoration: const InputDecoration(
              hintText: '0-30',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              FilteringTextInputFormatter.allow(
                RegExp(r'^([0-9]|[12][0-9]|30)$'),
              ),
            ],
            textAlign: TextAlign.center,
            onChanged: (value) {
              final distance = int.tryParse(value);
              if (distance != null && distance >= 0 && distance <= 30) {
                widget.tab.searchBloc.add(UpdateDistance(distance));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryAndOptions(BuildContext context, SearchState state) {
    final categoryTree = SearchScopeSelector(
      selectedFacets: _selectedCategoryFacets,
      shrinkWrapManualSelector: true,
      onSelectionChanged: (selection) {
        setState(() {
          _selectedCategoryFacets = selection;
        });
      },
    );

    if (!state.isAdvancedSearchEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'בחר קטגוריות לחיפוש המעודכן',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 12),
          categoryTree,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final advancedControls = AdvancedSearchControls(
          tab: widget.tab,
          compactMode: true,
          onEmptySubmit: () => _performSearch(context),
        );

        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: SingleChildScrollView(child: advancedControls),
              ),
              const SizedBox(width: 16),
              Expanded(child: categoryTree),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            advancedControls,
            const SizedBox(height: 16),
            categoryTree,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      bloc: widget.tab.searchBloc,
      builder: (context, state) {
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'מצב חיפוש:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  _buildSearchModeToggle(state),
                  if (widget.tab.spacingValues.isEmpty &&
                      !state.fuzzy &&
                      !state.isTypoToleranceEnabled)
                    _buildDistanceField(context, state),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: RtlTextField(
                      controller: widget.tab.queryController,
                      focusNode: widget.tab.searchFieldFocusNode,
                      decoration: InputDecoration(
                        hintText: 'הזן טקסט לחיפוש...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: widget.tab.queryController.clear,
                        ),
                      ),
                      textAlign: TextAlign.right,
                      onSubmitted: (_) => _performSearch(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  RecommendedActionButton(
                    text: 'חפש',
                    icon: FluentIcons.search_24_regular,
                    onPressed: () => _performSearch(context),
                  ),
                  const SizedBox(width: 8),
                  NeutralActionButton(
                    text: 'סגור',
                    icon: FluentIcons.dismiss_24_regular,
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: colorScheme.outlineVariant),
              const SizedBox(height: 16),
              _buildCategoryAndOptions(context, state),
            ],
          ),
        );
      },
    );
  }
}
