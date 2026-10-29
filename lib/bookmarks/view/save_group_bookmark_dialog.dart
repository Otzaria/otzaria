import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// שמירת סימניה מרוכזת לכל הספרים הפתוחים: אוסף את מיקומי כל טאבי הקריאה,
/// מציג דיאלוג בחירה, ובשמירה מזהה קבוצה דומה קיימת ומציע להחליפה.
Future<void> showSaveGroupBookmarkDialog(BuildContext context) async {
  final tabsBloc = context.read<TabsBloc>();
  final bookmarkBloc = context.read<BookmarkBloc>();
  final tabsState = tabsBloc.state;

  final entries = <Bookmark>[];
  final seenKeys = <String>{};
  Bookmark? activeEntry;
  for (final tab in tabsState.tabs) {
    for (final pane in leafPanes(tab)) {
      final bookmark = await bookmarkFromReadingTab(
        pane,
        useStoredPositionFallback: true,
      );
      if (bookmark == null) continue;
      // שני טאבים של אותו ספר באותו מיקום = רשומה אחת בקבוצה.
      final key =
          '${bookIdentity(bookmark.book)}|${bookmark.index}'
          '|${bookmark.targetKind.name}';
      if (!seenKeys.add(key)) continue;
      entries.add(bookmark);
      if (identical(tab, tabsState.currentTab)) {
        activeEntry ??= bookmark;
      }
    }
  }

  if (entries.isEmpty) {
    UiSnack.show(NotesMessages.noOpenBooksForGroupBookmark);
    return;
  }

  if (!context.mounted) return;
  final result = await showDialog<({String name, List<Bookmark> selected})>(
    context: context,
    builder: (_) => _SaveGroupBookmarkDialog(
      entries: entries,
      suggestedName: (activeEntry ?? entries.first).ref,
    ),
  );
  if (result == null || !context.mounted) return;

  final group = BookmarkGroup(
    name: result.name,
    items: result.selected,
    createdAt: DateTime.now(),
  );

  final similar = bookmarkBloc.findSimilarGroup(group.bookIdentities);
  if (similar == null) {
    bookmarkBloc.addGroup(group);
    UiSnack.show(NotesMessages.groupBookmarkSaved);
    return;
  }

  // true = החלף את הישנה, false = שמור כחדשה, null (Esc) = ביטול.
  final replace = await showTwoActionsDialog(
    context: context,
    title: 'סימניה מרוכזת דומה כבר קיימת',
    content:
        'כבר שמורה הסימניה המרוכזת "${similar.name}" עבור ספרים אלה או '
        'רובם. האם להחליף אותה במיקומים החדשים, או לשמור סימניה נוספת?',
    cancelText: 'שמור כסימניה נוספת',
    confirmText: 'החלף את הישנה',
  );
  if (replace == null) return;

  if (replace) {
    bookmarkBloc.replaceGroup(similar.id, group);
    UiSnack.show(NotesMessages.groupBookmarkReplaced);
  } else {
    bookmarkBloc.addGroup(group);
    UiSnack.show(NotesMessages.groupBookmarkSaved);
  }
}

class _SaveGroupBookmarkDialog extends StatefulWidget {
  final List<Bookmark> entries;
  final String suggestedName;

  const _SaveGroupBookmarkDialog({
    required this.entries,
    required this.suggestedName,
  });

  @override
  State<_SaveGroupBookmarkDialog> createState() =>
      _SaveGroupBookmarkDialogState();
}

class _SaveGroupBookmarkDialogState extends State<_SaveGroupBookmarkDialog> {
  late final TextEditingController _nameController;
  late final List<bool> _selected;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName);
    _selected = List<bool>.filled(widget.entries.length, true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final selected = <Bookmark>[
      for (var i = 0; i < widget.entries.length; i++)
        if (_selected[i]) widget.entries[i],
    ];
    if (selected.isEmpty) {
      UiSnack.show(NotesMessages.groupBookmarkNoSelection);
      return;
    }
    final name = _nameController.text.trim();
    Navigator.of(context).pop((
      name: name.isEmpty ? widget.suggestedName : name,
      selected: selected,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppCustomContentDialog(
      title: 'שמירת סימניה מרוכזת',
      icon: FluentIcons.bookmark_add_24_regular,
      scrollable: false,
      actions: [
        ActionButton.ghost(
          text: 'ביטול',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(text: 'שמור', onPressed: _save),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RtlTextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'שם הסימניה'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Text(
            'הספרים שיישמרו במיקומם הנוכחי:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: widget.entries.length,
              itemBuilder: (context, i) {
                final entry = widget.entries[i];
                return CheckboxListTile(
                  value: _selected[i],
                  onChanged: (value) =>
                      setState(() => _selected[i] = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: entry.book is PdfBook
                      ? const Icon(OtzariaIcons.book_pdf_24_regular)
                      : null,
                  title: Text(entry.book.title),
                  subtitle: Text(
                    ItemsListView.locationSubtitle(entry) ?? entry.ref,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
