import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/migration/sync/background_db_sync_worker.dart';
import 'package:otzaria/migration/sync/background_sync_initializer.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart'
    show FileSyncResult;
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show clearCommentatorOrderCache;

part 'custom_folders_event.dart';
part 'custom_folders_state.dart';

typedef LoadCustomFoldersFn = List<CustomFolder> Function();
typedef SaveCustomFoldersFn = Future<void> Function(List<CustomFolder> folders);
typedef SyncCustomFoldersFn =
    Future<FileSyncResult> Function(
      List<CustomFolder> folders, {
      String? onlyFolderPath,
    });
typedef DeleteCustomFolderFromDbFn = Future<void> Function(CustomFolder folder);

class CustomFoldersBloc extends Bloc<CustomFoldersEvent, CustomFoldersState> {
  // תלות צרה במקום LibraryBloc מלא — בנייתו מאתחלת את כל ספקי הספרייה,
  // מה שמכביד על בדיקות ומרחיב את משטח התלויות שלא לצורך.
  final void Function(LibraryEvent event) _addLibraryEvent;
  final LoadCustomFoldersFn? _loadFoldersOverride;
  final SaveCustomFoldersFn? _saveFoldersOverride;
  final SyncCustomFoldersFn? _syncFoldersOverride;
  final DeleteCustomFolderFromDbFn? _deleteFolderFromDbOverride;

  CustomFoldersBloc({
    required this._addLibraryEvent,
    LoadCustomFoldersFn? loadFolders,
    SaveCustomFoldersFn? saveFolders,
    SyncCustomFoldersFn? syncFolders,
    DeleteCustomFolderFromDbFn? deleteFolderFromDb,
  }) : _loadFoldersOverride = loadFolders,
       _saveFoldersOverride = saveFolders,
       _syncFoldersOverride = syncFolders,
       _deleteFolderFromDbOverride = deleteFolderFromDb,
       super(const CustomFoldersState()) {
    on<LoadCustomFolders>(_onLoad);
    on<AddCustomFolder>(_onAdd);
    on<RemoveCustomFolder>(_onRemove);
    on<ToggleAddToDatabase>(_onToggleAddToDatabase);
    on<RescanCustomFolders>(_onRescan);
    on<ImportUserContentFiles>(_onImportUserFiles);
    on<ClearUserContent>(_onClearUserContent);
  }

  void _onLoad(LoadCustomFolders event, Emitter<CustomFoldersState> emit) {
    emit(state.copyWith(folders: _loadFolders()));
  }

  /// רענון הספרייה בעקבות סריקת תיקיות אישיות שהסתיימה, בדילוג על prune
  /// מיותר. רק סריקה שכיסתה את כל התיקיות מייתרת את סנכרון הרקע של הסשן —
  /// סריקה ממוקדת (תיקייה אחת) לא מכסה תיקיות אחרות וקובצי links.
  void _refreshLibraryAfterScan(
    Set<String> changedBookKeys, {
    bool coversAllFolders = false,
  }) {
    if (coversAllFolders) {
      BackgroundSyncInitializer.markCustomFoldersSyncedThisSession();
    }
    _addLibraryEvent(
      RefreshLibrary(
        changedBookKeys: changedBookKeys,
        source: RefreshSource.customFoldersScan,
      ),
    );
  }

