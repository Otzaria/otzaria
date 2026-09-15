import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/search/utils/facet_helper.dart';

class SearchScopePreferencesData {
  final bool searchAllCategories;
  final Set<String> manualFacets;

  const SearchScopePreferencesData({
    required this.searchAllCategories,
    required this.manualFacets,
  });
}

/// היקף חיפוש שהמשתמש שמר בשם — צירוף facets (קטגוריות, ספרים וממדים).
class SavedSearchScope {
  final String name;
  final Set<String> facets;

  const SavedSearchScope({required this.name, required this.facets});
}

class SearchScopePreferences {
  static const String _searchAllKey = 'key-search-all-categories-enabled';
  static const String _manualFacetsKey = 'key-search-manual-category-facets';
  static const String _dimensionFacetsKey = 'key-search-dimension-facets';
  static const String _savedScopesKey = 'key-search-saved-scopes';

  SearchScopePreferences._();

  static SearchScopePreferencesData load() {
    final searchAll = Settings.getValue<bool>(_searchAllKey) ?? true;
    final rawManualFacets = Settings.getValue<String>(_manualFacetsKey);

    if (rawManualFacets == null || rawManualFacets.trim().isEmpty) {
      return _canonicalize(
        searchAllCategories: searchAll,
        manualFacets: const {},
      );
    }

    try {
      final decoded = jsonDecode(rawManualFacets);
      if (decoded is! List) {
        return _canonicalize(
          searchAllCategories: searchAll,
          manualFacets: const {},
        );
      }

      final facets = decoded
          .whereType<String>()
          .map(_normalizeFacet)
          .where((facet) => facet.isNotEmpty && facet != '/')
          .toSet();

      return _canonicalize(
        searchAllCategories: searchAll,
        manualFacets: facets,
      );
    } catch (e) {
      // JSON פגום מאפס רק את ה-facets — לא את העדפת 'חפש בהכל' שנקראה
      debugPrint('[SearchScope] manual facets JSON parse failed: $e');
      return _canonicalize(
        searchAllCategories: searchAll,
        manualFacets: const {},
      );
    }
  }

  static Future<void> save({
    required bool searchAllCategories,
    required Set<String> manualFacets,
  }) async {
    final normalized =
        manualFacets
            .map(_normalizeFacet)
            .where((facet) => facet.isNotEmpty && facet != '/')
            .toList()
          ..sort();

    final canonicalized = _canonicalize(
      searchAllCategories: searchAllCategories,
      manualFacets: normalized.toSet(),
    );

    await Settings.setValue<bool>(
      _searchAllKey,
      canonicalized.searchAllCategories,
    );
    await Settings.setValue<String>(
      _manualFacetsKey,
      jsonEncode(canonicalized.manualFacets.toList()..sort()),
    );
  }

  /// ה-facets הממדיים השמורים (`/base`, `/era/<שם>`, `/author/<שם>`).
  /// נשמרים תחת מפתח נפרד מבחירת הקטגוריות הידנית, כדי שעץ הקטגוריות
  /// והממדים לא יזהמו זה את זה.
  static Set<String> loadDimensionFacets() {
    final String? raw;
    try {
      raw = Settings.getValue<String>(_dimensionFacetsKey);
    } catch (e) {
      // Settings לא אותחל (בדיקות ווידג'ט / אתחול מוקדם) — אין העדפות.
      debugPrint('[SearchScope] settings unavailable for dimensions: $e');
      return const {};
    }
    if (raw == null || raw.trim().isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const {};
      }
      return decoded
          .whereType<String>()
          .map((facet) => facet.trim())
          .where(FacetHelper.isDimensionFacet)
          .toSet();
    } catch (e) {
      debugPrint('[SearchScope] dimension facets JSON parse failed: $e');
      return const {};
    }
  }

  static Future<void> saveDimensionFacets(Set<String> facets) async {
    final normalized =
        facets
            .map((facet) => facet.trim())
            .where(FacetHelper.isDimensionFacet)
            .toList()
          ..sort();
    try {
      await Settings.setValue<String>(
        _dimensionFacetsKey,
        jsonEncode(normalized),
      );
    } catch (e) {
      // Settings לא אותחל (בדיקות ווידג'ט) — ההעדפה פשוט לא תישמר.
      debugPrint(
        '[SearchScope] settings unavailable, dimensions not saved: $e',
      );
    }
  }

  /// ההיקפים השמורים בשם, בסדר שבו נשמרו.
  static List<SavedSearchScope> loadSavedScopes() {
    final String? raw;
    try {
      raw = Settings.getValue<String>(_savedScopesKey);
    } catch (e) {
      debugPrint('[SearchScope] settings unavailable for saved scopes: $e');
      return const [];
    }
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map &&
              entry['name'] is String &&
              (entry['name'] as String).trim().isNotEmpty &&
              entry['facets'] is List)
            SavedSearchScope(
              name: (entry['name'] as String).trim(),
              facets: (entry['facets'] as List)
                  .whereType<String>()
                  .map((f) => f.trim())
                  .where((f) => f.isNotEmpty)
                  .toSet(),
            ),
      ];
    } catch (e) {
      debugPrint('[SearchScope] saved scopes JSON parse failed: $e');
      return const [];
    }
  }

  static Future<void> saveSavedScopes(List<SavedSearchScope> scopes) async {
    final encoded = jsonEncode([
      for (final scope in scopes)
        {'name': scope.name, 'facets': scope.facets.toList()..sort()},
    ]);
    try {
      await Settings.setValue<String>(_savedScopesKey, encoded);
    } catch (e) {
      debugPrint('[SearchScope] settings unavailable, scopes not saved: $e');
    }
  }

  /// שומר את [facets] בשם [name]; שם קיים מוחלף במקומו.
  static Future<List<SavedSearchScope>> addSavedScope(
    String name,
    Set<String> facets,
  ) async {
    final trimmed = name.trim();
    final scope = SavedSearchScope(name: trimmed, facets: Set.of(facets));
    final current = loadSavedScopes();
    final index = current.indexWhere((s) => s.name == trimmed);
    final next = [...current];
    if (index >= 0) {
      next[index] = scope;
    } else {
      next.add(scope);
    }
    await saveSavedScopes(next);
    return next;
  }

  static Future<List<SavedSearchScope>> removeSavedScope(String name) async {
    final next = [
      for (final s in loadSavedScopes())
        if (s.name != name) s,
    ];
    await saveSavedScopes(next);
    return next;
  }

  static SearchScopePreferencesData _canonicalize({
    required bool searchAllCategories,
    required Set<String> manualFacets,
  }) {
    return SearchScopePreferencesData(
      searchAllCategories: searchAllCategories,
      manualFacets: manualFacets,
    );
  }

  static String _normalizeFacet(String facet) {
    final trimmed = facet.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final normalized = trimmed.replaceAll(RegExp(r'/+'), '/');
    if (normalized == '/') {
      return '/';
    }

    return normalized.startsWith('/') ? normalized : '/$normalized';
  }
}
