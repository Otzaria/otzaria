import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../helpers/memory_settings_cache.dart';
import '../support/recording_search_engine.dart';
import '../support/search_engine_test_init.dart';

/// "שמור על סדר המילים המקורי" (issue #2006): הבחירה מגיעה למנוע רק כשהיא
/// חלה — לא במקורב ולא עם מרווחים ידניים.
Future<void> main() async {
  // sanitizeQuery מאציל למנוע ה-Rust הנייטיבי.
  final engineReady = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingSearchEngine engine;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  SearchBloc buildBloc(
    SearchConfiguration configuration, {
    RecordingSearchEngine? recording,
  }) {
    engine = recording ?? RecordingSearchEngine();
    return SearchBloc(
      initialConfiguration: configuration,
      repository: SearchRepository(engineProvider: () async => engine),
    );
  }

  Future<void> settle(SearchBloc bloc) =>
      bloc.stream.firstWhere((state) => !state.isLoading);

  group('סדר המילים בבקשה למנוע', () {
    test('UpdateWordOrder מריץ מחדש עם anyOrder', () async {
      final bloc = buildBloc(const SearchConfiguration(distance: 2));
      addTearDown(bloc.close);
      bloc.add(UpdateSearchQuery('ברא אלהים'));
      await settle(bloc);
      expect(engine.lastRequest!.anyOrder, isFalse);

      bloc.add(UpdateWordOrder(true));
      await bloc.stream.firstWhere((state) => state.isLoading);
      await settle(bloc);
      expect(bloc.state.anyOrder, isTrue);
      expect(engine.lastRequest!.anyOrder, isTrue);
      expect(engine.lastRequest!.distance, 2);
    });

    test('גרסת WithoutSearch מעדכנת את ה-state בלי לפנות למנוע', () async {
      final bloc = buildBloc(const SearchConfiguration());
      addTearDown(bloc.close);
      bloc.add(UpdateWordOrderWithoutSearch(true));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.anyOrder, isTrue);
      expect(engine.lastRequest, isNull);
    });

    test('שאילתה של מילה אחת אינה שולחת anyOrder', () async {
      final bloc = buildBloc(const SearchConfiguration(anyOrder: true));
      addTearDown(bloc.close);
      bloc.add(UpdateSearchQuery('ברא'));
      await settle(bloc);
      expect(engine.lastRequest!.anyOrder, isFalse);
    });

    test('מרווח ידני מבטל את anyOrder בבקשה', () async {
      final bloc = buildBloc(const SearchConfiguration(anyOrder: true));
      addTearDown(bloc.close);
      bloc.add(
        UpdateSearchQuery('ברא אלהים', customSpacing: const {'0-1': '3'}),
      );
      await settle(bloc);
      expect(engine.lastRequest!.anyOrder, isFalse);
    });

    test('במקורב ובטווח פסקה anyOrder אינו נשלח', () async {
      for (final configuration in const [
        SearchConfiguration(searchMode: SearchMode.fuzzy, anyOrder: true),
        SearchConfiguration(
          anyOrder: true,
          proximityScope: SearchScope.sameParagraph,
        ),
      ]) {
        final bloc = buildBloc(configuration);
        bloc.add(UpdateSearchQuery('ברא אלהים'));
        await settle(bloc);
        await bloc.close();
        expect(engine.lastRequest!.anyOrder, isFalse);
      }
    });

    test('במדויק anyOrder נשלח גם כשנשמר טווח מהמצב המתקדם', () async {
      final bloc = buildBloc(
        const SearchConfiguration(
          searchMode: SearchMode.exact,
          anyOrder: true,
          proximityScope: SearchScope.sameSection,
        ),
      );
      addTearDown(bloc.close);
      bloc.add(UpdateSearchQuery('ברא אלהים'));
      await settle(bloc);
      expect(engine.lastRequest!.anyOrder, isTrue);
    });

    test('טעינת תוצאות נוספות נושאת את anyOrder', () async {
      final bloc = buildBloc(
        const SearchConfiguration(anyOrder: true, numResults: 1),
        recording: _CountingEngine(),
      );
      addTearDown(bloc.close);
      bloc.add(UpdateSearchQuery('ברא אלהים'));
      await settle(bloc);
      engine.lastRequest = null;
      bloc.add(LoadMoreResults());
      await settle(bloc);
      expect(engine.lastRequest!.anyOrder, isTrue);
    });
  }, skip: !engineReady);
}

/// מונה תוצאות גבוה מהרשימה, כדי ש"טען עוד" יפנה למנוע.
class _CountingEngine extends RecordingSearchEngine {
  @override
  Stream<SearchStreamUpdate> searchStreamWithCounts(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    lastRequest = request;
    yield const SearchStreamUpdate(
      totalCount: 5,
      bookCounts: {},
      results: [],
      truncated: false,
    );
  }
}