  Future<void> _onAdd(
    AddCustomFolder event,
    Emitter<CustomFoldersState> emit,
  ) async {
    final currentFolders = _loadFolders();
    final newFolders = CustomFoldersManager.addFolder(
      currentFolders,
      event.path,
    );
    await _saveFolders(newFolders);
    emit(
      state.copyWith(
        folders: newFolders,
        isSyncing: true,
        activePath: event.path,
        message: null,
        error: null,
      ),
    );

    try {
      final repository = await UserBooksDatabaseHolder.instance.repository;
      final folderName = event.path.split(RegExp(r'[/\\]')).last;
      final result = await DatabaseLibraryProvider.instance
          .scanAndAddExternalBooksFromFolder(
            event.path,
            folderName,
            repository,
          );

      if (result.isSuccess) {
        _refreshLibraryAfterScan({
          for (final id in result.updatedBookIds)
            IndexingRepository.userBookKey(id),
        });
        if (result.hasPartialFailure) {
          final failedMsg = result.failedDetails.isNotEmpty
              ? result.failedDetails.map((d) => '"${d.$1}": ${d.$2}').join('\n')
              : 'כשל: ${result.failedBooks}';
          emit(
            state.copyWith(
              isSyncing: false,
              error: [
                '${result.addedBooks} ספרים נוספו, ${result.updatedBooks} עודכנו',
                if (failedMsg.isNotEmpty) failedMsg,
              ].join('\n'),
            ),
          );
        } else {
          emit(
            state.copyWith(
              isSyncing: false,
              message: result.hasChanges
                  ? '${result.addedBooks} ספרים נוספו, ${result.updatedBooks} עודכנו'
                  : 'התיקייה נוספה. לא נמצאו ספרים חדשים.',
            ),
          );
        }
      } else {
        emit(
          state.copyWith(
            isSyncing: false,
            error: 'שגיאת סריקה: ${result.fatalError}',
          ),
        );
      }
    } catch (e) {
      emit(state.copyWith(isSyncing: false, error: 'שגיאה בסריקת התיקייה: $e'));
    }
  }

  Future<void> _onRemove(
    RemoveCustomFolder event,
    Emitter<CustomFoldersState> emit,
  ) async {
    final currentFolders = _loadFolders();
    final newFolders = CustomFoldersManager.removeFolder(
      currentFolders,
      event.folder.path,
    );
    await _saveFolders(newFolders);
    emit(state.copyWith(folders: newFolders, message: null, error: null));

    if (event.deleteFromDb) {
      emit(state.copyWith(isSyncing: true, message: null, error: null));
      try {
        await _deleteFolderFromDb(event.folder);
        emit(
          state.copyWith(
            isSyncing: false,
            message: 'התיקייה והספרים הוסרו מהתוכנה.',
          ),
        );
      } catch (e) {
        emit(
          state.copyWith(
            isSyncing: false,
            error: 'שגיאה בהסרת הספרים מהתוכנה: $e',
          ),
        );
        return;
      }
    } else {
      emit(
        state.copyWith(
          message: 'התיקייה הוסרה. הספרים נשארו בתוכנה.',
        ),
      );
    }
    _addLibraryEvent(RefreshLibrary());
  }

  Future<void> _onToggleAddToDatabase(
    ToggleAddToDatabase event,
    Emitter<CustomFoldersState> emit,
  ) async {
    final currentFolders = _loadFolders();
    final newFolders = CustomFoldersManager.updateFolderDbSetting(
      currentFolders,
      event.folder.path,
      event.value,
    );
    await _saveFolders(newFolders);
    emit(
      state.copyWith(
        folders: newFolders,
        isSyncing: true,
        activePath: event.folder.path,
        message: null,
        error: null,
      ),
    );

    try {
      // סריקה ממוקדת לתיקייה שהוחלפה בלבד — שינוי תיקייה אחת לא צריך לסרוק
      // מחדש את כל התיקיות ולהריץ prune מלא על כל הספרים האישיים.
      final result = await _syncCustomFolders(
        newFolders,
        onlyFolderPath: event.folder.path,
      );
      if (!event.value) {
        emit(
          state.copyWith(
            isSyncing: false,
            message:
                'תוכן הספרים נסרק ועודכן.\nמעתה הספרים ייקראו ישירות מהקבצים.',
          ),
        );
      } else {
        final hasChanges = result.addedBooks > 0 || result.updatedBooks > 0;
        emit(
          state.copyWith(
            isSyncing: false,
            message: hasChanges
                ? 'הסריקה הושלמה: ${result.addedBooks} ספרים נוספו, '
                      '${result.updatedBooks} עודכנו'
                : null,
          ),
        );
      }
      _refreshLibraryAfterScan({
        for (final id in result.updatedBookIds)
          IndexingRepository.userBookKey(id),
      });
    } catch (e) {
      emit(state.copyWith(isSyncing: false, error: 'שגיאה בסנכרון: $e'));
    }
  }

