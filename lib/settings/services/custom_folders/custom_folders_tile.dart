import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/widgets/confirmation_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/migration/sync/background_db_sync_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/migration/core/models/category.dart';
import 'package:otzaria/widgets/zip_extraction_progress_dialog.dart';

/// Widget להוספה וניהול תיקיות מותאמות אישית
class CustomFoldersTile extends StatefulWidget {
  const CustomFoldersTile({super.key});

  @override
  State<CustomFoldersTile> createState() => _CustomFoldersTileState();
}

class _CustomFoldersTileState extends State<CustomFoldersTile> {
  List<CustomFolder> _folders = [];
  bool _isExpanded = false;

  // _isSyncing is backed by the singleton queue — persists across widget rebuilds.
  // A freshly-opened screen immediately reflects a scan that started earlier.
  bool get _isSyncing => DatabaseLibraryProvider.operationQueue.isBusy;

  void _onBusyChanged() {
    if (mounted) setState(() {});
  }

  static const String _customFoldersReloadNotice =
      'לאחר הוספת ספרים חדשים לתיקייה קיימת, יש ללחוץ על סמל הרענון.';

  @override
  void initState() {
    super.initState();
    DatabaseLibraryProvider.operationQueue.busyCount
        .addListener(_onBusyChanged);
    _loadFolders();
  }

  @override
  void dispose() {
    DatabaseLibraryProvider.operationQueue.busyCount
        .removeListener(_onBusyChanged);
    super.dispose();
  }

  void _loadFolders() {
    final jsonString =
        Settings.getValue<String>(SettingsRepository.keyCustomFolders);
    setState(() {
      _folders = CustomFoldersManager.loadFolders(jsonString);
    });
  }

  Future<void> _saveFolders() async {
    final jsonString = CustomFoldersManager.saveFolders(_folders);
    await Settings.setValue(SettingsRepository.keyCustomFolders, jsonString);
  }

  Future<void> _addFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      // בדיקה שהתיקייה קיימת
      final dir = Directory(path);
      if (!await dir.exists()) {
        if (!mounted) return;
        UiSnack.showError('התיקייה לא נמצאה');
        return;
      }

      // בדיקה וחילוץ קובץ ZIP אם קיים - עם דיאלוג
      bool zipExtracted = false;
      String? extractedFileName;

      // בדיקה אם יש ZIP
      final zipFiles = dir
          .listSync()
          .where((entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.zip'))
          .cast<File>()
          .toList();

      if (zipFiles.isNotEmpty) {
        if (!mounted) return;

        await ZipExtractionProgressDialog.showAndExtract(
          context: context,
          path: path,
          onSuccess: (extractionResult) {
            if (extractionResult.successfullyExtracted) {
              zipExtracted = true;
              extractedFileName = extractionResult.extractedFileName;
            }
          },
          onError: (errorMessage) {
            UiSnack.showError(errorMessage);
          },
        );

        if (!mounted) return;
      }

      setState(() {
        _folders = CustomFoldersManager.addFolder(_folders, path);
        if (_folders.length == 1) {
          _isExpanded = true;
        }
      });
      await _saveFolders();

      // סריקת הספרים בתיקייה והוספתם ל-DB כספרים חיצוניים (ברקע).
      // RefreshLibrary מופעל אחרי גמר הסריקה כדי לא לחסום את ה-UI.
      // סריקה ברקע — _activeScanCount מנוהל בתוך _startBackgroundScan.
      _startBackgroundScan(path);

      if (!mounted) return;
      String successMessage =
          'התיקייה "${path.split(Platform.pathSeparator).last}" נוספה בהצלחה';
      if (zipExtracted && extractedFileName != null) {
        successMessage += '\nהקובץ "$extractedFileName" חולץ בהצלחה!';
      }
      UiSnack.show(
        successMessage,
        duration: const Duration(seconds: 9),
      );
    }
  }

