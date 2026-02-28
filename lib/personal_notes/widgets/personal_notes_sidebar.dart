import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/notes_search_header.dart';
import 'package:otzaria/personal_notes/widgets/note_tile.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';

class PersonalNotesSidebar extends StatefulWidget {
  final String bookId;
  final ValueChanged<int> onNavigateToLine;

  const PersonalNotesSidebar({
    super.key,
    required this.bookId,
    required this.onNavigateToLine,
  });

  @override
  State<PersonalNotesSidebar> createState() => PersonalNotesSidebarState();

  static PersonalNotesSidebarState? of(BuildContext context) {
    return context.findAncestorStateOfType<PersonalNotesSidebarState>();
  }
}

class PersonalNotesSidebarState extends State<PersonalNotesSidebar> {
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
      context.read<PersonalNotesBloc>().add(const CancelCreatingPersonalNote());
      context.read<PersonalNotesBloc>().add(LoadPersonalNotes(widget.bookId));
    }
  }

  Future<void> _cancelNewNote({bool confirmIfDirty = true}) async {
    if (!mounted) return;
    context.read<PersonalNotesBloc>().add(const CancelCreatingPersonalNote());
  }

  void _saveNewNote(PersonalNoteEditorResult result) {
    final bloc = context.read<PersonalNotesBloc>();
    final lineNumber = bloc.state.newNoteLineNumber;
    final selectedText = bloc.state.newNoteSelectedText;

    if (lineNumber == null) return;

    bloc.add(AddPersonalNote(
      bookId: widget.bookId,
      lineNumber: lineNumber,
      content: result.content,
      contentPlain: result.contentPlain,
      contentFormat: result.contentFormat,
      selectedText: selectedText?.trim(),
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ההערה נשמרה בהצלחה')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // בודקים אם TextBookBloc זמין בהקשר הנוכחי
    final hasTextBookBloc =
        context.findAncestorWidgetOfExactType<BlocProvider<TextBookBloc>>() !=
            null;

    final child = BlocBuilder<PersonalNotesBloc, PersonalNotesState>(
      buildWhen: (previous, current) {
        if (previous.isCreatingNewNote != current.isCreatingNewNote) {
          return true;
        }
        return current.bookId == widget.bookId;
      },
      builder: (context, state) {
        if (state.isLoading && state.locatedNotes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NotesSearchHeader(bookId: widget.bookId),
            const Divider(height: 1),
            Expanded(
              child: hasTextBookBloc
                  ? BlocBuilder<TextBookBloc, TextBookState>(
                      buildWhen: (previous, current) {
                        if (previous is TextBookLoaded &&
                            current is TextBookLoaded) {
                          return previous.selectedIndex !=
                              current.selectedIndex;
                        }
                        return true;
                      },
                      builder: (context, textBookState) {
                        final selectedLineNumber =
                            textBookState is TextBookLoaded
                                ? (textBookState.selectedIndex != null
                                    ? textBookState.selectedIndex! + 1
                                    : null)
                                : null;

                        return _buildContent(
                          context,
                          state,
                          selectedLineNumber: selectedLineNumber,
                        );
                      },
                    )
                  : _buildContent(context, state, selectedLineNumber: null),
            ),
          ],
        );
      },
    );

    // אם TextBookBloc זמין, נעטוף עם listener
    if (hasTextBookBloc) {
      return MultiBlocListener(
        listeners: [
          BlocListener<TextBookBloc, TextBookState>(
            listener: (context, state) {
              if (state is TextBookLoaded) {
                context
                    .read<PersonalNotesBloc>()
                    .add(UpdateVisibleLines(state.visibleIndices));
              }
            },
          ),
        ],
        child: child,
      );
    }

    return child;
  }

  Widget _buildContent(
    BuildContext context,
    PersonalNotesState state, {
    int? selectedLineNumber,
  }) {
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

    final defaultExpanded = !(Settings.getValue<bool>(
            SettingsRepository.keyPersonalNotesCollapsedByDefault) ??
        true);

    final items = <Widget>[];

    // עורך הערה חדשה
    if (state.isCreatingNewNote) {
      items.add(_buildNewNoteEditor(context, state));
    }

    // הערות ממוקמות
    if (state.filteredLocatedNotes.isNotEmpty) {
      items.addAll(
        state.filteredLocatedNotes.map(
          (note) => NoteTile(
            note: note,
            onTap: () => widget.onNavigateToLine(note.lineNumber!),
            onSave: (result) => _saveInline(context, note, result),
            onDelete: () => _confirmDelete(context, note),
            onLinkTap: (url) => _handleNoteLinkTap(context, url),
            defaultExpanded: defaultExpanded,
            bookId: widget.bookId,
            linkableNotes: [
              ...state.locatedNotes,
              ...state.missingNotes,
            ],
            extraAction: IconButton(
              tooltip: 'שנה שיוך לשורה נבחרת',
              icon: const Icon(FluentIcons.pin_24_regular, size: 18),
              iconSize: 18,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              onPressed: () => _reanchorNote(context, note, selectedLineNumber),
            ),
          ),
        ),
      );
    }

    // הערות חסרות מיקום
    if (state.filteredMissingNotes.isNotEmpty) {
      if (state.filteredLocatedNotes.isNotEmpty) {
        items.add(
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
        );
      }
      items.addAll(
        state.filteredMissingNotes.map(
          (note) => NoteTile(
            note: note,
            onTap: () => _reposition(context, note),
            onSave: (result) => _saveInline(context, note, result),
            onDelete: () => _confirmDelete(context, note),
            onLinkTap: (url) => _handleNoteLinkTap(context, url),
            defaultExpanded: defaultExpanded,
            bookId: widget.bookId,
            linkableNotes: [
              ...state.locatedNotes,
              ...state.missingNotes,
            ],
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceTint
                .withValues(alpha: 0.05),
            subtitle: note.lastKnownLineNumber != null
                ? Text(
                    'שורה קודמת: ${note.lastKnownLineNumber}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  )
                : null,
            extraAction: IconButton(
              tooltip: 'מיקום מחדש',
              icon: const Icon(FluentIcons.location_24_regular, size: 18),
              iconSize: 18,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              onPressed: () => _reposition(context, note),
            ),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      final message =
          state.showOnlyVisible && state.visibleLineIndices.isNotEmpty
              ? 'אין הערות לטקסט הנראה במסך'
              : (state.searchQuery.isNotEmpty
                  ? 'לא נמצאו הערות התואמות לחיפוש'
                  : 'אין עדיין הערות על ספר זה');
      items.add(
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
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
        ),
      );
    }

    if (state.isLoading) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: items,
    );
  }

  Widget _buildNewNoteEditor(BuildContext context, PersonalNotesState state) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.note_add_24_regular,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'הערה חדשה - שורה ${state.newNoteLineNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'ביטול',
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: _cancelNewNote,
                iconSize: 20,
              ),
            ],
          ),
          const SizedBox(height: 8),
          InlineNoteEditor(
            referenceText: state.newNoteReferenceText,
            bookId: widget.bookId,
            linkableNotes: [
              ...state.locatedNotes,
              ...state.missingNotes,
            ],
            onSave: _saveNewNote,
            onCancel: _cancelNewNote,
          ),
        ],
      ),
    );
  }

  void _saveInline(
    BuildContext context,
    PersonalNote note,
    PersonalNoteEditorResult result,
  ) {
    if (!mounted) return;
    if (result.contentPlain.trim().isEmpty) return;
    context.read<PersonalNotesBloc>().add(
          UpdatePersonalNote(
            bookId: widget.bookId,
            noteId: note.id,
            content: result.content,
            contentPlain: result.contentPlain,
            contentFormat: result.contentFormat,
          ),
        );
  }

  Future<void> _handleNoteLinkTap(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme != 'otzaria') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('קישור חיצוני: $url')),
      );
      return;
    }

    switch (uri.host) {
      case 'book':
        final bookId = uri.queryParameters['bookId'] ?? '';
        final line = int.tryParse(uri.queryParameters['line'] ?? '');
        if (line == null) return;
        if (bookId.isEmpty || bookId == widget.bookId) {
          widget.onNavigateToLine(line);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('קישור לספר אחר: $bookId')),
        );
        return;
      case 'note':
        final noteId = uri.queryParameters['id'];
        if (noteId == null) return;
        final state = context.read<PersonalNotesBloc>().state;
        final allNotes = [...state.locatedNotes, ...state.missingNotes];
        PersonalNote? note;
        for (final candidate in allNotes) {
          if (candidate.id == noteId) {
            note = candidate;
            break;
          }
        }
        if (note == null) return;
        if (note.lineNumber != null) {
          widget.onNavigateToLine(note.lineNumber!);
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('הערה מקושרת'),
            content: PersonalNoteContentView(note: note!),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('סגור'),
              ),
            ],
          ),
        );
        return;
      default:
        return;
    }
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

  void _reanchorToSelectedLineWith(
    PersonalNotesBloc bloc,
    ScaffoldMessengerState messenger,
    PersonalNote note,
    int selectedLineNumber,
  ) {
    bloc.add(
      RepositionPersonalNote(
        bookId: widget.bookId,
        noteId: note.id,
        lineNumber: selectedLineNumber,
      ),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('ההערה שויכה לשורה $selectedLineNumber')),
    );
  }

  Future<void> _reanchorNote(
    BuildContext context,
    PersonalNote note,
    int? selectedLineNumber,
  ) async {
    final bloc = context.read<PersonalNotesBloc>();
    final messenger = ScaffoldMessenger.of(context);
    if (selectedLineNumber != null) {
      final choice = await showSelectionDialog<String>(
        context: context,
        title: 'שינוי שיוך הערה',
        items: [
          SelectionItem(
            label: 'שייך לשורה נבחרת ($selectedLineNumber)',
            value: 'selected',
          ),
          const SelectionItem(
            label: 'הקלד מספר שורה',
            value: 'manual',
          ),
        ],
      );
      if (!mounted) return;
      if (choice == 'selected') {
        _reanchorToSelectedLineWith(
          bloc,
          messenger,
          note,
          selectedLineNumber,
        );
        return;
      }
      if (choice == null) return;
    }

    if (!context.mounted) return;
    final result = await showInputDialog(
      context: context,
      title: 'שנה שיוך הערה',
      subtitle: note.lineNumber != null
          ? 'מיקום נוכחי: שורה ${note.lineNumber}'
          : null,
      labelText: 'שורה חדשה',
      hintText: 'הקלד מספר שורה',
      initialValue: note.lineNumber?.toString() ?? '',
      keyboardType: TextInputType.number,
    );
    if (!mounted) return;

    final newLine = result != null ? int.tryParse(result) : null;
    if (newLine != null) {
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
