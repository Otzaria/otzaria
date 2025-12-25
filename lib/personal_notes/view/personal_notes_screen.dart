import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/widgets/confirmation_dialog.dart';
import 'package:otzaria/widgets/input_dialog.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

class PersonalNotesManagerScreen extends StatefulWidget {
  const PersonalNotesManagerScreen({super.key});

  @override
  State<PersonalNotesManagerScreen> createState() =>
      _PersonalNotesManagerScreenState();
}

class _PersonalNotesManagerScreenState
    extends State<PersonalNotesManagerScreen> {
  final PersonalNotesRepository _repository = PersonalNotesRepository();

  List<BookNotesInfo> _books = [];
  String? _selectedFilter; // null = all notes
  bool _isLoadingBooks = true;
  String? _booksError;
  final Map<String, PersonalNotesState> _bookStates = {};
  final Map<String, bool> _expansionState = {};
  bool _isNavigationVisible = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  double _navigationWidth = 250.0;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    setState(() {
      _isLoadingBooks = true;
      _booksError = null;
    });

    try {
      final books = await _repository.listBooksWithNotes();
      if (!mounted) return;
      setState(() {
        _books = books;
        _isLoadingBooks = false;
      });
      // Load all books
      for (final book in books) {
        context.read<PersonalNotesBloc>().add(LoadPersonalNotes(book.bookId));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booksError = e.toString();
        _isLoadingBooks = false;
      });
    }
  }

  void _onFilterChanged(String? filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingBooks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_booksError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'אירעה שגיאה בעת טעינת רשימת ההערות:\n${_booksError!}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadBooks,
              child: const Text('נסה שוב'),
            ),
          ],
        ),
      );
    }

    if (_books.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('לא נמצאו הערות אישיות'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadBooks,
              child: const Text('רענון'),
            ),
          ],
        ),
      );
    }

    return BlocListener<PersonalNotesBloc, PersonalNotesState>(
      listener: (context, state) {
        // Store the state for each book and trigger rebuild
        if (state.bookId != null) {
          setState(() {
            _bookStates[state.bookId!] = state;
          });

          // If this is a new book (not in _books list), refresh the books list
          final bookExists = _books.any((book) => book.bookId == state.bookId);
          if (!bookExists &&
              (state.locatedNotes.isNotEmpty ||
                  state.missingNotes.isNotEmpty)) {
            _loadBooks();
          }
        }
      },
      child: Column(
        children: [
          // שורת כלים עליונה לכל רוחב העמוד
          _buildTopBar(),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)),
          // תוכן העמוד
          Expanded(
            child: Row(
              children: [
                // Right sidebar navigation - גובה מלא
                if (_isNavigationVisible) ...[
                  SizedBox(
                    width: _navigationWidth,
                    child: _buildNotesTree(),
                  ),
                  // Resizable divider
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _navigationWidth =
                              (_navigationWidth - details.delta.dx)
                                  .clamp(150.0, 500.0);
                        });
                      },
                      child: Container(
                        width: 8,
                        color: Colors.transparent,
                        child: Center(
                          child: VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // Main content area
                Expanded(
                  child: _buildAllNotesList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          // לחצן סגירה/פתיחה של חלונית הניווט
          IconButton(
            tooltip: _isNavigationVisible ? 'הסתר ניווט' : 'הצג ניווט',
            onPressed: () {
              setState(() {
                _isNavigationVisible = !_isNavigationVisible;
              });
            },
            icon: const Icon(Icons.menu),
          ),
          const SizedBox(width: 8),
          // חלונית חיפוש באמצע
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
          // לחצן ריענון
          IconButton(
            tooltip: 'רענן',
            onPressed: _loadBooks,
            icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesTree() {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) {
        if (libraryState.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (libraryState.error != null) {
          return Center(child: Text('Error: ${libraryState.error}'));
        }

        if (libraryState.library == null) {
          return const Center(child: Text('No library data available'));
        }

        final rootCategory = libraryState.library!;
        final totalNotesCount =
            _getNotesCountForCategory(rootCategory) + _getMissingNotesCount();
        final isRootExpanded = _expansionState['/personal_notes_root'] ?? true;
        final isRootSelected = _selectedFilter == null;

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Column(
              children: [
                // Root "הערות אישיות" folder
                InkWell(
                  onTap: () => _onFilterChanged(null),
                  child: Container(
                    padding: const EdgeInsets.only(
                      right: 16.0,
                      left: 16.0,
                      top: 12.0,
                      bottom: 12.0,
                    ),
                    decoration: BoxDecoration(
                      color: isRootSelected
                          ? Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.3)
                          : null,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isRootExpanded
                              ? FluentIcons.folder_open_24_regular
                              : FluentIcons.folder_24_regular,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'הערות אישיות',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        if (totalNotesCount > 0)
                          Text(
                            '($totalNotesCount)',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _expansionState['/personal_notes_root'] =
                                  !isRootExpanded;
                            });
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              isRootExpanded
                                  ? FluentIcons.chevron_up_24_regular
                                  : FluentIcons.chevron_down_24_regular,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isRootExpanded) ...[
                  ..._buildCategoryChildren(rootCategory, 0),
                  _buildMissingNotesTile(),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  int _getMissingNotesCount() {
    int count = 0;
    for (final state in _bookStates.values) {
      count += state.missingNotes.length;
    }
    return count;
  }

  int _getNotesCountForBook(String bookTitle) {
    final state = _bookStates[bookTitle];
    if (state != null) {
      return state.locatedNotes.length + state.missingNotes.length;
    }
    return 0;
  }

  int _getNotesCountForCategory(Category category) {
    int count = 0;

    // Deduplicate books by title to avoid counting notes twice
    // when the same book exists in both PDF and text formats
    final seenTitles = <String>{};
    for (final book in category.books) {
      if (!seenTitles.contains(book.title)) {
        count += _getNotesCountForBook(book.title);
        seenTitles.add(book.title);
      }
    }

    for (final subCat in category.subCategories) {
      count += _getNotesCountForCategory(subCat);
    }
    return count;
  }

  Widget _buildMissingNotesTile() {
    final count = _getMissingNotesCount();
    if (count == 0) return const SizedBox.shrink();

    final isSelected = _selectedFilter == '__missing__';

    return InkWell(
      onTap: () => _onFilterChanged('__missing__'),
      child: Container(
        padding: const EdgeInsets.only(
          right: 16.0 + 24.0,
          left: 16.0,
          top: 12.0,
          bottom: 12.0,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.warning_24_regular,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'הערות ללא מיקום',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            if (count > 0)
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(Category category, int count, int level) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    final isExpanded = _expansionState[category.path] ?? level <= 1;
    final isSelected = _selectedFilter == category.path;

    return Column(
      children: [
        InkWell(
          onTap: () => _onFilterChanged(category.path),
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (level * 24.0),
              left: 16.0,
              top: 12.0,
              bottom: 12.0,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? FluentIcons.folder_open_24_regular
                      : FluentIcons.folder_24_regular,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (count > 0)
                  Text(
                    '($count)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 8),
                if (category.subCategories.isNotEmpty ||
                    category.books.isNotEmpty)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expansionState[category.path] = !isExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        isExpanded
                            ? FluentIcons.chevron_up_24_regular
                            : FluentIcons.chevron_down_24_regular,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded && category.path != '/__missing__')
          ..._buildCategoryChildren(category, level),
      ],
    );
  }

  List<Widget> _buildCategoryChildren(Category category, int level) {
    final List<Widget> children = [];

    for (final subCategory in category.subCategories) {
      final count = _getNotesCountForCategory(subCategory);
      if (count > 0) {
        children.add(_buildCategoryTile(subCategory, count, level + 1));
      }
    }

    // Deduplicate books by title - keep only first occurrence
    // This handles cases where the same book exists in both PDF and text formats
    final seenTitles = <String>{};
    for (final book in category.books) {
      // Skip if we already added a book with this title
      if (seenTitles.contains(book.title)) {
        continue;
      }

      final count = _getNotesCountForBook(book.title);
      if (count > 0) {
        children.add(_buildBookTile(book, count, level + 1));
        seenTitles.add(book.title);
      }
    }

    return children;
  }

  Widget _buildBookTile(Book book, int count, int level) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    final isSelected = _selectedFilter == book.title;

    return InkWell(
      onTap: () => _onFilterChanged(book.title),
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 24.0) + 32.0,
          left: 16.0,
          top: 10.0,
          bottom: 10.0,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.book_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                book.title,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (count > 0)
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _getBooksInCategory(Category category) {
    final List<String> bookTitles = [];

    void collectBooks(Category cat) {
      for (final book in cat.books) {
        bookTitles.add(book.title);
      }
      for (final subCat in cat.subCategories) {
        collectBooks(subCat);
      }
    }

    collectBooks(category);
    return bookTitles;
  }

  Widget _buildAllNotesList() {
    final allNotes = <_NoteWithBook>[];

    // Collect all notes from all books
    for (final book in _books) {
      final state = _bookStates[book.bookId];
      if (state != null) {
        for (final note in state.locatedNotes) {
          allNotes.add(_NoteWithBook(note: note, bookId: book.bookId));
        }
        if (_selectedFilter == '__missing__' || _selectedFilter == null) {
          for (final note in state.missingNotes) {
            allNotes.add(_NoteWithBook(
                note: note, bookId: book.bookId, isMissing: true));
          }
        }
      }
    }

    // סינון לפי חיפוש
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      allNotes.removeWhere((noteWithBook) {
        final note = noteWithBook.note;
        return !note.content.toLowerCase().contains(query) &&
            !note.bookId.toLowerCase().contains(query) &&
            !(note.lineNumber?.toString().contains(query) ?? false);
      });
    }

    // Filter by selected filter
    List<_NoteWithBook> filteredNotes;

    if (_selectedFilter == null) {
      // Show all notes
      filteredNotes = allNotes;
    } else if (_selectedFilter == '__missing__') {
      // Show only missing notes
      filteredNotes = allNotes.where((n) => n.isMissing).toList();
    } else if (_selectedFilter!.startsWith('/')) {
      // Category selected - find all books in this category
      final libraryState = context.read<LibraryBloc>().state;
      if (libraryState.library != null) {
        Category? findCategory(Category cat, String path) {
          if (cat.path == path) return cat;
          for (final subCat in cat.subCategories) {
            final found = findCategory(subCat, path);
            if (found != null) return found;
          }
          return null;
        }

        final category = findCategory(libraryState.library!, _selectedFilter!);
        if (category != null) {
          final booksInCategory = _getBooksInCategory(category);
          filteredNotes = allNotes
              .where((n) => booksInCategory.contains(n.bookId))
              .toList();
        } else {
          filteredNotes = [];
        }
      } else {
        filteredNotes = [];
      }
    } else {
      // Book selected
      filteredNotes =
          allNotes.where((n) => n.bookId == _selectedFilter).toList();
    }

    // Filter missing notes if not showing missing filter
    final displayNotes =
        _selectedFilter == '__missing__' ? filteredNotes : filteredNotes;

    // Sort by book and line number
    displayNotes.sort((a, b) {
      final bookCompare = a.bookId.compareTo(b.bookId);
      if (bookCompare != 0) return bookCompare;
      return (a.note.lineNumber ?? 0).compareTo(b.note.lineNumber ?? 0);
    });

    if (displayNotes.isEmpty) {
      return const Center(
        child: Text('אין הערות להצגה'),
      );
    }

    // Group notes by book for headers - always show book names
    final groupedNotes = <_NotesGroup>[];
    String? currentBookId;
    List<_NoteWithBook> currentGroup = [];

    for (final note in displayNotes) {
      if (note.bookId != currentBookId) {
        if (currentGroup.isNotEmpty) {
          groupedNotes
              .add(_NotesGroup(bookId: currentBookId!, notes: currentGroup));
        }
        currentBookId = note.bookId;
        currentGroup = [note];
      } else {
        currentGroup.add(note);
      }
    }
    if (currentGroup.isNotEmpty) {
      groupedNotes
          .add(_NotesGroup(bookId: currentBookId!, notes: currentGroup));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: groupedNotes.length,
      itemBuilder: (context, groupIndex) {
        final group = groupedNotes[groupIndex];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (group.bookId != 'all')
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 16),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.text_align_right_24_regular,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        group.bookId,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                // Calculate how many cards can fit based on available width
                // Each card needs minimum 400px, plus 12px spacing between cards
                const minCardWidth = 400.0;
                const spacing = 12.0;
                final availableWidth = constraints.maxWidth;

                // Calculate maximum number of cards that can fit
                // Formula: (width + spacing) / (cardWidth + spacing)
                int crossAxisCount =
                    ((availableWidth + spacing) / (minCardWidth + spacing))
                        .floor();

                // Ensure at least 1 card per row
                if (crossAxisCount < 1) crossAxisCount = 1;

                // Calculate actual card width based on available space
                final actualCardWidth =
                    (availableWidth - (spacing * (crossAxisCount - 1))) /
                        crossAxisCount;

                // Adjust aspect ratio based on actual card width
                // Target height is around 150px (lower = more rectangular), so aspectRatio = width / 150
                final aspectRatio = actualCardWidth / 150.0;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: aspectRatio,
                  ),
                  itemCount: group.notes.length,
                  itemBuilder: (context, noteIndex) {
                    final item = group.notes[noteIndex];
                    return _buildNoteCard(item.note, item.isMissing);
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoteCard(PersonalNote note, bool isMissing) {
    return GestureDetector(
      onTap: isMissing ? () => _repositionMissing(note) : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ],
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        isMissing ? 'הערה ללא מיקום' : note.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'עריכה',
                          icon:
                              const Icon(FluentIcons.edit_24_regular, size: 18),
                          onPressed: () => _editNote(note),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                        if (isMissing) ...[
                          IconButton(
                            tooltip: 'מיקום מחדש',
                            icon: const Icon(FluentIcons.location_24_regular,
                                size: 18),
                            onPressed: () => _repositionMissing(note),
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ],
                        IconButton(
                          tooltip: 'מחיקה',
                          icon: const Icon(FluentIcons.delete_24_regular,
                              size: 18),
                          onPressed: () => _deleteNote(note),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    note.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black87,
                        ),
                  ),
                ),
                if (isMissing && note.lastKnownLineNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text(
                      'שורה קודמת: ${note.lastKnownLineNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                    ),
                  ),
              ],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              child: Text(
                _formatDate(note.updatedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(PersonalNote note) async {
    final controller = TextEditingController(text: note.content);
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

    final trimmed = result.trim();
    if (trimmed.isEmpty) {
      UiSnack.show('ההערה ריקה, לא נשמרה');
      return;
    }

    if (!mounted) return;
    context.read<PersonalNotesBloc>().add(
          UpdatePersonalNote(
            bookId: note.bookId,
            noteId: note.id,
            content: trimmed,
          ),
        );
    UiSnack.show('ההערה עודכנה');
  }

  Future<void> _deleteNote(PersonalNote note) async {
    final shouldDelete = await showConfirmationDialog(
      context: context,
      title: 'מחיקת הערה',
      content: 'האם למחוק את ההערה לצמיתות?',
      confirmText: 'מחק',
      isDangerous: true,
    );

    if (shouldDelete == true) {
      if (!mounted) return;
      context.read<PersonalNotesBloc>().add(
            DeletePersonalNote(
              bookId: note.bookId,
              noteId: note.id,
            ),
          );
      UiSnack.show('ההערה נמחקה');
    }
  }

  Future<void> _repositionMissing(PersonalNote note) async {
    final result = await showInputDialog(
      context: context,
      title: 'מיקום מחדש של הערה',
      subtitle: note.lastKnownLineNumber != null
          ? 'שורה קודמת: ${note.lastKnownLineNumber}'
          : null,
      labelText: 'מספר שורה חדש',
      initialValue: (note.lastKnownLineNumber ?? '').toString(),
      keyboardType: TextInputType.number,
    );

    final newLine = result != null ? int.tryParse(result) : null;

    if (newLine != null) {
      if (!mounted) return;
      context.read<PersonalNotesBloc>().add(
            RepositionPersonalNote(
              bookId: note.bookId,
              noteId: note.id,
              lineNumber: newLine,
            ),
          );
      UiSnack.show('ההערה הועברה לשורה $newLine');
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

class _NoteWithBook {
  final PersonalNote note;
  final String bookId;
  final bool isMissing;

  _NoteWithBook({
    required this.note,
    required this.bookId,
    this.isMissing = false,
  });
}

class _NotesGroup {
  final String bookId;
  final List<_NoteWithBook> notes;

  _NotesGroup({
    required this.bookId,
    required this.notes,
  });
}
