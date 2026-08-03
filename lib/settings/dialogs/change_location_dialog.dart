import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/move_directory.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

class ChangeLocationResult {
  final String newPath;
  final bool moveContents;

  const ChangeLocationResult(this.newPath, {required this.moveContents});
}

/// מרכז את לוגיקת הדיאלוג, UiSnack, וביצוע הפעולה.
/// [onPathChanged] — עדכון נתיב ללא העברת קבצים.
/// [onAfterMove] — עדכון state לאחר שהקבצים הועברו (moveDirectory נקרא כאן אוטומטית).
/// [onMoveContents] — מסלול העברה מותאם (למשל הספרייה, שדורש סגירת DB ורענון);
/// כשהוא מסופק הוא מחליף לגמרי את moveDirectory+onAfterMove.
/// [moveContentsWarning] — טקסט אזהרה שיוצג בדיאלוג כשבוחרים "העבר תוכן".
Future<void> Function(BuildContext) makeChangeLocationCallback({
  required String currentPath,
  required String folderName,
  required Future<void> Function(String newPath) onPathChanged,
  Future<void> Function(String newPath)? onAfterMove,
  Future<void> Function(BuildContext ctx, String from, String to)?
  onMoveContents,
  String? moveContentsWarning,
  String? defaultPath,
}) {
  final canMoveContents =
      (onAfterMove != null || onMoveContents != null) && currentPath.isNotEmpty;
  return (ctx) async {
    final result = await showChangeLocationDialog(
      context: ctx,
      currentPath: currentPath,
      folderName: folderName,
      canMoveContents: canMoveContents,
      defaultPath: defaultPath,
      moveContentsWarning: moveContentsWarning,
    );
    if (result == null) return;

    if (!(result.moveContents && canMoveContents)) {
      await onPathChanged(result.newPath);
      return;
    }

    if (onMoveContents != null) {
      if (!ctx.mounted) return;
      await onMoveContents(ctx, currentPath, result.newPath);
      return;
    }

    UiSnack.showChecking(SettingsMessages.movingFolderFiles(folderName));
    try {
      final deleteWarning = await moveDirectory(currentPath, result.newPath);
      await onAfterMove!(result.newPath);
      UiSnack.hide();
      if (deleteWarning != null) {
        UiSnack.showWarning(
          SettingsMessages.folderMovedSourceNotDeleted(
            folderName,
            deleteWarning,
          ),
        );
      } else {
        UiSnack.show(SettingsMessages.folderMoved(folderName));
      }
    } catch (e) {
      UiSnack.hide();
      UiSnack.showError(SettingsMessages.folderMoveError(folderName, e));
    }
  };
}

/// סורק את ספרי הספרייה שבתוך [from] ומחזיר:
/// - [include]: שמות הרשומות העליונות שיש להעביר (קבצי DB מנוהלים + ספרי
///   קובץ מזוהים). כך מועברים רק ספרים מזוהים, וקבצים אקראיים שהמשתמש הוסיף
///   נשארים במקומם.
/// - [relocated]: ספרי קובץ שרשומתם באינדקס נשמרת לפי נתיב מוחלט (PDF, וספרי
///   קובץ ללא id יציב), ולכן רשומתם תישבר בהעברה ויש לנקותה אחרי ההעברה.
Future<({Set<String> include, List<Book> relocated})> _scanLibraryMove(
  String from,
) async {
  final include = DatabaseConstants.libraryManagedEntryNames();
  final relocated = <Book>[];
  try {
    final library = await DataRepository.instance.library;
    for (final book in library.getAllBooks()) {
      if (book is! FileBook) continue;
      final path = book.path;
      if (path.isEmpty) continue;
      if (!p.equals(from, path) && !p.isWithin(from, path)) continue;
      final segments = p.split(p.relative(path, from: from));
      if (segments.isNotEmpty && segments.first.isNotEmpty) {
        include.add(segments.first);
      }
      if (IndexingRepository.hasPathKeyedIndexEntry(book)) relocated.add(book);
    }
  } catch (e) {
    debugPrint('[performLibraryMove] library scan failed: $e');
  }
  return (include: include, relocated: relocated);
}

