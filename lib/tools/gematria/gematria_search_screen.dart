import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:otzaria/tools/gematria/models/gematria_search_result.dart';
import 'package:otzaria/tools/gematria/widgets/gematria_result_card.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

class GematriaSearchScreen extends StatefulWidget {
  const GematriaSearchScreen({super.key});

  @override
  GematriaSearchScreenState createState() => GematriaSearchScreenState();
}

class GematriaSearchScreenState extends State<GematriaSearchScreen> {
  static const double _settingsPanelWidth = 360;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<GematriaSearchResult> _searchResults = [];
  bool _isSearching = false;
  int? _lastGematriaValue; // ערך הגימטריה האחרון שחיפשנו
  bool _hasMoreResults = false; // האם יש יותר תוצאות מהמקסימום
  bool _hasSearched = false; // האם בוצע חיפוש בפועל
  bool _showingSettings = false;

  // סדר ספרי התנ"ך
  static const List<String> _tanachOrder = [
    // תורה
    'בראשית', 'שמות', 'ויקרא', 'במדבר', 'דברים',
    // נביאים ראשונים
    'יהושע', 'שופטים', 'שמואל א', 'שמואל ב', 'מלכים א', 'מלכים ב',
    // נביאים אחרונים
    'ישעיהו', 'ירמיהו', 'יחזקאל',
    'הושע', 'יואל', 'עמוס', 'עובדיה', 'יונה', 'מיכה', 'נחום', 'חבקוק', 'צפניה',
    'חגי', 'זכריה', 'מלאכי',
    // כתובים
    'תהלים', 'משלי', 'איוב',
    'שיר השירים', 'רות', 'איכה', 'קהלת', 'אסתר',
    'דניאל', 'עזרא', 'נחמיה', 'דברי הימים א', 'דברי הימים ב',
  ];