  /// סריקת תיקייה והוספת הספרים שבה ל-DB כספרים חיצוניים (ברקע).
  ///
  /// מחזירה [Future<ScanResult>] שמסתיים כשכל כתיבות ה-DB גמורות.
  /// הקריאה אינה חוסמת — המתקשר צריך להגדיל את [_activeScanCount]
  /// לפני הקריאה ולהקטין אותו ב-then/catchError.
  Future<ScanResult> _scanAndAddExternalBooks(String folderPath) async {
    try {
      final sqliteProvider = SqliteDataProvider.instance;
      if (!sqliteProvider.isInitialized) {
        await sqliteProvider.initialize();
      }
      final repository = sqliteProvider.repository;
      if (repository == null) {
        debugPrint('Repository not available for scanning external books');
        return ScanResult(fatalError: 'מסד הנתונים לא זמין');
      }
      final folderName = folderPath.split(Platform.pathSeparator).last;
      return await DatabaseLibraryProvider.instance
          .scanAndAddExternalBooksFromFolder(
              folderPath, folderName, repository);
    } catch (e) {
      debugPrint('Error scanning external books: $e');
      return ScanResult(fatalError: e);
    }
  }

  /// מפעיל סריקה ברקע ומעדכן את ה-UI לפי התוצאה.
  /// הספירה מנוהלת על ידי operationQueue; אין צורך בספירה מקומית.
  void _startBackgroundScan(String folderPath) {
    if (!mounted) return;
    // תופסים רפרנס לפני הסריקה — RefreshLibrary יישלח גם אם ה-widget יתפרק
    // באמצע הסריקה (כגון שהמשתמש יסגור את המסך).
    final libraryBloc = context.read<LibraryBloc>();
    _scanAndAddExternalBooks(folderPath).then((result) {
      // רענון הספרייה תמיד — גם אם ה-widget כבר לא mounted.
      if (result.isSuccess) {
        libraryBloc.add(RefreshLibrary());
      }
      // הודעות UI רק אם ה-widget עדיין חי.
      if (!mounted) return;
      if (!result.isSuccess) {
        UiSnack.showError('שגיאת סריקה: ${result.fatalError}');
      } else if (result.hasPartialFailure) {
        UiSnack.show(
          '${result.addedBooks} ספרים נוספו, '
          '${result.updatedBooks} עודכנו '
          '(כשל: ${result.failedBooks})',
        );
      }
    });
  }

  /// הסרת תיקייה מהתוכנה.
  /// מנתק את הקישור של התיקייה מהתוכנה (התוכנה מפסיקה לסרוק אותה).
  /// שואל את המשתמש אם למחוק גם את הנתונים מה-DB.
  /// קבצים פיזיים לעולם לא נמחקים.
  Future<void> _removeFolder(CustomFolder folder) async {
    debugPrint(
        '[CustomFolders] _removeFolder START: name=${folder.name}, path=${folder.path}, addToDatabase=${folder.addToDatabase}');

    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'הסרת תיקייה',
      content: 'האם להסיר את התיקייה "${folder.name}" מהספרייה?\n'
          'הקבצים המקוריים לא יימחקו.',
      isDangerous: false,
    );

    if (confirmed != true) {
      debugPrint('[CustomFolders] _removeFolder CANCELLED by user');
      return;
    }

    // הסרת הקישור מהתוכנה (מפסיקה לסרוק את התיקייה)
    debugPrint('[CustomFolders] _removeFolder: removing link from settings...');
    setState(() {
      _folders = CustomFoldersManager.removeFolder(_folders, folder.path);
    });
    await _saveFolders();
    debugPrint(
        '[CustomFolders] _removeFolder: link removed. Remaining folders: ${_folders.length}');

    if (!mounted) return;

    // שואל אם למחוק גם מה-DB
    debugPrint(
        '[CustomFolders] _removeFolder: asking user about DB deletion...');
    final deleteFromDb = await showTwoActionsDialog(
      context: context,
      title: 'מחיקה ממסד הנתונים',
      content: 'התיקייה הוסרה מהרשימה.\n'
          'האם למחוק גם את הספרים ממסד הנתונים?',
      cancelText: 'השאר ב-DB',
      confirmText: 'מחק מ-DB',
    );

    if (deleteFromDb == true) {
      debugPrint('[CustomFolders] _removeFolder: user chose DELETE FROM DB');
      await _deleteFolderFromDatabase(folder);
      if (mounted) {
        UiSnack.show('התיקייה והספרים נמחקו ממסד הנתונים.');
      }
    } else {
      debugPrint('[CustomFolders] _removeFolder: user chose KEEP IN DB');
      if (mounted) {
        UiSnack.show('התיקייה הוסרה. הספרים נשארו במסד הנתונים.');
      }
    }

