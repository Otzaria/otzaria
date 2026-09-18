import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

/// לחיצה על ספר בעץ סינון התוצאות מצמצמת בצד הלקוח, בלי חיפוש מנוע נוסף.
/// זיהוי הספר של תוצאה הוא לפי `filePath` — המפתח היציב של האינדקס — ולא לפי
/// הסדר הקטלוגי שבמזהה המסמך, שזז כשספרים נוספו/נמחקו מאז האינדוקס.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  const query = 'שיעור הילוך מיל';
  const dorFacet = '/הלכה/מחברי זמננו/id:5869';
  const beitShearimFacet = '/שו״ת/אחרונים/id:6234';
  const pdfPath = r'C:\books\beit-shearim.pdf';

  late TextBook dorHamlaktim;
  late TextBook beitShearim;
  late PdfBook beitShearimPdf;
  late TextBook officialShabbat;
  late TextBook personalShabbat;
  late Library library;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    dorHamlaktim = TextBook(
      id: 5869,
      title: 'דור המלקטים על אורח חיים',
      categoryPath: 'הלכה, מחברי זמננו',
    );
    beitShearim = TextBook(
      id: 6234,
      title: 'בית שערים אורח חיים',
      categoryPath: 'שו״ת, אחרונים',
    );
    beitShearimPdf = PdfBook(
      title: 'בית שערים',
      path: pdfPath,
      categoryPath: 'שו״ת, אחרונים',
    );
    officialShabbat = TextBook(id: 5, title: 'שבת', categoryPath: 'הלכה');
    personalShabbat = TextBook(
      id: 5,
      title: 'שבת',
      categoryPath: 'הלכה',
      source: BookSource.user,
    );

    library = Library(categories: const []);
    library.books.addAll([
      dorHamlaktim,
      beitShearim,
      beitShearimPdf,
      officialShabbat,
      personalShabbat,
    ]);
    DataRepository.instance.library = Future.value(library);
  });

  /// מסמן שהעץ נבנה על החיפוש הנוכחי (ספירות + חתימה), ואז שולח את האירוע
  /// שהלחיצה בחלונית הסינון מייצרת.
  Future<void> Function(SearchBloc) clickFacet(
    String facet, {
    String? signatureOverride,
    Map<String, int>? treeCounts,
    SearchEvent Function(String facet)? eventBuilder,
  }) {
    return (bloc) async {
      bloc.add(
        ReplaceFacetCounts(
          treeCounts ?? {'/': 2, facet: 1},
          requestId: 0,
          signature:
              signatureOverride ??
              bloc.facetRecountSignatureForTesting(UpdateSearchQuery(query)),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // בלי החתימה כל לחיצה הייתה נופלת למנוע, וטסטי הצמצום היו "עוברים"
      // בלי לבדוק את הצמצום עצמו.
      expect(bloc.facetCountsSignatureForTesting, isNotNull);
      bloc.add((eventBuilder ?? SetFacet.new)(facet));
      await Future<void>.delayed(Duration.zero);
    };
  }

  SearchState seededState({
    required List<SearchResult> results,
    List<String> currentFacets = const ['/'],
    int numResults = 100,
    ResultGroupingMode grouping = ResultGroupingMode.none,
  }) {
    return SearchState(
      searchQuery: query,
      results: results,
      totalResults: results.length,
      configuration: SearchConfiguration(
        currentFacets: currentFacets,
        searchScopeFacets: const ['/'],
        numResults: numResults,
        resultGrouping: grouping,
      ),
    );
  }

  int streamCallsOf(SearchBloc bloc) =>
      (bloc.repositoryForTesting as _RecordingSearchRepository).streamCalls;

  group('צמצום מקומי בלחיצה על ספר בעץ התוצאות', () {
    blocTest<SearchBloc, SearchState>(
      'מזהה את הספר לפי המפתח היציב גם כשהסדר הקטלוגי שבמזהה המסמך זז',
      build: () => SearchBloc(repository: _RecordingSearchRepository()),
      seed: () => seededState(
        results: [
          _result(book: dorHamlaktim, staleCatalogueOrder: 1, segment: 51538),
          _result(book: beitShearim, staleCatalogueOrder: 0, segment: 431),
        ],
      ),
      act: clickFacet(beitShearimFacet),
      verify: (bloc) {
        expect(
          bloc.state.results.map((result) => result.filePath),
          ['id:6234'],
          reason: 'התוצאה של בית שערים חייבת להישאר',
        );
        expect(bloc.state.totalResults, 1);
        expect(bloc.state.currentFacets, [beitShearimFacet]);
        expect(bloc.state.isLoading, isFalse);
        expect(
          streamCallsOf(bloc),
          0,
          reason: 'צמצום מקומי אינו פונה למנוע',
        );
      },
    );

    blocTest<SearchBloc, SearchState>(
      'לחיצה על הספר השני מצמצמת אליו, ולא לשכנו בסדר הקטלוגי',
      build: () => SearchBloc(repository: _RecordingSearchRepository()),
      seed: () => seededState(
        results: [
          _result(book: dorHamlaktim, staleCatalogueOrder: 1, segment: 51538),
          _result(book: beitShearim, staleCatalogueOrder: 0, segment: 431),
        ],
      ),
      act: clickFacet(dorFacet),
      verify: (bloc) {
        expect(bloc.state.results.map((result) => result.filePath), [
          'id:5869',
        ]);
        expect(bloc.state.currentFacets, [dorFacet]);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'כמה הופעות באותו ספר נשמרות יחד',
      build: () => SearchBloc(repository: _RecordingSearchRepository()),
      seed: () => seededState(
        results: [
          _result(book: dorHamlaktim, staleCatalogueOrder: 7, segment: 40578),
          _result(book: dorHamlaktim, staleCatalogueOrder: 7, segment: 51538),
          _result(book: beitShearim, staleCatalogueOrder: 8, segment: 431),
        ],
      ),
      act: clickFacet(dorFacet),
      verify: (bloc) {
        expect(bloc.state.results, hasLength(2));
        expect(
          bloc.state.results.map((result) => result.segment.toInt()),
          [40578, 51538],
        );
        expect(bloc.state.totalResults, 2);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'לחיצה על קטגוריה שומרת את הספרים שתחתיה בלבד',
      build: () => SearchBloc(repository: _RecordingSearchRepository()),
      seed: () => seededState(
        results: [
          _result(book: dorHamlaktim, staleCatalogueOrder: 1, segment: 51538),
          _result(book: beitShearim, staleCatalogueOrder: 0, segment: 431),
        ],
      ),
      act: clickFacet('/הלכה'),
      verify: (bloc) {
        expect(bloc.state.results.map((result) => result.filePath), [
          'id:5869',
        ]);
        expect(bloc.state.currentFacets, ['/הלכה']);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'תוצאת PDF מזוהה לפי נתיב הקובץ',
      build: () => SearchBloc(repository: _RecordingSearchRepository()),
      seed: () => seededState(
        results: [
          _result(book: beitShearimPdf, staleCatalogueOrder: 0, segment: 2),
          _result(book: dorHamlaktim, staleCatalogueOrder: 1, segment: 51538),
        ],
      ),
      act: (bloc) => clickFacet(
        FacetHelper.buildBookFacet(
          FacetHelper.resolveCategoryPath(beitShearimPdf),
          beitShearimPdf,
        ),
      )(bloc),
      verify: (bloc) {
        expect(bloc.state.results, hasLength(1));
        expect(bloc.state.results.single.isPdf, isTrue);
        expect(bloc.state.results.single.filePath, pdfPath);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'ספר אישי וספר רשמי בעלי אותו id נבדלים זה מזה',
      // המפתח היציב מבחין ביניהם ('uid:5' מול 'id:5'); הסדר הקטלוגי לא.
      build: () => SearchBloc(repository: _RecordingSearchRepository()),
      seed: () => seededState(
        results: [
          _result(book: officialShabbat, staleCatalogueOrder: 4, segment: 1),
          _result(book: personalShabbat, staleCatalogueOrder: 3, segment: 2),
        ],
      ),
      act: clickFacet('/הלכה/uid:5'),
      verify: (bloc) {
        expect(bloc.state.results.map((result) => result.filePath), ['uid:5']);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'הצמצום אינו נוגע בהיקף הסריקה של החיפוש',
      build: () => SearchBloc(repository: _RecordingSearchRepository()),
      seed: () => seededState(
        results: [_result(book: beitShearim, staleCatalogueOrder: 0)],
      ),
      act: clickFacet(beitShearimFacet),
      verify: (bloc) {
        expect(bloc.state.searchScopeFacets, ['/']);
        expect(bloc.state.currentFacets, [beitShearimFacet]);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'הסרת ספר מבחירה מרובה (Ctrl+לחיצה) מצמצמת לספרים שנשארו',
      build: () => SearchBloc(repository: _RecordingSearchRepository()),
      seed: () => seededState(
        currentFacets: [dorFacet, beitShearimFacet],
        results: [
          _result(book: dorHamlaktim, staleCatalogueOrder: 1, segment: 51538),
          _result(book: beitShearim, staleCatalogueOrder: 0, segment: 431),
        ],
      ),
      act: clickFacet(
        beitShearimFacet,
        treeCounts: {'/': 2, dorFacet: 1, beitShearimFacet: 1},
        eventBuilder: RemoveFacet.new,
      ),
      verify: (bloc) {
        expect(bloc.state.results.map((result) => result.filePath), [
          'id:5869',
        ]);
        expect(bloc.state.currentFacets, [dorFacet]);
        expect(streamCallsOf(bloc), 0);
      },
    );
  });

  // blocTest אינו תומך בדילוג ישיר (skip שלו סופר states) — לכן העטיפה בקבוצה.
  group(
    'נפילה למסלול המנוע (דורש מנוע נייטיבי)',
    () {
      blocTest<SearchBloc, SearchState>(
        'הרחבה — לחיצה על ספר אחר — אינה עוברת במסלול המקומי',
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        seed: () => seededState(
          results: [_result(book: beitShearim, staleCatalogueOrder: 0)],
          currentFacets: [beitShearimFacet],
        ),
        act: clickFacet(dorFacet),
        verify: (bloc) {
          expect(streamCallsOf(bloc), 1);
          expect(bloc.state.results, isNotEmpty);
        },
      );

      blocTest<SearchBloc, SearchState>(
        'הוספת ספר לבחירה (Ctrl+לחיצה) היא הרחבה וחוזרת למנוע',
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        seed: () => seededState(
          results: [_result(book: beitShearim, staleCatalogueOrder: 0)],
          currentFacets: [beitShearimFacet],
        ),
        act: clickFacet(dorFacet, eventBuilder: AddFacet.new),
        verify: (bloc) {
          expect(streamCallsOf(bloc), 1);
          expect(bloc.state.currentFacets, [beitShearimFacet, dorFacet]);
        },
      );

      blocTest<SearchBloc, SearchState>(
        'ביטול הסינון האחרון חוזר לכל ההיקף ולא ל"אין תוצאות"',
        // רשימת facets ריקה נקראת בחיפוש כ"אין במה לחפש", ורוקנה את התוצאות
        // בלי לפנות למנוע.
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        seed: () => seededState(
          results: [_result(book: beitShearim, staleCatalogueOrder: 0)],
          currentFacets: [beitShearimFacet],
        ),
        act: clickFacet(beitShearimFacet, eventBuilder: RemoveFacet.new),
        verify: (bloc) {
          expect(bloc.state.currentFacets, ['/']);
          expect(streamCallsOf(bloc), 1);
          expect(bloc.state.results, isNotEmpty);
        },
      );

      blocTest<SearchBloc, SearchState>(
        'ביטול הסינון האחרון בחיפוש ממוקד חוזר להיקף הסריקה',
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        seed: () => SearchState(
          searchQuery: query,
          results: [_result(book: beitShearim, staleCatalogueOrder: 0)],
          totalResults: 1,
          configuration: const SearchConfiguration(
            currentFacets: [beitShearimFacet],
            searchScopeFacets: ['/שו״ת'],
          ),
        ),
        act: clickFacet(beitShearimFacet, eventBuilder: RemoveFacet.new),
        verify: (bloc) => expect(bloc.state.currentFacets, ['/שו״ת']),
      );

      blocTest<SearchBloc, SearchState>(
        'סינון שהתרוקן למרות שהעץ הבטיח תוצאות נופל למנוע',
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        seed: () => seededState(
          results: [_result(book: dorHamlaktim, staleCatalogueOrder: 0)],
        ),
        act: clickFacet(beitShearimFacet),
        verify: (bloc) {
          expect(streamCallsOf(bloc), 1);
          expect(bloc.state.results, isNotEmpty);
        },
      );

      blocTest<SearchBloc, SearchState>(
        'תוצאה שספרה אינו בקטלוג נופלת למנוע',
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        seed: () => seededState(
          results: [
            SearchResult(
              id: IndexingRepository.buildCatalogueDocumentId(
                catalogueOrder: 0,
                ordinal: 0,
              ),
              title: 'ספר שהוסר מהספרייה',
              reference: 'סימן א',
              text: query,
              segment: BigInt.one,
              isPdf: false,
              filePath: 'id:999999',
              mergedCount: 1,
              merged: const [],
            ),
          ],
        ),
        act: clickFacet(beitShearimFacet),
        verify: (bloc) => expect(streamCallsOf(bloc), 1),
      );

      blocTest<SearchBloc, SearchState>(
        'תוצאות חתוכות (הגענו למכסה) אינן מצומצמות מקומית',
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        seed: () => seededState(
          results: [
            _result(book: dorHamlaktim, staleCatalogueOrder: 0, segment: 1),
            _result(book: beitShearim, staleCatalogueOrder: 1, segment: 2),
          ],
          numResults: 2,
        ),
        act: clickFacet(beitShearimFacet),
        verify: (bloc) => expect(streamCallsOf(bloc), 1),
      );

      blocTest<SearchBloc, SearchState>(
        'במצב איחוד תוצאות הצמצום חוזר למנוע',
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        seed: () => seededState(
          results: [_result(book: beitShearim, staleCatalogueOrder: 0)],
          grouping: ResultGroupingMode.sameSection,
        ),
        act: clickFacet(beitShearimFacet),
        verify: (bloc) => expect(streamCallsOf(bloc), 1),
      );

      blocTest<SearchBloc, SearchState>(
        'חתימת ספירות שאינה של החיפוש האחרון מחזירה למנוע',
        build: () => SearchBloc(repository: _RecordingSearchRepository()),
        // היקף הסריקה שווה לבחירה, כדי שהנפילה למנוע לא תגרור ספירת-ספרים
        // נפרדת — היא רצה מול מנוע החיפוש האמיתי ולא מול ה-repository המוזרק.
        seed: () => SearchState(
          searchQuery: query,
          results: [_result(book: beitShearim, staleCatalogueOrder: 0)],
          totalResults: 1,
          configuration: const SearchConfiguration(
            currentFacets: ['/'],
            searchScopeFacets: [beitShearimFacet],
          ),
        ),
        act: clickFacet(
          beitShearimFacet,
          signatureOverride: 'חתימה-של-חיפוש-אחר',
        ),
        verify: (bloc) => expect(streamCallsOf(bloc), 1),
      );
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );
}

/// תוצאה שמזהה המסמך שלה נושא סדר קטלוגי שכבר אינו תואם למיקום הספר
/// בספרייה — כמו אינדקס שנבנה לפני שספרים נוספו או נמחקו.
SearchResult _result({
  required Book book,
  required int staleCatalogueOrder,
  int segment = 1,
}) {
  return SearchResult(
    id: IndexingRepository.buildCatalogueDocumentId(
      catalogueOrder: staleCatalogueOrder,
      ordinal: 0,
    ),
    title: book.title,
    reference: '${book.title}, סימן א',
    text: 'שיעור הילוך מיל',
    segment: BigInt.from(segment),
    isPdf: book is PdfBook,
    filePath: IndexingRepository.buildIndexedBookFilePath(book),
    mergedCount: 1,
    merged: const [],
  );
}

class _RecordingSearchRepository extends SearchRepository {
  int streamCalls = 0;

  /// תוצאה שהמנוע מחזיר בנפילה למסלול המלא — כדי שהטסטים יוכלו לאמת שהמשתמש
  /// רואה תוצאות, ולא רק שהמנוע נקרא.
  static final SearchResult engineResult = SearchResult(
    id: BigInt.from(1),
    title: 'תוצאה מהמנוע',
    reference: 'סימן א',
    text: 'שיעור הילוך מיל',
    segment: BigInt.one,
    isPdf: false,
    filePath: 'id:6234',
    mergedCount: 1,
    merged: const [],
  );

  @override
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    int chunkSize = 50,
    ResultsOrder order = ResultsOrder.relevance,
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    ResultGrouping? grouping,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) async* {
    streamCalls++;
    yield SearchStreamUpdate(
      totalCount: 1,
      bookCounts: const {'id:6234': 1},
      results: [engineResult],
      truncated: false,
    );
  }
}
