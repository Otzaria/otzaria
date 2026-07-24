import 'dart:async';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomFoldersBloc', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyCustomFolders, '');
    });

    test(
      'RescanCustomFolders קורא את רשימת התיקיות העדכנית מההגדרות',
      () async {
        final oldFolder = _folder('C:/old-folder');
        final newFolder = _folder('C:/new-folder');
        await _saveFolders([oldFolder]);

        final syncedFolders = <List<CustomFolder>>[];
        final recordedEvents = <LibraryEvent>[];
        final bloc = CustomFoldersBloc(
          addLibraryEvent: recordedEvents.add,
          syncFolders: (folders, {String? onlyFolderPath}) async {
            syncedFolders.add(List<CustomFolder>.from(folders));
            return const FileSyncResult();
          },
        )..add(const LoadCustomFolders());

        await bloc.stream.firstWhere((state) => state.folders.isNotEmpty);

        await _saveFolders([newFolder]);
        bloc.add(const RescanCustomFolders(showNoChangesMessage: false));

        await bloc.stream.firstWhere(
          (state) =>
              !state.isSyncing &&
              state.folders.length == 1 &&
              state.folders.single.path == newFolder.path,
        );

        expect(syncedFolders, hasLength(1));
        expect(syncedFolders.single, [newFolder]);
        expect(bloc.state.folders, [newFolder]);
        expect(
          recordedEvents.whereType<RefreshLibrary>(),
          hasLength(1),
        );

        await bloc.close();
      },
    );

    test(
      'RescanCustomFolders מעביר onlyFolderPath לסנכרון (סריקה ממוקדת)',
      () async {
        final folder = _folder('C:/personal-books');
        await _saveFolders([folder]);

        final scopedPaths = <String?>[];
        final bloc = CustomFoldersBloc(
          addLibraryEvent: (_) {},
          syncFolders: (folders, {String? onlyFolderPath}) async {
            scopedPaths.add(onlyFolderPath);
            return const FileSyncResult();
          },
        )..add(const LoadCustomFolders());

        await bloc.stream.firstWhere((state) => state.folders.isNotEmpty);

        bloc.add(
          const RescanCustomFolders(
            showNoChangesMessage: false,
            onlyFolderPath: 'C:/personal-books',
          ),
        );
        await bloc.stream.firstWhere((state) => !state.isSyncing);

        expect(scopedPaths, ['C:/personal-books']);

        await bloc.close();
      },
    );

    test('ToggleAddToDatabase מסמן activePath לתיקייה הנטענת בלבד '
        'ומאפס בסיום', () async {
      final folderA = _folder('C:/folder-a');
      final folderB = _folder('C:/folder-b');
      await _saveFolders([folderA, folderB]);

      // משהים את הסנכרון כדי לבדוק את ה-state בזמן הטעינה.
      final syncStarted = Completer<void>();
      final releaseSync = Completer<void>();
      final bloc = CustomFoldersBloc(
        addLibraryEvent: (_) {},
        syncFolders: (folders, {String? onlyFolderPath}) async {
          syncStarted.complete();
          await releaseSync.future;
          return const FileSyncResult();
        },
      )..add(const LoadCustomFolders());

      await bloc.stream.firstWhere((state) => state.folders.isNotEmpty);

      bloc.add(ToggleAddToDatabase(folderA, true));
      await syncStarted.future;

      // תוך כדי הסנכרון רק folderA מסומנת כפעילה.
      expect(bloc.state.isSyncing, isTrue);
      expect(bloc.state.activePath, folderA.path);

      releaseSync.complete();
      await bloc.stream.firstWhere((state) => !state.isSyncing);

      // בסיום activePath מתאפס.
      expect(bloc.state.activePath, isNull);

      await bloc.close();
    });

    test('RescanCustomFolders אינו מסמן activePath (פעולה גלובלית)', () async {
      final folder = _folder('C:/folder');
      await _saveFolders([folder]);

      final syncStarted = Completer<void>();
      final releaseSync = Completer<void>();
      final bloc = CustomFoldersBloc(
        addLibraryEvent: (_) {},
        syncFolders: (folders, {String? onlyFolderPath}) async {
          syncStarted.complete();
          await releaseSync.future;
          return const FileSyncResult();
        },
      )..add(const LoadCustomFolders());

      await bloc.stream.firstWhere((state) => state.folders.isNotEmpty);

      bloc.add(const RescanCustomFolders());
      await syncStarted.future;

      expect(bloc.state.isSyncing, isTrue);
      expect(bloc.state.activePath, isNull);

      releaseSync.complete();
      await bloc.stream.firstWhere((state) => !state.isSyncing);

      await bloc.close();
    });

    test('RemoveCustomFolder מאפס isSyncing כשמחיקה מה-DB נכשלת', () async {
      final folder = _folder('C:/folder-to-remove');
      await _saveFolders([folder]);

      final recordedEvents = <LibraryEvent>[];
      final bloc = CustomFoldersBloc(
        addLibraryEvent: recordedEvents.add,
        deleteFolderFromDb: (_) async {
          throw Exception('db failed');
        },
      )..add(const LoadCustomFolders());

      await bloc.stream.firstWhere((state) => state.folders.isNotEmpty);

      bloc.add(RemoveCustomFolder(folder, deleteFromDb: true));

      await bloc.stream.firstWhere((state) => state.error != null);

      expect(bloc.state.isSyncing, isFalse);
      expect(bloc.state.folders, isEmpty);
      expect(bloc.state.error, contains('db failed'));
      expect(
        CustomFoldersManager.loadFolders(
          Settings.getValue<String>(SettingsRepository.keyCustomFolders),
        ),
        isEmpty,
      );
      expect(recordedEvents, isEmpty);

      await bloc.close();
    });
  });
}

CustomFolder _folder(String path) {
  return CustomFolder(
    path: path,
    addToDatabase: true,
    addedAt: DateTime(2026, 5, 7),
  );
}

Future<void> _saveFolders(List<CustomFolder> folders) {
  return Settings.setValue<String>(
    SettingsRepository.keyCustomFolders,
    CustomFoldersManager.saveFolders(folders),
  );
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
