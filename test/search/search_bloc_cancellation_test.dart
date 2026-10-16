import 'dart:async';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

/// חיפוש חדש, איפוס וסגירת הטאב מבטלים במנוע את החיפוש הקודם, ושאילתת
/// `/…/` מגיעה למנוע כפי שהוקלדה.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  group('ביטול חיפוש במנוע', () {
    late _RecordingRepository repository;
    late SearchBloc bloc;

    setUp(() {
      repository = _RecordingRepository();
      bloc = SearchBloc(repository: repository);
    });

    tearDown(() async {
      await bloc.close();
      for (final stream in repository.streams) {
        await stream.close();
      }
    });

    Future<void> waitForRequests(int count) async {
      for (var i = 0; i < 100 && repository.requests.length < count; i++) {
        await pumpEventQueue();
      }
      expect(repository.requests, hasLength(count));
    }

    test('חיפוש חדש מבטל את הקודם במזהה שונה', () async {
      bloc.add(UpdateSearchQuery('שלום'));
      await waitForRequests(1);
      final first = repository.requests.single.cancelRequestId;
      expect(first, isNotNull);
      expect(repository.cancelled, isEmpty);

      bloc.add(UpdateSearchQuery('עולם'));
      await waitForRequests(2);
      final second = repository.requests.last.cancelRequestId;
      expect(second, isNot(first));
      expect(repository.cancelled, [first]);
    });

    test('ניקוי השאילתה וסגירה מבטלים את החיפוש הרץ', () async {
      bloc.add(UpdateSearchQuery('שלום'));
      await waitForRequests(1);
      bloc.add(UpdateSearchQuery(''));
      await bloc.stream.firstWhere((s) => s.searchQuery.isEmpty);
      final first = repository.requests.single.cancelRequestId;
      expect(repository.cancelled, [first]);

      bloc.add(UpdateSearchQuery('עולם'));
      await waitForRequests(2);
      await bloc.close();
      expect(repository.cancelled, [
        first,
        repository.requests.last.cancelRequestId,
      ]);
    });

    test('ביטול שמגיע כשגיאה אינו מוצג למשתמש', () async {
      bloc.add(UpdateSearchQuery('שלום'));
      await waitForRequests(1);
      repository.streams.single.addError(
        Exception('AnyhowException(lexical search cancelled)'),
      );
      await bloc.stream.firstWhere((s) => !s.isLoading);
      expect(bloc.state.errorMessage, isNull);
    });

    test('`/…/` תקין נשלח כפי שהוקלד, פסול מנוקה כטקסט', () async {
      bloc.add(UpdateSearchQuery(' /מש.ה|אהרן/ '));
      await waitForRequests(1);
      expect(repository.requests.single.query, '/מש.ה|אהרן/');

      bloc.add(UpdateSearchQuery('/(משה/'));
      await waitForRequests(2);
      expect(
        repository.requests.last.query,
        SearchQueryBuilder.sanitizeQuery('/(משה/'),
      );
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  group('תת-בחירה מהעץ: ספירת הטווח המלא', () {
    late _RecordingRepository repository;
    late _CountingIndex index;
    late TantivyDataProvider previousIndex;
    late SearchBloc bloc;

    setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));

    setUp(() {
      previousIndex = TantivyDataProvider.instance;
      TantivyDataProvider.instance = index = _CountingIndex();
      DataRepository.instance.library = Future.value(Library(categories: []));
      repository = _RecordingRepository();
      bloc = SearchBloc(repository: repository);
    });

    tearDown(() async {
      await bloc.close();
      for (final stream in repository.streams) {
        await stream.close();
      }
      TantivyDataProvider.instance = previousIndex;
    });

    Future<void> searchInSubselection(String query) async {
      bloc.add(const SetFacetsWithoutSearch(['/תנך'], keepScope: true));
      bloc.add(UpdateSearchQuery(query));
      for (var i = 0; i < 100 && repository.requests.isEmpty; i++) {
        await pumpEventQueue();
      }
      expect(repository.requests.single.facets, ['/תנך']);
      await pumpEventQueue(times: 50);
    }

    test('רג\'קס חוצה-רווחים: הספירה רצה אחרי הזרם, לא במקביל לו', () async {
      await searchInSubselection(r'/שמע .* ישראל/');
      expect(index.countedScopes, isEmpty);

      await repository.streams.single.close();
      await bloc.stream.firstWhere((s) => !s.isLoading);
      await pumpEventQueue(times: 50);
      expect(index.countedScopes, [
        ['/'],
      ]);
    });

    test('שאילתה רגילה: הספירה רצה במקביל לזרם', () async {
      await searchInSubselection('שלום');
      expect(index.countedScopes, [
        ['/'],
      ]);
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}

/// סופר בלי מנוע את הקריאות לספירה לפי ספר, ושומר את הטווח של כל אחת.
class _CountingIndex extends Fake implements TantivyDataProvider {
  final countedScopes = <List<String>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #countByBook) {
      countedScopes.add(invocation.positionalArguments[1] as List<String>);
      return Future.value(<String, int>{});
    }
    return super.noSuchMethod(invocation);
  }
}

class _RecordingRepository extends SearchRepository {
  final requests = <SearchEngineRequest>[];
  final streams = <StreamController<SearchStreamUpdate>>[];
  final cancelled = <int>[];

  @override
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    SearchEngineRequest request, {
    int chunkSize = 50,
  }) {
    requests.add(request);
    final controller = StreamController<SearchStreamUpdate>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<void> cancelLexicalSearch(int requestId) async {
    cancelled.add(requestId);
  }
}
