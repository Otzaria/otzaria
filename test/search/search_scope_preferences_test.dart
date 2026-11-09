import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_scope_preferences.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchScopePreferences', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    test('שומר ומחזיר מצב של חיפוש בכל הקטגוריות', () async {
      await SearchScopePreferences.save(
        searchAllCategories: true,
        manualFacets: {'/תנ"ך', '/הלכה/שולחן ערוך'},
      );

      final loaded = SearchScopePreferences.load();

      expect(loaded.searchAllCategories, isTrue);
      expect(
        loaded.manualFacets,
        {'/תנ"ך', '/הלכה/שולחן ערוך'},
      );
    });

    test('מסנן ערכים לא תקינים ושומר facets מנורמלים בלבד', () async {
      await Settings.setValue<String>(
        'key-search-manual-category-facets',
        '["", "/", "תנך", "//הלכה///שוע"]',
      );
      await Settings.setValue<bool>(
        'key-search-all-categories-enabled',
        false,
      );

      final loaded = SearchScopePreferences.load();

      expect(loaded.searchAllCategories, isFalse);
      expect(loaded.manualFacets, {'/תנך', '/הלכה/שוע'});
    });

    test(
      'שומר מצב של תחום חיפוש ידני ריק בלי להדליק את כל הקטגוריות',
      () async {
        await SearchScopePreferences.save(
          searchAllCategories: false,
          manualFacets: const {},
        );

        final loaded = SearchScopePreferences.load();

        expect(loaded.searchAllCategories, isFalse);
        expect(loaded.manualFacets, isEmpty);
      },
    );

    test('טוען מצב persisted של תחום ידני ריק כפי שנשמר', () async {
      await Settings.setValue<bool>('key-search-all-categories-enabled', false);
      await Settings.setValue<String>(
        'key-search-manual-category-facets',
        '[]',
      );

      final loaded = SearchScopePreferences.load();

      expect(loaded.searchAllCategories, isFalse);
      expect(loaded.manualFacets, isEmpty);
    });

    test('מטפל ב-payload חוקי שאינו רשימה בלי לשנות את מצב הסוויץ׳', () async {
      await Settings.setValue<bool>('key-search-all-categories-enabled', false);
      await Settings.setValue<String>(
        'key-search-manual-category-facets',
        '{"unexpected":true}',
      );

      final loaded = SearchScopePreferences.load();

      expect(loaded.searchAllCategories, isFalse);
      expect(loaded.manualFacets, isEmpty);
    });

    group('היקפים שמורים (issue #1083)', () {
      test('שמירה וטעינה משמרות שם, facets וסדר', () async {
        await SearchScopePreferences.addSavedScope('ראשונים וקבלה', {
          '/ראשונים',
          '/קבלה',
          '/era/אחרונים',
        });
        await SearchScopePreferences.addSavedScope('תורה', {'/תנ"ך/תורה'});

        final loaded = SearchScopePreferences.loadSavedScopes();

        expect(loaded.map((s) => s.name), ['ראשונים וקבלה', 'תורה']);
        expect(loaded.first.facets, {'/ראשונים', '/קבלה', '/era/אחרונים'});
      });

      test('שם קיים מוחלף במקומו ולא נוסף שוב', () async {
        await SearchScopePreferences.addSavedScope('א', {'/x'});
        await SearchScopePreferences.addSavedScope('ב', {'/y'});
        await SearchScopePreferences.addSavedScope(' א ', {'/z'});

        final loaded = SearchScopePreferences.loadSavedScopes();

        expect(loaded.map((s) => s.name), ['א', 'ב']);
        expect(loaded.first.facets, {'/z'});
      });

      test('מחיקה מסירה רק את ההיקף בשם הנתון', () async {
        await SearchScopePreferences.addSavedScope('א', {'/x'});
        await SearchScopePreferences.addSavedScope('ב', {'/y'});

        final next = await SearchScopePreferences.removeSavedScope('א');

        expect(next.map((s) => s.name), ['ב']);
        expect(
          SearchScopePreferences.loadSavedScopes().map((s) => s.name),
          ['ב'],
        );
      });

      test('JSON פגום או רשומות חסרות-שם מדולגים', () async {
        await Settings.setValue<String>(
          'key-search-saved-scopes',
          '[{"name":"","facets":["/x"]},{"name":"טוב","facets":["/y",3]},'
              '{"facets":["/z"]},"garbage"]',
        );
        final loaded = SearchScopePreferences.loadSavedScopes();
        expect(loaded.map((s) => s.name), ['טוב']);
        expect(loaded.single.facets, {'/y'});

        await Settings.setValue<String>('key-search-saved-scopes', '{not json');
        expect(SearchScopePreferences.loadSavedScopes(), isEmpty);
      });
    });
  });
}
