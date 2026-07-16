import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// פקדי סינון לפי מאפייני-ספר — ספרי יסוד (`/base`), תקופה (`/era/<שם>`)
/// ומחבר (`/author/<שם>`) — כרכיב נשלט (controlled): מקבל את הבחירה
/// הנוכחית ומדווח כל שינוי ב-[onChanged]. אינו תלוי ב-bloc, כך שהוא
/// משובץ גם בסרגל תוצאות החיפוש (דרך [SearchDimensionFilters]) וגם
/// בדיאלוג החיפוש, ששם הבחירה נכנסת ישירות ל-facets של החיפוש שישוגר.
class SearchDimensionControls extends StatefulWidget {
  /// הבחירה הנוכחית — נתיבי facet ממדיים בלבד (`/base`, `/era/...`,
  /// `/author/...`).
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const SearchDimensionControls({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<SearchDimensionControls> createState() =>
      _SearchDimensionControlsState();
}

class _SearchDimensionControlsState extends State<SearchDimensionControls> {
  static const int _minAuthorQueryLength = 2;
  static const int _authorSuggestionsLimit = 15;

  /// חמש התקופות שהאינדקס מטביע. 'שאר מפרשים' לעולם לא מוטבעת — לא מוצעת.
  static final List<String> _eraNames = [
    for (final era in CommentaryEra.values)
      if (era != CommentaryEra.other) era.hebrewName,
  ];

  TextEditingController? _authorFieldController;

  void _toggle(String facet, {required bool selected}) {
    final next = Set<String>.from(widget.selected);
    if (selected) {
      next.add(facet);
    } else {
      next.remove(facet);
    }
    widget.onChanged(next);
  }

  Future<Iterable<String>> _buildAuthorSuggestions(
    String query,
    Set<String> selectedAuthorFacets,
  ) async {
    final trimmed = query.trim();
    if (trimmed.length < _minAuthorQueryLength) {
      return const Iterable<String>.empty();
    }
    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      return const Iterable<String>.empty();
    }
    try {
      final names = await repository.searchAuthorNames(
        trimmed,
        limit: _authorSuggestionsLimit,
      );
      return names.where((name) =>
          !selectedAuthorFacets.contains(FacetHelper.buildAuthorFacet(name)));
    } catch (e) {
      debugPrint('[SearchDimensionControls] author suggestions failed: $e');
      return const Iterable<String>.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dimensions = widget.selected;
    final baseOnly = dimensions.contains(FacetHelper.baseDimensionFacet);
    final selectedEraFacets = dimensions
        .where((facet) => facet.startsWith(FacetHelper.eraDimensionPrefix))
        .toSet();
    final selectedAuthorFacets = dimensions
        .where((facet) => facet.startsWith(FacetHelper.authorDimensionPrefix))
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBaseBooksSwitch(context, baseOnly: baseOnly),
        const SizedBox(height: 4),
        _buildEraSection(context, selectedEraFacets),
        const SizedBox(height: 12),
        _buildAuthorSection(context, selectedAuthorFacets),
      ],
    );
  }

  Widget _buildBaseBooksSwitch(BuildContext context, {required bool baseOnly}) {
    final colorScheme = Theme.of(context).colorScheme;
    // Material (ולא Container+BoxDecoration): ListTile מצייר רקע ואפקט
    // לחיצה על ה-Material הקרוב — קופסה מעוצבת מעליו מסתירה אותם
    // ומציפה assertion של Flutter בכל לחיצה.
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: SwitchListTile.adaptive(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        title: const Text(
          'חיפוש בספרי היסוד בלבד',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        value: baseOnly,
        onChanged: (value) => _toggle(
          FacetHelper.baseDimensionFacet,
          selected: value,
        ),
      ),
    );
  }

