import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:io';

import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/widgets/dialogs/confirmation_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/dialogs/zip_extraction_progress_dialog.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';

/// סיווג הרכב הקבצים בתיקייה מותאמת אישית — קובע אילו אפשרויות אחסון
/// רלוונטיות ואילו הסברים להציג למשתמש.
enum _FolderContentKind {
  /// אין קבצים נתמכים בתיקייה.
  empty,

  /// רק קבצי טקסט (TXT) — ניתן לשמור כעותק עצמאי בתוכנה.
  textOnly,

  /// רק קבצי PDF/Word/EPUB — נקראים תמיד ישירות מהקבצים.
  binaryOnly,

  /// גם טקסט וגם PDF/Word/EPUB — רק הטקסט יישמר כעותק עצמאי.
  mixed,
}

/// Widget להוספה וניהול תיקיות מותאמות אישית
class CustomFoldersPanel extends StatefulWidget {
  const CustomFoldersPanel({super.key});

  @override
  State<CustomFoldersPanel> createState() => _CustomFoldersPanelState();
}

class _CustomFoldersPanelState extends State<CustomFoldersPanel> {
  bool _isExpanded = false;

  /// תוצאות סיווג הרכב הקבצים לכל תיקייה (לפי נתיב). מתמלא בעצלתיים
  /// כשהרשימה נפתחת, כדי לא לסרוק תיקיות שאינן מוצגות.
  final Map<String, _FolderContentKind> _folderKinds = {};
  final Set<String> _scanningFolders = {};