  Future<void> _onRescan(
    RescanCustomFolders event,
    Emitter<CustomFoldersState> emit,
  ) async {
    final currentFolders = _loadFolders();
    emit(
      state.copyWith(
        folders: currentFolders,
        isSyncing: true,
        message: null,
        error: null,
      ),
    );
    try {
      final result = await _syncCustomFolders(
        currentFolders,
        onlyFolderPath: event.onlyFolderPath,
      );
      final hasChanges = result.addedBooks > 0 || result.updatedBooks > 0;
      final message = hasChanges
          ? 'הסריקה הושלמה: ${result.addedBooks} ספרים נוספו, '
                '${result.updatedBooks} עודכנו'
          : event.showNoChangesMessage
          ? 'הסריקה הושלמה. לא נמצאו ספרים חדשים.'
          : null;
      emit(state.copyWith(isSyncing: false, message: message));
      _refreshLibraryAfterScan(
        {
          for (final id in result.updatedBookIds)
            IndexingRepository.userBookKey(id),
        },
        // כשל חלקי לא מסומן כהשלמה — סנכרון הרקע יקבל הזדמנות לנסות שוב.
        coversAllFolders: event.onlyFolderPath == null && result.errors.isEmpty,
      );
    } catch (e) {
      emit(
        state.copyWith(
          isSyncing: false,
          error: 'שגיאה בסריקת תיקיות אישיות: $e',
        ),
      );
    }
  }

  /// מייבא דורות וקישורים מקבצים שהמשתמש בחר — לצמיתות, בדריסה מצטברת. מנקה
  /// את מטמוני הדור כדי שהשינוי ייכנס לתוקף מיד.
  Future<void> _onImportUserFiles(
    ImportUserContentFiles event,
    Emitter<CustomFoldersState> emit,
  ) async {
    if (event.paths.isEmpty) return;
    emit(state.copyWith(isSyncing: true, message: null, error: null));
    try {
      final userDb =
          (await UserBooksDatabaseHolder.instance.repository).database;
      final r = await importUserFilesSafe(event.paths, userDb);
      if (r.generationsApplied > 0 || r.linksApplied > 0) {
        GenerationCache.instance.clear();
        clearCommentatorOrderCache();
        CommentaryService.clearEraCache();
        _addLibraryEvent(RefreshLibrary());
      }
      final imp = (
        generations: r.generationsApplied,
        links: r.linksApplied,
        errors: r.errors,
      );
      emit(
        state.copyWith(
          isSyncing: false,
          message:
              _importSummary(imp) ??
              (r.errors.isEmpty
                  ? 'לא נמצאו נתונים לייבוא בקבצים שנבחרו.'
                  : null),
          error: _importErrorText(imp),
        ),
      );
    } catch (e) {
      emit(state.copyWith(isSyncing: false, error: 'שגיאה בייבוא הקבצים: $e'));
    }
  }

  /// מוחק את כל הדורות והקישורים המיובאים ומנקה את מטמוני הדור.
  Future<void> _onClearUserContent(
    ClearUserContent event,
    Emitter<CustomFoldersState> emit,
  ) async {
    emit(state.copyWith(isSyncing: true, message: null, error: null));
    try {
      final userDb =
          (await UserBooksDatabaseHolder.instance.repository).database;
      await UserContentRepository(userDb).clearAllUserContent();
      GenerationCache.instance.clear();
      clearCommentatorOrderCache();
      CommentaryService.clearEraCache();
      _addLibraryEvent(RefreshLibrary());
      emit(
        state.copyWith(
          isSyncing: false,
          message: 'הדורות והקישורים המיובאים נמחקו.',
        ),
      );
    } catch (e) {
      emit(state.copyWith(isSyncing: false, error: 'שגיאה במחיקת הנתונים: $e'));
    }
  }

  /// תקציר ייבוא להודעה, או null אם לא יובא דבר.
  String? _importSummary(
    ({int generations, int links, List<String> errors}) imp,
  ) {
    final parts = <String>[];
    if (imp.generations > 0) parts.add('${imp.generations} דורות');
    if (imp.links > 0) parts.add('${imp.links} קישורים');
    return parts.isEmpty ? null : 'יובאו ${parts.join(' ו-')}';
  }