  Widget _buildEraSection(BuildContext context, Set<String> selectedEraFacets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: 'תקופה'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: [
            for (final eraName in _eraNames)
              FilterChip(
                label: Text(eraName, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                selected: selectedEraFacets
                    .contains(FacetHelper.buildEraFacet(eraName)),
                onSelected: (selected) => _toggle(
                  FacetHelper.buildEraFacet(eraName),
                  selected: selected,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuthorSection(
    BuildContext context,
    Set<String> selectedAuthorFacets,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedAuthors = selectedAuthorFacets
        .map((facet) =>
            facet.substring(FacetHelper.authorDimensionPrefix.length))
        .toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: 'מחבר'),
        const SizedBox(height: 4),
        Autocomplete<String>(
          optionsBuilder: (textEditingValue) => _buildAuthorSuggestions(
              textEditingValue.text, selectedAuthorFacets),
          onSelected: (authorName) {
            _toggle(
              FacetHelper.buildAuthorFacet(authorName),
              selected: true,
            );
            _authorFieldController?.clear();
          },
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
            _authorFieldController = textEditingController;
            return RtlTextField(
              controller: textEditingController,
              focusNode: focusNode,
              onSubmitted: (_) => onFieldSubmitted(),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'הקלד שם מחבר…',
                hintStyle: const TextStyle(fontSize: 13),
                isDense: true,
                prefixIcon: const Icon(FluentIcons.person_24_regular, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: AlignmentDirectional.topStart,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 220, maxWidth: 280),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(
                          option,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        if (selectedAuthors.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final author in selectedAuthors)
                InputChip(
                  label: Text(author, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  deleteIconColor: colorScheme.onSurfaceVariant,
                  onDeleted: () => _toggle(
                    '${FacetHelper.authorDimensionPrefix}$author',
                    selected: false,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// חלונית "תקופה, מחבר וספרי יסוד" בסרגל תוצאות החיפוש — עטיפה מחוברת-bloc
/// של [SearchDimensionControls].
///
/// הממדים רוכבים על אותה רשימת facets שכבר נשלחת למנוע: OR בתוך ממד,
/// AND בין ממדים ומול קבוצת הקטגוריות. לכן כל שינוי כאן לוקח את בחירת
/// הקטגוריות הנוכחית מה-state ומצרף אליה את מחרוזות הממדים, ומשוגר דרך
/// [SetFacetsWithoutSearch] + [UpdateSearchQuery] (ולא דרך AddFacet/
/// RemoveFacet — המסלול הממוזער בצד-לקוח של ה-bloc מסנן לפי נתיבי
/// קטגוריה בלבד ואינו מכיר את סמנטיקת ה-AND של הממדים).
class SearchDimensionFilters extends StatefulWidget {
  final SearchingTab tab;

  const SearchDimensionFilters({super.key, required this.tab});

  @override
  State<SearchDimensionFilters> createState() => _SearchDimensionFiltersState();
}

class _SearchDimensionFiltersState extends State<SearchDimensionFilters> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePersistedDimensions();
    });
  }

  /// שחזור הבחירה השמורה לטאב "נקי" בלבד: אם כבר רץ חיפוש (או שה-state
  /// כבר נושא ממדים) לא דורסים את ההיקף שנקבע לו.
  void _restorePersistedDimensions() {
    if (!mounted) return;
    final persisted = SearchScopePreferences.loadDimensionFacets();
    if (persisted.isEmpty) return;

    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;
    if (state.searchQuery.isNotEmpty || state.isLoading) return;
    if (FacetHelper.dimensionFacetsOf(state.currentFacets).isNotEmpty) return;

    final categories = FacetHelper.categoryFacetsOf(state.currentFacets);
    final effectiveCategories = categories.isEmpty ? const ['/'] : categories;
    final sortedDimensions = persisted.toList()..sort();
    searchBloc.add(
        SetFacetsWithoutSearch([...effectiveCategories, ...sortedDimensions]));
  }

  /// מחליף את קבוצת הממדים הפעילה, משמר את בחירת הקטגוריות הנוכחית,
  /// שומר בהעדפות ומריץ מחדש את החיפוש (אם יש שאילתה).
  void _applyDimensions(Set<String> newDimensions) {
    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;

    final categories = FacetHelper.categoryFacetsOf(state.currentFacets);
    final effectiveCategories = categories.isEmpty ? const ['/'] : categories;
    final sortedDimensions = newDimensions.toList()..sort();

    SearchScopePreferences.saveDimensionFacets(newDimensions);
    searchBloc.add(
        SetFacetsWithoutSearch([...effectiveCategories, ...sortedDimensions]));

    if (state.searchQuery.isEmpty) return;
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      state.configuration.searchMode,
      customSpacing: widget.tab.spacingValues,
      alternativeWords: widget.tab.alternativeWords,
      searchOptions: widget.tab.effectiveSearchOptions(
        query: state.searchQuery,
      ),
    );
    searchBloc.add(UpdateSearchQuery(
      state.searchQuery,
      customSpacing: normalizedParameters.customSpacing,
      alternativeWords: normalizedParameters.alternativeWords,
      searchOptions: normalizedParameters.searchOptions,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      buildWhen: (previous, current) =>
          previous.currentFacets != current.currentFacets,
      builder: (context, state) {
        final dimensions =
            FacetHelper.dimensionFacetsOf(state.currentFacets).toSet();

        // בלי PageStorageKey בכוונה: ExpansionTile שומר את מצב-הפתיחה
        // (bool) ב-PageStorage תחת המפתח, ושרשרת המפתחות של שדה
        // הטקסט הפנימי (Autocomplete) זהה — הגלילה שלו הייתה קוראת את
        // ה-bool ומתרסקת בהמרה ל-double (תקיעת רינדור בכל פתיחה).
        return ExpansionTile(
          initiallyExpanded: dimensions.isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(
            FluentIcons.filter_add_20_regular,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'תקופה, מחבר וספרי יסוד',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (dimensions.isNotEmpty) ...[
                const SizedBox(width: 6),
                _ActiveCountBadge(count: dimensions.length),
              ],
              const SizedBox(width: 6),
              Tooltip(
                message: 'הסינון חל על אינדקס שנבנה בגרסה זו',
                child: Icon(
                  FluentIcons.info_20_regular,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          children: [
            SearchDimensionControls(
              selected: dimensions,
              onChanged: _applyDimensions,
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ActiveCountBadge extends StatelessWidget {
  final int count;

  const _ActiveCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