Future<void> remapMovedFileBookPaths(
  Iterable<Book> books,
  String from,
  String to,
) async {
  final movedBooks = books.where((book) {
    if (book is! FileBook || book.id == null) {
      return false;
    }
    return p.equals(from, book.path) || p.isWithin(from, book.path);
  }).cast<FileBook>();

  if (movedBooks.isEmpty) return;

  final userBooks = movedBooks.where((book) => book.isUserBook).toList();
  if (userBooks.isEmpty) return;

  final repository = await UserBooksDatabaseHolder.instance.repository;
  for (final book in userBooks) {
    final storage = await _movedStorage(book, from, to);
    await repository.updateBookStorage(
      book.id!,
      storage.path,
      storage.fileSize,
      storage.lastModified,
    );
  }
}

Future<({String path, int? fileSize, int? lastModified})> _movedStorage(
  FileBook book,
  String from,
  String to,
) async {
  final newPath = p.join(to, p.relative(book.path, from: from));
  final file = File(newPath);
  final exists = await file.exists();
  return (
    path: newPath,
    fileSize: exists ? await file.length() : null,
    lastModified: exists
        ? (await file.lastModified()).millisecondsSinceEpoch
        : null,
  );
}

@visibleForTesting
bool shouldCopyIndexDuringLibraryMove({
  required bool indexNeedsMove,
  required bool indexingActive,
}) => indexNeedsMove && !indexingActive;

Future<bool> _pathExists(String path) async =>
    await Directory(path).exists() ||
    await File(path).exists() ||
    await Link(path).exists();

Future<void> _ensureMoveTargetAvailable(String path) async {
  if (await _pathExists(path)) {
    throw FileSystemException('יעד ההעברה כבר קיים', path);
  }
}

Future<void> _deleteIfExists(String path) async {
  if (await Directory(path).exists()) {
    await Directory(path).delete(recursive: true);
  } else if (await File(path).exists()) {
    await File(path).delete();
  } else if (await Link(path).exists()) {
    await Link(path).delete();
  }
}

Future<void> _restoreMoveSettings({
  required String? libraryPath,
  required String? libraryFolderName,
  required String? dbEffectivePath,
  required String? indexPath,
  required String? databasesPath,
  required String? androidLibraryRoot,
}) async {
  await Settings.setValue<String?>(
    SettingsRepository.keyLibraryPath,
    libraryPath,
  );
  await Settings.setValue<String?>(
    SettingsRepository.keyLibraryFolderName,
    libraryFolderName,
  );
  await Settings.setValue<String?>(
    SettingsRepository.keyDbEffectivePath,
    dbEffectivePath,
  );
  await Settings.setValue<String?>(SettingsRepository.keyIndexPath, indexPath);
  await Settings.setValue<String?>(
    SettingsRepository.keyDatabasesPath,
    databasesPath,
  );
  if (Platform.isAndroid) {
    await Settings.setValue<String?>(
      SettingsRepository.keyAndroidLibraryRoot,
      androidLibraryRoot,
    );
  }
}

Future<void> _cleanupCreatedMoveTargets({
  String? stagingRoot,
  required String newLibrary,
  required String newIndex,
  required String newDatabases,
  required bool finalLibraryCreated,
  required bool finalIndexCreated,
  required bool finalDatabasesCreated,
}) async {
  if (stagingRoot != null) {
    try {
      await _deleteIfExists(stagingRoot);
    } catch (e) {
      debugPrint('[performLibraryMove] staging cleanup failed: $e');
    }
  }
  if (finalLibraryCreated) {
    try {
      await _deleteIfExists(newLibrary);
    } catch (e) {
      debugPrint('[performLibraryMove] library cleanup failed: $e');
    }
  }
  if (finalIndexCreated) {
    try {
      await _deleteIfExists(newIndex);
    } catch (e) {
      debugPrint('[performLibraryMove] index cleanup failed: $e');
    }
  }
  if (finalDatabasesCreated) {
    try {
      await _deleteIfExists(newDatabases);
    } catch (e) {
      debugPrint('[performLibraryMove] databases cleanup failed: $e');
    }
  }
}

@visibleForTesting
Future<void> ensureLibraryMoveTargetAvailableForTesting(String path) =>
    _ensureMoveTargetAvailable(path);

@visibleForTesting
Future<void> cleanupCreatedMoveTargetsForTesting({
  String? stagingRoot,
  required String newLibrary,
  required String newIndex,
  required String newDatabases,
  required bool finalLibraryCreated,
  required bool finalIndexCreated,
  required bool finalDatabasesCreated,
}) => _cleanupCreatedMoveTargets(
  stagingRoot: stagingRoot,
  newLibrary: newLibrary,
  newIndex: newIndex,
  newDatabases: newDatabases,
  finalLibraryCreated: finalLibraryCreated,
  finalIndexCreated: finalIndexCreated,
  finalDatabasesCreated: finalDatabasesCreated,
);

