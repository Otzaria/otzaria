import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
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
import 'package:otzaria/settings/dialogs/change_location_dialog.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/widgets/expandable_settings_tile.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/move_directory.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

// ── דיאלוג מאוחד להגדרת/עדכון מיקום הספרייה ────────────────────────────────
//
// כרטיס "פעולה" בוחר את *מקור* הקבצים: הורדה מהאינטרנט, בחירת קובץ מהמחשב,
// ובמצב עדכון גם העברת תוכן הספרייה הקיימת. מקטע "תיקיית היעד" בוחר *לאן*
// הקבצים ילכו — תחת התיקייה שתיבחר נוצרות "books" (הספרייה) ו-"index" (אינדקס).
// "שימוש בספרייה קיימת במקומה" הוא היוצא מן הכלל: אין העתקה ואין יעד — הנתיב
// שנבחר נשמר כמות שהוא, והאינדקס נקבע תחת השורש שלו.
// כשיש ספרייה קיימת והיעד נשאר במקום הנוכחי — עדכון במקום עם גיבוי בטוח;
// כשהיעד שונה — רלוקציה: הקבצים נכתבים ליעד החדש, והישנים נמחקים בהצלחה.

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
        create: (_) => EmptyLibraryBloc(),
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

enum _LibraryAction {
  moveContents,
  useInPlace,
  download,
  chooseFile,
  chooseArchive,
}

const _kSeforimAssetLabel = 'ספריית הספרים (seforim.db)';
const _kCatalogAssetLabel = 'קטלוג אוצר החכמה';
const _kLexicalAssetLabel = 'מילון לחיפוש מקורב';
const _kTalmudAssetLabel = 'תלמוד בבלי';

/// כל נכסי הספרייה שהתוכנה מזהה בתיקיית מקור, לפי הסדר, עם ההשלכה של היעדרם.
const _kLibraryAssets = <({String label, String consequence})>[
  (label: _kSeforimAssetLabel, consequence: ''),
  (label: _kCatalogAssetLabel, consequence: 'חיפוש בספריות נוספות לא יפעל.'),
  (
    label: _kLexicalAssetLabel,
    consequence: 'החיפוש המקורב לא יפעל (ייעשה שימוש בחיפוש רגיל).',
  ),
  (label: _kTalmudAssetLabel, consequence: 'ספרי התלמוד בבלי לא ייכללו.'),
];

