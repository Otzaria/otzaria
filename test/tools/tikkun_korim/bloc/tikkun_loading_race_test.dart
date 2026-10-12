import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

import '../support/tikkun_fakes.dart';

class _DeferredLoader implements TikkunTextLoader {
  final started = Completer<void>();
  final pending = Completer<String>();

  @override
  Future<String> loadRawText(String name) {
    if (name == 'שופטים' && !started.isCompleted) {
      started.complete();
      return pending.future;
    }
    return Future.value('תוכן חדש נבחר');
  }
}

void main() {
  for (final section in [TikkunSection.haftarot, TikkunSection.torahReadings]) {
    test('שינוי מנהג מרענן תוכן שאינו מתאים עוד: $section', () async {
      final data = FakeTikkunDataSource();
      final store = FakeTikkunSettingsStore(
        settings: const TikkunSettings(
          startupMode: 'lastPosition',
          nusach: 'sephard',
          nusachLand: 'diaspora',
        ),
        navState: TikkunNavState(
          section: section,
          haftarahId: 'h3',
          torahReadingId: 'r3',
        ),
      );
      final bloc = TikkunKorimBloc(
        repository: TikkunKorimRepository(
          engine: FakeTikkunEngine(),
          data: data,
          textLoader: FakeTikkunTextLoader(),
          computeRunner: syncComputeRunner,
        ),
        data: data,
        settingsStore: store,
        widthModelOf: (_) => fakeWidths,
        measureRoofs: (_) async {},
      );
      addTearDown(bloc.close);
      final ready = bloc.stream.firstWhere((s) => !s.isLoading);
      bloc.add(const TikkunStarted());
      await ready;
      final updated = section == TikkunSection.haftarot
          ? store.settings.copyWith(nusachLand: 'israel')
          : store.settings.copyWith(nusach: 'ashkenaz');
      final changes = bloc.stream.firstWhere((s) => s.settings == updated);
      bloc.add(TikkunSettingsUpdated(updated));
      await changes;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        bloc.state.headerTitle,
        section == TikkunSection.haftarot ? 'הפטרת בראשית' : 'ראש חודש',
      );
    });
  }

  test('תוצאת ספר ישן אינה מחליפה את המדור החדש', () async {
    final loader = _DeferredLoader();
    final data = FakeTikkunDataSource();
    final repo = TikkunKorimRepository(
      engine: FakeTikkunEngine(),
      data: data,
      textLoader: loader,
      computeRunner: syncComputeRunner,
    );
    final bloc = TikkunKorimBloc(
      repository: repo,
      data: data,
      settingsStore: FakeTikkunSettingsStore(
        settings: const TikkunSettings(startupMode: 'lastPosition'),
        navState: const TikkunNavState(
          section: TikkunSection.neviim,
          tanachBookId: 'shoftim',
        ),
      ),
      widthModelOf: (_) => fakeWidths,
      measureRoofs: (_) async {},
    );
    addTearDown(bloc.close);
    bloc.add(const TikkunStarted());
    await loader.started.future;
    final ready = bloc.stream.firstWhere(
      (s) => s.nav.section == TikkunSection.ketuvim && !s.isLoading,
    );
    bloc.add(const TikkunSectionChanged(TikkunSection.ketuvim));
    await ready;
    final selectedPages = bloc.state.pages;
    loader.pending.complete('תוכן ישן שגוי');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bloc.state.pages, same(selectedPages));
    expect(bloc.state.nav.tanachBookId, 'ester');
  });

  test(
    'דיווח שורה על העמודים הישנים במהלך טעינה אינו משנה את הניווט',
    () async {
      var roofs = Completer<void>()..complete();
      final store = FakeTikkunSettingsStore(
        settings: const TikkunSettings(startupMode: 'lastPosition'),
      );
      final data = FakeTikkunDataSource();
      final bloc = TikkunKorimBloc(
        repository: TikkunKorimRepository(
          engine: FakeTikkunEngine(),
          data: data,
          textLoader: FakeTikkunTextLoader(),
          computeRunner: syncComputeRunner,
        ),
        data: data,
        settingsStore: store,
        widthModelOf: (_) => fakeWidths,
        measureRoofs: (_) => roofs.future,
      );
      addTearDown(bloc.close);
      final ready = bloc.stream.firstWhere((s) => !s.isLoading);
      bloc.add(const TikkunStarted());
      await ready;
      expect(bloc.state.nav.parashaName, 'בראשית');

      roofs = Completer<void>();
      bloc.add(const TikkunParashaChanged('נח'));
      await Future<void>.delayed(Duration.zero);
      final saved = store.navState;
      // שורה 0 של העמוד המוצג עדיין שייכת לבראשית.
      bloc.add(const TikkunVisibleLineChanged(0));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.nav.parashaName, 'נח');
      expect(store.navState, saved);

      final loaded = bloc.stream.firstWhere((s) => !s.isLoading);
      roofs.complete();
      await loaded;
      expect(bloc.state.nav.parashaName, 'נח');
      expect(bloc.state.nav.currentColumnIndex, 1);
    },
  );

  test('טעינה שהחלה לפני ניקוי המטמון אינה מאכלסת אותו מחדש', () async {
    final loader = _DeferredLoader();
    final repo = TikkunKorimRepository(
      engine: FakeTikkunEngine(),
      data: FakeTikkunDataSource(),
      textLoader: loader,
      computeRunner: syncComputeRunner,
    );
    final pending = repo.processedBook('שופטים', fakeWidths);
    await loader.started.future;
    repo.clearCaches();
    loader.pending.complete('תוכן ישן שגוי');
    await pending;
    expect(repo.cachedBookNames, isEmpty);
  });
}
