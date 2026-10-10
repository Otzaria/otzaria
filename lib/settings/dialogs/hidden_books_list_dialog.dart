import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
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

    return ListDialogFrame(
      icon: FluentIcons.eye_off_24_regular,
      title: context.settingsText('בחירות הסתרה ישירות'),
      counter: '${entries.length}',
      maxWidth: 640,
      heightFactor: 0.8,
      children: [
        const SizedBox(height: 8),
        Text(
          context.settingsText(
            'הרשימה מציגה בחירות ישירות. להסרת הסתרה בירושה, בטלו את הסתרת קטגוריית האב.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    context.settingsText('אין בחירות הסתרה'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: cs.surfaceContainerHighest,
                  ),
                  itemBuilder: (_, i) {
                    final entry = entries[i];
                    return ListTile(
                      leading: Icon(entry.icon, size: 20),
                      title: Text(entry.label),
                      trailing: ActionButton.ghost(
                        text: context.settingsText('בטל הסתרה'),
                        onPressed: entry.remove,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ActionButton.recommended(
              text: context.settingsText('שמור'),
              onPressed: () =>
                  Navigator.of(context).pop(_changed ? _selection : null),
            ),
            const SizedBox(width: 8),
            if (entries.isNotEmpty)
              ActionButton.warning(
                text: context.settingsText('בטל הכול'),
                onPressed: _clearAll,
              ),
            const Spacer(),
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