/// סורק תיקיית מקור ומחזיר תוויות של נכסי הספרייה שזוהו בה, בגרסה דחוסה או
/// רגילה. seforim.db הוא הנכס הנדרש; השאר נלווים ומיובאים אם קיימים.
Future<List<String>> _scanFolderAssets(String folder) async {
  Future<bool> anyExists(List<String> names) async {
    for (final name in names) {
      if (await File(p.join(folder, name)).exists()) return true;
    }
    return false;
  }

  final found = <String>[];
  if (await anyExists([
    DatabaseConstants.databaseFileName,
    DatabaseConstants.databaseArchiveFileName,
  ])) {
    found.add(_kSeforimAssetLabel);
  }
  if (await anyExists([
    DatabaseConstants.externalCatalogDatabaseFileName,
    DatabaseConstants.externalCatalogArchiveFileName,
  ])) {
    found.add(_kCatalogAssetLabel);
  }
  if (await File(
    p.join(folder, DatabaseConstants.lexicalDatabaseFileName),
  ).exists()) {
    found.add(_kLexicalAssetLabel);
  }
  if (await File(
        p.join(folder, DatabaseConstants.talmudBavliArchiveFileName),
      ).exists() ||
      await Directory(
        p.join(folder, DatabaseConstants.talmudBavliFolderName),
      ).exists()) {
    found.add(_kTalmudAssetLabel);
  }
  return found;
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

  /// תיקיית המקור לייבוא (פעולת [_LibraryAction.chooseFile]) והנכסים שזוהו בה.
  String? _sourceFolder;
  List<String> _detectedAssets = const [];

  String? _sourceArchive;

  /// תיקייה שנבחרה לשימוש במקומה, והאם נמצא בה seforim.db לא-דחוס. שימוש
  /// במקום דורש DB מוכן — גרסה דחוסה מחייבת חילוץ, כלומר ייבוא רגיל.
  String? _inPlaceFolder;
  bool _inPlaceHasDatabase = false;

  /// הנכסים הקיימים כבר בספרייה הנוכחית (רלוונטי בעדכון במקום — הם יישמרו).
  List<String> _systemAssets = const [];

  /// האם מקטע "מחיקה וייבוא" (הורדה/בחירת קובץ) פרוס — רלוונטי כשיש ספרייה.
  bool _replaceExpanded = false;

  /// נתיב האינדקס הישן — נלכד בעליית הדיאלוג כדי שנוכל למחוק אותו ברלוקציה.
  String? _oldIndexPath;

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
    if (_hasLibrary) {
      // best-effort: הנתיב נחוץ רק למחיקת האינדקס הישן ברלוקציה.
      AppPaths.getIndexPath()
          .then((path) {
            if (mounted) _oldIndexPath = path;
          })
          .catchError((_) {});
      // סורק אילו נכסים כבר קיימים בספרייה — כדי לא להזהיר על מה שכבר יש.
      _scanFolderAssets(widget.currentLibraryPath!)
          .then((assets) {
            if (mounted) setState(() => _systemAssets = assets);
          })
          .catchError((_) {});
    }
  }

  bool get _isAtDefaultRoot => _targetRoot == widget.defaultTargetPath;

  Future<void> _pickTargetRoot() async {
    final path = await FilePicker.getDirectoryPath(
      lockParentWindow: true,
      dialogTitle: context.settingsText('בחר את תיקיית היעד לספרייה'),
    );
    if (path != null && mounted) setState(() => _targetRoot = path);
  }

  /// בוחר תיקיית מקור לייבוא וסורק אילו נכסי ספרייה זוהו בה (דחוסים או רגילים).
  Future<void> _pickSourceFolder() async {
    final folder = await FilePicker.getDirectoryPath(
      lockParentWindow: true,
      dialogTitle: context.settingsText('בחר תיקייה המכילה את קבצי הספרייה'),
    );
    if (folder == null || !mounted) return;
    final detected = await _scanFolderAssets(folder);
    if (!mounted) return;
    setState(() {
      _sourceFolder = folder;
      _detectedAssets = detected;
    });
  }

  /// בחירת הקובץ ישירות מספקת נתיב נגיש גם מ-Android Scoped Storage.
  Future<void> _pickSourceDatabaseFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['db'],
      dialogTitle: context.settingsText(
        'בחר את קובץ {file}',
        args: {'file': DatabaseConstants.databaseFileName},
      ),
      lockParentWindow: true,
    );
    final file = result?.files.singleOrNull;
    if (file?.path == null || !mounted) return;
    if (file!.name != DatabaseConstants.databaseFileName) {
      UiSnack.showError(
        context.settingsText(
          'יש לבחור את {file}',
          args: {'file': DatabaseConstants.databaseFileName},
        ),
      );
      return;
    }
    setState(() {
      _sourceFolder = p.dirname(file.path!);
      _detectedAssets = [_kSeforimAssetLabel];
    });
  }

  /// בוחר תיקיית ספרייה קיימת לשימוש במקומה (ללא העתקה).
  Future<void> _pickInPlaceFolder() async {
    final folder = await FilePicker.getDirectoryPath(
      lockParentWindow: true,
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

  Future<void> _pickSourceArchive() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'zst'],
      dialogTitle: context.settingsText('בחר ארכיון ספרייה (ZIP או ZST)'),
      lockParentWindow: true,
    );
    final file = result?.files.singleOrNull;
    if (file?.path == null || !mounted) return;
    setState(() => _sourceArchive = file!.path);
  }

  /// נכס יהיה קיים לאחר הייבוא אם זוהה בתיקיית המקור, או שהוא כבר קיים
  /// בספרייה בעדכון במקום (רלוקציה כותבת רק את מה שיובא).
  bool _presentAfterImport(String label) {
    if (_detectedAssets.contains(label)) return true;
    if (_hasLibrary && !_isRelocating && _systemAssets.contains(label)) {
      return true;
    }
    return false;
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
      case _LibraryAction.chooseFile:
        if (_targetRoot == null) return false;
        if (_sourceFolder == null || _detectedAssets.isEmpty) return false;
        // חובה שקובץ הספרייה יהיה קיים לאחר הייבוא (מהתיקייה או מספרייה קיימת).
        return _presentAfterImport(_kSeforimAssetLabel);
      case _LibraryAction.chooseArchive:
        return _targetRoot != null && _sourceArchive != null;
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

  /// תת-כותרת לאפשרות "בחירת תיקייה": לפני בחירה — הנחיה; אחרי בחירה —
  /// "כל הקבצים זוהו", או אזהרה תמציתית רק על קבצים שיישארו חסרים לאחר הייבוא.
  String _importSubtitle() {
    if (_sourceFolder == null) {
      return context.settingsText(
        'בחר תיקייה שקיימים בה קובצי הספרייה והמערכת',
      );
    }
    final missing = _kLibraryAssets
        .where((a) => !_presentAfterImport(a.label))
        .toList();
    if (missing.isEmpty) return context.settingsText('כל הקבצים זוהו');
    if (missing.any((a) => a.label == _kSeforimAssetLabel)) {
      return context.settingsText(
        'חסר קובץ הספרייה (seforim.db) — לא ניתן להמשיך בלי הספרייה',
      );
    }
    if (missing.length == 1) {
      return context.settingsText(
        '{label} חסר — {consequence}',
        args: {
          'label': missing.first.label,
          'consequence': missing.first.consequence,
        },
      );
    }
    return context.settingsText(
      'יישארו חסרים: {items}',
      args: {'items': missing.map((a) => a.label).join(", ")},
    );
  }

  String _archiveSubtitle() => _sourceArchive == null
      ? context.settingsText('בחר קובץ ZIP או ZST המכיל את seforim.db')
      : p.basename(_sourceArchive!);

  void _confirm() {
    switch (_action) {
      case _LibraryAction.moveContents:
        _moveExisting();
      case _LibraryAction.useInPlace:
        _useInPlace();
      case _LibraryAction.download:
        _download();
      case _LibraryAction.chooseFile:
        _import();
      case _LibraryAction.chooseArchive:
        _importArchive();
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
          isDownload: true,
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
    final source = _sourceFolder;
    if (root == null || source == null) return;
    // גיבוי ה-DB הישן רק בעדכון במקום שמחליף את seforim.db (אחרת המחיקה של
    // הגיבוי בהצלחה הייתה מוחקת DB שלא הוחלף). רלוקציה → מחיקת הישן ב-listener.
    final backup =
        (_hasLibrary &&
            !_isRelocating &&
            _detectedAssets.contains(_kSeforimAssetLabel))
        ? widget.currentLibraryPath
        : null;
    context.read<EmptyLibraryBloc>().add(
      ImportLibraryFolderRequested(
        sourceFolder: source,
        targetPath: p.join(root, 'books'),
        backupExistingPath: backup,
      ),
    );
  }

  void _importArchive() {
    final root = _targetRoot;
    final archive = _sourceArchive;
    if (root == null || archive == null) return;
    final backup = _hasLibrary && !_isRelocating
        ? widget.currentLibraryPath
        : null;
    context.read<EmptyLibraryBloc>().add(
      ImportLibraryArchiveRequested(
        archivePath: archive,
        targetPath: p.join(root, 'books'),
        backupExistingPath: backup,
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
        final relocating = _isRelocating;
        // יעד שורש חדש (הגדרה או רלוקציה) — האינדקס יושב תחת אותו שורש.
        if ((!_hasLibrary || relocating) && _targetRoot != null) {
          await Settings.setValue<String>(
            SettingsRepository.keyIndexPath,
            p.join(_targetRoot!, 'index'),
          );
        }
        if (relocating) await _deleteOldAfterRelocation();
        if (context.mounted) Navigator.of(context).pop(true);
      },
      builder: (context, state) {
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
              ? null
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
    final chooseFileSelected = _action == _LibraryAction.chooseFile;
    final chooseArchiveSelected = _action == _LibraryAction.chooseArchive;

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
    final chooseFileOption = SettingsActionTile.radioOption(
      title: context.settingsText('בחירת תיקייה מהמחשב'),
      subtitle: _importSubtitle(),
      selected: chooseFileSelected,
      onTap: () => setState(() => _action = _LibraryAction.chooseFile),
      actions: [
        ActionButton.neutral(
          text: context.settingsText('בחר תיקייה'),
          onPressed: chooseFileSelected ? _pickSourceFolder : null,
          icon: FluentIcons.folder_open_24_regular,
        ),
        ActionButton.neutral(
          text: context.settingsText('בחר קובץ ספרייה'),
          onPressed: chooseFileSelected ? _pickSourceDatabaseFile : null,
          icon: FluentIcons.document_24_regular,
        ),
      ],
    );
    final chooseArchiveOption = SettingsActionTile.radioOption(
      title: context.settingsText('בחירת קובץ דחוס'),
      subtitle: _archiveSubtitle(),
      selected: chooseArchiveSelected,
      onTap: () => setState(() => _action = _LibraryAction.chooseArchive),
      actions: [
        ActionButton.neutral(
          text: context.settingsText('בחר קובץ דחוס'),
          onPressed: chooseArchiveSelected ? _pickSourceArchive : null,
          icon: FluentIcons.archive_24_regular,
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
                  // הורדה/בחירת קובץ מחליפות את הספרייה הקיימת — מקובצות תחת
                  // מקטע נפרש כדי להבליט שהן פעולות מחיקה-והחלפה.
                  ExpandableSection(
                    title: context.settingsText('מחיקה וייבוא ספרייה'),
                    subtitle: context.settingsText(
                      'הספרייה הקיימת תוחלף (עם גיבוי אוטומטי עד להצלחה)',
                    ),
                    isExpanded:
                        _replaceExpanded ||
                        downloadSelected ||
                        chooseFileSelected ||
                        chooseArchiveSelected,
                    onTap: () =>
                        setState(() => _replaceExpanded = !_replaceExpanded),
                    children: [
                      downloadOption,
                      chooseFileOption,
                      chooseArchiveOption,
                    ],
                  ),
                ]
              : [
                  downloadOption,
                  if (_inPlaceSupported) useInPlaceOption,
                  chooseFileOption,
                  chooseArchiveOption,
                ],
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
          ),
        if (state is EmptyLibraryError && state.errorMessage != null)
          MoveContentsWarning(text: state.errorMessage!),
        if (downloadSelected && downloadDisabled != null)
          MoveContentsWarning(text: downloadDisabled),
      ],
    );
  }
}
