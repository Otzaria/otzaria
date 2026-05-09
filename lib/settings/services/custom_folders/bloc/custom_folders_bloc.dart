import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/sync/background_db_sync_worker.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';

part 'custom_folders_event.dart';
part 'custom_folders_state.dart';

typedef LoadCustomFoldersFn = List<CustomFolder> Function();
typedef SaveCustomFoldersFn = Future<void> Function(List<CustomFolder> folders);
typedef SyncCustomFoldersFn = Future<FileSyncResult> Function(
  List<CustomFolder> folders,
);
typedef DeleteCustomFolderFromDbFn = Future<void> Function(CustomFolder folder);

class CustomFoldersBloc extends Bloc<CustomFoldersEvent, CustomFoldersState> {
  final LibraryBloc _libraryBloc;
  final LoadCustomFoldersFn? _loadFoldersOverride;
  final SaveCustomFoldersFn? _saveFoldersOverride;
  final SyncCustomFoldersFn? _syncFoldersOverride;
  final DeleteCustomFolderFromDbFn? _deleteFolderFromDbOverride;

  CustomFoldersBloc({
    required LibraryBloc libraryBloc,
    LoadCustomFoldersFn? loadFolders,
    SaveCustomFoldersFn? saveFolders,
    SyncCustomFoldersFn? syncFolders,
    DeleteCustomFolderFromDbFn? deleteFolderFromDb,
  })  : _libraryBloc = libraryBloc,
        _loadFoldersOverride = loadFolders,
        _saveFoldersOverride = saveFolders,
        _syncFoldersOverride = syncFolders,
        _deleteFolderFromDbOverride = deleteFolderFromDb,
        super(const CustomFoldersState()) {
    on<LoadCustomFolders>(_onLoad);
    on<AddCustomFolder>(_onAdd);
    on<RemoveCustomFolder>(_onRemove);
    on<ToggleAddToDatabase>(_onToggleAddToDatabase);
    on<RescanCustomFolders>(_onRescan);
  }

  void _onLoad(LoadCustomFolders event, Emitter<CustomFoldersState> emit) {
    emit(state.copyWith(folders: _loadFolders()));
  }

  Future<void> _onAdd(
      AddCustomFolder event, Emitter<CustomFoldersState> emit) async {
    final currentFolders = _loadFolders();
    final newFolders =
        CustomFoldersManager.addFolder(currentFolders, event.path);
    await _saveFolders(newFolders);
    emit(state.copyWith(
      folders: newFolders,
      isSyncing: true,
      message: null,
      error: null,
    ));

    try {
      final sqliteProvider = SqliteDataProvider.instance;
      if (!sqliteProvider.isInitialized) await sqliteProvider.initialize();
      final repository = sqliteProvider.repository;
      if (repository == null) {
        emit(state.copyWith(isSyncing: false, error: 'מסד הנתונים לא זמין'));
        return;
      }
      final folderName = event.path.split(RegExp(r'[/\\]')).last;
      final result = await DatabaseLibraryProvider.instance
          .scanAndAddExternalBooksFromFolder(
              event.path, folderName, repository);

      if (result.isSuccess) {
        _libraryBloc.add(RefreshLibrary());
        if (result.hasPartialFailure) {
          emit(state.copyWith(
            isSyncing: false,
            error:
                '${result.addedBooks} ספרים נוספו, ${result.updatedBooks} עודכנו (כשל: ${result.failedBooks})',
          ));
        } else {
          emit(state.copyWith(isSyncing: false));
        }
      } else {
        emit(state.copyWith(
            isSyncing: false, error: 'שגיאת סריקה: ${result.fatalError}'));
      }
    } catch (e) {
      emit(state.copyWith(isSyncing: false, error: 'שגיאה בסריקת התיקייה: $e'));
    }
  }

  Future<void> _onRemove(
      RemoveCustomFolder event, Emitter<CustomFoldersState> emit) async {
    final currentFolders = _loadFolders();
    final newFolders =
        CustomFoldersManager.removeFolder(currentFolders, event.folder.path);
    await _saveFolders(newFolders);
    emit(state.copyWith(folders: newFolders, message: null, error: null));

    if (event.deleteFromDb) {
      emit(state.copyWith(isSyncing: true, message: null, error: null));
      try {
        await _deleteFolderFromDb(event.folder);
        emit(state.copyWith(
          isSyncing: false,
          message: 'התיקייה והספרים נמחקו ממסד הנתונים.',
        ));
      } catch (e) {
        emit(state.copyWith(
          isSyncing: false,
          error: 'שגיאה במחיקת התיקייה ממסד הנתונים: $e',
        ));
        return;
      }
    } else {
      emit(state.copyWith(
        message: 'התיקייה הוסרה. הספרים נשארו במסד הנתונים.',
      ));
    }
    _libraryBloc.add(RefreshLibrary());
  }

