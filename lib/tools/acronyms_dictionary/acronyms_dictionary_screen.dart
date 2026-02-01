import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'dart:convert';

class AcronymsDictionaryScreen extends StatefulWidget {
  const AcronymsDictionaryScreen({super.key});

  @override
  State<AcronymsDictionaryScreen> createState() =>
      _AcronymsDictionaryScreenState();
}

class _AcronymsDictionaryScreenState extends State<AcronymsDictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  Map<String, List<String>> _dictionaryData = {};
  List<MapEntry<String, List<String>>> _filteredResults = [];
  bool _isLoading = true;

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
          await rootBundle.loadString('assets/Acronyms.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      if (!mounted) return;

      setState(() {
        _dictionaryData = jsonData.map((key, value) {
          if (value is List) {
            return MapEntry(key, value.cast<String>());
          }
          return MapEntry(key, <String>[]);
        });
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
      _filteredResults = _dictionaryData.entries
          .where((entry) =>
              entry.key.contains(query) ||
              entry.value.any((meaning) => meaning.contains(query)))
          .toList();
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
                hintText: 'חפש ראשי תיבות...',
                labelText: 'הזן ראשי תיבות או פירוש',
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

  Widget _buildResultsList() {
    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.text_quote_24_regular,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'הזן ראשי תיבות לחיפוש במילון',
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

  Widget _buildResultCard(MapEntry<String, List<String>> entry) {
    final acronym = entry.key;
    final meanings = entry.value;

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
                    'ראשי תיבות:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    acronym,
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
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'פירוש:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...meanings.asMap().entries.map((meaningEntry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        meanings.length > 1
                            ? '${meaningEntry.key + 1}. ${meaningEntry.value}'
                            : meaningEntry.value,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
