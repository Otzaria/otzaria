import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/acronyms_dictionary/widgets/acronym_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

class AcronymsDictionaryScreen extends StatefulWidget {
  const AcronymsDictionaryScreen({super.key});

  @override
  State<AcronymsDictionaryScreen> createState() =>
      _AcronymsDictionaryScreenState();
}

class _AcronymsDictionaryScreenState extends State<AcronymsDictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final DictionaryLookupRepository _dictionaryRepository =
      DictionaryLookupRepository.instance;
  Map<String, List<String>> _dictionaryData = {};
  List<MapEntry<String, List<String>>> _filteredResults = [];
  bool _isLoading = true;

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
        _dictionaryData = _dictionaryRepository.getAllAcronyms();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
      UiSnack.showError(ToolsMessages.dictionaryLoadError(e));
    }
  }

  void _performSearch(String query) {
    query = query.trim();

    if (query.isEmpty) {
      setState(() {
        _filteredResults = [];
      });
      return;
    }

    setState(() {
      _filteredResults = _dictionaryData.entries
          .where((entry) =>
              entry.key.contains(query) ||
              _dictionaryRepository.acronymMatchesQuery(
                acronym: entry.key,
                query: query,
              ) ||
              entry.value.any((meaning) => meaning.contains(query)))
          .toList();
    });
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
        icon: FluentIcons.search_24_regular,
        message: 'לא נמצאו תוצאות',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) {
        final entry = _filteredResults[index];
        return AcronymResultCard(
          acronym: entry.key,
          meanings: entry.value,
        );
      },
    );
  }
}