Future<void> _closeUserDatabasesForMove() async {
  await UserBooksDatabaseHolder.instance.close();
  await CacheDatabaseHolder.instance.close();
  await PersonalNotesDatabase.instance.close();
  await PluginSystemDatabase.instance.close();
}

/// מעביר את ספריית אוצריא למיקום חדש. [to] היא התיקייה שהמשתמש בחר, ותחתיה
/// נוצרות `<to>/books`, `<to>/index` ו-`<to>/databases`, כך שמבנה
/// התיקיות נשמר ולא נשפך לתיקיית האב.
///
/// סדר בטוח שמתמודד עם נעילת קבצים: מעתיק קודם ל-staging, מקדם ליעד הסופי
/// רק אחרי הצלחה, מעדכן הגדרות, סוגר חיבורים, ורק אחרי רענון מוחק את המקור.
/// אינדקס חי בזמן אינדוקס לא מועתק; הוא נפתח/נבנה מחדש במיקום החדש.
Future<void> performLibraryMove({
  required BuildContext context,
  required String from,
  required String to,
}) async {
  final newLibrary = p.join(to, p.basename(from));
  if (p.equals(from, newLibrary)) return;
  if (p.isWithin(from, newLibrary)) {
    UiSnack.showError(SettingsMessages.cannotMoveLibraryIntoItself);
    return;
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  _showBlockingProgress(
    context,
    context.settingsText(
      'מעביר את הספרייה למיקום החדש…\nהתוכנה לא תהיה פעילה עד לסיום הפעולה.',
    ),
  );

  final scan = await _scanLibraryMove(from);
  final include = scan.include;
  final oldIndex = await AppPaths.getIndexPath();
  final newIndex = p.join(to, p.basename(oldIndex));
  final oldDatabases = await AppPaths.getDatabasesPath();
  final newDatabases = p.join(to, p.basename(oldDatabases));
  final indexNeedsMove =
      !p.equals(oldIndex, newIndex) && await Directory(oldIndex).exists();
  final databasesNeedsMove =
      !p.equals(oldDatabases, newDatabases) &&
      await Directory(oldDatabases).exists();
  final indexingActive = TantivyDataProvider.instance.isIndexing.value;
  final shouldCopyIndex = shouldCopyIndexDuringLibraryMove(
    indexNeedsMove: indexNeedsMove,
    indexingActive: indexingActive,
  );
  if (indexingActive) {
    IndexingRepository(TantivyDataProvider.instance).cancelIndexing();
  }

  final previousLibraryPath = Settings.getValue<String>(
    SettingsRepository.keyLibraryPath,
  );
  final previousLibraryFolderName = Settings.getValue<String>(
    SettingsRepository.keyLibraryFolderName,
  );
  final previousDbEffectivePath = Settings.getValue<String>(
    SettingsRepository.keyDbEffectivePath,
  );
  final previousIndexPath = Settings.getValue<String>(
    SettingsRepository.keyIndexPath,
  );
  final previousDatabasesPath = Settings.getValue<String>(
    SettingsRepository.keyDatabasesPath,
  );
  // Android: שורש הספרייה נע ליעד החדש (למשל כרטיס SD) כך שברירת המחדל של
  // הספרייה תישאר עקבית. שאר נתוני האפליקציה נשארים באחסון הפנימי.
  final previousAndroidLibraryRoot = Settings.getValue<String>(
    SettingsRepository.keyAndroidLibraryRoot,
  );

  String? stagingRoot;
  var finalLibraryCreated = false;
  var finalIndexCreated = false;
  var finalDatabasesCreated = false;
  var settingsUpdated = false;

  try {
    await _ensureMoveTargetAvailable(newLibrary);
    if (indexNeedsMove) {
      await _ensureMoveTargetAvailable(newIndex);
    }
    if (databasesNeedsMove) {
      await _ensureMoveTargetAvailable(newDatabases);
      await _closeUserDatabasesForMove();
    }

    final staging = await Directory(
      p.join(to, '.otzaria_move_${DateTime.now().millisecondsSinceEpoch}'),
    ).create(recursive: true);
    stagingRoot = staging.path;
    final stagedLibrary = p.join(staging.path, p.basename(newLibrary));
    final stagedIndex = p.join(staging.path, p.basename(newIndex));
    final stagedDatabases = p.join(staging.path, p.basename(newDatabases));

    // 1. מעתיקים ל-staging בלבד. אם ההעתקה נכשלת, היעד הסופי נשאר נקי.
    await copyDirectoryEntries(from, stagedLibrary, includeOnly: include);
    if (shouldCopyIndex) {
      await copyDirectoryEntries(oldIndex, stagedIndex);
    }
    if (databasesNeedsMove) {
      await copyDirectoryEntries(oldDatabases, stagedDatabases);
    }
    await Directory(stagedLibrary).rename(newLibrary);
    finalLibraryCreated = true;
    if (shouldCopyIndex) {
      await Directory(stagedIndex).rename(newIndex);
      finalIndexCreated = true;
    }
    if (databasesNeedsMove) {
      await Directory(stagedDatabases).rename(newDatabases);
      finalDatabasesCreated = true;
    }
    await _deleteIfExists(staging.path);
    stagingRoot = null;

    // 2. עדכון נתיבי ספרי קובץ שהועברו יחד עם הספרייה.
    await remapMovedFileBookPaths(scan.relocated, from, newLibrary);
    // 3. עדכון הגדרות המיקום בקבצי המשתמש.
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      newLibrary,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
    if (indexNeedsMove) {
      // בזמן אינדוקס פעיל לא מעתיקים אינדקס חי; הרענון יפתח/יבנה אינדקס חדש.
      await Settings.setValue<String>(
        SettingsRepository.keyIndexPath,
        newIndex,
      );
    }
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      newDatabases,
    );
    if (Platform.isAndroid) {
      await Settings.setValue<String>(
        SettingsRepository.keyAndroidLibraryRoot,
        to,
      );
    }
    settingsUpdated = true;
    // 4. מיפוי נתיבי הספרים הפתוחים *בזיכרון* (לא רק ב-Hive), אחרת שמירת
    //    הטאבים בעת הרענון תדרוס את המיפוי וה-PDF ייפתח מהנתיב הישן.
    //    awaited בכוונה: חובה שהמיפוי יושלם לפני ה-reset/restart, אחרת יש race.
    if (context.mounted) {
      await context.read<TabsBloc>().remapBookPathsAwaitable(from, newLibrary);
    }
    // 5. סגירת חיבורי ה-DB (משחרר את נעילת seforim.db) והפניה למיקום החדש.
    await resetRuntimeStateForAppRestart();
    // 6. פתיחה מחדש של האינדקס בנתיב החדש — סוגר את האינדקס הישן ומשחרר אותו.
    try {
      await TantivyDataProvider.instance.reopenIndex();
    } catch (e) {
      // כשל בפתיחת האינדקס אינו עוצר את ההעברה — הרענון/אינדוקס מחדש יתקן.
      debugPrint('[performLibraryMove] reopenIndex failed: $e');
    }
    if (indexNeedsMove &&
        !shouldCopyIndex &&
        await Directory(newIndex).exists()) {
      finalIndexCreated = true;
    }
    // 7. ניקוי רשומות אינדקס של ספרי קובץ שנתיבם השתנה (PDF וכו'), כדי
    //    שהאינדוקס שלאחר הרענון יוסיף אותם בנתיב החדש בלי כפילויות. ספרי
    //    הטקסט מ-DB מאונדקסים לפי id ושורדים את ההעברה — אינם נוגעים בזה.
    if (scan.relocated.isNotEmpty) {
      try {
        await IndexingRepository(
          TantivyDataProvider.instance,
        ).dropRelocatedFileBookEntries(scan.relocated);
      } catch (e) {
        debugPrint('[performLibraryMove] index cleanup failed: $e');
      }
    }
  } catch (e) {
    if (settingsUpdated) {
      await _restoreMoveSettings(
        libraryPath: previousLibraryPath,
        libraryFolderName: previousLibraryFolderName,
        dbEffectivePath: previousDbEffectivePath,
        indexPath: previousIndexPath,
        databasesPath: previousDatabasesPath,
        androidLibraryRoot: previousAndroidLibraryRoot,
      );
    }
    await _cleanupCreatedMoveTargets(
      stagingRoot: stagingRoot,
      newLibrary: newLibrary,
      newIndex: newIndex,
      newDatabases: newDatabases,
      finalLibraryCreated: finalLibraryCreated,
      finalIndexCreated: finalIndexCreated,
      finalDatabasesCreated: finalDatabasesCreated,
    );
    if (navigator.canPop()) navigator.pop();
    UiSnack.showError(SettingsMessages.libraryMoveError(e));
    return;
  }

  if (!context.mounted) return;
  if (navigator.canPop()) navigator.pop();

  await showSingleActionDialog(
    context: context,
    title: context.settingsText('הספרייה הועברה'),
    content: context.settingsText(
      'הספרייה הועברה בהצלחה למיקום החדש. התוכנה תיטען מחדש כעת, '
      'והספרים הפתוחים ייטענו מהמיקום החדש.',
    ),
    confirmText: context.settingsText('טען מחדש'),
  );
  if (!context.mounted) return;
  // רענון מלא: בונה מחדש את עץ הווידג'טים, טוען את הספרייה והטאבים מהמיקום
  // החדש, וסוגר את הספרים הפתוחים — מה שמשחרר את נעילת קובצי ה-PDF הישנים.
  RestartWidget.restartApp(
    context,
    afterRestart: () async {
      await WebViewEnvironmentHolder.disposeForAppRestart();
      // המתנה קצרה לשחרור מלא של file-handles של הספרים שנסגרו, לפני המחיקה.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final leftover = await deleteMovedEntries(from, includeOnly: include);
      var indexDeleteFailed = false;
      var databasesDeleteFailed = false;
      if (indexNeedsMove && await Directory(oldIndex).exists()) {
        try {
          await Directory(oldIndex).delete(recursive: true);
        } catch (_) {
          indexDeleteFailed = true;
        }
      }
      if (databasesNeedsMove && await Directory(oldDatabases).exists()) {
        try {
          await Directory(oldDatabases).delete(recursive: true);
        } catch (_) {
          databasesDeleteFailed = true;
        }
      }
      if (leftover != null || indexDeleteFailed || databasesDeleteFailed) {
        UiSnack.showWarning(SettingsMessages.libraryMovedOldFilesLeft);
      }
    },
  );
}

