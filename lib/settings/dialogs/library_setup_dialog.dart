import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/android_storage_service.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/settings/services/custom_folders/android_folder_import_channel.dart';
import 'package:otzaria/settings/dialogs/change_location_dialog.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/widgets/expandable_settings_tile.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/move_directory.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// דיאלוג מאוחד להגדרת/עדכון מיקום הספרייה. יוצר [EmptyLibraryBloc] משלו
/// ומחזיר `true` אם הספרייה הוגדרה/עודכנה/הועברה בהצלחה.
/// [currentLibraryPath] ריק → מצב הגדרה ראשונית; אחרת מצב עדכון/רלוקציה.
Future<bool> showLibrarySetupDialog({
  required BuildContext context,
  required String defaultTargetPath,
  String? currentLibraryPath,
  String folderName = 'ספריית אוצריא',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: settingsDialogBuilder(
      context,
      (_) => BlocProvider<EmptyLibraryBloc>(
        create: (_) =>
            debugCreateLibrarySetupBloc?.call() ?? EmptyLibraryBloc(),
        child: _LibrarySetupDialogContent(
          defaultTargetPath: defaultTargetPath,
          currentLibraryPath: currentLibraryPath,
          folderName: folderName,
        ),
      ),
    ),
  );
  return result ?? false;
}

/// מחליף את ה-bloc של הדיאלוג בבדיקות (למשל פריסה מזויפת שממתינה לביטול).
@visibleForTesting
EmptyLibraryBloc Function()? debugCreateLibrarySetupBloc;

/// מחליף את בורר התיקיות של אנדרואיד בבדיקות.
@visibleForTesting
Future<PackageFolder?> Function()? debugPickAndroidSourceFolder;

/// מחליף את יעדי האחסון של אנדרואיד בבדיקות (ומדמה בכך אנדרואיד).
@visibleForTesting
Future<List<({bool isRemovable, String root})>> Function()?
debugAndroidStorageChoices;

/// אחסון פנימי, ולצדו כל כרטיס SD (תיקיית האפליקציה שעליו).
Future<List<({bool isRemovable, String root})>> _androidStorageChoices() async {
  final internal = (isRemovable: false, root: await AppPaths.getDataRootPath());
  final options = await AndroidStorageService.listStorageOptions();
  return [
    internal,
    for (final option in options)
      if (option.libraryRoot != null)
        (isRemovable: true, root: option.libraryRoot!),
  ];
}

enum _LibraryAction { moveContents, useInPlace, download, chooseFolder }

/// תוצאת סריקת תיקיית מקור. [source] null — התוכנה אינה מורשית לקרוא אותה.
@visibleForTesting
class LibraryFolderScan {
  final LibrarySourceScan? source;
  const LibraryFolderScan(this.source);

  bool get readable => source != null;
  Set<LibraryComponent> get found => source?.components ?? const {};
}

/// בדיקת קריאה בפועל של קובץ שנמצא. ב-Android Scoped Storage `exists()` מחזיר
/// true גם לקובץ שאין לאפליקציה הרשאה לפתוח (issue #1219).
@visibleForTesting
Future<void> Function(File file)? debugLibraryFolderReadProbe;

Future<void> _probeRead(File file) async {
  final handle = await file.open();
  await handle.close();
}

/// סורק תיקיית מקור: חבילת מסייע ההורדה, או קובצי הספרייה עצמם (ראה
/// [scanLibrarySource]).
@visibleForTesting
Future<LibraryFolderScan> scanLibraryFolder(PackageFolder folder) async {
  final LibrarySourceScan source;
  try {
    source = await scanLibrarySource(folder);
  } on FileSystemException {
    return const LibraryFolderScan(null);
  }
  final probe = _firstLocalFile(source);
  if (probe != null) {
    try {
      await (debugLibraryFolderReadProbe ?? _probeRead)(File(probe));
    } on PathAccessException {
      return const LibraryFolderScan(null);
    }
  }
  return LibraryFolderScan(source);
}

/// קובץ ראשון לבדיקת קריאה — רק בתיקייה רגילה; SAF כבר העניק גישה.
String? _firstLocalFile(LibrarySourceScan source) {
  final packages = source.packages.packages;
  if (packages != null) {
    return source.folder.localPath(packages.library.parts.first.entry);
  }
  for (final asset in source.raw.assets.values) {
    final path = asset.parts.isEmpty
        ? null
        : asset.folder.localPath(asset.parts.first.entry);
    if (path != null) return path;
  }
  return null;
}

class _LibrarySetupDialogContent extends StatefulWidget {
  final String folderName;
  final String defaultTargetPath;
  final String? currentLibraryPath;