  Future<void> _onToggleAddToDatabase(
      ToggleAddToDatabase event, Emitter<CustomFoldersState> emit) async {
    final currentFolders = _loadFolders();
    final newFolders = CustomFoldersManager.updateFolderDbSetting(
      currentFolders,
      event.folder.path,
      event.value,
    );
    await _saveFolders(newFolders);
    emit(state.copyWith(
      folders: newFolders,
      isSyncing: true,
      message: null,
      error: null,
    ));

    try {
      final result = await _syncCustomFolders(newFolders);
      if (!event.value) {
        emit(state.copyWith(
          isSyncing: false,
          message:
              'תוכן הספרים נסרק ועודכן.\nמעתה הספרים ייקראו ישירות מהקבצים.',
        ));
      } else {
        final hasChanges = result.addedBooks > 0 || result.updatedBooks > 0;
        emit(state.copyWith(
          isSyncing: false,
          message: hasChanges
              ? 'הסריקה הושלמה: ${result.addedBooks} ספרים נוספו, ${result.updatedBooks} עודכנו'
              : null,
        ));
      }
      _libraryBloc.add(RefreshLibrary());
    } catch (e) {
      emit(state.copyWith(isSyncing: false, error: 'שגיאה בסנכרון: $e'));
    }
  }

  Future<void> _onRescan(
      RescanCustomFolders event, Emitter<CustomFoldersState> emit) async {
    final currentFolders = _loadFolders();
    emit(state.copyWith(
      folders: currentFolders,
      isSyncing: true,
      message: null,
      error: null,
    ));
    try {
      final result = await _syncCustomFolders(currentFolders);
      final hasChanges = result.addedBooks > 0 || result.updatedBooks > 0;
      final message = hasChanges
          ? 'הסריקה הושלמה: ${result.addedBooks} ספרים נוספו, ${result.updatedBooks} עודכנו'
          : event.showNoChangesMessage
              ? 'הסריקה הושלמה. לא נמצאו ספרים חדשים.'
              : null;
      emit(state.copyWith(isSyncing: false, message: message));
      _libraryBloc.add(RefreshLibrary());
    } catch (e) {
      emit(state.copyWith(
          isSyncing: false, error: 'שגיאה בסריקת תיקיות אישיות: $e'));
    }
  }

  List<CustomFolder> _loadFolders() {
    final override = _loadFoldersOverride;
    if (override != null) {
      return override();
    }

    final jsonString =
        Settings.getValue<String>(SettingsRepository.keyCustomFolders);
    return CustomFoldersManager.loadFolders(jsonString);
  }

  Future<FileSyncResult> _syncCustomFolders(List<CustomFolder> folders) {
    final override = _syncFoldersOverride;
    if (override != null) {
      return override(folders);
    }

    return _runSync(folders);
  }

  Future<void> _deleteFolderFromDb(CustomFolder folder) {
    final override = _deleteFolderFromDbOverride;
    if (override != null) {
      return override(folder);
    }

    return _deleteFromDatabase(folder);
  }

  Future<FileSyncResult> _runSync(List<CustomFolder> folders) async {
    final sqliteProvider = SqliteDataProvider.instance;
    if (!sqliteProvider.isInitialized) await sqliteProvider.initialize();
    if (!sqliteProvider.isInitialized) throw Exception('מסד הנתונים לא זמין');

    final dbPath = sqliteProvider.dbPath;
    final libraryPath = Settings.getValue<String>('key-library-path');
    if (libraryPath == null || libraryPath.isEmpty) {
      throw Exception('נתיב הספרייה לא מוגדר');
    }

    final folderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
            '';
    final result = await runCustomFoldersDbSyncInIsolate(
      dbPath: dbPath,
      libraryPath: libraryPath,
      customFolders: folders,
      folderName: folderName,
    );
    await FileSyncService.saveCustomFoldersSignature(folders);
    return result;
  }

  Future<void> _deleteFromDatabase(CustomFolder folder) async {
    final sqliteProvider = SqliteDataProvider.instance;
    if (!sqliteProvider.isInitialized) await sqliteProvider.initialize();
    final repository = sqliteProvider.repository;
    if (repository == null) return;

    final rootCategories = await repository.getRootCategories();
    Category? personalCategory;
    for (final cat in rootCategories) {
      if (cat.title == 'ספרים אישיים') {
        personalCategory = cat;
        break;
      }
    }
    if (personalCategory == null) return;

    final folderCategories =
        await repository.getCategoryChildren(personalCategory.id);
    Category? folderCategory;
    for (final cat in folderCategories) {
      if (cat.title == folder.name) {
        folderCategory = cat;
        break;
      }
    }
    if (folderCategory == null) return;

    await runDeleteFolderFromDbInIsolate(
      dbPath: sqliteProvider.dbPath,
      folderCategoryId: folderCategory.id,
      personalCategoryId: personalCategory.id,
    );
  }

  Future<void> _saveFolders(List<CustomFolder> folders) async {
    final override = _saveFoldersOverride;
    if (override != null) {
      await override(folders);
      return;
    }

    await Settings.setValue(
      SettingsRepository.keyCustomFolders,
      CustomFoldersManager.saveFolders(folders),
    );
  }
}
