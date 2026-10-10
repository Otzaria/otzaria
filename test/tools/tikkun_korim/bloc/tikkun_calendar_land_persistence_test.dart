import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../support/tikkun_fakes.dart';

class _ObservedSettingsStore extends TikkunSettingsStore {
  final saved = Completer<void>();

  @override
  Future<void> save(TikkunSettings settings) async {
    await super.save(settings);
    saved.complete();
  }
}

TikkunKorimBloc _buildBloc(TikkunSettingsStore store) {
  final data = FakeTikkunDataSource();
  return TikkunKorimBloc(
    data: data,
    repository: TikkunKorimRepository(
      engine: FakeTikkunEngine(),
      data: data,
      textLoader: FakeTikkunTextLoader(),
      computeRunner: syncComputeRunner,
    ),
    settingsStore: store,
    widthModelOf: (_) => fakeWidths,
    measureRoofs: (_) async {},
    upcomingParasha: (_, {required inIsrael}) => 'נח',
  );
}

void main() {
  for (final explicit in [false, true]) {
    late _ObservedSettingsStore store;
    blocTest<TikkunKorimBloc, TikkunKorimState>(
      explicit
          ? 'בחירה מפורשת השווה לעיר נשמרת דרך BLoC'
          : 'שינוי עיר בטאב פתוח וזום אינו מקבע מנהג נגזר',
      setUp: () async {
        await Settings.init(cacheProvider: MemoryCacheProvider());
        await Settings.setValue<String>(
          SettingsRepository.keySelectedCity,
          'לונדון',
        );
        store = _ObservedSettingsStore();
      },
      build: () => _buildBloc(store),
      act: (bloc) async {
        final loaded = bloc.stream.firstWhere((state) => !state.isLoading);
        bloc.add(const TikkunStarted());
        await loaded;
        expect(bloc.state.settings.nusachLand, 'diaspora');
        await Settings.setValue<String>(
          SettingsRepository.keySelectedCity,
          'ירושלים',
        );
        final opened = bloc.state.settings;
        bloc.add(
          TikkunSettingsUpdated(
            explicit
                ? opened.copyWith(nusachLand: 'diaspora', zoom: 1.5)
                : opened.copyWith(zoom: 1.5),
          ),
        );
        await store.saved.future;
      },
      verify: (bloc) async {
        expect(bloc.state.settings.nusachLand, 'diaspora');
        expect(bloc.state.settings.zoom, 1.5);
        expect(
          Settings.getValue<String>(TikkunSettingsKeys.nusachLand),
          explicit ? 'diaspora' : isNull,
        );
        final reopened = _buildBloc(const TikkunSettingsStore());
        addTearDown(reopened.close);
        final loaded = reopened.stream.firstWhere((state) => !state.isLoading);
        reopened.add(const TikkunStarted());
        await loaded;
        expect(
          reopened.state.settings.nusachLand,
          explicit ? 'diaspora' : 'israel',
        );
        expect(reopened.state.settings.zoom, 1.5);
      },
    );
  }
}
