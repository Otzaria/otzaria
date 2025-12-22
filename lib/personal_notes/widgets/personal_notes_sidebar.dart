import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/confirmation_dialog.dart';
import 'package:otzaria/widgets/input_dialog.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

class PersonalNotesSidebar extends StatefulWidget {
  final String bookId;
  final ValueChanged<int> onNavigateToLine;

  const PersonalNotesSidebar({
    super.key,
    required this.bookId,
    required this.onNavigateToLine,
  });

  @override
  State<PersonalNotesSidebar> createState() => _PersonalNotesSidebarState();
}

class _PersonalNotesSidebarState extends State<PersonalNotesSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showOnlyVisible = true; // ברירת מחדל: הצג רק הערות לטקסט הנראה

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PersonalNotesBloc>().add(LoadPersonalNotes(widget.bookId));
    });
  }

  @override
  void didUpdateWidget(covariant PersonalNotesSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId) {
      _searchController.clear();
      _searchQuery = '';
      context.read<PersonalNotesBloc>().add(LoadPersonalNotes(widget.bookId));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // בדיקה אם יש TextBookBloc בהקשר (לא קיים ב-PDF)
    final textBookBloc = context.read<TextBookBloc?>();
    
    if (textBookBloc == null) {
      // מצב PDF - אין TextBookBloc
      return BlocBuilder<PersonalNotesBloc, PersonalNotesState>(
        buildWhen: (previous, current) => current.bookId == widget.bookId,
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, state, const []),
              const Divider(height: 1),
              Expanded(
                child: _buildContent(context, state, const []),
              ),
            ],
          );
        },
      );
    }

    // מצב טקסט רגיל - יש TextBookBloc
    return BlocBuilder<TextBookBloc, TextBookState>(
      buildWhen: (previous, current) {
        if (previous is TextBookLoaded && current is TextBookLoaded) {
          return previous.visibleIndices != current.visibleIndices;
        }
        return true;
      },
      builder: (context, textBookState) {
        final visibleIndices = textBookState is TextBookLoaded
            ? textBookState.visibleIndices
            : <int>[];

        return BlocBuilder<PersonalNotesBloc, PersonalNotesState>(
          buildWhen: (previous, current) => current.bookId == widget.bookId,
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, state, visibleIndices),
                const Divider(height: 1),
                Expanded(
                  child: _buildContent(context, state, visibleIndices),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, PersonalNotesState state,
      List<int> visibleIndices) {
    final totalNotes = state.locatedNotes.length + state.missingNotes.length;
    final visibleNotes = _showOnlyVisible && visibleIndices.isNotEmpty
        ? state.locatedNotes
            .where((n) =>
                n.lineNumber != null &&
                visibleIndices.contains(n.lineNumber! - 1))
            .length
        : totalNotes;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: RtlTextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'חפש בהערות...',
                    prefixIcon: const Icon(FluentIcons.search_24_regular),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'רענן',
                onPressed: () {
                  context
                      .read<PersonalNotesBloc>()
                      .add(LoadPersonalNotes(widget.bookId));
                },
                icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _showOnlyVisible = !_showOnlyVisible;
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _showOnlyVisible
                              ? FluentIcons.checkbox_checked_24_regular
                              : FluentIcons.checkbox_unchecked_24_regular,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'הצג רק הערות לטקסט הנראה',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Text(
                '$visibleNotes/$totalNotes',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, PersonalNotesState state,
      List<int> visibleIndices) {
    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            state.errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    if (state.locatedNotes.isEmpty && state.missingNotes.isEmpty) {
      return const Center(
        child: Text('אין עדיין הערות על ספר זה'),
      );
    }

    // סינון ההערות לפי הטקסט הנראה במסך
    var locatedNotes = state.locatedNotes;
    if (_showOnlyVisible && visibleIndices.isNotEmpty) {
      locatedNotes = locatedNotes.where((note) {
        if (note.lineNumber == null) return false;
        // lineNumber הוא 1-based, visibleIndices הוא 0-based
        return visibleIndices.contains(note.lineNumber! - 1);
      }).toList();
    }

    // סינון ההערות לפי שאילתת החיפוש
    final filteredLocatedNotes = _searchQuery.isEmpty
        ? locatedNotes
        : locatedNotes.where((note) {
            final query = _searchQuery.toLowerCase();
            return note.content.toLowerCase().contains(query) ||
                note.lineNumber.toString().contains(query);
          }).toList();

    // הערות חסרות מיקום - מוצגות רק אם לא מסננים לפי טקסט נראה
    final filteredMissingNotes = _showOnlyVisible
        ? <PersonalNote>[]
        : (_searchQuery.isEmpty
            ? state.missingNotes
            : state.missingNotes.where((note) {
                final query = _searchQuery.toLowerCase();
                return note.content.toLowerCase().contains(query) ||
                    (note.lastKnownLineNumber?.toString().contains(query) ??
                        false);
              }).toList());

    // אם אין תוצאות
    if (filteredLocatedNotes.isEmpty && filteredMissingNotes.isEmpty) {
      final message = _showOnlyVisible && visibleIndices.isNotEmpty
          ? 'אין הערות לטקסט הנראה במסך'
          : (_searchQuery.isNotEmpty
              ? 'לא נמצאו הערות התואמות לחיפוש'
              : 'אין עדיין הערות על ספר זה');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (filteredLocatedNotes.isNotEmpty) ...[
          ...filteredLocatedNotes.map(
            (note) => _LocatedNoteTile(
              note: note,
              onTap: () => widget.onNavigateToLine(note.lineNumber!),
              onEdit: () => _editNote(context, note),
              onDelete: () => _confirmDelete(context, note),
              searchQuery: _searchQuery,
            ),
          ),
        ],
        if (filteredMissingNotes.isNotEmpty) ...[
          if (filteredLocatedNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'הערות חסרות מיקום',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
            ),
          ...filteredMissingNotes.map(
            (note) => _MissingNoteTile(
              note: note,
              onReposition: () => _reposition(context, note),
              onEdit: () => _editNote(context, note),
              onDelete: () => _confirmDelete(context, note),
              searchQuery: _searchQuery,
            ),
          ),
        ],
        if (state.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Future<void> _editNote(BuildContext context, PersonalNote note) async {
    final controller = TextEditingController(text: note.content);
    final bloc = context.read<PersonalNotesBloc>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => PersonalNoteEditorDialog(
        title: 'ערוך הערה',
        controller: controller,
        referenceText: note.displayTitle,
        icon: FluentIcons.edit_24_regular,
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    bloc.add(
      UpdatePersonalNote(
        bookId: widget.bookId,
        noteId: note.id,
        content: result,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, PersonalNote note) async {
    final bloc = context.read<PersonalNotesBloc>();
    final shouldDelete = await showConfirmationDialog(
      context: context,
      title: 'מחיקת הערה',
      content: 'האם למחוק את ההערה לצמיתות?',
      confirmText: 'מחק',
      isDangerous: true,
    );

    if (shouldDelete == true) {
      if (!mounted) return;
      bloc.add(
        DeletePersonalNote(
          bookId: widget.bookId,
          noteId: note.id,
        ),
      );
    }
  }

  Future<void> _reposition(BuildContext context, PersonalNote note) async {
    final bloc = context.read<PersonalNotesBloc>();

    final result = await showInputDialog(
      context: context,
      title: 'שחזור מיקום הערה',
      subtitle: note.lastKnownLineNumber != null
          ? 'המיקום האחרון הידוע: שורה ${note.lastKnownLineNumber}'
          : null,
      labelText: 'שורה חדשה',
      hintText: 'הקלד מספר שורה',
      initialValue: note.lastKnownLineNumber?.toString() ?? '',
      keyboardType: TextInputType.number,
    );

    final newLine = result != null ? int.tryParse(result) : null;

    if (newLine != null) {
      if (!mounted) return;
      bloc.add(
        RepositionPersonalNote(
          bookId: widget.bookId,
          noteId: note.id,
          lineNumber: newLine,
        ),
      );
    }
  }
}

class _LocatedNoteTile extends StatefulWidget {
  final PersonalNote note;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String searchQuery;

  const _LocatedNoteTile({
    required this.note,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.searchQuery = '',
  });

  @override
  State<_LocatedNoteTile> createState() => _LocatedNoteTileState();
}

class _LocatedNoteTileState extends State<_LocatedNoteTile> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: widget.onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.note.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _NoteActions(
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                  isExpanded: _isExpanded,
                  onToggleExpansion: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _isExpanded
              ? InkWell(
                  onTap: widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
                    color: Theme.of(context).colorScheme.surface,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        widget.note.content,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                        textAlign: TextAlign.justify,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Divider(
          height: 1,
          thickness: 0.5,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ],
    );
  }
}

class _MissingNoteTile extends StatefulWidget {
  final PersonalNote note;
  final VoidCallback onReposition;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String searchQuery;

  const _MissingNoteTile({
    required this.note,
    required this.onReposition,
    required this.onEdit,
    required this.onDelete,
    this.searchQuery = '',
  });

  @override
  State<_MissingNoteTile> createState() => _MissingNoteTileState();
}

class _MissingNoteTileState extends State<_MissingNoteTile> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: widget.onReposition,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: Theme.of(context)
                .colorScheme
                .surfaceTint
                .withValues(alpha: 0.05),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'הערה ללא מיקום',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                _NoteActions(
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                  isExpanded: _isExpanded,
                  onToggleExpansion: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  extraAction: IconButton(
                    tooltip: 'מיקום מחדש',
                    icon: const Icon(FluentIcons.location_24_regular, size: 18),
                    iconSize: 18,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: widget.onReposition,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _isExpanded
              ? InkWell(
                  onTap: widget.onReposition,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceTint
                        .withValues(alpha: 0.05),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.note.lastKnownLineNumber != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              'שורה קודמת: ${widget.note.lastKnownLineNumber}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            widget.note.content,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  height: 1.5,
                                ),
                            textAlign: TextAlign.justify,
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Divider(
          height: 1,
          thickness: 0.5,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ],
    );
  }
}

class _NoteActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isExpanded;
  final VoidCallback onToggleExpansion;
  final Widget? extraAction;

  const _NoteActions({
    required this.onEdit,
    required this.onDelete,
    required this.isExpanded,
    required this.onToggleExpansion,
    this.extraAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'עריכה',
          icon: const Icon(FluentIcons.edit_24_regular, size: 18),
          iconSize: 18,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          onPressed: onEdit,
        ),
        if (extraAction != null) extraAction!,
        IconButton(
          tooltip: 'מחיקה',
          icon: const Icon(FluentIcons.delete_24_regular, size: 18),
          iconSize: 18,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          onPressed: onDelete,
        ),
        IconButton(
          tooltip: isExpanded ? 'סגור' : 'פתח',
          icon: AnimatedRotation(
            turns: isExpanded ? 0.5 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              FluentIcons.chevron_down_24_regular,
              size: 18,
            ),
          ),
          iconSize: 18,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          onPressed: onToggleExpansion,
        ),
      ],
    );
  }
}