void _showBlockingProgress(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: settingsDialogBuilder(
      context,
      (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<ChangeLocationResult?> showChangeLocationDialog({
  required BuildContext context,
  required String currentPath,
  required String folderName,
  bool canMoveContents = true,
  String? defaultPath,
  String? moveContentsWarning,
}) => showDialog<ChangeLocationResult>(
  context: context,
  builder: settingsDialogBuilder(
    context,
    (_) => _ChangeLocationDialogContent(
      currentPath: currentPath,
      folderName: folderName,
      canMoveContents: canMoveContents,
      defaultPath: defaultPath,
      moveContentsWarning: moveContentsWarning,
    ),
  ),
);

class _ChangeLocationDialogContent extends StatefulWidget {
  final String currentPath;
  final String folderName;
  final bool canMoveContents;
  final String? defaultPath;
  final String? moveContentsWarning;

  const _ChangeLocationDialogContent({
    required this.currentPath,
    required this.folderName,
    required this.canMoveContents,
    this.defaultPath,
    this.moveContentsWarning,
  });

  @override
  State<_ChangeLocationDialogContent> createState() =>
      _ChangeLocationDialogContentState();
}

class _ChangeLocationDialogContentState
    extends State<_ChangeLocationDialogContent> {
  String? _selectedPath;
  late bool _moveContents;

  @override
  void initState() {
    super.initState();
    _moveContents = widget.canMoveContents;
  }

  // true כשהמיקום האפקטיבי (נבחר או נוכחי) כבר שווה לברירת המחדל
  bool get _isAtDefault =>
      (_selectedPath ?? widget.currentPath) == widget.defaultPath;

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath(lockParentWindow: true);
    if (path != null && mounted) setState(() => _selectedPath = path);
  }

  void _confirm() {
    if (_selectedPath == null) return;
    Navigator.of(context).pop(
      ChangeLocationResult(_selectedPath!, moveContents: _moveContents),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCustomContentDialog(
      title: locationDialogTitle(
        folderName: widget.folderName,
        isSetup: widget.currentPath.isEmpty,
      ),
      onConfirm: _selectedPath != null ? _confirm : null,
      handleEnterKey: _selectedPath != null,
      actions: [
        ActionButton.ghost(
          text: context.settingsText('ביטול'),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        ActionButton.recommended(
          text: context.settingsText('אישור'),
          onPressed: _selectedPath != null ? _confirm : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCard(
            title: context.settingsText('פעולה'),
            subtitle: context.settingsText(
              'בחר אם להעביר את קבצי הספרייה למיקום החדש, או לעדכן את ההגדרה בלבד',
            ),
            children: [
              if (widget.canMoveContents)
                SettingsActionTile.radioOption(
                  title: context.settingsText('העבר תוכן תיקייה'),
                  subtitle: context.settingsText(
                    'כל הקבצים יועברו מהמיקום הנוכחי למיקום החדש',
                  ),
                  selected: _moveContents,
                  onTap: () => setState(() => _moveContents = true),
                ),
              SettingsActionTile.radioOption(
                title: widget.currentPath.isEmpty
                    ? context.settingsText('הגדרת מיקום')
                    : context.settingsText('שנה מיקום בלבד'),
                subtitle: widget.currentPath.isEmpty
                    ? context.settingsText(
                        'האפשרות היחידה — ההגדרה תעודכן לנתיב שתבחר',
                      )
                    : context.settingsText(
                        'ההגדרה תעודכן, הקבצים יישארו במיקומם הנוכחי',
                      ),
                selected: !_moveContents,
                onTap: widget.canMoveContents
                    ? () => setState(() => _moveContents = false)
                    : null,
              ),
            ],
          ),
          if (widget.moveContentsWarning != null && _moveContents)
            MoveContentsWarning(text: widget.moveContentsWarning!),
          TargetFolderSection(
            folderName: widget.folderName,
            isSetup: widget.currentPath.isEmpty,
            selectedPath: _selectedPath,
            defaultPath: widget.defaultPath,
            isAtDefault: _isAtDefault,
            onPickFolder: _pickFolder,
            onUseDefault: () =>
                setState(() => _selectedPath = widget.defaultPath),
          ),
        ],
      ),
    );
  }
}

class MoveContentsWarning extends StatelessWidget {
  final String text;

  const MoveContentsWarning({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.info_24_regular, color: cs.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.settingSubtitle.copyWith(
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// כותרת דיאלוג מיקום — "הגדרת מיקום X" כשאין מיקום קודם, אחרת "שינוי מיקום X".
/// משותפת לדיאלוג הרגיל ולדיאלוג הספרייה כדי לשמור נוסח אחיד.
String locationDialogTitle({
  required String folderName,
  required bool isSetup,
}) => isSetup ? 'הגדרת מיקום $folderName' : 'שינוי מיקום $folderName';

/// מקטע בחירת תיקיית היעד — משותף לדיאלוג הרגיל ולדיאלוג הספרייה.
/// [isSetup] קובע את הכותרת: "תיקיית היעד ל..." כשאין מיקום קודם,
/// אחרת "מיקום חדש". "מיקום ברירת מחדל" מוצג לפני "בחירת מיקום".
class TargetFolderSection extends StatelessWidget {
  final String folderName;
  final bool isSetup;
  final String? selectedPath;
  final String? defaultPath;
  final bool isAtDefault;
  final VoidCallback onPickFolder;
  final VoidCallback onUseDefault;

  const TargetFolderSection({
    super.key,
    required this.folderName,
    required this.isSetup,
    required this.selectedPath,
    required this.defaultPath,
    required this.isAtDefault,
    required this.onPickFolder,
    required this.onUseDefault,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: isSetup
          ? context.settingsText(
              'תיקיית היעד ל{folder}',
              args: {'folder': folderName},
            )
          : context.settingsText('מיקום חדש'),
      subtitle: context.settingsText(
        'בחר מיקום מותאם אישית, או השתמש במיקום ברירת המחדל של האפליקציה',
      ),
      children: [
        if (defaultPath != null && defaultPath!.isNotEmpty)
          SettingsActionTile.path(
            icon: FluentIcons.home_24_regular,
            title: context.settingsText('מיקום ברירת מחדל'),
            path: defaultPath,
            placeholder: '',
            enabled: !isAtDefault,
            actions: [
              ActionButton.neutral(
                text: context.settingsText('השתמש בברירת מחדל'),
                onPressed: isAtDefault ? null : onUseDefault,
              ),
            ],
          ),
        SettingsActionTile.path(
          icon: FluentIcons.folder_open_24_regular,
          title: context.settingsText('בחירת מיקום'),
          path: selectedPath,
          placeholder: context.settingsText('טרם נבחר מיקום'),
          actions: [
            ActionButton.recommended(
              text: context.settingsText(
                selectedPath == null ? 'בחר תיקייה' : 'שנה מיקום',
              ),
              onPressed: onPickFolder,
              icon: FluentIcons.folder_open_24_regular,
            ),
          ],
        ),
      ],
    );
  }
}