    // רענון הספרייה
    debugPrint('[CustomFolders] _removeFolder: refreshing library...');
    if (mounted) {
      context.read<LibraryBloc>().add(RefreshLibrary());
    }
    debugPrint('[CustomFolders] _removeFolder END');
  }

  /// מחיקת תיקייה מה-DB
  Future<void> _deleteFolderFromDatabase(CustomFolder folder) async {
    debugPrint(
        '[CustomFolders] _deleteFolderFromDatabase START: ${folder.name}');
    try {
      final sqliteProvider = SqliteDataProvider.instance;
      if (!sqliteProvider.isInitialized) {
        await sqliteProvider.initialize();
      }

      final repository = sqliteProvider.repository;
      if (repository == null) {
        debugPrint(
            '[CustomFolders] _deleteFolderFromDatabase: repository is NULL, aborting');
        return;
      }

      // Lightweight reads to resolve category IDs — done on main isolate.
      final rootCategories = await repository.getRootCategories();
      Category? personalCategory;
      for (final cat in rootCategories) {
        if (cat.title == 'ספרים אישיים') {
          personalCategory = cat;
          break;
        }
      }
      if (personalCategory == null) {
        debugPrint(
            '[CustomFolders] _deleteFolderFromDatabase: "ספרים אישיים" NOT FOUND');
        return;
      }

      final folderCategories =
          await repository.getCategoryChildren(personalCategory.id);
      Category? folderCategory;
      for (final cat in folderCategories) {
        if (cat.title == folder.name) {
          folderCategory = cat;
          break;
        }
      }
      if (folderCategory == null) {
        debugPrint(
            '[CustomFolders] _deleteFolderFromDatabase: "${folder.name}" NOT FOUND');
        return;
      }

      // Heavy recursive delete runs in a background isolate.
      // Serialisation is handled inside runDeleteFolderFromDbInIsolate.
      await runDeleteFolderFromDbInIsolate(
        dbPath: sqliteProvider.dbPath,
        folderCategoryId: folderCategory.id,
        personalCategoryId: personalCategory.id,
      );
      debugPrint(
          '[CustomFolders] _deleteFolderFromDatabase: deletion COMPLETE');
    } catch (e, stackTrace) {
      debugPrint('[CustomFolders] _deleteFolderFromDatabase ERROR: $e');
      debugPrint('[CustomFolders] stackTrace: $stackTrace');
    }
  }

  Future<void> _toggleAddToDatabase(CustomFolder folder, bool value) async {
    debugPrint(
        '[CustomFolders] _toggleAddToDatabase: ${folder.name}, newValue=$value (was ${folder.addToDatabase})');
    if (value) {
      // הצגת אזהרה לפני הפעלה
      final confirmed = await showConfirmationDialog(
        context: context,
        title: 'הכנסת תוכן ל-DB',
        content: 'תוכן הספרים יישמר במסד הנתונים.\n'
            'הקבצים המקוריים יישארו במקום.\n\n'
            'האם להמשיך?',
        isDangerous: false,
      );

      if (confirmed != true) {
        debugPrint('[CustomFolders] _toggleAddToDatabase ON cancelled by user');
        return;
      }

      debugPrint(
          '[CustomFolders] _toggleAddToDatabase ON confirmed, saving setting...');
      setState(() {
        _folders = CustomFoldersManager.updateFolderDbSetting(
            _folders, folder.path, value);
      });
      await _saveFolders();

      // הפעל סנכרון
      debugPrint('[CustomFolders] _toggleAddToDatabase ON: starting sync...');
      await _rescanCustomFolders(showNoChangesMessage: false);
    } else {
      // כיבוי - עדכון הגדרות והפעלת סנכרון כדי לנקות את ה-DB
      debugPrint('[CustomFolders] _toggleAddToDatabase OFF: saving setting');
      setState(() {
        _folders = CustomFoldersManager.updateFolderDbSetting(
            _folders, folder.path, value);
      });
      await _saveFolders();

      // הפעל סנכרון כדי להחיל את שינוי הסטטוס על הספרים
      debugPrint('[CustomFolders] _toggleAddToDatabase OFF: starting sync...');
      await _rescanCustomFolders(showNoChangesMessage: false);

      debugPrint('[CustomFolders] _toggleAddToDatabase OFF: done.');

      if (mounted) {
        UiSnack.show('תוכן הספרים נסרק ועודכן.\n'
            'מעתה הספרים ייקראו ישירות מהקבצים.');
      }
    }
  }

  Future<void> _rescanCustomFolders({bool showNoChangesMessage = true}) async {
    try {
      final sqliteProvider = SqliteDataProvider.instance;
      if (!sqliteProvider.isInitialized) {
        await sqliteProvider.initialize();
      }
      if (!sqliteProvider.isInitialized) {
        throw Exception('מסד הנתונים לא זמין');
      }

      final dbPath = sqliteProvider.dbPath;
      final libraryPath = Settings.getValue<String>('key-library-path');
      if (libraryPath == null || libraryPath.isEmpty) {
        throw Exception('נתיב הספרייה לא מוגדר');
      }

      // _folders already holds the up-to-date state saved before this call.
      // Serialisation is handled inside runCustomFoldersDbSyncInIsolate.
      final folderName =
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName) ??
              '';
      final result = await runCustomFoldersDbSyncInIsolate(
        dbPath: dbPath,
        libraryPath: libraryPath,
        customFolders: _folders,
        folderName: folderName,
      );

      // Store signature on main isolate after worker succeeds.
      await FileSyncService.saveCustomFoldersSignature(_folders);

      if (mounted) {
        context.read<LibraryBloc>().add(RefreshLibrary());
      }

      if (!mounted) return;

      final hasChanges = result.addedBooks > 0 || result.updatedBooks > 0;
      final message = hasChanges
          ? 'הסריקה הושלמה: ${result.addedBooks} ספרים נוספו, ${result.updatedBooks} עודכנו'
          : 'הסריקה הושלמה. לא נמצאו ספרים חדשים.';

      if (hasChanges || showNoChangesMessage) {
        UiSnack.show(message);
      }
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError('שגיאה בסריקת תיקיות אישיות: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(FluentIcons.folder_add_24_regular),
          title: const Text('הוסף תיקייה לאוצריא'),
          subtitle: Text(
            _folders.isEmpty
                ? 'לחץ להוספת תיקיות אישיות'
                : '${_folders.length} תיקיות',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          hoverColor: Colors.transparent,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_folders.isNotEmpty)
                IconButton(
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(FluentIcons.arrow_clockwise_24_regular),
                  onPressed: _isSyncing ? null : _rescanCustomFolders,
                  tooltip: 'סרוק מחדש תיקיות אישיות',
                ),
              RecommendedActionButton(
                text: 'הוסף תיקייה',
                icon: FluentIcons.folder_add_24_regular,
                onPressed: _addFolder,
                isLoading: _isSyncing,
              ),
              if (_folders.isNotEmpty)
                IconButton(
                  icon: Icon(
                    _isExpanded
                        ? FluentIcons.chevron_up_24_regular
                        : FluentIcons.chevron_down_24_regular,
                  ),
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  tooltip: _isExpanded ? 'הסתר' : 'הצג תיקיות',
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      FluentIcons.info_24_regular,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _customFoldersReloadNotice,
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isExpanded && _folders.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(right: 16, left: 16, bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: _folders.map((folder) {
                return _buildFolderItem(folder);
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildFolderItem(CustomFolder folder) {
    return ListTile(
      dense: true,
      leading: Icon(
        FluentIcons.folder_24_filled,
        color: Theme.of(context).colorScheme.primary,
        size: 20,
      ),
      title: Text(
        folder.name,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        folder.path,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle להכנסה ל-DB
          Tooltip(
            message: 'הכנס תוכן ל-DB',
            child: _isSyncing && folder.addToDatabase
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: folder.addToDatabase,
                    onChanged: _isSyncing
                        ? null
                        : (value) => _toggleAddToDatabase(folder, value),
                  ),
          ),
          // כפתור הסרה — חסום בזמן סריקה כדי למנוע כתיבה מקבילה ל-DB
          IconButton(
            icon: const Icon(FluentIcons.delete_24_regular, size: 18),
            onPressed: _isSyncing ? null : () => _removeFolder(folder),
            tooltip: 'הסר תיקייה',
          ),
        ],
      ),
    );
  }
}
