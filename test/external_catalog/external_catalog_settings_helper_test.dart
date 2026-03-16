import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs', () {
    test('skips auto sync when external books are disabled', () async {
      final repository = _FakeExternalCatalogRepository();
      var invalidateCalls = 0;

      await ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs(
        SettingsState.initial().copyWith(
          showExternalBooks: false,
          autoSyncCatalogs: true,
        ),
        repository: repository,
        invalidateExternalBooksCache: () {
          invalidateCalls++;
        },
      );

      expect(repository.updateCalls, 0);
      expect(invalidateCalls, 0);
    });

    test('updates catalogs separately when auto sync is enabled', () async {
      final repository = _FakeExternalCatalogRepository(updateResult: true);
      var invalidateCalls = 0;

      await ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs(
        SettingsState.initial().copyWith(
          showExternalBooks: true,
          autoSyncCatalogs: true,
        ),
        repository: repository,
        invalidateExternalBooksCache: () {
          invalidateCalls++;
        },
      );

      expect(repository.updateCalls, 1);
      expect(invalidateCalls, 1);
    });

    test('skips auto sync when catalog database is missing', () async {
      final repository = _FakeExternalCatalogRepository(
        databaseExistsResult: false,
      );
      var invalidateCalls = 0;

      await ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs(
        SettingsState.initial().copyWith(
          showExternalBooks: true,
          autoSyncCatalogs: true,
        ),
        repository: repository,
        invalidateExternalBooksCache: () {
          invalidateCalls++;
        },
      );

      expect(repository.updateCalls, 0);
      expect(invalidateCalls, 0);
    });
  });
}

class _FakeExternalCatalogRepository extends ExternalCatalogRepository {
  _FakeExternalCatalogRepository({
    this.databaseExistsResult = true,
    this.updateResult = false,
  });

  final bool databaseExistsResult;
  final bool updateResult;
  int updateCalls = 0;

  @override
  Future<bool> databaseExists() async => databaseExistsResult;

  @override
  Future<bool> updateDatabaseIfNeeded() async {
    updateCalls++;
    return updateResult;
  }
}
