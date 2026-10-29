import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/settings/l10n/settings_dialog_scope.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/services/user_import_library.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// ניהול קובצי הייבוא: צפייה, השהיה, ייצוא ומחיקה. הרשימה מגיעה מה-bloc,
/// כדי ששינוי כאן ירענן את אותו מקור שמזין את שאר מסך ההגדרות.
class UserImportFilesDialog extends StatelessWidget {
  const UserImportFilesDialog({super.key});

  /// פותח את הדיאלוג ומבקש רשימה מעודכנת.
  static Future<void> show(BuildContext context) {
    final bloc = context.read<CustomFoldersBloc>()
      ..add(const LoadUserImportFiles());
    return showDialog<void>(
      context: context,
      // עוטף בשפת ההגדרות: דיאלוג נפתח מחוץ לתת-העץ של מסך ההגדרות ואינו
      // יורש את ה-SettingsTextScope שלו.
      builder: settingsDialogBuilder(
        context,
        (_) => BlocProvider.value(
          value: bloc,
          child: const UserImportFilesDialog(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCustomContentDialog(
      title: context.settingsText('קבצים מיובאים'),
      icon: FluentIcons.arrow_import_24_regular,
      scrollable: false,
      actions: [
        ActionButton.ghost(
          text: context.settingsText('סגור'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: BlocBuilder<CustomFoldersBloc, CustomFoldersState>(
        buildWhen: (p, c) =>
            p.importFiles != c.importFiles || p.isSyncing != c.isSyncing,
        builder: (context, state) {
          if (state.importFiles.isEmpty) {
            return OtzariaEmptyState(
              isCompact: true,
              icon: FluentIcons.arrow_import_24_regular,
              title: context.settingsText(
                'לא יובאו עדיין קבצים. השתמש ב"ייבוא נתונים" כדי להוסיף.',
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: ListDialogCard(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: state.importFiles.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: listDialogRowDivider(context).color,
                    ),
                    itemBuilder: (context, index) => _ImportFileRow(
                      file: state.importFiles[index],
                      busy: state.isSyncing,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ImportFileRow extends StatelessWidget {
  const _ImportFileRow({required this.file, required this.busy});

  final UserImportFile file;
  final bool busy;

  Future<void> _export(BuildContext context) async {
    final dialogTitle = context.settingsText('ייצוא');
    final content = await context.read<CustomFoldersBloc>().importFileContent(
      file.id,
    );
    if (content == null) {
      UiSnack.showError(SettingsMessages.importFileMissing);
      return;
    }
    if (!context.mounted) return;
    final saved = await saveFileWithExtension(
      fileName: file.name,
      extension: file.name.toLowerCase().endsWith('.json') ? '.json' : '.csv',
      bytes: utf8.encode(content),
      dialogTitle: '$dialogTitle: ${file.name}',
      context: context,
    );
    if (saved == null) return;
    UiSnack.showSuccess(SettingsMessages.importFileExported(saved));
  }

  Future<void> _delete(BuildContext context) async {
    final bloc = context.read<CustomFoldersBloc>();
    // שם הקובץ מחוץ למפתח התרגום — אחרת כל קובץ היה מפתח נפרד בקטלוג.
    // משתנה ולא קריאה בתוך אינטרפולציה, כדי שסורק המפתחות יראה אותה.
    final title = context.settingsText('מחיקת קובץ מיובא');
    final confirmed = await showWarningDialog(
      context: context,
      title: '$title: ${file.name}',
      content: context.settingsText(
        'הקובץ יוסר והנתונים שהגיעו ממנו יימחקו מהתוכנה.',
      ),
      subtitle: context.settingsText(
        'נתונים שהגיעו מקבצים אחרים יישארו. אפשר גם להשהות במקום למחוק.',
      ),
      confirmText: context.settingsText('מחק'),
    );
    if (confirmed == true) bloc.add(RemoveUserImportFile(file.id));
  }

  @override
  Widget build(BuildContext context) {
    final disabledColor = Theme.of(context).disabledColor;
    final cs = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(
        start: AppTokens.spaceMD,
        end: AppTokens.spaceSM,
      ),
      leading: Icon(
        _iconFor(file.kind),
        color: file.enabled ? cs.primary : disabledColor,
      ),
      title: Text(
        file.name,
        style: TextStyle(
          fontSize: AppTokens.fontMD + 1,
          fontWeight: FontWeight.w600,
          color: file.enabled ? cs.onSurface : disabledColor,
          // קובץ מושהה נשאר ברשימה; הקו מבדיל אותו מקובץ פעיל במבט אחד.
          decoration: file.enabled ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(
        [
          _kindLabel(context, file.kind),
          if (!file.enabled) context.settingsText('מושהה'),
        ].join(' · '),
        style: TextStyle(
          fontSize: AppTokens.fontSM,
          color: file.enabled ? cs.onSurfaceVariant : disabledColor,
        ),
      ),
      // ברוחב טלפון שלוש הפעולות מצמצמות את שם הקובץ לכמה אותיות — הן עוברות
      // לתפריט אחד.
      trailing: narrow
          ? PopupMenuButton<int>(
              enabled: !busy,
              tooltip: context.settingsText('פעולות'),
              onSelected: (action) {
                switch (action) {
                  case 0:
                    context.read<CustomFoldersBloc>().add(
                      SetUserImportFileEnabled(
                        file.id,
                        enabled: !file.enabled,
                      ),
                    );
                  case 1:
                    _export(context);
                  case 2:
                    _delete(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 0,
                  child: Text(
                    file.enabled
                        ? context.settingsText('השהה')
                        : context.settingsText('החזר לשימוש'),
                  ),
                ),
                PopupMenuItem(
                  value: 1,
                  child: Text(context.settingsText('ייצוא')),
                ),
                PopupMenuItem(
                  value: 2,
                  child: Text(context.settingsText('מחיקה')),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: file.enabled
                      ? context.settingsText('השהה')
                      : context.settingsText('החזר לשימוש'),
                  icon: Icon(
                    file.enabled
                        ? FluentIcons.pause_24_regular
                        : FluentIcons.play_24_regular,
                  ),
                  onPressed: busy
                      ? null
                      : () => context.read<CustomFoldersBloc>().add(
                          SetUserImportFileEnabled(
                            file.id,
                            enabled: !file.enabled,
                          ),
                        ),
                ),
                IconButton(
                  tooltip: context.settingsText('ייצוא'),
                  icon: const Icon(FluentIcons.arrow_export_24_regular),
                  onPressed: busy ? null : () => _export(context),
                ),
                IconButton(
                  tooltip: context.settingsText('מחיקה'),
                  icon: const Icon(FluentIcons.delete_24_regular),
                  onPressed: busy ? null : () => _delete(context),
                ),
              ],
            ),
    );
  }

  static String _kindLabel(BuildContext context, UserImportKind kind) =>
      switch (kind) {
        UserImportKind.links => context.settingsText('קישורים'),
        UserImportKind.generations => context.settingsText('דורות'),
        UserImportKind.headings => context.settingsText('כותרות'),
        UserImportKind.versions => context.settingsText('גרסאות'),
      };

  static IconData _iconFor(UserImportKind kind) => switch (kind) {
    UserImportKind.links => OtzariaIcons.link_24_regular,
    UserImportKind.generations => FluentIcons.people_team_24_regular,
    UserImportKind.headings => FluentIcons.text_header_1_24_regular,
    UserImportKind.versions => FluentIcons.document_copy_24_regular,
  };
}
