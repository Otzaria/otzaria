import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';

/// אזור נפרד בחלונית ההערות עם ההערות שנכתבו על המפרשים המוצגים לצד הספר.
/// לחיצה על הערה פותחת את הערות אותו מפרש בחלונית, ושם אפשר לערוך אותן.
class CommentaryNotesSection extends StatefulWidget {
  /// מפתחות ההערות של המפרשים, לפי סדר התצוגה.
  final List<String> bookIds;
  final void Function(String bookId, int lineNumber) onOpenNote;
  final PersonalNotesLoader loader;

  /// מתעדכן בכל שינוי בהערות, גם בשמירה שעוקפת את ה-PersonalNotesBloc.
  final ValueListenable<int>? revision;

  CommentaryNotesSection({
    super.key,
    required this.bookIds,
    required this.onOpenNote,
    this.loader = loadStoredPersonalNotes,
    ValueListenable<int>? revision,
  }) : revision = revision ?? PersonalNotesDatabase.instance.revision;

  @override
  State<CommentaryNotesSection> createState() => _CommentaryNotesSectionState();
}

class _CommentaryNotesSectionState extends State<CommentaryNotesSection> {
  List<(String, List<PersonalNote>)> _groups = const [];
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    widget.revision?.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant CommentaryNotesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      oldWidget.revision?.removeListener(_load);
      widget.revision?.addListener(_load);
    }
    if (!listEquals(oldWidget.bookIds, widget.bookIds)) _load();
  }

  @override
  void dispose() {
    widget.revision?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final groups = <(String, List<PersonalNote>)>[];
    for (final bookId in widget.bookIds) {
      final notes = (await widget.loader(
        bookId,
      )).where((note) => note.lineNumber != null).toList();
      if (notes.isNotEmpty) groups.add((bookId, notes));
    }
    if (!mounted || token != _loadToken) return;
    setState(() => _groups = groups);
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'הערות על המפרשים המוצגים',
            style: theme.textTheme.titleSmall,
          ),
        ),
        for (final (bookId, notes) in _groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              bookId,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final note in notes)
            ListTile(
              dense: true,
              title: Text(
                note.title.isNotEmpty ? note.title : 'שורה ${note.lineNumber}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                note.contentPlain,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => widget.onOpenNote(bookId, note.lineNumber!),
            ),
        ],
      ],
    );
  }
}