  String? _importErrorText(
    ({int generations, int links, List<String> errors}) imp,
  ) {
    if (imp.errors.isEmpty) return null;
    final shown = imp.errors.take(10).join('\n');
    final more = imp.errors.length > 10
        ? '\nועוד ${imp.errors.length - 10}…'
        : '';
    return 'שגיאות בייבוא הקבצים:\n$shown$more';
  }

  List<CustomFolder> _loadFolders() {
    final override = _loadFoldersOverride;
    if (override != null) {
      return override();
    }

    final jsonString = Settings.getValue<String>(
      SettingsRepository.keyCustomFolders,
    );
    return CustomFoldersManager.loadFolders(jsonString);
  }

  Future<FileSyncResult> _syncCustomFolders(
    List<CustomFolder> folders, {
    String? onlyFolderPath,
  }) {
    final override = _syncFoldersOverride;
    if (override != null) {
      return override(folders, onlyFolderPath: onlyFolderPath);
    }

    return _runSync(folders, onlyFolderPath: onlyFolderPath);
  }

  Future<void> _deleteFolderFromDb(CustomFolder folder) {
    final override = _deleteFolderFromDbOverride;
    if (override != null) {
      return override(folder);
    }

    return _deleteFromDatabase(folder);
  }

  Future<FileSyncResult> _runSync(
    List<CustomFolder> folders, {
    String? onlyFolderPath,
  }) async {
    final sqliteProvider = SqliteDataProvider.instance;
    if (!sqliteProvider.isInitialized) await sqliteProvider.initialize();
    if (!sqliteProvider.isInitialized) throw Exception('מסד הנתונים לא זמין');

    final dbPath = sqliteProvider.dbPath;
    final libraryPath = Settings.getValue<String>(
      SettingsRepository.keyLibraryPath,
    );
    if (libraryPath == null || libraryPath.isEmpty) {
      throw Exception('נתיב הספרייה לא מוגדר');
    }

    final folderName =
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
        '';
    final userBooksDbPath = await UserBooksDatabaseHolder.resolveDbPath();

    // הסנכרון כותב אך ורק ל-user_books.db ופותח את seforim.db read-only,
    // ולכן אין צורך לסגור את חיבור ה-RO הראשי.
    return await runCustomFoldersDbSyncInIsolate(
      dbPath: dbPath,
      userBooksDbPath: userBooksDbPath,
      libraryPath: libraryPath,
      customFolders: folders,
      folderName: folderName,
      onlyFolderPath: onlyFolderPath,
    );
  }

  Future<void> _deleteFromDatabase(CustomFolder folder) async {
    final sqliteProvider = SqliteDataProvider.instance;
    if (!sqliteProvider.isInitialized) await sqliteProvider.initialize();

    final userBooksDbPath = await UserBooksDatabaseHolder.resolveDbPath();

    // הזיהוי הוא לפי נתיב התיקייה (שם ה-source הייחודי), לא לפי שם
    // הקטגוריה — כך הסרת תיקייה לא תפגע בספרי תיקייה אחרת בעלת אותו
    // basename שממוזגת לאותה קטגוריה.
    // ה-close/reopen של ה-RO מנוהלים *בתוך* [runDeleteFolderFromDbInIsolate].
    // ההגדרות כבר נשמרו בלי התיקייה — _loadFolders מחזיר את הנשארות, כדי
    // שספרי legacy של תיקיית-בן מקוננת לא יימחקו עם האב.
    await runDeleteFolderFromDbInIsolate(
      dbPath: sqliteProvider.dbPath,
      userBooksDbPath: userBooksDbPath,
      folderPath: folder.path,
      otherConfiguredFolderPaths: [
        for (final other in _loadFolders())
          if (other.path != folder.path) other.path,
      ],
      prepareForWrite: sqliteProvider.closeForExternalWrite,
      restoreAfterWrite: sqliteProvider.reopenAfterExternalWrite,
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