  // מאזין לתור הגלובלי כדי שהכפתורים ייחסמו גם כשמסלול אחר (כגון file_sync)
  // כותב ל-DB באמצעות אותו תור.
  void _onQueueBusyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    DatabaseLibraryProvider.operationQueue.busyCount.addListener(
      _onQueueBusyChanged,
    );
  }

  @override
  void dispose() {
    DatabaseLibraryProvider.operationQueue.busyCount.removeListener(
      _onQueueBusyChanged,
    );
    super.dispose();
  }

  /// סורק את התיקייה (רק לפי סיומות, לא קורא תוכן) ומסווג את הרכב הקבצים.
  /// הסריקה אסינכרונית ולא חוסמת את ה-UI, ועוצרת מוקדם ברגע שהתגלה גם
  /// טקסט וגם קובץ בינארי (כלומר "מעורב").
  Future<_FolderContentKind> _classifyFolder(String path) async {
    var hasText = false;
    var hasBinary = false;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return _FolderContentKind.empty;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.txt')) {
          hasText = true;
        } else if (lower.endsWith('.pdf') ||
            lower.endsWith('.docx') ||
            lower.endsWith('.epub')) {
          hasBinary = true;
        }
        if (hasText && hasBinary) break;
      }
    } catch (_) {
      return _FolderContentKind.empty;
    }
    if (hasText && hasBinary) return _FolderContentKind.mixed;
    if (hasText) return _FolderContentKind.textOnly;
    if (hasBinary) return _FolderContentKind.binaryOnly;
    return _FolderContentKind.empty;
  }

  /// מתחיל סריקת סיווג לתיקייה אם טרם נסרקה. בטוח לקריאה חוזרת.
  void _ensureFolderClassified(String path) {
    if (_folderKinds.containsKey(path) || _scanningFolders.contains(path)) {
      return;
    }
    _scanningFolders.add(path);
    _classifyFolder(path).then((kind) {
      if (!mounted) return;
      setState(() {
        _folderKinds[path] = kind;
        _scanningFolders.remove(path);
      });
    });
  }

  Future<void> _addFolder() async {
    final bloc = context.read<CustomFoldersBloc>();
    final path = await FilePicker.getDirectoryPath(lockParentWindow: true);
    if (path == null) return;

    final dir = Directory(path);
    if (!await dir.exists()) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.folderNotFound);
      return;
    }

    bool zipExtracted = false;
    String? extractedFileName;

    final zipFiles = dir
        .listSync()
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.zip'),
        )
        .cast<File>()
        .toList();

    if (zipFiles.isNotEmpty) {
      if (!mounted) return;
      await ZipExtractionProgressDialog.showAndExtract(
        context: context,
        path: path,
        onSuccess: (result) {
          if (result.successfullyExtracted) {
            zipExtracted = true;
            extractedFileName = result.extractedFileName;
          }
        },
        onError: (msg) => UiSnack.showError(msg),
      );
    }

    bloc.add(AddCustomFolder(path));
    // אין צורך לאפס כאן את הסיווג — ה-listener מאפס את כל הקאש בסיום
    // הסריקה (כולל חילוץ ZIP ששינה את הרכב הקבצים).

    String msg = SettingsMessages.folderAdded(
      path.split(Platform.pathSeparator).last,
    );
    if (zipExtracted && extractedFileName != null) {
      msg += '\n${SettingsMessages.fileExtracted(extractedFileName)}';
    }
    UiSnack.show(msg, duration: const Duration(seconds: 9));
  }

  Future<void> _removeFolder(CustomFolder folder) async {
    final bloc = context.read<CustomFoldersBloc>();
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'הסרת תיקייה',
      content:
          'האם להסיר את התיקייה "${folder.name}" מהספרייה?\n'
          'הספרים יוסרו מהתוכנה, אך הקבצים המקוריים בדיסק לא יימחקו.',
      isDangerous: false,
    );
    if (confirmed != true || !mounted) return;

    // הסרת תיקייה תמיד מוחקת את ספריה מהתוכנה — גם אם תוכנם נשמר כעותק
    // עצמאי וגם אם הם מוגדרים לקריאה ישירה מהקבצים. ה-prune שרץ ברענון
    // ימחק אותם בכל מקרה, ולכן אין משמעות ל"השארה" שלהם ב-DB.
    bloc.add(RemoveCustomFolder(folder, deleteFromDb: true));
  }

  /// מחליף את מצב האחסון של התיקייה: עותק עצמאי בתוכנה (true) או קריאה
  /// ישירה מהקבצים (false).
  Future<void> _setStorageMode(CustomFolder folder, bool toDatabase) async {
    final bloc = context.read<CustomFoldersBloc>();
    if (toDatabase) {
      final confirmed = await showConfirmationDialog(
        context: context,
        title: 'שמירת עותק עצמאי בתוכנה',
        content:
            'עותק של תוכן הספרים יישמר בתוך התוכנה, כך שהם יעבדו גם '
            'אם הקבצים המקוריים יוזזו או יימחקו.\n'
            'הקבצים המקוריים יישארו במקומם.\n\n'
            'שים לב: אם תערוך קובץ בעתיד, יהיה עליך ללחוץ "סרוק מחדש" '
            'כדי שהשינוי יתעדכן.\n\n'
            'האם להמשיך?',
        isDangerous: false,
      );
      if (confirmed != true || !mounted) return;
    }
    bloc.add(ToggleAddToDatabase(folder, toDatabase));
  }

  /// פותח נתיב במנהל הקבצים של מערכת ההפעלה.
  void _openInFileManager(String path) {
    if (path.isEmpty) return;
    if (Platform.isWindows) {
      unawaited(Process.run('explorer', [path]));
    } else if (Platform.isMacOS) {
      unawaited(Process.run('open', [path]));
    } else if (Platform.isLinux) {
      unawaited(Process.run('xdg-open', [path]));
    }
  }

  /// תפריט אפשרויות לתיקייה — פתיחה במנהל הקבצים, העתקת נתיב והסרה.
  Future<void> _showFolderMenu(
    BuildContext anchorContext,
    CustomFolder folder,
  ) async {
    const entries = <AppMenuEntry<_FolderMenuAction>>[
      AppMenuEntry(
        value: _FolderMenuAction.openFolder,
        label: 'פתח תיקייה',
        icon: FluentIcons.folder_open_24_regular,
      ),
      AppMenuEntry(
        value: _FolderMenuAction.copyPath,
        label: 'העתק נתיב',
        icon: FluentIcons.copy_24_regular,
      ),
      AppMenuEntry(
        value: _FolderMenuAction.remove,
        label: 'הסר תיקייה',
        icon: FluentIcons.delete_24_regular,
        isDestructive: true,
      ),
    ];

    final selected = await showAnchoredAppMenu<_FolderMenuAction>(
      context: context,
      anchorContext: anchorContext,
      itemsBuilder: (m) => entries
          .map(
            (e) =>
                buildAppPopupMenuItem<_FolderMenuAction>(context, e, m, null),
          )
          .toList(),
    );

    if (selected == null || !mounted) return;

    switch (selected) {
      case _FolderMenuAction.openFolder:
        _openInFileManager(folder.path);
      case _FolderMenuAction.copyPath:
        await Clipboard.setData(ClipboardData(text: folder.path));
        UiSnack.showSuccess(SettingsMessages.pathCopied);
      case _FolderMenuAction.remove:
        await _removeFolder(folder);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CustomFoldersBloc, CustomFoldersState>(
      listenWhen: (prev, curr) =>
          (curr.message != null && curr.message != prev.message) ||
          (curr.error != null && curr.error != prev.error) ||
          (prev.isSyncing && !curr.isSyncing),
      listener: (context, state) {
        if (state.message != null) UiSnack.show(state.message!);
        if (state.error != null) UiSnack.showError(state.error!);
        if (!state.isSyncing) {
          // סריקה/סנכרון הסתיימו — ייתכן שתוכן התיקיות בדיסק השתנה (נוספו
          // או הוסרו קבצים). מאפסים את קאש סיווג סוגי הקבצים כדי שיחושב
          // מחדש, אחרת ה-UI עלול להציג מצב אחסון או הסבר מיושן.
          _folderKinds.clear();
          _scanningFolders.clear();
        }
      },
      builder: (context, state) {
        final folders = state.folders;
        final isSyncing =
            state.isSyncing || DatabaseLibraryProvider.operationQueue.isBusy;
        return ExpandableSection(
          icon: FluentIcons.folder_add_24_regular,
          title: 'הוסף תיקייה לאוצריא',
          subtitle: folders.isEmpty
              ? 'לחץ להוספת תיקיות אישיות'
              : '${folders.length} תיקיות',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (folders.isNotEmpty)
                IconButton(
                  icon: isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(FluentIcons.arrow_clockwise_24_regular),
                  onPressed: isSyncing
                      ? null
                      : () => context.read<CustomFoldersBloc>().add(
                          const RescanCustomFolders(),
                        ),
                  tooltip: 'סרוק מחדש תיקיות אישיות',
                ),
              ActionButton.recommended(
                text: 'הוסף תיקייה',
                icon: FluentIcons.folder_add_24_regular,
                onPressed: _addFolder,
                isLoading: isSyncing,
              ),
            ],
          ),
          isExpanded: _isExpanded,
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          hasContent: folders.isNotEmpty,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 16, left: 16, bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Column(
                children: [
                  _buildStorageLegend(),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  ...folders.map(
                    (folder) => _buildFolderItem(
                      folder,
                      isSyncing,
                      state.activePath,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFolderItem(
    CustomFolder folder,
    bool isSyncing,
    String? activePath,
  ) {
    // הספינר על תיקייה בודדת מוצג כשהפעולה נוגעת בה:
    // • כשזו התיקייה הפעילה (הוספה / החלפת מצב) — תמיד, גם אם היא מוגדרת
    //   לקריאה מהקבצים (תיקייה חדשה נוצרת עם addToDatabase=false אך עדיין
    //   נסרקת).
    // • כשהפעולה גלובלית (activePath == null, כגון סריקה מחדש או כתיבה דרך
    //   התור המשותף) — רק על תיקיות שנשמרות כעותק עצמאי, שהן אלו שנכתבות.
    final showFolderSpinner =
        isSyncing &&
        (activePath == folder.path ||
            (activePath == null && folder.addToDatabase));
    // מתחיל סיווג עצלן של הרכב הקבצים (פעם אחת לכל תיקייה).
    _ensureFolderClassified(folder.path);
    final kind = _folderKinds[folder.path];
    final cs = Theme.of(context).colorScheme;

    // קבצי PDF/Word נקראים תמיד מהקבצים — אין משמעות ל"עותק עצמאי".
    final binaryOnly = kind == _FolderContentKind.binaryOnly;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.folder_24_filled,
                color: cs.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      folder.name,
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      folder.path,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (showFolderSpinner)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Builder(
                builder: (buttonContext) => IconButton(
                  icon: const Icon(
                    FluentIcons.more_vertical_24_regular,
                    size: 18,
                  ),
                  onPressed: isSyncing
                      ? null
                      : () => _showFolderMenu(buttonContext, folder),
                  tooltip: 'אפשרויות',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // בחירת מצב אחסון. כשהתיקייה מכילה רק PDF/Word אין בחירה (הם
          // תמיד נקראים מהקבצים), ולכן מוצגת תווית במקום הפקד.
          if (!binaryOnly)
            Align(
              alignment: Alignment.centerRight,
              child: Opacity(
                opacity: isSyncing ? 0.5 : 1.0,
                child: IgnorePointer(
                  ignoring: isSyncing,
                  child: AppSegmentedControl<bool>(
                    currentValue: folder.addToDatabase,
                    onChanged: (value) => _setStorageMode(folder, value),
                    options: const [
                      SegmentOption(
                        value: false,
                        label: 'קריאה מהקבצים',
                        icon: FluentIcons.document_24_regular,
                      ),
                      SegmentOption(
                        value: true,
                        label: 'עותק עצמאי',
                        icon: FluentIcons.database_24_regular,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'קבצי PDF/Word — נקראים ישירות מהקבצים',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// מקרא המסביר את ההבדל בין מצבי האחסון. מוצג פעם אחת מעל רשימת
  /// התיקיות, במקום הסבר/אזהרה חוזרים תחת כל תיקייה.
  Widget _buildStorageLegend() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow(
            FluentIcons.document_24_regular,
            'קריאה מהקבצים: הספרים נקראים ישירות מהקבצים שבדיסק. אל תזיז '
            'אותם — אחרת לא ייפתחו. למחיקה: מחק את הקובץ מהדיסק וסרוק מחדש.',
          ),
          const SizedBox(height: 8),
          _legendRow(
            FluentIcons.database_24_regular,
            'עותק עצמאי: התוכן נשמר בתוך התוכנה ועובד גם אם הקבצים יוסרו. '
            'אחרי עריכת קובץ לחץ "סרוק מחדש" לעדכון; מחיקה רק דרך הספרייה.',
          ),
          const SizedBox(height: 8),
          _legendRow(
            FluentIcons.info_24_regular,
            'קבצי PDF ו-Word נקראים תמיד ישירות מהקבצים '
            '(לא נשמרים כעותק עצמאי).',
          ),
          const SizedBox(height: 8),
          _legendRow(
            FluentIcons.link_24_regular,
            'דורות וקישורים: לייבוא סדר דורות וקישורים לספרים האישיים השתמש '
            'בכפתור "ייבוא דורות וקישורים" שלהלן.',
          ),
        ],
      ),
    );
  }

  Widget _legendRow(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: cs.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

enum _FolderMenuAction { openFolder, copyPath, remove }

/// ייבוא ידני של דורות וקישורים מקבצי CSV/JSON שהמשתמש בוחר, ומחיקת כל
/// המיובא. הייבוא קבוע (לא תלוי בנוכחות הקבצים) ומצטבר בדריסה.
class UserContentImportTile extends StatelessWidget {
  const UserContentImportTile({super.key});

  Future<void> _import(BuildContext context) async {
    final bloc = context.read<CustomFoldersBloc>();
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['csv', 'json'],
      lockParentWindow: true,
    );
    if (result == null) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    bloc.add(ImportUserContentFiles(paths));
  }

  Future<void> _clear(BuildContext context) async {
    final bloc = context.read<CustomFoldersBloc>();
    final confirmed = await showWarningDialog(
      context: context,
      title: 'מחיקת דורות וקישורים',
      content: 'פעולה זו תמחק את כל הדורות והקישורים שיובאו לתוכנה.',
      subtitle: 'הספרים עצמם לא יימחקו — רק הדורות והקישורים המיובאים.',
      confirmText: 'מחק הכל',
    );
    if (confirmed == true) bloc.add(const ClearUserContent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CustomFoldersBloc, CustomFoldersState>(
      buildWhen: (p, c) => p.isSyncing != c.isSyncing,
      builder: (context, state) {
        final isSyncing =
            state.isSyncing || DatabaseLibraryProvider.operationQueue.isBusy;
        return SettingsActionTile.text(
          icon: FluentIcons.arrow_import_24_regular,
          title: 'ייבוא דורות וקישורים',
          subtitle:
              'בחר קובצי "דורות.csv", "<שם הספר>.links.csv" או קובצי קישורים '
              'של אוצריא ("<שם הספר>_links.json") והם ייקלטו לצמיתות. '
              'ייבוא חוזר מעדכן ערכים קיימים ומוסיף חדשים.',
          actions: [
            ActionButton.warning(
              text: 'נקה הכל',
              onPressed: isSyncing ? null : () => _clear(context),
            ),
            ActionButton.recommended(
              text: 'ייבוא דורות וקישורים',
              icon: FluentIcons.arrow_import_24_regular,
              onPressed: isSyncing ? null : () => _import(context),
              isLoading: isSyncing,
            ),
          ],
        );
      },
    );
  }
}
