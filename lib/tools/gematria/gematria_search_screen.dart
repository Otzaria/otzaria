import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'gematria_search.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/open_book.dart';

class GematriaSearchScreen extends StatefulWidget {
  const GematriaSearchScreen({super.key});

  @override
  GematriaSearchScreenState createState() => GematriaSearchScreenState();
}

class GematriaSearchScreenState extends State<GematriaSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<GematriaSearchResult> _searchResults = [];
  bool _isSearching = false;
  int _maxResults = 100; // ברירת מחדל
  int? _lastGematriaValue; // ערך הגימטריה האחרון שחיפשנו
  bool _filterDuplicates = false; // סינון תוצאות כפולות
  bool _wholeVerseOnly = false; // חיפוש פסוק שלם בלבד

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final searchText = _searchController.text.trim();
    if (searchText.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    try {
      // חישוב הגימטריה של הטקסט שהוזן
      final targetGimatria = GimatriaSearch.gimatria(searchText);
      _lastGematriaValue = targetGimatria;

      // קבלת נתיב הספרייה מההגדרות
      final libraryPath = Settings.getValue<String>('key-library-path') ?? '.';

      // חיפוש בתיקיות ספציפיות בלבד: תנך/תורה, תנך/נביאים, תנך/כתובים
      final searchPaths = [
        '$libraryPath/אוצריא/תנך/תורה',
        '$libraryPath/אוצריא/תנך/נביאים',
        '$libraryPath/אוצריא/תנך/כתובים',
      ];

      final List<SearchResult> allResults = [];
      for (final path in searchPaths) {
        final results = await GimatriaSearch.searchInFiles(
          path,
          targetGimatria,
          maxPhraseWords: 8,
          fileLimit: _maxResults,
          wholeVerseOnly: _wholeVerseOnly,
        );
        allResults.addAll(results);
        if (allResults.length >= _maxResults) break;
      }

      var results = allResults.take(_maxResults).toList();

      // סינון כפילויות אם נדרש
      if (_filterDuplicates) {
        final seen = <String>{};
        results = results.where((result) {
          final key = result.text;
          if (seen.contains(key)) {
            return false;
          }
          seen.add(key);
          return true;
        }).toList();
      }

      // המרת התוצאות לפורמט של המסך
      setState(() {
        _searchResults = results.map((result) {
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
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בחיפוש: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildSearchBar(),
          if (_lastGematriaValue != null) _buildStatusBar(),
          Expanded(
            child: _buildResultsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
            'נמצאו ${_searchResults.length} תוצאות',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'ערך גימטריה: $_lastGematriaValue',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('הגדרות חיפוש', textAlign: TextAlign.right),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: Text('מספר תוצאות מקסימלי:'),
              ),
              const SizedBox(height: 8),
              DropdownButton<int>(
                value: _maxResults,
                isExpanded: true,
                items: [50, 100, 200, 500, 1000].map((value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('$value'),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _maxResults = value;
                    });
                    setDialogState(() {});
                  }
                },
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text(
                  'סינון תוצאות כפולות',
                  textAlign: TextAlign.right,
                ),
                value: _filterDuplicates,
                onChanged: (value) {
                  setState(() {
                    _filterDuplicates = value ?? false;
                  });
                  setDialogState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text(
                  'חיפוש פסוק שלם בלבד',
                  textAlign: TextAlign.right,
                ),
                value: _wholeVerseOnly,
                onChanged: (value) {
                  setState(() {
                    _wholeVerseOnly = value ?? false;
                  });
                  setDialogState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: 'חפש גימטריה...',
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          prefixIcon: IconButton(
            icon: const Icon(Icons.search),
            onPressed: _performSearch,
            color: Theme.of(context).colorScheme.primary,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                      _lastGematriaValue = null;
                    });
                  },
                )
              : null,
        ),
        onSubmitted: (_) => _performSearch(),
      ),
    );
  }

  Widget _buildResultsList() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'לא נמצאו תוצאות',
              style: TextStyle(
                fontSize: 18,
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

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calculate_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'הזן ערך לחיפוש גימטריה',
              style: TextStyle(
                fontSize: 18,
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildResultCard(index + 1, _searchResults[index]);
      },
    );
  }

  Widget _buildResultCard(int number, GematriaSearchResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          final book = TextBook(title: result.bookTitle);
          final index = result.data.line - 1;
          final searchQuery = result.preview;
          openBook(context, book, index, searchQuery, ignoreHistory: true);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // מספר התוצאה
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // תוכן התוצאה
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // נתיב (כותרות) - אם קיים, אחרת שם הקובץ
                    Text(
                      result.internalPath.isNotEmpty
                          ? result.internalPath
                          : result.bookTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // המילים שנמצאו - בולטות
                    if (result.preview.isNotEmpty)
                      Text(
                        result.preview,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.right,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GematriaSearchResult {
  final String bookTitle;
  final String internalPath;
  final String preview;
  final dynamic data; // מידע נוסף שתרצה לשמור

  GematriaSearchResult({
    required this.bookTitle,
    required this.internalPath,
    this.preview = '',
    this.data,
  });
}
