import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/bloc/search_state.dart';

void main() {
  group('SearchBloc facet counts', () {
    blocTest<SearchBloc, SearchState>(
      'SetSearchMode מעדכן את מצב החיפוש ומפעיל ריענון שאילתה',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(SetSearchMode(SearchMode.fuzzy)),
      expect: () => [
        isA<SearchState>().having((state) => state.configuration.searchMode,
            'searchMode', SearchMode.fuzzy),
        isA<SearchState>().having((state) => state.configuration.searchMode,
            'searchMode', SearchMode.fuzzy),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'ToggleSearchMode מעביר ממתקדם למדויק',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(ToggleSearchMode()),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.exact);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'ToggleSearchMode מעביר ממדויק למקורב',
      build: SearchBloc.new,
      seed: () => const SearchState(
        configuration: SearchConfiguration(searchMode: SearchMode.exact),
      ),
      act: (bloc) => bloc.add(ToggleSearchMode()),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.fuzzy);
        expect(bloc.state.configuration.distance, 2);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'ToggleSearchMode מעביר ממקורב למתקדם',
      build: SearchBloc.new,
      seed: () => const SearchState(
        configuration: SearchConfiguration(searchMode: SearchMode.fuzzy),
      ),
      act: (bloc) => bloc.add(ToggleSearchMode()),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.advanced);
        expect(bloc.state.configuration.distance, 0);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'SetSearchMode שומר מרחק ידני שהמשתמש בחר',
      build: SearchBloc.new,
      seed: () => const SearchState(
        configuration: SearchConfiguration(
          searchMode: SearchMode.exact,
          distance: 6,
        ),
      ),
      act: (bloc) => bloc.add(SetSearchMode(SearchMode.fuzzy)),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.fuzzy);
        expect(bloc.state.configuration.distance, 6);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'ToggleSearchMode מחליף לברירת המחדל של fuzzy רק כשלא היה מרחק ידני',
      build: SearchBloc.new,
      seed: () => const SearchState(
        configuration: SearchConfiguration(
          searchMode: SearchMode.exact,
          distance: 0,
        ),
      ),
      act: (bloc) => bloc.add(ToggleSearchMode()),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.fuzzy);
        expect(bloc.state.configuration.distance, 2);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'SetSearchMode יכול לעבור ממצב מתקדם למדויק באירוע יחיד',
      build: SearchBloc.new,
      seed: () => SearchState(
        configuration: const SearchConfiguration(
          searchMode: SearchMode.advanced,
        ),
      ),
      act: (bloc) => bloc.add(SetSearchMode(SearchMode.exact)),
      expect: () => [
        isA<SearchState>().having((state) => state.configuration.searchMode,
            'searchMode', SearchMode.exact),
        isA<SearchState>().having((state) => state.configuration.searchMode,
            'searchMode', SearchMode.exact),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'SetSearchModeWithoutSearch מעדכן מצב חיפוש בלי ריענון שאילתה',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(SetSearchModeWithoutSearch(SearchMode.fuzzy)),
      expect: () => [
        isA<SearchState>()
            .having((state) => state.configuration.searchMode, 'searchMode',
                SearchMode.fuzzy)
            .having((state) => state.configuration.distance, 'distance', 2),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'UpdateDistanceWithoutSearch מעדכן מרחק בלי ריענון שאילתה',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(UpdateDistanceWithoutSearch(4)),
      expect: () => [
        isA<SearchState>()
            .having((state) => state.configuration.distance, 'distance', 4),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'UpdateFacetCounts ממזג עדכונים נקודתיים לקאש',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(UpdateFacetCounts({'/א': 1}));
        bloc.add(UpdateFacetCounts({'/ב': 2}));
      },
      expect: () => [
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 1)
            .having((state) => state.facetCounts['/א'], '/א', 1),
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 2)
            .having((state) => state.facetCounts['/א'], '/א', 1)
            .having((state) => state.facetCounts['/ב'], '/ב', 2),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'ReplaceFacetCounts מחליף אגרגציה מלאה ומסיר מפתחות ישנים',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(UpdateFacetCounts({'/ישן': 1, '/נשאר': 2}));
        bloc.add(ReplaceFacetCounts({'/נשאר': 3}));
      },
      expect: () => [
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 2)
            .having((state) => state.facetCounts['/ישן'], '/ישן', 1)
            .having((state) => state.facetCounts['/נשאר'], '/נשאר', 2),
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 1)
            .having((state) => state.facetCounts['/ישן'], '/ישן', isNull)
            .having((state) => state.facetCounts['/נשאר'], '/נשאר', 3),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'ניקוי query מאפס גם את facetCounts',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(UpdateFacetCounts({'/א': 1}));
        bloc.add(UpdateSearchQuery(''));
      },
      expect: () => [
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 1)
            .having((state) => state.facetCounts['/א'], '/א', 1),
        isA<SearchState>()
            .having((state) => state.searchQuery, 'searchQuery', '')
            .having((state) => state.facetCounts.isEmpty, 'facetCounts empty',
                true),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'SetFacetsWithoutSearch מעדכן גם currentFacets וגם searchScopeFacets',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(const SetFacetsWithoutSearch(['/תנ"ך'])),
      expect: () => [
        isA<SearchState>().having(
            (state) => state.currentFacets, 'currentFacets', [
          '/תנ"ך'
        ]).having((state) => state.searchScopeFacets, 'searchScopeFacets', [
          '/תנ"ך'
        ]).having((state) => state.hasScopedFacetFilter, 'hasScopedFacetFilter',
            true),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'SetFacet משנה פילטר נוכחי אבל שומר על טווח החיפוש המקורי',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(const SetFacetsWithoutSearch(['/תנ"ך']));
        bloc.add(SetFacet('/תנ"ך/ראשונים'));
      },
      expect: () => [
        isA<SearchState>().having(
            (state) => state.currentFacets, 'currentFacets', [
          '/תנ"ך'
        ]).having(
            (state) => state.searchScopeFacets, 'searchScopeFacets', ['/תנ"ך']),
        isA<SearchState>().having(
            (state) => state.currentFacets, 'currentFacets', [
          '/תנ"ך/ראשונים'
        ]).having(
            (state) => state.searchScopeFacets, 'searchScopeFacets', ['/תנ"ך']),
        isA<SearchState>()
            .having((state) => state.isLoading, 'isLoading', false)
            .having((state) => state.searchQuery, 'searchQuery', '')
            .having((state) => state.currentFacets, 'currentFacets', [
          '/תנ"ך/ראשונים'
        ]).having((state) => state.searchScopeFacets, 'searchScopeFacets',
                ['/תנ"ך']),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'SetFacetsWithoutSearch עם בחירה ריקה מסמן שלא נבחרו קטגוריות',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(const SetFacetsWithoutSearch([])),
      expect: () => [
        isA<SearchState>()
            .having((state) => state.currentFacets, 'currentFacets', []).having(
                (state) => state.searchScopeFacets,
                'searchScopeFacets',
                []).having((state) => state.hasNoSelectedFacets, 'hasNoSelectedFacets', true),
      ],
    );
  });
}
