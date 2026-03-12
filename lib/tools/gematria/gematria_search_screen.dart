// lib/tools/gematria/gematria_search_screen.dart
//
// מסך חיפוש גימטריה.
// ויג'טים הוצאו ל-widgets/ ומודלים ל-models/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:otzaria/tools/gematria/models/gematria_search_result.dart';
import 'package:otzaria/tools/gematria/models/search_result.dart';
import 'package:otzaria/tools/gematria/widgets/gematria_result_card.dart';
import 'package:otzaria/tools/gematria/widgets/gematria_settings_panel.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

class GematriaSearchScreen extends StatefulWidget {
  const GematriaSearchScreen({super.key});

  @override
  GematriaSearchScreenState createState() => GematriaSearchScreenState();
}

class GematriaSearchScreenState extends State<GematriaSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<GematriaSearchResult> _searchResults = [];
  bool _isSearching = false;
  int? _lastGematriaValue;
  bool _hasMoreResults = false;
  bool _hasSearched = false;
  bool _showingSettings = false;

  // ─── ספרי תנ"ך בסדרם ───────────────────────────────────────────────────────
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
    final bookName = fileName.replaceAll('.txt', '').trim();
    final index = _tanachOrder.indexOf(bookName);
    return index >= 0 ? index : 999;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleSettings() =>
      setState(() => _showingSettings = !_showingSettings);

  // ─── קיצור מקשים ────────────────────────────────────────────────────────────

  SingleActivator _parseShortcut(String shortcut) {
    final parts = shortcut.toLowerCase().split('+');
    final key = parts.last;
    final hasCtrl = parts.contains('ctrl');
    final hasShift = parts.contains('shift');
    final hasAlt = parts.contains('alt');

    final LogicalKeyboardKey logicalKey;
    if (key == 'comma') {
      logicalKey = LogicalKeyboardKey.comma;
    } else if (key.length == 1) {
      logicalKey = LogicalKeyboardKey(
        LogicalKeyboardKey.keyA.keyId + key.codeUnitAt(0) - 'a'.codeUnitAt(0),
      );
    } else {
      logicalKey = LogicalKeyboardKey.keyA;
    }

    return SingleActivator(logicalKey,
        control: hasCtrl, shift: hasShift, alt: hasAlt);
  }

  // ─── חיפוש ──────────────────────────────────────────────────────────────────

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

    int? targetGimatria;
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
      targetGimatria =
          GimatriaSearch.gimatria(searchText, method: gematriaMethod);
      if (useWithKolel) {
        targetGimatria += searchText.trim().split(RegExp(r'\s+')).length;
      }
    }

    if (targetGimatria == 0) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _lastGematriaValue = targetGimatria;
      _hasSearched = true;
    });

    try {
      final libraryPath =
          Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';

      final List<String>? bookTitlesToSearch =
          torahOnly ? _tanachOrder.take(5).toList() : _tanachOrder;

      final searchPaths = torahOnly
          ? ['$libraryPath/ספרייה/תנך/תורה']
          : [
              '$libraryPath/ספרייה/תנך/תורה',
              '$libraryPath/ספרייה/תנך/נביאים',
              '$libraryPath/ספרייה/תנך/כתובים',
            ];

      final List<SearchResult> allResults = [];

      final searchResults = await GimatriaSearch.searchInFiles(
        searchPaths.first,
        targetGimatria,
        maxPhraseWords: 8,
        fileLimit: maxResults + 1,
        wholeVerseOnly: wholeVerseOnly,
        gematriaMethod: gematriaMethod,
        useWithKolel: useWithKolel,
        bookTitles: bookTitlesToSearch,
      );
      allResults.addAll(searchResults);

      if (allResults.isEmpty && searchPaths.length > 1) {
        for (int i = 1; i < searchPaths.length; i++) {
          final moreResults = await GimatriaSearch.searchInFiles(
            searchPaths[i],
            targetGimatria,
            maxPhraseWords: 8,
            fileLimit: maxResults + 1,
            wholeVerseOnly: wholeVerseOnly,
            gematriaMethod: gematriaMethod,
            useWithKolel: useWithKolel,
          );
          allResults.addAll(moreResults);
          if (allResults.length > maxResults) break;
        }
      }

      _hasMoreResults = allResults.length > maxResults;
      var finalResults = allResults.take(maxResults).toList();

      if (filterDuplicates) {
        final seen = <String>{};
        finalResults = finalResults.where((result) {
          final key = utils.removeVolwels(result.text);
          return seen.add(key);
        }).toList();
      }

      setState(() {
        _searchResults = finalResults.map((result) {
          final relativePath =
              result.file.replaceFirst(libraryPath, '').replaceAll('\\', '/');
          final fileName = relativePath.split('/').last.replaceAll('.txt', '');

          String displayPath = result.path.isNotEmpty ? result.path : fileName;
          if (result.verseNumber.isNotEmpty) {
            displayPath = '$displayPath, פסוק ${result.verseNumber}';
          } else if (result.path.isEmpty) {
            displayPath = '$displayPath, שורה ${result.line}';
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

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final contextSettingsShortcut =
        Settings.getValue<String>('key-shortcut-open-context-settings') ??
            'ctrl+shift+comma';

    return CallbackShortcuts(
      bindings: {
        _parseShortcut(contextSettingsShortcut): _toggleSettings,
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        child: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _buildSearchBar(),
                    if (_lastGematriaValue != null) _buildStatusBar(),
                    Expanded(child: _buildResultsList()),
                  ],
                ),
              ),
              GematriaSettingsPanel(
                isVisible: _showingSettings,
                onToggle: _toggleSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Search bar ──────────────────────────────────────────────────────────────

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
              hintText: 'חפש גימטריה...',
              onSubmitted: (_) => _performSearch(),
              onClear: () => setState(() {
                _searchResults = [];
                _lastGematriaValue = null;
                _hasSearched = false;
              }),
              leading: IconButton(
                icon: const Icon(FluentIcons.search_24_regular),
                onPressed: _performSearch,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          if (!_showingSettings)
            IconButton(
              icon: const Icon(FluentIcons.settings_24_regular),
              tooltip: 'הגדרות',
              onPressed: _toggleSettings,
            ),
        ],
      ),
    );
  }

  // ─── Status bar ──────────────────────────────────────────────────────────────

  Widget _buildStatusBar() {
    final resultsText = _hasMoreResults
        ? 'הוגבל ל-${_searchResults.length} תוצאות'
        : 'נמצאו ${_searchResults.length} תוצאות';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceMD - 4,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(resultsText, style: const TextStyle(fontSize: AppTokens.fontMD)),
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

  // ─── Results list ─────────────────────────────────────────────────────────────

  Widget _buildResultsList() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty && _hasSearched) {
      return _EmptyState(
        icon: FluentIcons.search_24_regular,
        message: 'לא נמצאו תוצאות',
      );
    }

    if (_searchResults.isEmpty) {
      return _EmptyState(
        icon: FluentIcons.calculator_24_regular,
        message: 'הזן ערך לחיפוש גימטריה',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) => GematriaResultCard(
        number: index + 1,
        result: _searchResults[index],
      ),
    );
  }
}

// ─── Empty state helper ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final dimColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: dimColor),
          const SizedBox(height: AppTokens.spaceMD),
          Text(
            message,
            style: TextStyle(
              fontSize: AppTokens.fontXL,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
