import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/acronyms_dictionary/widgets/acronym_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/keyboard_list_focus.dart';
import 'package:otzaria/widgets/tool_empty_state.dart';

class AcronymsDictionaryScreen extends StatefulWidget {
  const AcronymsDictionaryScreen({super.key});

  @override
  State<AcronymsDictionaryScreen> createState() =>
      _AcronymsDictionaryScreenState();
}

class _AcronymsDictionaryScreenState extends State<AcronymsDictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final DictionaryLookupRepository _dictionaryRepository =
      DictionaryLookupRepository.instance;
  final FocusNode _listFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final KeyboardListFocusController _keyboardListFocus;

  Map<String, List<String>> _dictionaryData = {};
  List<MapEntry<String, List<String>>> _filteredResults = [];
  bool _isLoading = true;
  int _focusedIndex = -1;

  @override
  void initState() {
    super.initState();
    _keyboardListFocus = KeyboardListFocusController(
      scrollController: _scrollController,
      estimatedItemExtent: 52,
    );
    _loadDictionary();
    _searchController.addListener(_performSearch);
  }

  /// מבקש פוקוס לרשימת ראשי התיבות.
  void requestKeyboardFocus() {
    requestFocusIfNeeded(_listFocusNode);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listFocusNode.dispose();
    _scrollController.dispose();
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
      setState(() => _isLoading = false);
      UiSnack.showError('שגיאה בטעינת המילון: $e');
    }
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _filteredResults = [];
        _focusedIndex = _keyboardListFocus.reset();
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
      _focusedIndex = _keyboardListFocus.reset(
        setToFirstWhenNotEmpty: true,
        itemCount: _filteredResults.length,
      );
    });
  }

  void _moveFocus(int delta) {
    if (_filteredResults.isEmpty) return;
    setState(() {
      _focusedIndex = _keyboardListFocus.moveFocus(
        delta: delta,
        itemCount: _filteredResults.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(child: _buildResultsList()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceSM,
        AppTokens.spaceMD,
        AppTokens.spaceSM,
        AppTokens.spaceSM,
      ),
      child: Row(
        children: [
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: OtzariaSearchField(
              controller: _searchController,
              hintText: 'חפש ראשי תיבות...',
              onClear: _searchController.clear,
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
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) {
        final entry = _filteredResults[index];
        return AcronymResultCard(
          acronym: entry.key,
          meanings: entry.value,
          isFocused: _focusedIndex == index,
          onTap: () => setState(() {
            _focusedIndex = index;
            _keyboardListFocus.focusedIndex = index;
          }),
        );
      },
    );
  }
}
