import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/attached_libraries/bloc/attached_libraries_bloc.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:path/path.dart' as p;

/// כרטיס "מסדי ספרים אישיים" בהגדרות הספרייה: צירוף קובצי מסד בפורמט
/// seforim.db, תיקיות מסדים, וניהול כל מסד מצורף.
class AttachedLibrariesPanel extends StatefulWidget {
  /// האם אפשר לקשר קובץ במקומו ולהוסיף תיקיות. במובייל הקובץ תמיד מועתק.
  final bool supportsLinking;

  const AttachedLibrariesPanel({super.key, required this.supportsLinking});

  @override
  State<AttachedLibrariesPanel> createState() => _AttachedLibrariesPanelState();
}

class _AttachedLibrariesPanelState extends State<AttachedLibrariesPanel> {
  @override
  void initState() {
    super.initState();
    context.read<AttachedLibrariesBloc>().add(const LoadAttachedLibraries());
  }

  Future<void> _importFile() async {
    final bloc = context.read<AttachedLibrariesBloc>();
    final files = await FilePicker.pickFiles(
      // בורר המערכת במובייל אינו מכיר את הסיומת db; הקובץ נבדק לפי תוכנו.
      type: widget.supportsLinking ? FileType.custom : FileType.any,
      allowedExtensions: widget.supportsLinking ? const ['db'] : null,
      dialogTitle: context.settingsText('בחר קובץ מסד ספרים'),
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
    final path = files.map((f) => f.path).whereType<String>().firstOrNull;
    if (path != null) bloc.add(ImportAttachedLibraryFile(path));
  }

  Future<void> _addFolder() async {
    final bloc = context.read<AttachedLibrariesBloc>();
    final path = await FilePicker.getDirectoryPath(
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
    if (path != null) bloc.add(AddAttachedLibraryFolder(path));
  }

  Future<void> _removeFolder(String folder) async {
    final bloc = context.read<AttachedLibrariesBloc>();
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('הסרת תיקיית מסדים'),
      content: context.settingsText(
        'המסדים שבתיקייה "{name}" יוסרו מהספרייה. הקבצים עצמם לא יימחקו.',
        args: {'name': p.basename(folder)},
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('הסר'),
    );
    if (confirmed == true) bloc.add(RemoveAttachedLibraryFolder(folder));
  }

  Future<void> _remove(AttachedLibrary library) async {
    final bloc = context.read<AttachedLibrariesBloc>();
    final isCopy = library.mode == AttachedLibraryMode.copy;
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('הסרת מסד'),
      content: isCopy
          ? context.settingsText(
              'המסד "{name}" יוסר מהספרייה, והעותק שלו בתוכנה יימחק.',
              args: {'name': library.displayName},
            )
          : context.settingsText(
              'המסד "{name}" יוסר מהספרייה. הקובץ עצמו לא יימחק.',
              args: {'name': library.displayName},
            ),
      subtitle: isCopy
          ? context.settingsText('שים לב שלא ניתן לבטל פעולה זו')
          : null,
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('הסר'),
    );
    if (confirmed == true) bloc.add(RemoveAttachedLibrary(library));
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    UiSnack.showSuccess(SettingsMessages.pathCopied);
  }

  Future<void> _showFolderMenu(BuildContext anchor, String folder) async {
    final selected = await _showMenu(anchor, [
      AppMenuEntry(
        value: _MenuAction.copyPath,
        label: context.settingsText('העתק נתיב'),
        icon: FluentIcons.copy_24_regular,
      ),
      AppMenuEntry(
        value: _MenuAction.remove,
        label: context.settingsText('הסר תיקייה'),
        icon: FluentIcons.delete_24_regular,
        isDestructive: true,
      ),
    ]);
    switch (selected) {
      case _MenuAction.copyPath:
        await _copyPath(folder);
      case _MenuAction.remove:
        await _removeFolder(folder);
      default:
        break;
    }
  }

  Future<void> _showLibraryMenu(
    BuildContext anchor,
    AttachedLibrary library,
    int index,
    int count,
  ) async {
    final bloc = context.read<AttachedLibrariesBloc>();
    final selected = await _showMenu(anchor, [
      AppMenuEntry(
        value: _MenuAction.toggleHidden,
        label: library.hidden
            ? context.settingsText('הצג בספרייה')
            : context.settingsText('הסתר מהספרייה'),
        icon: library.hidden
            ? FluentIcons.eye_24_regular
            : FluentIcons.eye_off_24_regular,
      ),
      AppMenuEntry(
        value: _MenuAction.moveUp,
        label: context.settingsText('הזז למעלה'),
        icon: FluentIcons.arrow_up_24_regular,
        enabled: index > 0,
      ),
      AppMenuEntry(
        value: _MenuAction.moveDown,
        label: context.settingsText('הזז למטה'),
        icon: FluentIcons.arrow_down_24_regular,
        enabled: index < count - 1,
      ),
      AppMenuEntry(
        value: _MenuAction.release,
        label: context.settingsText('שחרר קובץ'),
        icon: FluentIcons.lock_open_24_regular,
      ),
      AppMenuEntry(
        value: _MenuAction.copyPath,
        label: context.settingsText('העתק נתיב'),
        icon: FluentIcons.copy_24_regular,
      ),
      if (library.isImported)
        AppMenuEntry(
          value: _MenuAction.remove,
          label: context.settingsText('הסר מסד'),
          icon: FluentIcons.delete_24_regular,
          isDestructive: true,
        ),
    ]);
    switch (selected) {
      case _MenuAction.toggleHidden:
        bloc.add(SetAttachedLibraryHidden(library, !library.hidden));
      case _MenuAction.moveUp:
        bloc.add(MoveAttachedLibrary(library, -1));
      case _MenuAction.moveDown:
        bloc.add(MoveAttachedLibrary(library, 1));
      case _MenuAction.release:
        bloc.add(ReleaseAttachedLibrary(library));
      case _MenuAction.copyPath:
        await _copyPath(library.path);
      case _MenuAction.remove:
        await _remove(library);
      case null:
        break;
    }
  }

  Future<_MenuAction?> _showMenu(
    BuildContext anchor,
    List<AppMenuEntry<_MenuAction>> entries,
  ) {
    return showAnchoredAppMenu<_MenuAction>(
      context: context,
      anchorContext: anchor,
      itemsBuilder: (metrics) => [
        for (final entry in entries)
          buildAppPopupMenuItem<_MenuAction>(context, entry, metrics, null),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AttachedLibrariesBloc, AttachedLibrariesState>(
      listenWhen: (previous, current) =>
          current.notice != null && current.notice != previous.notice,
      listener: (context, state) {
        final notice = state.notice!;
        notice.isError
            ? UiSnack.showError(notice.text)
            : UiSnack.show(notice.text);
      },
      builder: (context, state) {
        final libraries = state.libraries;
        return SettingsCard(
          cardId: 'library.attached_libraries',
          title: context.settingsText('מסדי ספרים אישיים'),
          subtitle: widget.supportsLinking
              ? context.settingsText(
                  'צירוף קובצי מסד בפורמט של ספריית אוצריא. הספרים נקראים '
                  'ישירות מהמסד, והקובץ עצמו אינו משתנה.',
                )
              : context.settingsText(
                  'צירוף קובצי מסד בפורמט של ספריית אוצריא. הקובץ שנבחר '
                  'מועתק לאחסון התוכנה.',
                ),
          children: [
            _buildActionsTile(context, state),
            for (final folder in state.folders) _buildFolderTile(folder),
            for (var i = 0; i < libraries.length; i++)
              _AttachedLibraryTile(
                library: libraries[i],
                enabled: !state.isBusy,
                onPlacementChanged: (placement) => context
                    .read<AttachedLibrariesBloc>()
                    .add(SetAttachedLibraryPlacement(libraries[i], placement)),
                onMenu: (anchor) =>
                    _showLibraryMenu(anchor, libraries[i], i, libraries.length),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActionsTile(BuildContext context, AttachedLibrariesState state) {
    final count = state.libraries.length;
    return SettingsActionTile.text(
      icon: FluentIcons.database_24_regular,
      title: context.settingsText('צירוף מסד'),
      subtitle: count == 0
          ? context.settingsText('לא צורפו מסדים')
          : context.settingsText('{count} מסדים', args: {'count': count}),
      actions: [
        IconButton(
          icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
          onPressed: state.isBusy
              ? null
              : () => context.read<AttachedLibrariesBloc>().add(
                  const RescanAttachedLibraries(),
                ),
          tooltip: context.settingsText('בדוק מחדש את המסדים'),
        ),
        if (widget.supportsLinking)
          ActionButton.neutral(
            text: context.settingsText('הוסף תיקיית מסדים'),
            icon: FluentIcons.folder_add_24_regular,
            onPressed: state.isBusy ? null : _addFolder,
          ),
        ActionButton.recommended(
          text: context.settingsText('ייבא קובץ מסד'),
          icon: FluentIcons.database_arrow_down_20_regular,
          onPressed: state.isBusy ? null : _importFile,
          isLoading: state.isBusy,
        ),
      ],
    );
  }

  Widget _buildFolderTile(String folder) {
    return SettingsActionTile.path(
      icon: FluentIcons.folder_24_regular,
      title: context.settingsText('תיקיית מסדים'),
      path: folder,
      placeholder: '',
      pinnedTrailing: Builder(
        builder: (anchor) => IconButton(
          icon: const Icon(FluentIcons.more_vertical_24_regular, size: 18),
          onPressed: () => _showFolderMenu(anchor, folder),
          tooltip: context.settingsText('אפשרויות'),
        ),
      ),
    );
  }
}

enum _MenuAction { toggleHidden, moveUp, moveDown, release, copyPath, remove }

class _AttachedLibraryTile extends StatelessWidget {
  const _AttachedLibraryTile({
    required this.library,
    required this.enabled,
    required this.onPlacementChanged,
    required this.onMenu,
  });

  final AttachedLibrary library;
  final bool enabled;
  final ValueChanged<AttachedLibraryPlacement> onPlacementChanged;
  final void Function(BuildContext anchor) onMenu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SettingsActionTile(
      icon: library.hidden
          ? FluentIcons.database_24_regular
          : FluentIcons.database_24_filled,
      iconColor: library.isOk && !library.hidden
          ? cs.primary
          : cs.onSurfaceVariant,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              library.displayName,
              context.settingsText(
                '{count} ספרים',
                args: {'count': library.bookCount},
              ),
              if (library.hidden) context.settingsText('מוסתר'),
            ].join('  •  '),
            style: AppTextStyles.settingTitle,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _statusChip(context),
              if (library.isOk)
                for (final capability in library.capabilities)
                  _InfoChip(label: _capabilityLabel(context, capability)),
            ],
          ),
        ],
      ),
      subtitle: Text(
        library.path,
        textDirection: TextDirection.ltr,
        style: AppTextStyles.settingSubtitle.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
      pinnedTrailing: Builder(
        builder: (anchor) => IconButton(
          icon: const Icon(FluentIcons.more_vertical_24_regular, size: 18),
          onPressed: enabled ? () => onMenu(anchor) : null,
          tooltip: context.settingsText('אפשרויות'),
        ),
      ),
      actions: [
        if (library.isOk)
          IgnorePointer(
            ignoring: !enabled,
            child: AppSegmentedControl<AttachedLibraryPlacement>(
              currentValue: library.placement,
              onChanged: onPlacementChanged,
              options: [
                SegmentOption(
                  value: AttachedLibraryPlacement.separateRoot,
                  label: context.settingsText('בנפרד'),
                  icon: FluentIcons.folder_24_regular,
                ),
                SegmentOption(
                  value: AttachedLibraryPlacement.mergeIntoLibrary,
                  label: context.settingsText('ממוזג'),
                  icon: FluentIcons.merge_24_regular,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statusChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, background, foreground) = switch (library.status) {
      AttachedLibraryStatus.ok => (
        context.settingsText('זמין'),
        cs.primaryContainer,
        cs.onPrimaryContainer,
      ),
      AttachedLibraryStatus.unreachable => (
        context.settingsText('לא זמין'),
        cs.surfaceContainerHighest,
        cs.onSurfaceVariant,
      ),
      AttachedLibraryStatus.duplicateSlug => (
        context.settingsText('מזהה כפול'),
        cs.errorContainer,
        cs.onErrorContainer,
      ),
      AttachedLibraryStatus.invalid => (
        _problemLabel(context, library.problem),
        cs.errorContainer,
        cs.onErrorContainer,
      ),
    };
    return _InfoChip(
      label: label,
      background: background,
      foreground: foreground,
    );
  }

  static String _problemLabel(
    BuildContext context,
    AttachedLibraryProblem? problem,
  ) => switch (problem) {
    AttachedLibraryProblem.notSqlite => context.settingsText(
      'אינו מסד SQLite',
    ),
    AttachedLibraryProblem.pendingJournal => context.settingsText(
      'פתוח בתוכנה אחרת',
    ),
    AttachedLibraryProblem.noBooks => context.settingsText('אין טבלת ספרים'),
    _ => context.settingsText('לא ניתן לפתוח'),
  };

  static String _capabilityLabel(
    BuildContext context,
    AttachedLibraryCapability capability,
  ) => switch (capability) {
    AttachedLibraryCapability.categories => context.settingsText('קטגוריות'),
    AttachedLibraryCapability.toc => context.settingsText('תוכן עניינים'),
    AttachedLibraryCapability.links => context.settingsText('קישורים'),
    AttachedLibraryCapability.altToc => context.settingsText('כותרות'),
    AttachedLibraryCapability.versions => context.settingsText('גרסאות'),
    AttachedLibraryCapability.authors => context.settingsText('מחברים'),
    AttachedLibraryCapability.generations => context.settingsText('דורות'),
    AttachedLibraryCapability.acronyms => context.settingsText('ראשי תיבות'),
    AttachedLibraryCapability.lineRef => context.settingsText('הפניות'),
    AttachedLibraryCapability.defaultCommentators => context.settingsText(
      'מפרשי ברירת מחדל',
    ),
    AttachedLibraryCapability.externalLinks => context.settingsText(
      'קישורים לספרים אחרים',
    ),
  };
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, this.background, this.foreground});

  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground ?? cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// ברירת המחדל לפי הפלטפורמה: קישור במחשב, העתקה במובייל.
bool get attachedLibrariesSupportLinking =>
    !(Platform.isAndroid || Platform.isIOS);
