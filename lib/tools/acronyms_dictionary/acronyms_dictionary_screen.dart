import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/otzaria_search_field.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/acronyms_dictionary/widgets/acronym_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/keyboard_list_focus.dart';
import 'package:otzaria/widgets/tool_empty_state.dart';
import 'package:otzaria/widgets/tool_ui_helpers.dart';
import 'package:otzaria/widgets/app_top_bar.dart';

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
  final FocusNode _searchFocusNode = FocusNode();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearchField());
  }

  /// מבקש פוקוס לרשימת ראשי התיבות.
  void requestKeyboardFocus() {
    _focusSearchField();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _focusSearchField() {
    if (!mounted || !_searchFocusNode.canRequestFocus) return;
    requestFocusIfNeeded(_searchFocusNode);
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

    return Focus(
      focusNode: _listFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveFocus(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveFocus(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) => AppTopBar(
              center: OtzariaSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: 'חפש ראשי תיבות...',
                autofocus: true,
                onClear: () => setState(() {
                  _filteredResults = [];
                  _focusedIndex = -1;
                }),
              ),
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
