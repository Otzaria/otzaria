import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../helpers/memory_settings_cache.dart';
import '../support/recording_search_engine.dart';
import '../support/search_engine_test_init.dart';

/// רגרסיה: חיפוש-מחדש פנימי (מיון/קיבוץ/היקף) חייב לשאת את האפשרויות
/// פר-מילה. "ניקוד" מעביר את המנוע לשדה המנוקד, ובלעדיו תוצאות התנ"ך
/// (הטקסט המנוקד בספרייה) נושרות.
Future<void> main() async {
  // sanitizeQuery מאציל למנוע ה-Rust הנייטיבי.
  final engineReady = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  const query = 'בראשית ברא';
  const nikudOptions = {
    'בראשית_0': {'ניקוד': true},
  };
  const spacing = {'0-1': '3'};
  const alternatives = {
    1: ['יצר'],
  };
  const negativeOptions = {
    'תוהו_0': {'טעמים': true},
  };

  late RecordingSearchEngine engine;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  SearchBloc buildBloc() {
    engine = RecordingSearchEngine();
    return SearchBloc(
      initialConfiguration: const SearchConfiguration(currentFacets: ['/']),
      repository: SearchRepository(engineProvider: () async => engine),
    );
  }

  /// מריץ חיפוש משתמש מלא ואז את [settingsChange], ומחזיר את הבקשה
  /// האחרונה שהגיעה למנוע.
  Future<SearchEngineRequest> requestAfter(
    SearchEvent settingsChange, {
    String negativeQuery = '',
  }) async {
    final bloc = buildBloc();
    bloc.add(
      UpdateSearchQuery(
        query,
        negativeQuery: negativeQuery,
        searchOptions: nikudOptions,
        customSpacing: spacing,
        alternativeWords: alternatives,
        negativeSearchOptions: negativeQuery.isEmpty ? null : negativeOptions,
      ),
    );
    await bloc.stream.firstWhere((state) => !state.isLoading);

    bloc.add(settingsChange);
    await bloc.stream.firstWhere((state) => !state.isLoading);
    await bloc.close();
    return engine.lastRequest!;
  }

  group(
    'חיפוש-מחדש פנימי משמר את האפשרויות המתקדמות',
    () {
      test('החיפוש הראשוני מעביר את האפשרויות למנוע', () async {
        final request = await requestAfter(UpdateNumResults(200));
        expect(request.searchOptions, nikudOptions);
      });

      test('שינוי סדר המיון אינו מאבד את אפשרויות הניקוד', () async {
        final request = await requestAfter(
          UpdateSortOrder(ResultsOrder.generation),
        );

        expect(request.order, ResultsOrder.generation);
        expect(request.searchOptions, nikudOptions);
        expect(request.customSpacing, spacing);
        expect(request.alternativeWords, alternatives);
      });

      test('שינוי קיבוץ התוצאות אינו מאבד את האפשרויות', () async {
        final request = await requestAfter(
          UpdateResultGrouping(ResultGroupingMode.sameSection),
        );

        expect(request.searchOptions, nikudOptions);
      });

      // צמצום היקף עם תוצאות מלאות ביד מסונן מקומית ואינו פונה למנוע, ולכן
      // נמדד כאן המיון שאחריו — הוא זה שחייב לשאת את האפשרויות.
      test('צמצום היקף ואחריו מיון אינם מאבדים את האפשרויות', () async {
        final bloc = buildBloc();
        bloc.add(
          UpdateSearchQuery(
            query,
            searchOptions: nikudOptions,
            customSpacing: spacing,
          ),
        );
        await bloc.stream.firstWhere((state) => !state.isLoading);

        bloc.add(AddFacet('/תנך'));
        await bloc.stream.firstWhere((state) => !state.isLoading);
        expect(bloc.state.currentFacets, contains('/תנך'));

        bloc.add(UpdateSortOrder(ResultsOrder.catalogue));
        await bloc.stream.firstWhere((state) => !state.isLoading);
        await bloc.close();

        expect(engine.lastRequest!.facets, contains('/תנך'));
        expect(engine.lastRequest!.searchOptions, nikudOptions);
        expect(engine.lastRequest!.customSpacing, spacing);
      });

      test('הפרמטרים השליליים שורדים לחיצת קטגוריה ואחריה מיון', () async {
        final bloc = buildBloc();
        bloc.add(
          UpdateSearchQuery(
            query,
            negativeQuery: 'תוהו',
            searchOptions: nikudOptions,
            negativeSearchOptions: negativeOptions,
          ),
        );
        await bloc.stream.firstWhere((state) => !state.isLoading);

        // SetFacet נושא רק את הפרמטרים החיוביים — השליליים חייבים להישמר.
        bloc.add(SetFacet('/תנך', searchOptions: nikudOptions));
        await bloc.stream.firstWhere((state) => !state.isLoading);

        bloc.add(UpdateSortOrder(ResultsOrder.catalogue));
        await bloc.stream.firstWhere((state) => !state.isLoading);
        await bloc.close();

        expect(engine.lastRequest!.searchOptions, nikudOptions);
        expect(engine.lastRequest!.negativeSearchOptions, negativeOptions);
      });

      test('איפוס החיפוש אינו מדליף אפשרויות לחיפוש הבא', () async {
        final bloc = buildBloc();
        bloc.add(UpdateSearchQuery(query, searchOptions: nikudOptions));
        await bloc.stream.firstWhere((state) => !state.isLoading);

        bloc.add(ResetSearch());
        bloc.add(
          UpdateSearchQuery(
            'שמות',
            // חיפוש נקי, בלי אפשרויות.
          ),
        );
        await bloc.stream.firstWhere((state) => !state.isLoading);
        await bloc.close();

        expect(engine.lastRequest!.searchOptions, isEmpty);
      });

      test('חיפוש שנעצר בהיעדר היקף אינו מדליף אפשרויות לחיפוש הבא', () async {
        final bloc = SearchBloc(
          initialConfiguration: const SearchConfiguration(currentFacets: []),
          repository: SearchRepository(
            engineProvider: () async => engine = RecordingSearchEngine(),
          ),
        );
        bloc.add(UpdateSearchQuery(query, searchOptions: nikudOptions));
        await bloc.stream.first;

        bloc.add(SetFacetsWithoutSearch(const ['/']));
        bloc.add(UpdateSearchQuery('שמות'));
        await bloc.stream.firstWhere((state) => !state.isLoading);
        await bloc.close();

        expect(engine.lastRequest!.searchOptions, isEmpty);
      });
    },
    skip: engineReady ? null : searchEngineSkipReason,
  );
}
