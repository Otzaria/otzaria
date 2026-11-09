import 'dart:async';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomFoldersBloc', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
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

    // #2164: הסנכרון פותח את seforim.db ואת user_books.db ומעכב את הרענון.
    test('RescanCustomFolders בלי תיקיות מרענן בלי להריץ סנכרון', () async {
      var syncCalls = 0;
      final recordedEvents = <LibraryEvent>[];
      final bloc = CustomFoldersBloc(
        addLibraryEvent: recordedEvents.add,
        syncFolders: (folders, {String? onlyFolderPath}) async {
          syncCalls++;
          return const FileSyncResult();
        },
      );

      bloc.add(const RescanCustomFolders(showNoChangesMessage: false));
      await bloc.stream.firstWhere((state) => !state.isSyncing);

      expect(syncCalls, 0);
      expect(recordedEvents.whereType<RefreshLibrary>(), hasLength(1));

      await bloc.close();
    });

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

    for (final failure in [false, true]) {
      test(
        failure
            ? 'RemoveCustomFolder משלים בכשל שמירת ההגדרות בלי למחוק ספרים'
            : 'RemoveCustomFolder משלים רק לאחר המחיקה ושליחת הרענון',
        () async {
          final folder = _folder('C:/folder-to-remove');
          await _saveFolders([folder]);
          final recordedEvents = <LibraryEvent>[];
          var deleted = false;
          final bloc = CustomFoldersBloc(
            addLibraryEvent: recordedEvents.add,
            saveFolders: failure
                ? (_) async => throw StateError('save-failed')
                : null,
            deleteFolderFromDb: (_) async => deleted = true,
          )..add(const LoadCustomFolders());
          await bloc.stream.firstWhere((state) => state.folders.isNotEmpty);
          final done = Completer<String?>();
          bloc.add(
            RemoveCustomFolder(folder, deleteFromDb: true, completer: done),
          );
          final error = await done.future;
          if (failure) {
            expect(error, contains('save-failed'));
            expect(bloc.state.error, error);
            expect(bloc.state.folders, [folder]);
            expect(deleted, isFalse);
            expect(recordedEvents, isEmpty);
          } else {
            expect(error, isNull);
            expect(deleted, isTrue);
            expect(recordedEvents.whereType<RefreshLibrary>(), hasLength(1));
          }
          await bloc.close();
        },
      );
    }

    // מסלול `library.refreshUserBooks` של תוסף: הקורא אינו UI ולכן
    // הודעות הטקסט לא מספיקות לו — הוא ממתין ל-completedScan של הבקשה שלו.
    test('RescanCustomFolders עם requestId מדווח את תוצאת הסריקה', () async {
      await _saveFolders([_folder('C:/personal-books')]);

      final recordedEvents = <LibraryEvent>[];
      final bloc = CustomFoldersBloc(
        addLibraryEvent: recordedEvents.add,
        syncFolders: (folders, {String? onlyFolderPath}) async =>
            const FileSyncResult(
              addedBooks: 3,
              updatedBooks: 1,
              errors: ['ספר.txt נכשל'],
            ),
      );

      final completed = bloc.stream.firstWhere(
        (state) => state.completedScan?.requestId == 7,
      );
      bloc.add(
        const RescanCustomFolders(showNoChangesMessage: false, requestId: 7),
      );

      final outcome = (await completed).completedScan!;
      expect(outcome.isSuccess, isTrue);
      expect(outcome.addedBooks, 3);
      expect(outcome.updatedBooks, 1);
      expect(outcome.errors, ['ספר.txt נכשל']);
      // הרענון נשלח לפני הדיווח, כדי שמי שממתין לתוצאה לא יקדים אותו.
      final refreshEvents = recordedEvents.whereType<RefreshLibrary>().toList();
      expect(refreshEvents, hasLength(1));
      expect(refreshEvents.single.requestIds, {7});

      await bloc.close();
    });

    test('סריקה שנכשלה מדווחת ככשל לבעל ה-requestId', () async {
      await _saveFolders([_folder('C:/personal-books')]);

      final bloc = CustomFoldersBloc(
        addLibraryEvent: (_) {},
        syncFolders: (folders, {String? onlyFolderPath}) async =>
            throw Exception('scan failed'),
      );

      final completed = bloc.stream.firstWhere(
        (state) => state.completedScan?.requestId == 1,
      );
      bloc.add(const RescanCustomFolders(requestId: 1));

      final outcome = (await completed).completedScan!;
      expect(outcome.isSuccess, isFalse);
      expect(outcome.failureMessage, contains('scan failed'));

      await bloc.close();
    });

    test('סריקה מהממשק (ללא requestId) אינה מדווחת תוצאה', () async {
      await _saveFolders([_folder('C:/personal-books')]);

      final bloc = CustomFoldersBloc(
        addLibraryEvent: (_) {},
        syncFolders: (folders, {String? onlyFolderPath}) async =>
            const FileSyncResult(addedBooks: 2),
      );

      bloc.add(const RescanCustomFolders(showNoChangesMessage: false));
      await bloc.stream.firstWhere((state) => !state.isSyncing);

      expect(bloc.state.completedScan, isNull);

      await bloc.close();
    });
    test(
      'SetFolderMergeMode שומר את החריגה ומרענן את הספרייה בלי סריקה',
      () async {
        await _saveFolders([_folder('C:/personal-books')]);

        final recordedEvents = <LibraryEvent>[];
        var syncCalls = 0;
        final bloc = CustomFoldersBloc(
          addLibraryEvent: recordedEvents.add,
          syncFolders: (folders, {String? onlyFolderPath}) async {
            syncCalls++;
            return const FileSyncResult();
          },
        )..add(const LoadCustomFolders());

        await bloc.stream.firstWhere((state) => state.folders.isNotEmpty);

        bloc.add(SetFolderMergeMode(bloc.state.folders.single, false));
        await bloc.stream.firstWhere(
          (state) => state.folders.single.mergeIntoLibrary == false,
        );

        expect(
          CustomFoldersManager.loadFolders(
            Settings.getValue<String>(SettingsRepository.keyCustomFolders),
          ).single.mergeIntoLibrary,
          isFalse,
          reason: 'החריגה נשמרת להגדרות ולא רק ל-state',
        );
        expect(syncCalls, 0, reason: 'שינוי מיקום בעץ אינו סורק את הדיסק');
        expect(recordedEvents.whereType<RefreshLibrary>(), hasLength(1));

        await bloc.close();
      },
    );

    test(
      'SetFolderHidden שומר את ההסתרה ומרענן את הספרייה בלי סריקה',
      () async {
        await _saveFolders([_folder('C:/personal-books')]);

        final recordedEvents = <LibraryEvent>[];
        var syncCalls = 0;
        final bloc = CustomFoldersBloc(
          addLibraryEvent: recordedEvents.add,
          syncFolders: (folders, {String? onlyFolderPath}) async {
            syncCalls++;
            return const FileSyncResult();
          },
        )..add(const LoadCustomFolders());

        await bloc.stream.firstWhere((state) => state.folders.isNotEmpty);

        bloc.add(SetFolderHidden(bloc.state.folders.single, true));
        await bloc.stream.firstWhere((state) => state.folders.single.hidden);

        expect(
          CustomFoldersManager.loadFolders(
            Settings.getValue<String>(SettingsRepository.keyCustomFolders),
          ).single.hidden,
          isTrue,
          reason: 'ההסתרה נשמרת להגדרות ולא רק ל-state',
        );
        expect(syncCalls, 0, reason: 'הסתרה אינה סורקת ואינה מוחקת מה-DB');
        expect(recordedEvents.whereType<RefreshLibrary>(), hasLength(1));

        bloc.add(SetFolderHidden(bloc.state.folders.single, false));
        await bloc.stream.firstWhere((state) => !state.folders.single.hidden);
        expect(recordedEvents.whereType<RefreshLibrary>(), hasLength(2));

        await bloc.close();
      },
    );
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
