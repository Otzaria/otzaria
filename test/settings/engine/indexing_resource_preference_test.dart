import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/models/indexing_resource_policy.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test(
    'explicit override survives a new settings repository and can return to auto',
    () async {
      for (final mode in IndexingResourceMode.values) {
        await SettingsRepository().updateIndexingResourceMode(mode);
        expect(
          SettingsRepository().readSettings()['indexingResourceMode'],
          mode,
        );
        expect(
          SettingsRepository.allKeys,
          contains(SettingsRepository.keyIndexingResourceMode),
        );
      }
    },
  );

  test('settings bloc stores the selection before showing it', () async {
    final bloc = SettingsBloc(repository: SettingsRepository());
    addTearDown(bloc.close);
    final changed = bloc.stream.firstWhere(
      (s) => s.indexingResourceMode == IndexingResourceMode.economy,
    );
    bloc.add(const UpdateIndexingResourceMode(IndexingResourceMode.economy));
    await changed;
    expect(
      SettingsRepository().readSettings()['indexingResourceMode'],
      IndexingResourceMode.economy,
    );
  });
}