  const _LibrarySetupDialogContent({
    required this.folderName,
    required this.defaultTargetPath,
    this.currentLibraryPath,
  });

  @override
  State<_LibrarySetupDialogContent> createState() =>
      _LibrarySetupDialogContentState();
}

class _LibrarySetupDialogContentState
    extends State<_LibrarySetupDialogContent> {
  _LibraryAction? _action;
  String? _targetRoot;

  /// מה נמצא בתיקיית המקור שנבחרה (פעולת [_LibraryAction.chooseFolder]).
  LibraryFolderScan? _source;

  /// תיקייה שנבחרה לשימוש במקומה, והאם נמצא בה seforim.db לא-דחוס. שימוש
  /// במקום דורש DB מוכן — גרסה דחוסה מחייבת חילוץ, כלומר ייבוא רגיל.
  String? _inPlaceFolder;
  bool _inPlaceHasDatabase = false;

  /// הרכיבים הקיימים כבר בספרייה הנוכחית (רלוונטי בעדכון במקום — הם יישמרו).
  Set<LibraryComponent> _systemAssets = const {};

  /// האם מקטע "מחיקה וייבוא" (הורדה/ייבוא) פרוס — רלוונטי כשיש ספרייה.
  bool _replaceExpanded = false;

  /// נתיב האינדקס הישן — נלכד בעליית הדיאלוג כדי שנוכל למחוק אותו ברלוקציה.
  String? _oldIndexPath;

  /// סיכום הייבוא כשחסרים בספרייה רכיבים; הדיאלוג נסגר רק אחרי שהמשתמש ראה.
  LibraryImportReport? _report;

  /// יעדי האחסון באנדרואיד; null בשולחן העבודה (בורר תיקיות חופשי).
  List<({bool isRemovable, String root})>? _storageChoices;

  bool get _hasLibrary => (widget.currentLibraryPath ?? '').isNotEmpty;

  /// שימוש במקום מוצע בשולחן העבודה בלבד: ב-Android/iOS ספרייה בתיקייה שאינה
  /// של האפליקציה אינה נגישה ל-sqlite3 native, וה-DB נאלץ להיות מועתק פנימה.
  bool get _inPlaceSupported => !Platform.isAndroid && !Platform.isIOS;

  /// שורש הספרייה הקיימת (ההורה של books/index), או null במצב הגדרה.
  String? get _currentRoot =>
      _hasLibrary ? AppPaths.libraryRootOf(widget.currentLibraryPath!) : null;

  /// היעד שונה מהמיקום הנוכחי → רלוקציה (כתיבה ליעד חדש ומחיקת הישן).
  bool get _isRelocating => _hasLibrary && _targetRoot != _currentRoot;

  @override
  void initState() {
    super.initState();
    // ברירת המחדל: העברת תוכן כשיש ספרייה, אחרת הורדה מהאינטרנט.
    _action = _hasLibrary
        ? _LibraryAction.moveContents
        : _LibraryAction.download;
    _targetRoot = _hasLibrary
        ? _currentRoot
        : (widget.defaultTargetPath.isEmpty ? null : widget.defaultTargetPath);
    if (Platform.isAndroid || debugAndroidStorageChoices != null) {
      _storageChoices = const [];
      (debugAndroidStorageChoices ?? _androidStorageChoices)()
          .then((choices) {
            if (mounted) setState(() => _storageChoices = choices);
          })
          .catchError((_) {});
    }
    if (_hasLibrary) {
      // best-effort: הנתיב נחוץ רק למחיקת האינדקס הישן ברלוקציה.
      AppPaths.getIndexPath()
          .then((path) {
            if (mounted) _oldIndexPath = path;
          })
          .catchError((_) {});
      // סורק אילו רכיבים כבר קיימים בספרייה — כדי לא להזהיר על מה שכבר יש.
      scanLibraryFolder(DirectoryPackageFolder(widget.currentLibraryPath!))
          .then((scan) {
            if (mounted) setState(() => _systemAssets = scan.found);
          })
          .catchError((_) {});
    }
  }

  bool get _isAtDefaultRoot => _targetRoot == widget.defaultTargetPath;

  bool get _targetOnSdCard =>
      _storageChoices?.any((c) => c.isRemovable && c.root == _targetRoot) ??
      false;

  Future<void> _pickTargetRoot() async {
    final path = await FilePicker.getDirectoryPath(
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
      dialogTitle: context.settingsText('בחר את תיקיית היעד לספרייה'),
    );
    if (path != null && mounted) setState(() => _targetRoot = path);
  }

  /// בוחר תיקיית מקור לייבוא וסורק אילו רכיבי ספרייה נמצאו בה.
  Future<void> _pickSourceFolder() async {
    final PackageFolder? folder;
    if (Platform.isAndroid || debugPickAndroidSourceFolder != null) {
      folder = await (debugPickAndroidSourceFolder ?? _pickSafFolder)();
    } else {
      final path = await FilePicker.getDirectoryPath(
        windowsOptions: kModalWindowsOptions,
        linuxOptions: kModalLinuxOptions,
        dialogTitle: context.settingsText('בחר תיקייה המכילה את קבצי הספרייה'),
      );
      folder = path == null ? null : DirectoryPackageFolder(path);
    }
    if (folder == null || !mounted) return;
    LibraryFolderScan scan;
    try {
      scan = await scanLibraryFolder(folder);
    } on PlatformException catch (e) {
      debugPrint('[LibrarySetup] סריקת התיקייה ב-SAF נכשלה: $e');
      scan = const LibraryFolderScan(null);
    }
    if (!mounted) return;
    setState(() => _source = scan);
  }

  /// באנדרואיד ל-dart:io אין גישה לתיקייה שנבחרה — כל הקריאה עוברת דרך SAF.
  static Future<PackageFolder?> _pickSafFolder() async {
    final picked = await const AndroidFolderImportChannel().pickFolder();
    return picked == null
        ? null
        : SafPackageFolder(treeUri: picked.uri, name: picked.name);
  }

  /// בוחר תיקיית ספרייה קיימת לשימוש במקומה (ללא העתקה).
  Future<void> _pickInPlaceFolder() async {
    final folder = await FilePicker.getDirectoryPath(
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
      dialogTitle: context.settingsText('בחר את תיקיית הספרייה הקיימת'),
    );
    if (folder == null || !mounted) return;
    final hasDb = await File(
      p.join(folder, DatabaseConstants.databaseFileName),
    ).exists();
    if (!mounted) return;
    setState(() {
      _inPlaceFolder = folder;
      _inPlaceHasDatabase = hasDb;
    });
  }

  /// רכיב יהיה קיים לאחר הייבוא אם נמצא בתיקיית המקור, או שהוא כבר קיים
  /// בספרייה בעדכון במקום (רלוקציה כותבת רק את מה שיובא).
  bool _presentAfterImport(LibraryComponent component) {
    if (_source?.found.contains(component) ?? false) return true;
    return _hasLibrary && !_isRelocating && _systemAssets.contains(component);
  }

  bool _canConfirm(EmptyLibraryState state) {
    switch (_action) {
      case _LibraryAction.useInPlace:
        // שימוש במקום אינו כותב לשום מקום — תיקיית היעד אינה רלוונטית לו.
        return _inPlaceFolder != null && _inPlaceHasDatabase;
      case _LibraryAction.moveContents:
        // העברת תוכן ליעד זהה למיקום הנוכחי היא no-op — דורש יעד שונה.
        return _targetRoot != null && _isRelocating;
      case _LibraryAction.download:
        return _targetRoot != null && state.downloadDisabledReason == null;
      case _LibraryAction.chooseFolder:
        final source = _source?.source;
        if (_targetRoot == null || source == null) return false;
        if (source.packages.packages != null) return true;
        if (source.raw.assets.isEmpty) return false;
        // חובה שקובץ הספרייה יהיה קיים לאחר הייבוא (מהתיקייה או מספרייה קיימת).
        return _presentAfterImport(LibraryComponent.libraryDb);
      case null:
        return false;
    }
  }

  /// תת-כותרת לאפשרות "שימוש בספרייה קיימת": לפני בחירה — הנחיה; אחרי בחירה —
  /// הנתיב שנבחר, או הסבר מדוע התיקייה אינה מתאימה.
  String _inPlaceSubtitle() {
    final folder = _inPlaceFolder;
    if (folder == null) {
      return context.settingsText(
        'בחר תיקייה שמכילה את {file} — הקבצים יישארו במקומם ולא יועתקו',
        args: {'file': DatabaseConstants.databaseFileName},
      );
    }
    if (!_inPlaceHasDatabase) {
      return context.settingsText(
        'לא נמצא {file} בתיקייה שנבחרה',
        args: {'file': DatabaseConstants.databaseFileName},
      );
    }
    return folder;
  }

  /// תת-כותרת לאפשרות הייבוא: לפני בחירה — הנחיה; אחרי בחירה — מה נמצא או
  /// מדוע אי אפשר להמשיך. הפירוט לפי רכיב מוצג מתחת לכרטיס.
  String _importSubtitle() {
    final scan = _source;
    if (scan == null) {
      // מ-Android 11 בורר התיקיות חוסם את שורש Download ואת שורש האחסון.
      if (Platform.isAndroid) {
        return context.settingsText(
          'בחר את התיקייה שבה נמצאים קובצי הספרייה — בזיכרון המכשיר או בכרטיס זיכרון, גם תיקייה שחולצה מהקובץ שהורד. את התיקייה Download עצמה Android אינו מאפשר לבחור: העתיקו את הקבצים לתיקייה בתוכה',
        );
      }
      return context.settingsText(
        'בחר תיקייה שקיימים בה קובצי הספרייה — גם קבצים שהוכנו במסייע ההורדה',
      );
    }
    final source = scan.source;
    if (source == null) {
      return context.settingsText(
        'לתוכנה אין הרשאת קריאה לתיקייה שנבחרה — יש לבחור תיקייה אחרת',
      );
    }
    final packageText = _packageSubtitle(source.packages);
    if (packageText != null) return packageText;
    final problem = source.raw.problem;
    if (problem != null) {
      return context.settingsText(
        'קובץ הספרייה נמצא אך אינו שלם: {problem}',
        args: {'problem': problem},
      );
    }
    if (!_presentAfterImport(LibraryComponent.libraryDb)) {
      return context.settingsText(
        'לא נמצא בתיקייה קובץ הספרייה (seforim.db או seforim.db.zst) — לא ניתן להמשיך בלי הספרייה',
      );
    }
    return context.settingsText('נמצאו קובצי הספרייה — הפירוט למטה');
  }

  /// תיאור קובצי המסייע שנמצאו, או מה חסר בהם. null — אין קובצי מסייע, או
  /// שהם פגומים אבל לצדם ספרייה רגילה שתיובא במקומם.
  String? _packageSubtitle(LibraryPackageScan scan) {
    if (scan.isEmpty) return null;
    final packages = scan.packages;
    if (packages != null) {
      return context.settingsText(
        packages.index == null
            ? 'נמצאה ספרייה מקבצים שהורדו (גרסה {version})'
            : 'נמצאה ספרייה מקבצים שהורדו (גרסה {version}), כולל אינדקס חיפוש מוכן',
        args: {'version': packages.version},
      );
    }
    if (_source?.found.contains(LibraryComponent.libraryDb) ?? false) {
      return null;
    }
    final file = scan.problemFile ?? '';
    return switch (scan.problem!) {
      LibraryPackageProblem.incompleteParts => context.settingsText(
        _source?.source?.singleVolume ?? false
            ? 'חסר הקובץ {file} — כנראה ששאר קובצי ה-ZIP חולצו לתיקיות שלצד התיקייה שנבחרה. יש לבחור את התיקייה שמכילה את כולן'
            : Platform.isAndroid
            ? 'חסר הקובץ {file} — יש לחלץ את כל קובצי ה-ZIP ולבחור את התיקייה שאליה חולצו, גם אם כל אחד חולץ לתיקייה משלו'
            : 'חסר הקובץ {file} — יש להכין את התיקייה מחדש במסייע ההורדה',
        args: {'file': file},
      ),
      LibraryPackageProblem.conflictingParts => context.settingsText(
        'הקובץ {file} נמצא בשתי תיקיות בגדלים שונים — יש למחוק את התיקיות שחולצו ולחלץ מחדש את כל קובצי ה-ZIP',
        args: {'file': file},
      ),
      LibraryPackageProblem.invalidManifest => context.settingsText(
        Platform.isAndroid
            ? 'הקובץ {file} פגום — יש להוריד ולחלץ מחדש את קובץ ה-ZIP שבו הוא נמצא'
            : 'הקובץ {file} פגום — יש להכין את התיקייה מחדש במסייע ההורדה',
        args: {'file': file},
      ),
      LibraryPackageProblem.indexWithoutLibrary => context.settingsText(
        'בתיקייה יש אינדקס חיפוש בלי הספרייה עצמה',
      ),
    };
  }

  void _confirm() {
    switch (_action) {
      case _LibraryAction.moveContents:
        _moveExisting();
      case _LibraryAction.useInPlace:
        _useInPlace();
      case _LibraryAction.download:
        _download();
      case _LibraryAction.chooseFolder:
        _import();
      case null:
        break;
    }
  }

  void _useInPlace() {
    final folder = _inPlaceFolder;
    if (folder == null) return;
    context.read<EmptyLibraryBloc>().add(UseLibraryInPlaceRequested(folder));
  }

  void _moveExisting() {
    final root = _targetRoot;
    if (root == null) return;
    // performLibraryMove יוצר books+index תחת היעד ומטפל בסגירת ה-DB, ברענון
    // ובמחיקת הקבצים הישנים.
    performLibraryMove(
      context: context,
      from: widget.currentLibraryPath!,
      to: root,
    );
  }

  void _download() {
    final bloc = context.read<EmptyLibraryBloc>();
    if (_hasLibrary && !_isRelocating) {
      bloc.add(
        UpdateLibraryRequested(
          targetPath: widget.currentLibraryPath!,
          existingLibraryPath: widget.currentLibraryPath!,
        ),
      );
    } else {
      final root = _targetRoot;
      if (root == null) return;
      bloc.add(DownloadLibraryRequested(targetPath: p.join(root, 'books')));
    }
  }

  void _import() {
    final root = _targetRoot;
    final source = _source?.source;
    if (root == null || source == null) return;
    final books = p.join(root, 'books');
    final inPlace = _hasLibrary && !_isRelocating;
    final packages = source.packages.packages;
    if (packages != null) {
      context.read<EmptyLibraryBloc>().add(
        ImportLibraryPackageRequested(
          packages: packages,
          targetPath: books,
          backupExistingPath: inPlace ? widget.currentLibraryPath : null,
        ),
      );
      return;
    }
    // גיבוי ה-DB הישן רק בעדכון במקום שמחליף את seforim.db (אחרת המחיקה של
    // הגיבוי בהצלחה הייתה מוחקת DB שלא הוחלף). רלוקציה → מחיקת הישן ב-listener.
    final replacesDb = source.raw.assets.containsKey(
      LibraryComponent.libraryDb,
    );
    context.read<EmptyLibraryBloc>().add(
      ImportLibraryFolderRequested(
        assets: source.raw,
        targetPath: books,
        backupExistingPath: inPlace && replacesDb
            ? widget.currentLibraryPath
            : null,
      ),
    );
  }

  /// לאחר רלוקציה מוצלחת: משחרר את חיבורי ה-DB/אינדקס הישנים ומוחק את קבצי
  /// הספרייה המנוהלים ואת האינדקס במיקום הישן. best-effort — קבצי משתמש
  /// שאינם מנוהלים נשמרים, וכשל במחיקה מציג אזהרה בלבד.
  Future<void> _deleteOldAfterRelocation() async {
    final leftoverWarning = context.settingsText(
      'הספרייה עודכנה במיקום החדש, אך חלק מהקבצים הישנים לא נמחקו. '
      'ניתן למחוק אותם ידנית מהמיקום הישן.',
    );
    final oldBooks = widget.currentLibraryPath!;
    final oldIndex = _oldIndexPath;
    final newIndex = p.join(_targetRoot!, 'index');
    // באנדרואיד אינדקס מוכן מותקן תמיד באחסון הפנימי — במקום של הישן.
    final installedIndex =
        _action == _LibraryAction.chooseFolder &&
            _source?.source?.packages.packages?.index != null
        ? await LibraryPackageImporter.indexTargetFor(
            p.join(_targetRoot!, 'books'),
          )
        : null;
    try {
      await SqliteDataProvider.instance.dispose();
    } catch (_) {}
    try {
      await TantivyDataProvider.instance.reopenIndex();
    } catch (_) {}
    final leftover = await deleteMovedEntries(
      oldBooks,
      includeOnly: DatabaseConstants.libraryManagedEntryNames(),
    );
    var indexDeleteFailed = false;
    if (oldIndex != null &&
        oldIndex.isNotEmpty &&
        !p.equals(oldIndex, newIndex) &&
        (installedIndex == null || !p.equals(oldIndex, installedIndex)) &&
        await Directory(oldIndex).exists()) {
      try {
        await Directory(oldIndex).delete(recursive: true);
      } catch (_) {
        indexDeleteFailed = true;
      }
    }
    if (leftover != null || indexDeleteFailed) {
      UiSnack.showWarning(leftoverWarning);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<EmptyLibraryBloc, EmptyLibraryState>(
      listener: (context, state) async {
        if (state is! EmptyLibraryDirectorySelected) return;
        // שימוש במקום אינו מעביר קבצים — הספרייה הישנה נשארת ואינה נמחקת,
        // והאינדקס נקבע לפי השורש של התיקייה שנבחרה.
        if (_action == _LibraryAction.useInPlace) {
          await Settings.setValue<String>(
            SettingsRepository.keyIndexPath,
            p.join(AppPaths.libraryRootOf(state.selectedPath!), 'index'),
          );
          if (context.mounted) Navigator.of(context).pop(true);
          return;
        }
        // גילוי חסר אינו בחירה באחסון פנימי — שומרים רק יעד שאומת.
        for (final choice in _storageChoices ?? const []) {
          if (choice.root != _targetRoot) continue;
          await AppPaths.setAndroidLibraryRoot(
            choice.isRemovable ? choice.root : null,
          );
          break;
        }
        final relocating = _isRelocating;
        // יעד שורש חדש (הגדרה או רלוקציה) — האינדקס יושב תחת אותו שורש.
        if ((!_hasLibrary || relocating) && _targetRoot != null) {
          await Settings.setValue<String>(
            SettingsRepository.keyIndexPath,
            p.join(_targetRoot!, 'index'),
          );
        }
        if (relocating) await _deleteOldAfterRelocation();
        if (!context.mounted) return;
        final report = state.importReport;
        if (report != null && report.missing.isNotEmpty) {
          setState(() => _report = report);
          return;
        }
        Navigator.of(context).pop(true);
      },
      builder: (context, state) {
        final report = _report;
        if (report != null) {
          void close() => Navigator.of(context).pop(true);
          return AppCustomContentDialog(
            title: context.settingsText('הספרייה הותקנה'),
            onConfirm: close,
            handleEnterKey: true,
            actions: [
              ActionButton.recommended(
                text: context.settingsText('סגור'),
                onPressed: close,
              ),
            ],
            child: _ImportSummary(report: report),
          );
        }
        final working = state.isLoading;
        final canConfirm = !working && _canConfirm(state);
        return AppCustomContentDialog(
          title: _hasLibrary
              ? context.settingsText(
                  'עדכון {folder}',
                  args: {'folder': widget.folderName},
                )
              : context.settingsText(
                  'הגדרת {folder}',
                  args: {'folder': widget.folderName},
                ),
          onConfirm: canConfirm ? _confirm : null,
          handleEnterKey: canConfirm,
          actions: working
              ? [
                  if (state is EmptyLibraryExtracting && state.cancellable)
                    ActionButton.ghost(
                      text: context.settingsText('ביטול'),
                      onPressed: () => context.read<EmptyLibraryBloc>().add(
                        CancelLibraryImportRequested(),
                      ),
                    ),
                ]
              : [
                  ActionButton.ghost(
                    text: context.settingsText('ביטול'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  ActionButton.recommended(
                    text: context.settingsText('אישור'),
                    onPressed: canConfirm ? _confirm : null,
                  ),
                ],
          child: working
              ? _buildProgress(context, state)
              : _buildSelection(context, state),
        );
      },
    );
  }

  Widget _buildProgress(BuildContext context, EmptyLibraryState state) {
    final message = state is EmptyLibraryDownloading
        ? state.message
        : state is EmptyLibraryExtracting
        ? state.message
        : context.settingsText('מעבד...');
    final progress = state is EmptyLibraryDownloading
        ? (state.progress > 0 ? state.progress : null)
        : state is EmptyLibraryExtracting
        ? state.progress
        : null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          state is EmptyLibraryDownloading
              ? FluentIcons.arrow_download_24_regular
              : FluentIcons.folder_zip_24_regular,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: AppTokens.borderRadiusAll,
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        if (progress != null) ...[
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSelection(BuildContext context, EmptyLibraryState state) {
    final downloadDisabled = state.downloadDisabledReason;
    final moveSelected = _action == _LibraryAction.moveContents;
    final inPlaceSelected = _action == _LibraryAction.useInPlace;
    final downloadSelected = _action == _LibraryAction.download;
    final chooseFolderSelected = _action == _LibraryAction.chooseFolder;
    final source = _source?.source;

    final useInPlaceOption = SettingsActionTile.radioOption(
      title: context.settingsText('שימוש בספרייה קיימת במקומה'),
      subtitle: _inPlaceSubtitle(),
      subtitleLtr: _inPlaceFolder != null && _inPlaceHasDatabase,
      selected: inPlaceSelected,
      onTap: () => setState(() => _action = _LibraryAction.useInPlace),
      actions: [
        ActionButton.neutral(
          text: context.settingsText(
            _inPlaceFolder == null ? 'בחר תיקייה קיימת' : 'שנה תיקייה',
          ),
          onPressed: inPlaceSelected ? _pickInPlaceFolder : null,
          icon: FluentIcons.folder_open_24_regular,
        ),
      ],
    );
    final downloadOption = SettingsActionTile.radioOption(
      title: context.settingsText(
        _hasLibrary ? 'הורדת הספרייה מחדש' : 'הורדת הספרייה',
      ),
      subtitle: context.settingsText('הספרייה תורד ותחולץ אל תיקיית היעד'),
      selected: downloadSelected,
      onTap: () => setState(() => _action = _LibraryAction.download),
    );
    final chooseFolderOption = SettingsActionTile.radioOption(
      title: context.settingsText(
        Platform.isAndroid
            ? 'ייבוא מתיקיית קובצי הספרייה'
            : 'בחירת תיקייה מהמחשב',
      ),
      subtitle: _importSubtitle(),
      selected: chooseFolderSelected,
      onTap: () => setState(() => _action = _LibraryAction.chooseFolder),
      actions: [
        ActionButton.neutral(
          text: context.settingsText('בחר תיקייה'),
          onPressed: chooseFolderSelected ? _pickSourceFolder : null,
          icon: FluentIcons.folder_open_24_regular,
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          title: context.settingsText('פעולה'),
          subtitle: context.settingsText(
            _hasLibrary
                ? 'בחר כיצד לעדכן או להעביר את הספרייה, ולאחר מכן אשר'
                : 'בחר להוריד את הספרייה מהאינטרנט, להצביע על ספרייה קיימת או לייבא אותה',
          ),
          children: _hasLibrary
              ? [
                  SettingsActionTile.radioOption(
                    title: context.settingsText('העברת תוכן התיקייה'),
                    subtitle: context.settingsText(
                      'קבצי הספרייה הקיימת יועברו לתיקיית היעד',
                    ),
                    selected: moveSelected,
                    onTap: () =>
                        setState(() => _action = _LibraryAction.moveContents),
                  ),
                  if (_inPlaceSupported) useInPlaceOption,
                  // הורדה/ייבוא מחליפים את הספרייה הקיימת — מקובצים תחת
                  // מקטע נפרש כדי להבליט שהן פעולות מחיקה-והחלפה.
                  ExpandableSection(
                    title: context.settingsText('החלפת הספרייה בספרייה אחרת'),
                    subtitle: context.settingsText(
                      'הספרייה הקיימת תוחלף (עם גיבוי אוטומטי עד להצלחה)',
                    ),
                    isExpanded:
                        _replaceExpanded ||
                        downloadSelected ||
                        chooseFolderSelected,
                    onTap: () =>
                        setState(() => _replaceExpanded = !_replaceExpanded),
                    children: [downloadOption, chooseFolderOption],
                  ),
                ]
              : [
                  downloadOption,
                  if (_inPlaceSupported) useInPlaceOption,
                  chooseFolderOption,
                ],
        ),
        if (chooseFolderSelected && source != null)
          _SourceComponents(
            found: _foundFiles(source),
            existing: _hasLibrary && !_isRelocating ? _systemAssets : const {},
          ),
        // שימוש במקום אינו כותב קבצים — אין לו יעד לבחור.
        if (!inPlaceSelected)
          TargetFolderSection(
            folderName: widget.folderName,
            isSetup: !_hasLibrary,
            selectedPath: _targetRoot,
            defaultPath: widget.defaultTargetPath.isEmpty
                ? null
                : widget.defaultTargetPath,
            isAtDefault: _isAtDefaultRoot,
            onPickFolder: _pickTargetRoot,
            onUseDefault: () =>
                setState(() => _targetRoot = widget.defaultTargetPath),
            storageChoices: _storageChoices,
            onSelectStorage: (root) => setState(() => _targetRoot = root),
          ),
        if (_targetOnSdCard)
          MoveContentsWarning(
            text: context.settingsText(
              'אם הכרטיס יוסר, האפליקציה לא תוכל לגשת לספרים עד שיוחזר.\n\n'
              'שים לב: תיקיית האפליקציה שבכרטיס נספרת כמטמון של האפליקציה — '
              '"ניקוי מטמון" בהגדרות המכשיר ימחק ממנה את הספרייה.',
            ),
          ),
        if (state is EmptyLibraryError && state.errorMessage != null)
          MoveContentsWarning(text: state.errorMessage!),
        if (downloadSelected && downloadDisabled != null)
          MoveContentsWarning(text: downloadDisabled),
      ],
    );
  }
}

/// לכל רכיב שנמצא — שם הקובץ שממנו יותקן.
Map<LibraryComponent, String> _foundFiles(LibrarySourceScan source) {
  final packages = source.packages.packages;
  if (packages == null) {
    return {
      for (final MapEntry(:key, :value) in source.raw.assets.entries)
        key: value.sourceName,
    };
  }
  final index = packages.index;
  return {
    for (final component in source.components)
      component: component == LibraryComponent.searchIndex && index != null
          ? index.archiveName
          : packages.library.archiveName,
  };
}

String _componentLabel(BuildContext context, LibraryComponent component) =>
    switch (component) {
      LibraryComponent.libraryDb => context.settingsText(
        'ספריית הספרים (seforim.db)',
      ),
      LibraryComponent.talmudBavli => context.settingsText(
        'תלמוד בבלי (קובצי PDF)',
      ),
      LibraryComponent.catalog => context.settingsText('קטלוג אוצר החכמה'),
      LibraryComponent.lexicon => context.settingsText('מילון לחיפוש מקורב'),
      LibraryComponent.searchIndex => context.settingsText('אינדקס חיפוש'),
    };

/// מה יקרה בלי הרכיב, לפני הייבוא.
String _missingConsequence(BuildContext context, LibraryComponent component) =>
    switch (component) {
      LibraryComponent.libraryDb => context.settingsText(
        'חובה — בלעדיו לא ניתן להתקין',
      ),
      LibraryComponent.talmudBavli => context.settingsText(
        'ספרי התלמוד בבלי לא ייכללו',
      ),
      LibraryComponent.catalog => context.settingsText(
        'חיפוש בספריות נוספות לא יפעל',
      ),
      LibraryComponent.lexicon => context.settingsText(
        'החיפוש המקורב לא יפעל (ייעשה שימוש בחיפוש רגיל)',
      ),
      LibraryComponent.searchIndex => context.settingsText(
        'התוכנה תבנה את אינדקס החיפוש אחרי ההתקנה',
      ),
    };

/// מה לעשות כשהרכיב חסר אחרי ההתקנה.
String _missingRemedy(BuildContext context, LibraryComponent component) {
  final file = switch (component) {
    LibraryComponent.libraryDb => DatabaseConstants.databaseArchiveFileName,
    LibraryComponent.talmudBavli =>
      DatabaseConstants.talmudBavliArchiveFileName,
    LibraryComponent.catalog =>
      DatabaseConstants.externalCatalogArchiveFileName,
    LibraryComponent.lexicon => DatabaseConstants.lexicalDatabaseFileName,
    LibraryComponent.searchIndex => throw ArgumentError.value(
      component,
      'component',
      'האינדקס נבנה בתוכנה ואינו מדווח כחסר',
    ),
  };
  return context.settingsText(
    'יורד אוטומטית בבדיקת העדכונים הבאה כשיש חיבור לאינטרנט, או שניתן להוסיף את {file} לתיקייה ולייבא שוב',
    args: {'file': file},
  );
}

/// שורה של רכיב: סימן, שם, ופירוט (קובץ שנמצא או מה חסר).
class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.label,
    required this.detail,
    required this.present,
    this.detailLtr = false,
    this.required = false,
    this.neutral = false,
  });

  final String label;
  final String detail;
  final bool present;
  final bool detailLtr;
  final bool required;

  /// לא נמצא, אך התוכנה תשלים אותו בעצמה.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            present
                ? FluentIcons.checkmark_circle_24_regular
                : neutral
                ? FluentIcons.info_24_regular
                : required
                ? FluentIcons.error_circle_24_regular
                : FluentIcons.dismiss_circle_24_regular,
            size: 20,
            color: present
                ? cs.primary
                : required
                ? cs.error
                : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(
                  detail,
                  textDirection: detailLtr ? TextDirection.ltr : null,
                  style: AppTextStyles.settingSubtitle.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// מה נמצא בתיקיית המקור, לפי רכיב.
class _SourceComponents extends StatelessWidget {
  const _SourceComponents({required this.found, required this.existing});

  final Map<LibraryComponent, String> found;

  /// רכיבים שכבר קיימים בספרייה ויישמרו בעדכון במקום.
  final Set<LibraryComponent> existing;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: context.settingsText('מה נמצא בתיקייה'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (final component in LibraryComponent.values)
                if (found[component] case final file?)
                  _ComponentRow(
                    label: _componentLabel(context, component),
                    detail: file,
                    detailLtr: true,
                    present: true,
                  )
                else if (existing.contains(component))
                  _ComponentRow(
                    label: _componentLabel(context, component),
                    detail: context.settingsText(
                      'לא נמצא בתיקייה — יישמר מהספרייה הנוכחית',
                    ),
                    present: true,
                  )
                else
                  _ComponentRow(
                    label: _componentLabel(context, component),
                    detail: _missingConsequence(context, component),
                    present: false,
                    required: component == LibraryComponent.libraryDb,
                    neutral: component == LibraryComponent.searchIndex,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// סיכום אחרי התקנה שחסרים בה רכיבים: מה הותקן, ומה לעשות עם החסר.
class _ImportSummary extends StatelessWidget {
  const _ImportSummary({required this.report});

  final LibraryImportReport report;

  @override
  Widget build(BuildContext context) {
    final imported = [
      for (final c in LibraryComponent.values)
        if (report.imported.contains(c)) c,
    ];
    final missing = [
      for (final c in LibraryComponent.values)
        if (report.missing.contains(c)) c,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          title: context.settingsText('הותקנו'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  for (final c in imported)
                    _ComponentRow(
                      label: _componentLabel(context, c),
                      detail: context.settingsText('הותקן בהצלחה'),
                      present: true,
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsCard(
          title: context.settingsText('חסרים'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  for (final c in missing)
                    _ComponentRow(
                      label: _componentLabel(context, c),
                      detail: _missingRemedy(context, c),
                      present: false,
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
