import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'dart:convert';

class AramaicDictionaryScreen extends StatefulWidget {
  const AramaicDictionaryScreen({super.key});

  @override
  State<AramaicDictionaryScreen> createState() =>
      _AramaicDictionaryScreenState();
}

class _AramaicDictionaryScreenState extends State<AramaicDictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _dictionaryData = [];
  List<Map<String, String>> _filteredResults = [];
  bool _isLoading = true;
  bool _isHebrewToAramaic =
      true; // כיוון התרגום: true = עברית->ארמית, false = ארמית->עברית

  @override
  void initState() {
    super.initState();
    _loadDictionary();
    _searchController.addListener(_performSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDictionary() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/dictionary.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // המילון נמצא תחת המפתח "מילון פשיטא"
      final List<dynamic> entries = jsonData['מילון פשיטא'] ?? [];

      setState(() {
        _dictionaryData = entries
            .map((entry) {
              if (entry is Map<String, dynamic>) {
                // כל רשומה היא מפה עם מפתח אחד (ארמית) וערך אחד (עברית)
                final aramaic = entry.keys.first;
                final hebrew = entry[aramaic].toString();
                return {'aramaic': aramaic, 'hebrew': hebrew};
              }
              return <String, String>{};
            })
            .where((entry) => entry.isNotEmpty)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        UiSnack.show('שגיאה בטעינת המילון: $e');
      }
    }
  }

  void _performSearch() {
    final query = _searchController.text.trim();

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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          _buildSearchBar(),
          _buildDirectionToggle(),
          Expanded(child: _buildResultsList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 8.0),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: RtlTextField(
              controller: _searchController,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: _isHebrewToAramaic
                    ? 'חפש מילה בעברית...'
                    : 'חפש מילה בארמית...',
                labelText:
                    _isHebrewToAramaic ? 'הזן מילה בעברית' : 'הזן מילה בארמית',
                prefixIcon: Icon(
                  FluentIcons.search_24_regular,
                  color: Theme.of(context).colorScheme.primary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'נקה',
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'עברית',
            style: TextStyle(
              fontSize: 16,
              fontWeight:
                  _isHebrewToAramaic ? FontWeight.bold : FontWeight.normal,
              color: _isHebrewToAramaic
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(
              _isHebrewToAramaic
                  ? FluentIcons.arrow_left_24_regular
                  : FluentIcons.arrow_right_24_regular,
            ),
            onPressed: _toggleDirection,
            tooltip: 'החלף כיוון',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'ארמית',
            style: TextStyle(
              fontSize: 16,
              fontWeight:
                  !_isHebrewToAramaic ? FontWeight.bold : FontWeight.normal,
              color: !_isHebrewToAramaic
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.book_24_regular,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'הזן מילה לחיפוש במילון',
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

    if (_filteredResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.search_24_regular,
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) {
        return _buildResultCard(_filteredResults[index]);
      },
    );
  }

  Widget _buildResultCard(Map<String, String> entry) {
    final aramaic = entry['aramaic']!;
    final hebrew = entry['hebrew']!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isHebrewToAramaic ? 'עברית:' : 'ארמית:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isHebrewToAramaic ? hebrew : aramaic,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Icon(
                _isHebrewToAramaic
                    ? FluentIcons.arrow_left_24_filled
                    : FluentIcons.arrow_right_24_filled,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isHebrewToAramaic ? 'ארמית:' : 'עברית:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isHebrewToAramaic ? aramaic : hebrew,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
