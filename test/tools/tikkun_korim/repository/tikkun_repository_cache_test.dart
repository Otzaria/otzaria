import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';

import '../support/tikkun_fakes.dart';

void main() {
  late FakeTikkunEngine engine;
  late FakeTikkunDataSource data;
  late FakeTikkunTextLoader loader;

  TikkunKorimRepository buildRepository() => TikkunKorimRepository(
    engine: engine,
    data: data,
    textLoader: loader,
    computeRunner: syncComputeRunner,
  );

  setUp(() {
    engine = FakeTikkunEngine();
    data = FakeTikkunDataSource();
    loader = FakeTikkunTextLoader();
  });

  group('מכסת מטמון הספרים', () {
    test('ספר רביעי מפנה את הישן ביותר', () async {
      final repo = buildRepository();
      for (final name in ['אחד', 'שנים', 'שלושה', 'ארבעה']) {
        await repo.processedBook(name, fakeWidths);
      }
      expect(
        repo.cachedBookNames.length,
        TikkunKorimRepository.maxCachedBooks,
      );
      expect(repo.cachedBookNames, isNot(contains('אחד')));
      expect(repo.cachedBookNames, contains('ארבעה'));
    });

    test('פנייה חוזרת מקדמת את הספר ומצילה אותו מהפינוי', () async {
      final repo = buildRepository();
      await repo.processedBook('אחד', fakeWidths);
      await repo.processedBook('שנים', fakeWidths);
      await repo.processedBook('שלושה', fakeWidths);
      await repo.processedBook('אחד', fakeWidths);
      await repo.processedBook('ארבעה', fakeWidths);
      expect(repo.cachedBookNames, contains('אחד'));
      expect(repo.cachedBookNames, isNot(contains('שנים')));
    });

    test('ספר במטמון אינו נטען שוב מהספרייה', () async {
      final repo = buildRepository();
      await repo.processedBook('אחד', fakeWidths);
      await repo.processedBook('אחד', fakeWidths);
      expect(loader.requested, ['אחד']);
    });
  });

  group('הטקסט הגולמי אינו נשמר', () {
    test('עיבוד חוזר של ספר שפונה טוען מחדש', () async {
      final repo = buildRepository();
      for (final name in ['אחד', 'שנים', 'שלושה', 'ארבעה', 'אחד']) {
        await repo.processedBook(name, fakeWidths);
      }
      expect(loader.requested.where((n) => n == 'אחד').length, 2);
    });

    test('עיבוד חוזר של התורה אינו טוען שוב את החומשים', () async {
      final repo = buildRepository();
      await repo.processedTorah(fakeWidths);
      await repo.processedTorah(fakeWidths);
      expect(engine.processTorahCalls, 1);
      expect(loader.requested.length, data.chumashim.length);
    });
  });

  group('טעמי עשרת הדברות', () {
    test('החלפת הטעם פוסלת את המטמון ומגיעה למנוע', () async {
      final repo = buildRepository();
      await repo.processedTorah(fakeWidths);
      await repo.processedBook('אחד', fakeWidths);
      expect(engine.lastDecalogueTaam, TikkunDecalogueTaam.merged);

      repo.useDecalogueTaam(TikkunDecalogueTaam.elyon);
      expect(repo.cachedBookNames, isEmpty);

      await repo.processedTorah(fakeWidths);
      expect(engine.processTorahCalls, 2);
      expect(engine.lastDecalogueTaam, TikkunDecalogueTaam.elyon);
    });

    test('אותו טעם אינו פוסל את המטמון', () async {
      final repo = buildRepository();
      await repo.processedTorah(fakeWidths);
      repo.useDecalogueTaam(TikkunDecalogueTaam.merged);
      await repo.processedTorah(fakeWidths);
      expect(engine.processTorahCalls, 1);
    });
  });

  group('שחרור', () {
    test('clearCaches מרוקן את התורה ואת הספרים', () async {
      final repo = buildRepository();
      await repo.processedTorah(fakeWidths);
      await repo.processedBook('אחד', fakeWidths);
      repo.clearCaches();
      expect(repo.cachedBookNames, isEmpty);
      await repo.processedTorah(fakeWidths);
      expect(engine.processTorahCalls, 2);
    });

    test('סגירת ה-BLoC משחררת את מטמון ה-repository', () async {
      final repo = buildRepository();
      final bloc = TikkunKorimBloc(
        repository: repo,
        data: data,
        settingsStore: FakeTikkunSettingsStore(),
        upcomingParasha: (_) => 'נח',
      );
      await repo.processedTorah(fakeWidths);
      await repo.processedBook('אחד', fakeWidths);
      await bloc.close();
      expect(repo.cachedBookNames, isEmpty);
      await repo.processedTorah(fakeWidths);
      expect(engine.processTorahCalls, 2);
    });
  });
}
