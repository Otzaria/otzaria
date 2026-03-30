// lib/tools/gematria/gematria_search_screen.dart
//
// שינויים:
//  • מסך צר (< 800): פאנל הגדרות נפתח כ-Overlay על גבי Stack (לא דוחק תוכן)
//  • מסך רחב: Row([תוכן, GematriaSettingsPanel]) — כמו קודם
//  • ניווט מקלדת ברשימה: ↑↓ בין כרטיסים, Focus על ListView

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/widgets/otzaria_search_field.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:otzaria/tools/gematria/models/gematria_search_result.dart';
import 'package:otzaria/tools/gematria/models/search_result.dart';
import 'package:otzaria/tools/gematria/widgets/gematria_result_card.dart';
import 'package:otzaria/widgets/tool_ui_helpers.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/keyboard_list_focus.dart';
import 'package:otzaria/widgets/tool_empty_state.dart';
import 'package:otzaria/widgets/app_top_bar.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/context_overlay_panel.dart';

class GematriaSearchScreen extends StatefulWidget {
  const GematriaSearchScreen({super.key});

  @override
  GematriaSearchScreenState createState() => GematriaSearchScreenState();
}

class GematriaSearchScreenState extends State<GematriaSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _screenFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final KeyboardListFocusController _keyboardListFocus;

  List<GematriaSearchResult> _searchResults = [];
  bool _isSearching = false;
  int? _lastGematriaValue;
  bool _hasMoreResults = false;
  bool _hasSearched = false;
  bool _showingSettings = false;

  // ── ניווט מקלדת ברשימה ───────────────────────────────────────────────────
  int _focusedCardIndex = -1;
  static const double _cardEstimatedHeight = 90.0;

  static const List<String> _tanachOrder = [
    'בראשית',
    'שמות',
    'ויקרא',
    'במדבר',
    'דברים',
    'יהושע',
    'שופטים',
    'שמואל א',
    'שמואל ב',
    'מלכים א',
    'מלכים ב',
    'ישעיהו',
    'ירמיהו',
    'יחזקאל',
    'הושע',
    'יואל',
    'עמוס',
    'עובדיה',
    'יונה',
    'מיכה',
    'נחום',
    'חבקוק',
    'צפניה',
    'חגי',
    'זכריה',
    'מלאכי',
    'תהלים',
    'משלי',
    'איוב',
    'שיר השירים',
    'רות',
    'איכה',
    'קהלת',
    'אסתר',
    'דניאל',
    'עזרא',
    'נחמיה',
    'דברי הימים א',
    'דברי הימים ב',
  ];

  int _getBookOrder(String fileName) {
    final index = _tanachOrder.indexOf(fileName.replaceAll('.txt', '').trim());
    return index >= 0 ? index : 999;
  }

  @override
  void initState() {
    super.initState();
    _keyboardListFocus = KeyboardListFocusController(
      scrollController: _scrollController,
      estimatedItemExtent: _cardEstimatedHeight,
    );
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearchField());
  }

  /// מבקש פוקוס למסך הגימטריה.
  void requestKeyboardFocus() {
    _focusSearchField();
  }

  void closeTransientPanels() {
    if (!_showingSettings) return;
    setState(() => _showingSettings = false);
  }

  @override
  void deactivate() {
    if (_showingSettings) {
      _showingSettings = false;
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _screenFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _focusSearchField() {
    if (!mounted || !_searchFocusNode.canRequestFocus) return;
    requestFocusIfNeeded(_searchFocusNode);
  }

  void _toggleSettings() =>
      setState(() => _showingSettings = !_showingSettings);

  // ── ניווט ↑↓ ברשימה ─────────────────────────────────────────────────────
  void _moveFocus(int delta) {
    if (_searchResults.isEmpty) return;
    setState(() {
      _focusedCardIndex = _keyboardListFocus.moveFocus(
        delta: delta,
        itemCount: _searchResults.length,
      );
    });
  }

  // ── חיפוש ─────────────────────────────────────────────────────────────────
  Future<void> _performSearch() async {
    final searchText = _searchController.text.trim();
    if (searchText.isEmpty) return;

    final useSmallGematria =
        Settings.getValue<bool>('key-gematria-use-small') ?? false;
    final useFinalLetters =
        Settings.getValue<bool>('key-gematria-use-final-letters') ?? false;
    final useWithKolel =
        Settings.getValue<bool>('key-gematria-use-with-kolel') ?? false;
    final maxResults =
        Settings.getValue<int>('key-gematria-max-results') ?? 100;
    final filterDuplicates =
        Settings.getValue<bool>('key-gematria-filter-duplicates') ?? false;
    final wholeVerseOnly =
        Settings.getValue<bool>('key-gematria-whole-verse-only') ?? false;
    final torahOnly =
        Settings.getValue<bool>('key-gematria-torah-only') ?? false;

    String gematriaMethod = 'regular';
    if (useSmallGematria) {
      gematriaMethod = 'small';
    } else if (useFinalLetters) {
      gematriaMethod = 'finalLetters';
    }

    final int targetGimatria;
    final numericValue = int.tryParse(searchText);
    if (numericValue != null) {
      targetGimatria = numericValue;
    } else {
      final validChars = RegExp(r'^[א-תםןךףץ\s0-9]+$');
      if (!validChars.hasMatch(searchText)) {
        if (mounted) {
          UiSnack.showError(
              'קלט לא תקין. יש להזין אותיות עבריות או מספרים בלבד.');
        }
        return;
      }
      int computed =
          GimatriaSearch.gimatria(searchText, method: gematriaMethod);
      if (useWithKolel) {
        computed += searchText.trim().split(RegExp(r'\s+')).length;
      }
      targetGimatria = computed;
    }

    if (targetGimatria == 0) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _lastGematriaValue = targetGimatria;
      _hasSearched = true;
      _focusedCardIndex = _keyboardListFocus.reset();
    });

    try {
      final libraryPath =
          Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
      final List<String> bookTitlesToSearch =
          torahOnly ? _tanachOrder.take(5).toList() : _tanachOrder;
      final searchPaths = torahOnly
          ? ['$libraryPath/ספרייה/תנך/תורה']
          : [
              '$libraryPath/ספרייה/תנך/תורה',
              '$libraryPath/ספרייה/תנך/נביאים',
              '$libraryPath/ספרייה/תנך/כתובים',
            ];

      final List<SearchResult> allResults = [];
      final first = await GimatriaSearch.searchInFiles(
        searchPaths.first,
        targetGimatria,
        maxPhraseWords: 8,
        fileLimit: maxResults + 1,
        wholeVerseOnly: wholeVerseOnly,
        gematriaMethod: gematriaMethod,
        useWithKolel: useWithKolel,
        bookTitles: bookTitlesToSearch,
      );
      allResults.addAll(first);

      if (allResults.isEmpty && searchPaths.length > 1) {
        for (int i = 1; i < searchPaths.length; i++) {
          final more = await GimatriaSearch.searchInFiles(
            searchPaths[i],
            targetGimatria,
            maxPhraseWords: 8,
            fileLimit: maxResults + 1,
            wholeVerseOnly: wholeVerseOnly,
            gematriaMethod: gematriaMethod,
            useWithKolel: useWithKolel,
          );
          allResults.addAll(more);
          if (allResults.length > maxResults) break;
        }
      }

      _hasMoreResults = allResults.length > maxResults;
      var finalResults = allResults.take(maxResults).toList();

      if (filterDuplicates) {
        final seen = <String>{};
        finalResults = finalResults.where((result) {
          return seen.add(utils.removeVolwels(result.text));
        }).toList();
      }

      setState(() {
        _searchResults = finalResults.map((result) {
          final fileName =
              result.file.split(RegExp(r'[/\\]')).last.replaceAll('.txt', '');
          String displayPath = result.path.isNotEmpty ? result.path : fileName;
          if (result.verseNumber.isNotEmpty) {
            displayPath = '$displayPath, פסוק ${result.verseNumber}';
          }
          return GematriaSearchResult(
            bookTitle: fileName,
            internalPath: displayPath,
            preview: result.text,
            data: result,
          );
        }).toList();

        _searchResults.sort((a, b) {
          final aOrder = _getBookOrder(a.bookTitle);
          final bOrder = _getBookOrder(b.bookTitle);
          if (aOrder != bOrder) return aOrder.compareTo(bOrder);
          return a.data.line.compareTo(b.data.line);
        });

        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      if (mounted) UiSnack.showError('שגיאה בחיפוש: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final searchShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-search-current-window'] ??
          ShortcutValidator.defaultShortcuts[
              'key-shortcut-search-current-window'] ??
          'ctrl+f',
    );
    final settingsShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-open-context-settings'] ??
          ShortcutValidator.defaultShortcuts[
              'key-shortcut-open-context-settings'] ??
          'ctrl+shift+comma',
    );
    final settingsShortcut =
        ShortcutHelper.activatorFromShortcut(settingsShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.comma,
                control: true, shift: true);
    final topBar = BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) => AppTopBar(
        center: OtzariaSearchField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          hintText: 'חפש גימטריה...',
          autofocus: true,
          onSubmitted: (_) => _performSearch(),
          onClear: () => setState(() {
            _searchResults = [];
            _lastGematriaValue = null;
            _hasSearched = false;
            _focusedCardIndex = _keyboardListFocus.reset();
          }),
          leading: IconButton(
            icon: const Icon(FluentIcons.search_24_regular),
            onPressed: _performSearch,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        trailingItems: [
          AppTopBarItem(
            widget: ToolbarActionButton(
              compact: settingsState.compactMenuMode,
              tooltip: _showingSettings
                  ? 'סגור הגדרות (Ctrl+Shift+,)'
                  : 'הגדרות (Ctrl+Shift+,)',
              icon: _showingSettings
                  ? FluentIcons.settings_24_filled
                  : FluentIcons.settings_24_regular,
              selected: _showingSettings,
              onPressed: _toggleSettings,
            ),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        settingsShortcut: _toggleSettings,
        ShortcutHelper.activatorFromShortcut(searchShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocusNode.requestFocus();
        },
      },
      child: Focus(
        focusNode: _screenFocusNode,
        canRequestFocus: false,
        skipTraversal: true,
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
            topBar,
            Expanded(
              child: Stack(
                children: [
                  ToolPanelWrapper(
                    centerContent: !_showingSettings,
                    child: Column(
                      children: [
                        if (_lastGematriaValue != null) _buildStatusBar(),
                        Expanded(child: _buildResultsList()),
                      ],
                    ),
                  ),
                  ContextOverlayPanel(
                    isOpen: _showingSettings,
                    onClose: _toggleSettings,
                    width: 400,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                'הגדרות',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const Expanded(
                          child: SingleChildScrollView(
                            child: GematriaSettingsTab(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status bar ─────────────────────────────────────────────────────────────
  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceSM,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _hasMoreResults
                ? 'הוגבל ל-${_searchResults.length} תוצאות'
                : 'נמצאו ${_searchResults.length} תוצאות',
            style: const TextStyle(fontSize: AppTokens.fontMD),
          ),
          Text(
            'ערך גימטריה: $_lastGematriaValue',
            style: const TextStyle(
              fontSize: AppTokens.fontLG,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ── Results list ───────────────────────────────────────────────────────────
  Widget _buildResultsList() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty && _hasSearched) {
      return const ToolEmptyState(
          icon: FluentIcons.search_24_regular, message: 'לא נמצאו תוצאות');
    }
    if (!_hasSearched) {
      return const ToolEmptyState(
          icon: FluentIcons.calculator_24_regular,
          message: 'הזן ערך לחיפוש גימטריה');
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) => GematriaResultCard(
        number: index + 1,
        result: _searchResults[index],
        isFocused: _focusedCardIndex == index,
        onTap: () => setState(() {
          _focusedCardIndex = index;
          _keyboardListFocus.focusedIndex = index;
        }),
      ),
    );
  }

}
