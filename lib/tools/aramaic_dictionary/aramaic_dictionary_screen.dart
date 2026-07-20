import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

class AramaicDictionaryScreen extends StatefulWidget {
  const AramaicDictionaryScreen({super.key});

  @override
  State<AramaicDictionaryScreen> createState() =>
      _AramaicDictionaryScreenState();
}

class _AramaicDictionaryScreenState extends State<AramaicDictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final DictionaryLookupRepository _dictionaryRepository =
      DictionaryLookupRepository.instance;
  List<Map<String, String>> _dictionaryData = [];
  List<Map<String, String>> _filteredResults = [];
  bool _isLoading = true;
  bool _isHebrewToAramaic = true;

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
      await _dictionaryRepository.ensureAramaicLoaded();
      final entries = _dictionaryRepository.getAllAramaicEntries();

      if (!mounted) return;

      setState(() {
        _dictionaryData = entries.map((entry) {
          return <String, String>{
            'aramaic': entry.aramaic,
            'hebrew': entry.hebrew,
          };
        }).toList();
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
      _filteredResults = _dictionaryData.where((entry) {
        final searchIn =
            _isHebrewToAramaic ? entry['hebrew']! : entry['aramaic']!;
        return searchIn.contains(query);
      }).toList();
    });
  }

  void _toggleDirection() {
    setState(() {
      _isHebrewToAramaic = !_isHebrewToAramaic;
      _searchController.clear();
      _filteredResults = [];
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
              hintText: _isHebrewToAramaic
                  ? 'חפש מילה בעברית...'
                  : 'חפש מילה בארמית...',
              autofocus: true,
              onChanged: _performSearch,
              onClear: () => setState(() => _filteredResults = []),
            ),
          ),
          Expanded(
            child: ToolPanelWrapper(
              child: Column(
                children: [
                  _buildDirectionToggle(),
                  Expanded(child: _buildResultsList()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionToggle() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceSM,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'עברית',
            style: TextStyle(
              fontSize: AppTokens.fontLG,
              fontWeight: _isHebrewToAramaic
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: _isHebrewToAramaic ? cs.primary : cs.onSurface,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD - 4),
          IconButton(
            icon: Icon(
              _isHebrewToAramaic
                  ? FluentIcons.arrow_right_24_regular
                  : FluentIcons.arrow_left_24_regular,
            ),
            onPressed: _toggleDirection,
            tooltip: 'החלף כיוון',
            style: IconButton.styleFrom(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD - 4),
          Text(
            'ארמית',
            style: TextStyle(
              fontSize: AppTokens.fontLG,
              fontWeight: !_isHebrewToAramaic
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: !_isHebrewToAramaic ? cs.primary : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_searchController.text.isEmpty) {
      return const ToolEmptyState(
        icon: FluentIcons.book_24_regular,
        message: 'הזן מילה לחיפוש במילון',
      );
    }

    if (_filteredResults.isEmpty) {
      return const ToolEmptyState(
        icon: FluentIcons.search_24_regular,
        message: 'לא נמצאו תוצאות',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) {
        final entry = _filteredResults[index];
        return AramaicResultCard(
          aramaic: entry['aramaic']!,
          hebrew: entry['hebrew']!,
          isHebrewToAramaic: _isHebrewToAramaic,
        );
      },
    );
  }
}
