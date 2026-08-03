import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:io';

import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/dialogs/zip_extraction_progress_dialog.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';

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
  /// שורת הגדרה נוספת השייכת לאותו כרטיס (למשל מיזוג ספרים אישיים לעץ הספרייה),
  /// מועברת מהטאב הראשי כי היא תלויה ב-bloc אחר.
  final Widget? mergeToggle;

  const CustomFoldersPanel({super.key, this.mergeToggle});

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
      title: context.settingsText('הסרת תיקייה'),
      content: context.settingsText(
        'האם להסיר את התיקייה "{name}" מהספרייה?\n'
        'הספרים יוסרו מהתוכנה, אך הקבצים המקוריים בדיסק לא יימחקו.',
        args: {'name': folder.name},
      ),
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
        title: context.settingsText('שמירת עותק עצמאי בתוכנה'),
        content: context.settingsText(
          'עותק של תוכן הספרים יישמר בתוך התוכנה, כך שהם יעבדו גם '
          'אם הקבצים המקוריים יוזזו או יימחקו.\n'
          'הקבצים המקוריים יישארו במקומם.\n\n'
          'שים לב: אם תערוך קובץ בעתיד, יהיה עליך ללחוץ "סרוק מחדש" '
          'כדי שהשינוי יתעדכן.\n\n'
          'האם להמשיך?',
        ),
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
    final entries = <AppMenuEntry<_FolderMenuAction>>[
      AppMenuEntry(
        value: _FolderMenuAction.openFolder,
        label: context.settingsText('פתח תיקייה'),
        icon: FluentIcons.folder_open_24_regular,
      ),
      AppMenuEntry(
        value: _FolderMenuAction.copyPath,
        label: context.settingsText('העתק נתיב'),
        icon: FluentIcons.copy_24_regular,
      ),
      AppMenuEntry(
        value: _FolderMenuAction.remove,
        label: context.settingsText('הסר תיקייה'),
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
        return SettingsCard(
          cardId: 'library.custom_folders',
          title: context.settingsText('ספרים אישיים'),
          subtitle: context.settingsText(
            'הוסף תיקיות עם ספרים או קבצים, בהוספת/הסרת קבצים יש לסרוק את התיקיה מחדש.',
          ),
          children: [
            ExpandableSection(
              icon: FluentIcons.folder_add_24_regular,
              title: context.settingsText('הוסף תיקייה'),
              subtitle: folders.isEmpty
                  ? context.settingsText('לחץ להוספת תיקיות אישיות')
                  : context.settingsText(
                      '{count} תיקיות',
                      args: {'count': folders.length},
                    ),
              trailing: ActionButton.recommended(
                text: context.settingsText('הוסף תיקייה'),
                icon: FluentIcons.folder_add_24_regular,
                onPressed: _addFolder,
                isLoading: isSyncing,
              ),
              isExpanded: _isExpanded,
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              hasContent: folders.isNotEmpty,
              children: [
                ..._buildStorageLegendTiles(context, isSyncing),
                ...folders.map(
                  (folder) => _buildFolderItem(
                    folder,
                    isSyncing,
                    state.activePath,
                  ),
                ),
              ],
            ),
            if (widget.mergeToggle != null) widget.mergeToggle!,
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

    return SettingsActionTile.path(
      icon: FluentIcons.folder_24_filled,
      iconColor: cs.primary,
      title: folder.name,
      path: folder.path,
      placeholder: '',
      // הכפתור נשאר צמוד לטקסט תמיד — בניגוד ל-actions, לא גולש למטה במסך צר.
      pinnedTrailing: Builder(
        builder: (buttonContext) => IconButton(
          icon: const Icon(FluentIcons.more_vertical_24_regular, size: 18),
          onPressed: isSyncing
              ? null
              : () => _showFolderMenu(buttonContext, folder),
          tooltip: context.settingsText('אפשרויות'),
        ),
      ),
      actions: [
        if (showFolderSpinner)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        // בחירת מצב אחסון. כשהתיקייה מכילה רק PDF/Word אין בחירה (הם
        // תמיד נקראים מהקבצים), ולכן מוצגת תווית במקום הפקד.
        if (!binaryOnly)
          Opacity(
            opacity: isSyncing ? 0.5 : 1.0,
            child: IgnorePointer(
              ignoring: isSyncing,
              child: AppSegmentedControl<bool>(
                currentValue: folder.addToDatabase,
                onChanged: (value) => _setStorageMode(folder, value),
                options: [
                  SegmentOption(
                    value: false,
                    label: context.settingsText('הצגה', context: 'storage'),
                    icon: FluentIcons.document_24_regular,
                  ),
                  SegmentOption(
                    value: true,
                    label: context.settingsText('הוספה'),
                    icon: FluentIcons.database_24_regular,
                  ),
                ],
              ),
            ),
          )
        else
          Text(
            context.settingsText('קבצי PDF/Word — נקראים ישירות מהקבצים'),
            style: AppTextStyles.settingSubtitle.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  /// מסביר בקצרה את ההבדל בין "הצגה" ל"הוספה", עם כפתור מידע נוסף
  /// וכפתור סריקה מחדש בסוף הכרטיס.
  List<Widget> _buildStorageLegendTiles(BuildContext context, bool isSyncing) {
    return [
      SettingsActionTile.text(
        icon: FluentIcons.info_24_regular,
        title: context.settingsText('הצגה או הוספה של הקבצים למערכת'),
        subtitle: context.settingsText(
          'הצגה: בודק את הקבצים בכל פתיחה של התוכנה ובכל פתיחת ספר, שינוי הספר מוצג מיידית בתוכנה.\n'
          'הוספה: מוסיף את התוכן הקיים לתוכנה, תוכן הקבצים ישתנה רק בסריקה מחדש, (קבצי PDF/Word רק יוצגו בתוכנה)',
        ),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.info_24_regular),
            onPressed: _showStorageInfoDialog,
            tooltip: context.settingsText('מידע נוסף'),
          ),
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
            tooltip: context.settingsText('סרוק מחדש תיקיות אישיות'),
          ),
        ],
      ),
    ];
  }

  /// דיאלוג מידע נוסף — מפרט את מצבי האחסון וסוגי הקבצים.
  Future<void> _showStorageInfoDialog() async {
    final cs = Theme.of(context).colorScheme;
    Widget item(IconData icon, String title, String subtitle) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.settingTitle.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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

    await showSingleActionDialog(
      context: context,
      title: context.settingsText('הצגה או הוספה של הקבצים'),
      confirmText: context.settingsText('סגור'),
      customContent: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            item(
              FluentIcons.document_24_regular,
              context.settingsText('הצגה', context: 'storage'),
              context.settingsText(
                'הספרים נקראים ישירות מהקבצים שבדיסק. אל תזיז אותם — אחרת '
                'הם לא ייפתחו. למחיקה: מחק את הקובץ מהדיסק וסרוק מחדש.',
              ),
            ),
            item(
              FluentIcons.database_24_regular,
              context.settingsText('הוספה'),
              context.settingsText(
                'התוכן נשמר בתוך התוכנה ועובד גם אם הקבצים יוסרו. אחרי '
                'עריכת קובץ לחץ "סרוק מחדש" לעדכון; מחיקה רק דרך הספרייה.',
              ),
            ),
            item(
              FluentIcons.info_24_regular,
              context.settingsText('קבצי PDF ו-Word'),
              context.settingsText(
                'אין אפשרות להוספה, והם רק מוצגים ונקראים ישירות מהקבצים שבדיסק.',
              ),
            ),
            item(
              FluentIcons.link_24_regular,
              context.settingsText('דורות וקישורים'),
              context.settingsText(
                'לייבוא סדר דורות וקישורים לספרים האישיים השתמש בכפתור '
                '"ייבוא דורות וקישורים" שבהמשך.',
              ),
            ),
          ],
        ),
      ),
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
      title: context.settingsText('מחיקת דורות וקישורים'),
      content: context.settingsText(
        'פעולה זו תמחק את כל הדורות והקישורים שיובאו לתוכנה.',
      ),
      subtitle: context.settingsText(
        'הספרים עצמם לא יימחקו — רק הדורות והקישורים המיובאים.',
      ),
      confirmText: context.settingsText('מחק הכל'),
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
          title: context.settingsText('ייבוא דורות וקישורים'),
          subtitle: context.settingsText(
            'בחר קובצי "דורות.csv", "<שם הספר>.links.csv" או קובצי קישורים '
            'של אוצריא ("<שם הספר>_links.json") והם יכנסו לספרייה. '
            'ייבוא חוזר מעדכן ערכים קיימים ומוסיף חדשים.',
          ),
          actions: [
            ActionButton.warning(
              text: context.settingsText('נקה הכל'),
              onPressed: isSyncing ? null : () => _clear(context),
            ),
            ActionButton.recommended(
              text: context.settingsText('ייבוא דורות וקישורים'),
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