  int _getBookOrder(String fileName) {
    // חילוץ שם הספר מהנתיב
    final bookName = fileName.replaceAll('.txt', '').trim();
    final index = _tanachOrder.indexOf(bookName);
    return index >= 0 ? index : 999; // ספרים לא מוכרים בסוף
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocusNode.requestFocus());
  }

  void requestKeyboardFocus() {
    if (!mounted || !_searchFocusNode.canRequestFocus) return;
    _searchFocusNode.requestFocus();
  }

  void closeTransientPanels() {
    if (!_showingSettings) return;
    setState(() => _showingSettings = false);
    _rerunSearchIfNeeded();
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
    super.dispose();
  }

  void _toggleSettings() {
    final wasVisible = _showingSettings;
    setState(() => _showingSettings = !_showingSettings);
    if (wasVisible) {
      _rerunSearchIfNeeded();
    }
  }

  void _rerunSearchIfNeeded() {
    if (_searchController.text.trim().isNotEmpty && _hasSearched) {
      _performSearch();
    }
  }

  void _clearResults() {
    setState(() {
      _searchResults = [];
      _lastGematriaValue = null;
      _hasSearched = false;
    });
  }

  Future<void> _performSearch() async {
    final searchText = _searchController.text.trim();

    if (searchText.isEmpty) {
      return;
    }

    // טעינת ההגדרות הבוקריות ישירות מה-Settings
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

    int? targetGimatria;

    // קביעת שיטת החישוב
    String gematriaMethod = 'regular';
    if (useSmallGematria) {
      gematriaMethod = 'small';
    } else if (useFinalLetters) {
      gematriaMethod = 'finalLetters';
    }

    // Check if input is a number
    final numericValue = int.tryParse(searchText);
    if (numericValue != null) {
      targetGimatria = numericValue;
    } else {
      // Check for invalid characters (allow Hebrew letters, final forms, spaces, and numbers)
      final validChars = RegExp(r'^[א-תםןךףץ\s0-9]+$');
      if (!validChars.hasMatch(searchText)) {
        if (mounted) {
          UiSnack.showError(
            'קלט לא תקין. יש להזין אותיות עבריות או מספרים בלבד.',
          );
        }
        return;
      }

      targetGimatria = GimatriaSearch.gimatria(
        searchText,
        method: gematriaMethod,
      );

      // הוספת הכולל - מספר המילים
      if (useWithKolel) {
        final wordCount = searchText.trim().split(RegExp(r'\s+')).length;
        targetGimatria += wordCount;
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
      // קבלת נתיב הספרייה מההגדרות
      final libraryPath =
          Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';

      // Define book titles to search based on settings
      List<String>? bookTitlesToSearch;
      if (torahOnly) {
        bookTitlesToSearch = _tanachOrder.take(5).toList(); // Torah only
      } else {
        bookTitlesToSearch = _tanachOrder; // All Tanach
      }

      // חיפוש בתיקיות ספציפיות בלבד (for fallback file search)
      final searchPaths = torahOnly
          ? ['$libraryPath/ספרייה/תנך/תורה']
          : [
              '$libraryPath/ספרייה/תנך/תורה',
              '$libraryPath/ספרייה/תנך/נביאים',
              '$libraryPath/ספרייה/תנך/כתובים',
            ];

      final List<SearchResult> allResults = [];

      // Try database search first with book titles
      final searchResults = await GimatriaSearch.searchInFiles(
        searchPaths.first, // folder parameter (used for fallback)
        targetGimatria,
        maxPhraseWords: 8,
        fileLimit: maxResults + 1, // מבקשים אחד יותר כדי לדעת אם יש עוד
        wholeVerseOnly: wholeVerseOnly,
        gematriaMethod: gematriaMethod,
        useWithKolel: useWithKolel,
        bookTitles: bookTitlesToSearch,
      );
      allResults.addAll(searchResults);

      // If database search didn't work, try other paths (fallback)
      if (allResults.isEmpty && searchPaths.length > 1) {
        for (int i = 1; i < searchPaths.length; i++) {
          final path = searchPaths[i];
          final moreResults = await GimatriaSearch.searchInFiles(
            path,
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

      // בדיקה אם יש יותר תוצאות מהמקסימום
      _hasMoreResults = allResults.length > maxResults;
      var finalResults = allResults.take(maxResults).toList();

      // סינון כפילויות אם נדרש
      if (filterDuplicates) {
        final seen = <String>{};
        finalResults = finalResults.where((result) {
          // הסרת ניקוד וטעמים לפני השוואה
          final key = utils.removeVolwels(result.text);
          if (seen.contains(key)) {
            return false;
          }
          seen.add(key);
          return true;
        }).toList();
      }

      // המרת התוצאות לפורמט של המסך
      setState(() {
        _searchResults = finalResults.map((result) {
          // חילוץ שם הקובץ
          final relativePath =
              result.file.replaceFirst(libraryPath, '').replaceAll('\\', '/');
          final fileName = relativePath.split('/').last.replaceAll('.txt', '');

          // בניית הנתיב עם מספר הפסוק
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

        // מיון התוצאות לפי סדר התנ"ך
        _searchResults.sort((a, b) {
          final aOrder = _getBookOrder(a.bookTitle);
          final bOrder = _getBookOrder(b.bookTitle);
          if (aOrder != bOrder) {
            return aOrder.compareTo(bOrder);
          }
          // אם אותו ספר, מיין לפי מספר השורה
          final aResult = a.data;
          final bResult = b.data;
          return aResult.line.compareTo(bResult.line);
        });

        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      UiSnack.showError('שגיאה בחיפוש: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const SingleActivator(LogicalKeyboardKey.keyF,
                control: true): () {
          _searchFocusNode.requestFocus();
        },
      },
      child: Column(
        children: [
          BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) => AppTopBar(
              center: OtzariaSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: 'חפש גימטריה...',
                autofocus: true,
                onSubmitted: (_) => _performSearch(),
                onClear: _clearResults,
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
                    tooltip: 'הגדרות גימטריה',
                    icon: FluentIcons.settings_24_regular,
                    selected: _showingSettings,
                    onPressed: _toggleSettings,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildResultsContent()),
                Positioned.fill(
                  child: _buildSettingsOverlay(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final resultsText = _hasMoreResults
        ? 'הוגבל ל-${_searchResults.length} תוצאות'
        : 'נמצאו ${_searchResults.length} תוצאות';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          Text(
            resultsText,
            style: const TextStyle(
              fontSize: 14,
            ),
          ),
          Text(
            'ערך גימטריה: $_lastGematriaValue',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsContent() {
    return ToolPanelWrapper(
      child: Column(
        children: [
          if (_lastGematriaValue != null) _buildStatusBar(),
          Expanded(child: _buildResultsList()),
        ],
      ),
    );
  }

  Widget _buildSettingsOverlay() {
    return ContextOverlayPanel(
      isOpen: _showingSettings,
      onClose: _toggleSettings,
      width: _settingsPanelWidth,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  'הגדרות',
                  textDirection: TextDirection.rtl,
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
    );
  }

  Widget _buildResultsList() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty && _hasSearched) {
      return const ToolEmptyState(
        icon: FluentIcons.search_24_regular,
        message: 'לא נמצאו תוצאות',
      );
    }

    if (_searchResults.isEmpty) {
      return const ToolEmptyState(
        icon: FluentIcons.calculator_24_regular,
        message: 'הזן ערך לחיפוש גימטריה',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return GematriaResultCard(
          number: index + 1,
          result: _searchResults[index],
        );
      },
    );
  }
}
