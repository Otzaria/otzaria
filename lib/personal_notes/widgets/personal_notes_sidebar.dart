import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

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

  // פונקציה סטטית לגישה ל-state מבחוץ
  static PersonalNotesSidebarState? of(BuildContext context) {
    return context.findAncestorStateOfType<PersonalNotesSidebarState>();
  }
}

class PersonalNotesSidebarState extends State<PersonalNotesSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showOnlyVisible = true; // ברירת מחדל: הצג רק הערות לטקסט הנראה

  // קונטרולרים לעורך הערה חדשה
  PersonalNoteEditorController? _newNoteController;
  final FocusNode _newNoteFocusNode = FocusNode();
  final ScrollController _newNoteScrollController = ScrollController();

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
      _cancelNewNote(); // ביטול יצירת הערה אם עוברים לספר אחר
      context.read<PersonalNotesBloc>().add(LoadPersonalNotes(widget.bookId));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newNoteFocusNode.dispose();
    _newNoteScrollController.dispose();
    super.dispose();
  }

  Future<void> _cancelNewNote({bool confirmIfDirty = true}) async {
    if (!mounted) return;

    if (confirmIfDirty && _newNoteController != null) {
      final result = _newNoteController!.buildResult();
      if (result.contentPlain.trim().isNotEmpty) {
        final shouldDiscard = await showConfirmationDialog(
          context: context,
          title: 'לבטל הערה?',
          content: 'יש הערה שלא נשמרה. האם לבטל ולמחוק את הטיוטה?',
          confirmText: 'מחק טיוטה',
          isDangerous: true,
        );
        if (!mounted) return;
        if (shouldDiscard != true) {
          return;
        }
      }
    }

    setState(() {
      _newNoteController = null;
    });
    context.read<PersonalNotesBloc>().add(const CancelCreatingPersonalNote());
  }

  void _saveNewNote() {
    if (_newNoteController == null) return;

    final bloc = context.read<PersonalNotesBloc>();
    final lineNumber = bloc.state.newNoteLineNumber;
    final selectedText = bloc.state.newNoteSelectedText;

    if (lineNumber == null) return;

    final result = _newNoteController!.buildResult();
    final trimmed = result.contentPlain.trim();

    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ההערה ריקה, לא נשמרה')),
      );
      return;
    }

    bloc.add(AddPersonalNote(
      bookId: widget.bookId,
      lineNumber: lineNumber,
      content: result.content,
      contentPlain: result.contentPlain,
      contentFormat: result.contentFormat,
      selectedText: selectedText?.trim(),
    ));

    _cancelNewNote(confirmIfDirty: false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ההערה נשמרה בהצלחה')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PersonalNotesBloc, PersonalNotesState>(
      buildWhen: (previous, current) {
        // תמיד rebuild אם משהו השתנה ביצירת הערה חדשה
        if (previous.isCreatingNewNote != current.isCreatingNewNote) {
    return true;
        }
        // rebuild אם זה הספר הנכון
        final shouldBuild = current.bookId == widget.bookId;
        return shouldBuild;
      },
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, state, visibleIndices),
                const Divider(height: 1),
                Expanded(
                  child: _buildContent(
                    context,
                    state,
                    visibleIndices,
                    selectedLineNumber: textBookState is TextBookLoaded
                        ? (textBookState.selectedIndex != null
                            ? textBookState.selectedIndex! + 1
                            : null)
                        : null,
                  ),
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

  Widget _buildContent(
    BuildContext context,
    PersonalNotesState state,
    List<int> visibleIndices, {
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
            return note.contentPlain.toLowerCase().contains(query) ||
                note.lineNumber.toString().contains(query);
          }).toList();

    // הערות חסרות מיקום - מוצגות רק אם לא מסננים לפי טקסט נראה
    final filteredMissingNotes = _showOnlyVisible
        ? <PersonalNote>[]
        : (_searchQuery.isEmpty
            ? state.missingNotes
            : state.missingNotes.where((note) {
                final query = _searchQuery.toLowerCase();
                return note.contentPlain.toLowerCase().contains(query) ||
                    (note.lastKnownLineNumber?.toString().contains(query) ??
                        false);
              }).toList());

    final defaultExpanded = !(Settings.getValue<bool>(
            SettingsRepository.keyPersonalNotesCollapsedByDefault) ??
        true);

    // בנה קונטרולר אם צריך
    if (state.isCreatingNewNote && _newNoteController == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _newNoteController = buildPersonalNoteEditorController(
            initialContent: state.newNoteInitialContent ?? '',
            initialFormat:
                state.newNoteInitialFormat ?? PersonalNoteContentFormat.plain,
          );
        });
        _newNoteFocusNode.requestFocus();
      });
    }

    final items = <Widget>[];

    // עורך הערה חדשה
    if (state.isCreatingNewNote && _newNoteController != null) {
      items.add(
        Container(
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
              PersonalNoteEditorBody(
                controller: _newNoteController!,
                focusNode: _newNoteFocusNode,
                scrollController: _newNoteScrollController,
                autofocus: true,
                referenceText: state.newNoteReferenceText,
                bookId: widget.bookId,
                linkableNotes: [
                  ...state.locatedNotes,
                  ...state.missingNotes,
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _cancelNewNote,
                    child: const Text('ביטול'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saveNewNote,
                    child: const Text('שמור'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (filteredLocatedNotes.isNotEmpty) {
      items.addAll(
        filteredLocatedNotes.map(
          (note) => _LocatedNoteTile(
            note: note,
              onTap: () => widget.onNavigateToLine(note.lineNumber!),
              onInlineSave: (result) => _saveInline(context, note, result),
              onDelete: () => _confirmDelete(context, note),
              onLinkTap: (url) => _handleNoteLinkTap(context, url),
              onReanchor: () => _reanchorNote(
                    context,
                    note,
                    selectedLineNumber,
                  ),
              searchQuery: _searchQuery,
              defaultExpanded: defaultExpanded,
              bookId: widget.bookId,
              linkableNotes: [
              ...state.locatedNotes,
              ...state.missingNotes,
            ],
          ),
        ),
      );
    }

    if (filteredMissingNotes.isNotEmpty) {
      if (filteredLocatedNotes.isNotEmpty) {
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
        filteredMissingNotes.map(
          (note) => _MissingNoteTile(
            note: note,
            onReposition: () => _reposition(context, note),
            onInlineSave: (result) => _saveInline(context, note, result),
            onDelete: () => _confirmDelete(context, note),
            onLinkTap: (url) => _handleNoteLinkTap(context, url),
            searchQuery: _searchQuery,
            defaultExpanded: defaultExpanded,
            bookId: widget.bookId,
            linkableNotes: [
              ...state.locatedNotes,
              ...state.missingNotes,
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      final message = _showOnlyVisible && visibleIndices.isNotEmpty
          ? 'אין הערות לטקסט הנראה במסך'
          : (_searchQuery.isNotEmpty
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
      subtitle:
          note.lineNumber != null ? 'מיקום נוכחי: שורה ${note.lineNumber}' : null,
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

class _LocatedNoteTile extends StatefulWidget {
  final PersonalNote note;
  final VoidCallback onTap;
  final ValueChanged<PersonalNoteEditorResult> onInlineSave;
  final VoidCallback? onReanchor;
  final VoidCallback onDelete;
  final ValueChanged<String> onLinkTap;
  final String searchQuery;
  final bool defaultExpanded;
  final String bookId;
  final List<PersonalNote> linkableNotes;

  const _LocatedNoteTile({
    required this.note,
    required this.onTap,
    required this.onInlineSave,
    this.onReanchor,
    required this.onDelete,
    required this.onLinkTap,
    this.searchQuery = '',
    required this.defaultExpanded,
    required this.bookId,
    required this.linkableNotes,
  });

  @override
  State<_LocatedNoteTile> createState() => _LocatedNoteTileState();
}

class _LocatedNoteTileState extends State<_LocatedNoteTile> {
  late bool _isExpanded;
  bool _isInlineEditing = false;
  PersonalNoteEditorController? _inlineController;
  final FocusNode _inlineFocusNode = FocusNode();
  final ScrollController _inlineScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.defaultExpanded;
  }

  @override
  void dispose() {
    _inlineFocusNode.dispose();
    _inlineScrollController.dispose();
    super.dispose();
  }

  void _startInlineEdit() {
    setState(() {
      _isExpanded = true;
      _isInlineEditing = true;
      _inlineController = buildPersonalNoteEditorController(
        initialContent: widget.note.content,
        initialFormat: widget.note.contentFormat,
      );
    });
  }

  void _cancelInlineEdit() {
    setState(() {
      _isInlineEditing = false;
      _inlineController = null;
    });
  }

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
                  onEdit: _startInlineEdit,
                  onDelete: widget.onDelete,
                  isExpanded: _isExpanded,
                  onToggleExpansion: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  extraAction: widget.onReanchor == null
                      ? null
                      : IconButton(
                          tooltip: 'שנה שיוך לשורה נבחרת',
                          icon:
                              const Icon(FluentIcons.pin_24_regular, size: 18),
                          iconSize: 18,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: widget.onReanchor,
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
                  onTap: widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
                    color: Theme.of(context).colorScheme.surface,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _isInlineEditing && _inlineController != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PersonalNoteEditorBody(
                                  controller: _inlineController!,
                                  focusNode: _inlineFocusNode,
                                  scrollController: _inlineScrollController,
                                  autofocus: true,
                                  referenceText: widget.note.displayTitle,
                                  bookId: widget.bookId,
                                  linkableNotes: widget.linkableNotes,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _cancelInlineEdit,
                                      child: const Text('ביטול'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: () {
                                        final result =
                                            _inlineController!.buildResult();
                                        widget.onInlineSave(result);
                                        _cancelInlineEdit();
                                      },
                                      child: const Text('שמור'),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : PersonalNoteContentView(
                              note: widget.note,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    height: 1.5,
                                  ),
                              onLinkTap: widget.onLinkTap,
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
  final ValueChanged<PersonalNoteEditorResult> onInlineSave;
  final VoidCallback onDelete;
  final ValueChanged<String> onLinkTap;
  final String searchQuery;
  final bool defaultExpanded;
  final String bookId;
  final List<PersonalNote> linkableNotes;

  const _MissingNoteTile({
    required this.note,
    required this.onReposition,
    required this.onInlineSave,
    required this.onDelete,
    required this.onLinkTap,
    this.searchQuery = '',
    required this.defaultExpanded,
    required this.bookId,
    required this.linkableNotes,
  });

  @override
  State<_MissingNoteTile> createState() => _MissingNoteTileState();
}

class _MissingNoteTileState extends State<_MissingNoteTile> {
  late bool _isExpanded;
  bool _isInlineEditing = false;
  PersonalNoteEditorController? _inlineController;
  final FocusNode _inlineFocusNode = FocusNode();
  final ScrollController _inlineScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.defaultExpanded;
  }

  @override
  void dispose() {
    _inlineFocusNode.dispose();
    _inlineScrollController.dispose();
    super.dispose();
  }

  void _startInlineEdit() {
    setState(() {
      _isExpanded = true;
      _isInlineEditing = true;
      _inlineController = buildPersonalNoteEditorController(
        initialContent: widget.note.content,
        initialFormat: widget.note.contentFormat,
      );
    });
  }

  void _cancelInlineEdit() {
    setState(() {
      _isInlineEditing = false;
      _inlineController = null;
    });
  }

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
                  onEdit: _startInlineEdit,
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
                          child: _isInlineEditing && _inlineController != null
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    PersonalNoteEditorBody(
                                      controller: _inlineController!,
                                      focusNode: _inlineFocusNode,
                                      scrollController: _inlineScrollController,
                                      autofocus: true,
                                      referenceText: widget.note.displayTitle,
                                      bookId: widget.bookId,
                                      linkableNotes: widget.linkableNotes,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: _cancelInlineEdit,
                                          child: const Text('ביטול'),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton(
                                          onPressed: () {
                                            final result = _inlineController!
                                                .buildResult();
                                            widget.onInlineSave(result);
                                            _cancelInlineEdit();
                                          },
                                          child: const Text('שמור'),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              : PersonalNoteContentView(
                                  note: widget.note,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        height: 1.5,
                                      ),
                                  onLinkTap: widget.onLinkTap,
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
