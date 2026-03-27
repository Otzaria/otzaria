import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/otzaria_search_field.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/keyboard_list_focus.dart';
import 'package:otzaria/widgets/tool_empty_state.dart';
import 'package:otzaria/widgets/app_top_bar.dart';
import 'package:otzaria/widgets/tool_ui_helpers.dart';

class AramaicDictionaryScreen extends StatefulWidget {
  const AramaicDictionaryScreen({super.key});

  @override
  State<AramaicDictionaryScreen> createState() =>
      _AramaicDictionaryScreenState();
}

class _AramaicDictionaryScreenState extends State<AramaicDictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final DictionaryLookupRepository _dictionaryRepository =
      DictionaryLookupRepository.instance;
  final FocusNode _listFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final KeyboardListFocusController _keyboardListFocus;

  List<Map<String, String>> _dictionaryData = [];
  List<Map<String, String>> _filteredResults = [];
  bool _isLoading = true;
  bool _isHebrewToAramaic = true;
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

  /// מבקש פוקוס לרשימת המילון.
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
      await _dictionaryRepository.ensureAramaicLoaded();
      final entries = _dictionaryRepository.getAllAramaicEntries();

      if (!mounted) return;

      setState(() {
        _dictionaryData = entries
            .map(
              (entry) => <String, String>{
                'aramaic': entry.aramaic,
                'hebrew': entry.hebrew,
              },
            )
            .toList();
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
      _filteredResults = _dictionaryData.where((entry) {
        final searchIn =
            _isHebrewToAramaic ? entry['hebrew']! : entry['aramaic']!;
        return searchIn.contains(query);
      }).toList();
      _focusedIndex = _keyboardListFocus.reset(
        setToFirstWhenNotEmpty: true,
        itemCount: _filteredResults.length,
      );
    });
  }

  void _toggleDirection() {
    setState(() {
      _isHebrewToAramaic = !_isHebrewToAramaic;
      _searchController.clear();
      _filteredResults = [];
      _focusedIndex = _keyboardListFocus.reset();
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
                hintText: _isHebrewToAramaic
                    ? 'חפש מילה בעברית...'
                    : 'חפש מילה בארמית...',
                onClear: () => setState(() {
                  _filteredResults = [];
                  _focusedIndex = -1;
                }),
              ),
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
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: AppTokens.fontLG,
              fontWeight:
                  _isHebrewToAramaic ? FontWeight.bold : FontWeight.normal,
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
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: AppTokens.fontLG,
              fontWeight:
                  !_isHebrewToAramaic ? FontWeight.bold : FontWeight.normal,
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
