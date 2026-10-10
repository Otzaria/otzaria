import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/acronyms_dictionary/widgets/acronym_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/tool_query.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

class AcronymsDictionaryScreen extends StatefulWidget {
  const AcronymsDictionaryScreen({
    super.key,
    this.repository,
    this.queryInbox,
  });

  final DictionaryLookupRepository? repository;
  final ToolQueryInbox? queryInbox;

  @override
  State<AcronymsDictionaryScreen> createState() =>
      _AcronymsDictionaryScreenState();
}

class _AcronymsDictionaryScreenState extends State<AcronymsDictionaryScreen>
    with ToolQueryConsumer {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final DictionaryLookupRepository _dictionaryRepository =
      widget.repository ?? DictionaryLookupRepository.instance;
  List<AcronymCatalogEntry> _catalog = [];
  List<AcronymCatalogEntry> _filteredResults = [];
  bool _isLoading = true;

  @override
  ToolQueryInbox? get toolQueryInbox => widget.queryInbox;

  @override
  bool get canApplyToolQuery => !_isLoading;

  @override
  void applyToolQuery(ToolQuery query) {
    fillSearchField(_searchController, query.text);
    _performSearch(query.text);
  }

  @override
  void initState() {
    super.initState();
    _loadDictionary();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocusNode.requestFocus(),
    );
  }

  void requestKeyboardFocus() {
    if (!mounted || !_searchFocusNode.canRequestFocus) return;
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDictionary() async {
    try {
      await _dictionaryRepository.ensureAcronymsLoaded();

      if (!mounted) return;

      setState(() {
        _catalog = _dictionaryRepository.getAcronymSearchCatalog();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
      UiSnack.showError(ToolsMessages.dictionaryLoadError(e));
    }
    consumeToolQuery();
  }

  void _performSearch(String query) {
    query = query.trim();

    if (query.isEmpty) {
      setState(() {
        _filteredResults = [];
      });
      return;
    }

    final normalizedQuery = _dictionaryRepository.normalizeAcronymQuery(query);

    setState(() {
      _filteredResults =
          _catalog
              .where(
                (entry) =>
                    entry.displayAcronym.contains(query) ||
                    (normalizedQuery.isNotEmpty &&
                        entry.normalizedKey.contains(normalizedQuery)) ||
                    entry.meanings.any((meaning) => meaning.contains(query)),
              )
              .toList()
            ..sort((a, b) {
              final rankCompare = _matchRank(
                a,
                query,
                normalizedQuery,
              ).compareTo(_matchRank(b, query, normalizedQuery));
              if (rankCompare != 0) return rankCompare;
              final lengthCompare = a.displayAcronym.length.compareTo(
                b.displayAcronym.length,
              );
              if (lengthCompare != 0) return lengthCompare;
              return a.displayAcronym.compareTo(b.displayAcronym);
            });
    });
  }

  /// דירוג התאמת מפתח לשאילתה: נמוך = דומה יותר.
  /// התאמה מדויקת < מתחיל ב- < מכיל < התאמה בפירוש בלבד.
  int _matchRank(
    AcronymCatalogEntry entry,
    String query,
    String normalizedQuery,
  ) {
    final key = entry.displayAcronym;
    if (key == query) return 0;
    if (key.startsWith(query)) return 1;
    if (key.contains(query)) return 2;
    if (normalizedQuery.isNotEmpty &&
        entry.normalizedKey.contains(normalizedQuery)) {
      return 3;
    }
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final searchShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-search-current-window'] ??
          ShortcutValidator
              .defaultShortcuts['key-shortcut-search-current-window'] ??
          'ctrl+f',
    );

    return CallbackShortcuts(
      bindings: {
        ShortcutHelper.activatorFromShortcut(searchShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocusNode.requestFocus();
        },
      },
      child: Column(
        children: [
          AppTopBar(
            center: OtzariaSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              icon: OtzariaIcons.search_in_quote_24_regular,
              hintText: 'חפש ראשי תיבות...',
              autofocus: true,
              onChanged: _performSearch,
              onClear: () => setState(() => _filteredResults = []),
            ),
          ),
          Expanded(
            child: ToolPanelWrapper(
              child: _buildResultsList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_searchController.text.isEmpty) {
      return const ToolEmptyState(
        icon: FluentIcons.text_quote_24_regular,
        message: 'הזן ראשי תיבות לחיפוש במילון',
      );
    }

    if (_filteredResults.isEmpty) {
      return const ToolEmptyState(
        icon: OtzariaIcons.search_24_regular,
        message: 'לא נמצאו תוצאות',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) {
        final entry = _filteredResults[index];
        return AcronymResultCard(
          acronym: entry.displayAcronym,
          meanings: entry.meanings,
        );
      },
    );
  }
}
