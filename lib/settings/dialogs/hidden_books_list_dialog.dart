import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// חלון הספרים והקטגוריות המוסתרים, עם ביטול הסתרה (issue #1448).
///
/// הרשימה בחלון נפרד ולא בגוף מסך ההגדרות: מספר ההסתרות אינו חסום, ורשימה
/// פנימית הייתה מאריכה את המסך בלי גבול.
///
/// מחזיר את הבחירה המעודכנת, או `null` כשלא השתנה דבר.
Future<HiddenLibrarySelection?> showHiddenBooksListDialog({
  required BuildContext context,
  required HiddenLibrarySelection hidden,
  required Map<String, String> titles,
}) {
  return showDialog<HiddenLibrarySelection>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (_) => _HiddenBooksListDialog(hidden: hidden, titles: titles),
    ),
  );
}

class _HiddenBooksListDialog extends StatefulWidget {
  final HiddenLibrarySelection hidden;

  /// מפתח ספר → כותרת. ספר שאינו בספרייה יוצג לפי המפתח הגולמי, כדי שאפשר
  /// יהיה להסיר גם הסתרה של ספר שנעלם.
  final Map<String, String> titles;

  const _HiddenBooksListDialog({required this.hidden, required this.titles});

  @override
  State<_HiddenBooksListDialog> createState() => _HiddenBooksListDialogState();
}

class _HiddenBooksListDialogState extends State<_HiddenBooksListDialog> {
  late Set<String> _bookKeys = {...widget.hidden.bookKeys};
  late Set<String> _categoryPaths = {...widget.hidden.categoryPaths};

  bool get _changed =>
      _bookKeys.length != widget.hidden.bookKeys.length ||
      _categoryPaths.length != widget.hidden.categoryPaths.length;

  HiddenLibrarySelection get _selection => HiddenLibrarySelection(
    bookKeys: _bookKeys,
    categoryPaths: _categoryPaths,
  );

  Future<void> _clearAll() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: 'לבטל את כל ההסתרות?',
      content: 'כל הספרים והקטגוריות המוסתרים יחזרו להיראות בממשק.',
      confirmText: 'בטל הכול',
    );
    if (confirmed != true) return;
    setState(() {
      _bookKeys = {};
      _categoryPaths = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final entries = [
      for (final path in _categoryPaths.toList()..sort())
        (
          label: path,
          icon: FluentIcons.folder_24_regular,
          remove: () => setState(() => _categoryPaths.remove(path)),
        ),
      for (final key in _bookKeys.toList()..sort())
        (
          label: widget.titles[key] ?? key,
          icon: OtzariaIcons.book_24_regular,
          remove: () => setState(() => _bookKeys.remove(key)),
        ),
    ];

    Widget row(({String label, IconData icon, VoidCallback remove}) entry) =>
        ListTile(
          shape: Border(bottom: listDialogRowDivider(context)),
          leading: Icon(entry.icon, size: 20, color: cs.primary),
          title: Tooltip(
            message: entry.label,
            child: Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTokens.fontMD + 1,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          // ברוחב טלפון הכפתור עם הטקסט היה מצמצם את שם הספר לכמה אותיות.
          trailing: MediaQuery.sizeOf(context).width < 520
              ? IconButton(
                  tooltip: context.settingsText('בטל הסתרה'),
                  icon: const Icon(FluentIcons.eye_24_regular),
                  onPressed: entry.remove,
                )
              : ActionButton.ghost(
                  text: context.settingsText('בטל הסתרה'),
                  onPressed: entry.remove,
                ),
        );

    return ListDialogFrame(
      icon: FluentIcons.eye_off_24_regular,
      title: context.settingsText('בחירות הסתרה ישירות'),
      counter: '${entries.length}',
      maxWidth: 640,
      heightFactor: 0.8,
      children: [
        const SizedBox(height: AppTokens.spaceSM),
        Text(
          context.settingsText(
            'הרשימה מציגה בחירות ישירות. להסרת הסתרה בירושה, בטלו את הסתרת קטגוריית האב.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        Flexible(
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: OtzariaEmptyState(
                    isCompact: true,
                    icon: FluentIcons.eye_24_regular,
                    title: context.settingsText('אין בחירות הסתרה'),
                  ),
                )
              : ListDialogCard(
                  child: ListView.builder(
                    shrinkWrap: true,
                    // גובה שורה קבוע: קפיצת פס הגלילה לא בונה את כל השורות בדרך
                    prototypeItem: row(
                      (
                        label: '',
                        icon: FluentIcons.folder_24_regular,
                        remove: () {},
                      ),
                    ),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => row(entries[i]),
                  ),
                ),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        Row(
          children: [
            // עוטף בשורה שנייה ברוחב טלפון במקום לגלוש.
            Expanded(
              child: Wrap(
                spacing: AppTokens.spaceSM,
                runSpacing: AppTokens.spaceSM,
                children: [
                  ActionButton.recommended(
                    text: context.settingsText('שמור'),
                    onPressed: () =>
                        Navigator.of(context).pop(_changed ? _selection : null),
                  ),
                  if (entries.isNotEmpty)
                    ActionButton.warning(
                      text: context.settingsText('בטל הכול'),
                      onPressed: _clearAll,
                    ),
                ],
              ),
            ),
            ActionButton.ghost(
              text: context.settingsText('סגור'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
