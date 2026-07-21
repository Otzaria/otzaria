import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_notes_import_export_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_export_dialog.dart';
import 'package:otzaria/personal_notes/utils/note_location_ref.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

class PersonalNotesManagerScreen extends StatefulWidget {
  const PersonalNotesManagerScreen({
    super.key,
    this.repository,
    this.importExportService,
  });

  final PersonalNotesRepository? repository;
  final PersonalNotesImportExportService? importExportService;

  @override
  State<PersonalNotesManagerScreen> createState() =>
      _PersonalNotesManagerScreenState();
}

class _PersonalNotesManagerScreenState
    extends State<PersonalNotesManagerScreen> {
  late final PersonalNotesRepository _repository;
  late final PersonalNotesImportExportService _importExportService;

  List<BookNotesInfo> _books = [];
  String? _selectedFilter; // null = all notes
  bool _isLoadingBooks = true;
  String? _booksError;
  final Map<String, PersonalNotesState> _bookStates = {};
  final Map<String, bool> _expansionState = {};
  // קאש ל-TOC לכל ספר, לחישוב כתובת המיקום של ההערות. נטען עצלן פעם אחת.
  final Map<String, Future<List<TocEntry>?>> _tocFutureByBook = {};
  bool _isNavigationVisible = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _windowFocusNode = FocusNode(skipTraversal: true);
  final ScrollController _contentScrollController = ScrollController();
  String _searchQuery = '';
  double _navigationWidth = 250.0;
  // טווח תאריכים לסינון לפי תאריך עדכון ההערה. null = ללא סינון תאריכים.
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PersonalNotesRepository();
    _importExportService =
        widget.importExportService ?? PersonalNotesImportExportService();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    // בריענון - לא מציגים ספינר אם כבר יש ספרים
    // בטעינה ראשונה - נשאר במצב טעינה
    final isRefresh = _books.isNotEmpty;

    if (!isRefresh) {
      setState(() {
        _isLoadingBooks = true;
        _booksError = null;
      });
    } else if (_booksError != null) {
      setState(() {
        _booksError = null;
      });
    }

    try {
      final books = await _repository.listBooksWithNotes();
      if (!mounted) return;
      setState(() {
        _books = books;
        _isLoadingBooks = false;
        _booksError = null;
      });
      _scheduleNotesLoad(books);
    } catch (e) {
      if (!mounted) return;
      if (_books.isEmpty) {
        setState(() {
          _booksError = e.toString();
          _isLoadingBooks = false;
        });
      } else {
        UiSnack.showError(NotesMessages.notesListLoadError(e));
      }
    }
  }

  void _scheduleNotesLoad(List<BookNotesInfo> books) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bloc = context.read<PersonalNotesBloc>();
      for (final book in books) {
        bloc.add(LoadPersonalNotes(book.bookId));
      }
    });
  }

  void _onFilterChanged(String? filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  /// פתיחת בורר טווח תאריכים לסינון ההערות לפי תאריך עדכון.
  ///
  /// משתמש בשני דיאלוגי [showDatePicker] קומפקטיים ברצף (תחילה תאריך התחלה ואז
  /// תאריך סיום) במקום [showDateRangePicker] מסך-מלא — כך מקבלים דיאלוג קטן רגיל
  /// עם ניווט נוח בין חודשים ושנים.
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(2000);

    final start = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: today,
      initialDate: _dateRange?.start ?? today,
      helpText: 'בחר תאריך התחלה',
      cancelText: 'ביטול',
      confirmText: 'הבא',
    );
    if (!mounted || start == null) return;

    final previousEnd = _dateRange?.end;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: today,
      initialDate: (previousEnd != null && !previousEnd.isBefore(start))
          ? previousEnd
          : today,
      helpText: 'בחר תאריך סיום',
      cancelText: 'ביטול',
      confirmText: 'סנן',
    );
    if (!mounted || end == null) return;

    setState(() {
      _dateRange = DateTimeRange(start: start, end: end);
    });
  }

  void _clearDateRange() {
    setState(() {
      _dateRange = null;
    });
  }

  /// פורמט תאריך לועזי קצר להצגה בבאנר הסינון.
  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  void requestKeyboardFocus() {
    if (!mounted || !_windowFocusNode.canRequestFocus) return;
    if (!_windowFocusNode.hasFocus) _windowFocusNode.requestFocus();
  }

  void _focusSearchField() {
    if (!mounted || !_searchFocusNode.canRequestFocus) return;
    if (!_searchFocusNode.hasFocus) _searchFocusNode.requestFocus();
  }

  KeyEventResult _handleWindowKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (FocusManager.instance.primaryFocus != _windowFocusNode) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _scrollContent(forward: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _scrollContent(forward: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollContent({required bool forward}) {
    if (!_contentScrollController.hasClients) return;
    final position = _contentScrollController.position;
    final delta = (position.viewportDimension * 0.85) * (forward ? 1 : -1);
    final target = (position.pixels + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _contentScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _windowFocusNode.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingBooks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_booksError != null && _books.isEmpty) {
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

    final searchShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-search-current-window'] ??
          ShortcutValidator
              .defaultShortcuts['key-shortcut-search-current-window'] ??
          'ctrl+f',
    );
    return CallbackShortcuts(
      bindings: {
        ShortcutHelper.activatorFromShortcut(searchShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _focusSearchField();
        },
      },
      child: Focus(
        focusNode: _windowFocusNode,
        autofocus: true,
        onKeyEvent: _handleWindowKeyEvent,
        child: BlocListener<PersonalNotesBloc, PersonalNotesState>(
          listener: (context, state) {
            // Store the state for each book and trigger rebuild
            if (state.bookId != null) {
              setState(() {
                _bookStates[state.bookId!] = state;
              });

              // If this is a new book (not in _books list), refresh the books list
              final bookExists = _books.any(
                (book) => book.bookId == state.bookId,
              );
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
              // תוכן העמוד
              Expanded(
                child: PrimaryScrollController(
                  controller: _contentScrollController,
                  child: AdaptiveSidePane(
                    isOpen: _isNavigationVisible,
                    alignment: AlignmentDirectional
                        .centerEnd, // ימין בעברית (RTL) - סרגל ניווט
                    mainContent: Column(
                      children: [
                        if (_dateRange != null) _buildDateFilterBanner(),
                        Expanded(child: _buildAllNotesList()),
                      ],
                    ),
                    paneWidth: _navigationWidth,
                    minMainContentWidth: 320,
                    onClose: () => setState(() => _isNavigationVisible = false),
                    onOpen: () => setState(() => _isNavigationVisible = true),
                    isResizable: true,
                    minPaneWidth: 150,
                    maxPaneWidth: 500,
                    onPaneWidthChanged: (nextWidth) {
                      _navigationWidth = nextWidth;
                    },
                    paneContent: _buildNotesTree(),
                    wrapPaneInFloatingPanel: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final isCompact = settingsState.compactMenuMode;
        return AppTopBar(
          leadingItems: [
            AppTopBarItem(
              widget: IconButton(
                tooltip: _isNavigationVisible ? 'הסתר ניווט' : 'הצג ניווט',
                onPressed: () {
                  setState(() {
                    _isNavigationVisible = !_isNavigationVisible;
                  });
                },
                icon: AnimatedSwitcher(
                  duration: AppTokens.animFast,
                  transitionBuilder: (child, animation) => RotationTransition(
                    turns: Tween<double>(
                      begin: 0.5,
                      end: 0.0,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    _isNavigationVisible
                        ? FluentIcons.panel_right_contract_24_regular
                        : FluentIcons.panel_right_24_regular,
                    key: ValueKey(_isNavigationVisible),
                    size: 24,
                  ),
                ),
                visualDensity: VisualDensity.standard,
                splashRadius: 22,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ],
          center: OtzariaSearchField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: 'חפש בהערות...',
            onSubmitted: (_) => requestKeyboardFocus(),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            onClear: () {
              setState(() {
                _searchQuery = '';
              });
            },
          ),
          trailingItems: [
            AppTopBarItem(
              widget: BarButton.icon(
                compact: isCompact,
                tooltip: _dateRange != null
                    ? 'סינון תאריך פעיל - לחץ לשינוי'
                    : 'סנן לפי תאריך',
                icon: _dateRange != null
                    ? FluentIcons.calendar_checkmark_24_filled
                    : FluentIcons.calendar_24_regular,
                flipInRtl: true,
                onPressed: _pickDateRange,
              ),
            ),
            AppTopBarItem(
              widget: BarButton.icon(
                compact: isCompact,
                tooltip: 'רענן',
                icon: FluentIcons.arrow_clockwise_24_regular,
                onPressed: _loadBooks,
              ),
            ),
            AppTopBarItem(
              widget: BarButton.icon(
                compact: isCompact,
                tooltip: 'גיבוי הערות',
                icon: FluentIcons.arrow_download_24_regular,
                onPressed: _exportNotes,
              ),
            ),
            AppTopBarItem(
              widget: BarButton.icon(
                compact: isCompact,
                tooltip: 'ייצוא לטקסט',
                icon: FluentIcons.document_text_24_regular,
                onPressed: _exportNotesToText,
              ),
            ),
            AppTopBarItem(
              widget: BarButton.icon(
                compact: isCompact,
                tooltip: 'ייבוא הערות',
                icon: FluentIcons.arrow_upload_24_regular,
                onPressed: _importNotes,
              ),
            ),
          ],
        );
      },
    );
  }

  /// טוען (פעם אחת, עם קאש) את ה-TOC של ספר טקסט לפי כותרתו, לחישוב המיקום.
  /// מחזיר Future ל-null כשהספר אינו ספר טקסט או שאינו בספרייה.
  Future<List<TocEntry>?> _tocFor(String bookId) {
    return _tocFutureByBook.putIfAbsent(bookId, () {
      final library = context.read<LibraryBloc>().state.library;
      final book = library?.findBookByTitle(bookId, TextBook);
      if (book is! TextBook) return Future.value(null);
      return book.tableOfContents;
    });
  }

  List<PersonalNote> _collectAllNotes() {
    final allNotes = <PersonalNote>[];
    for (final book in _books) {
      final state = _bookStates[book.bookId];
      if (state == null) continue;
      allNotes.addAll(state.locatedNotes);
      allNotes.addAll(state.missingNotes);
    }
    return allNotes;
  }

  Future<void> _exportNotes() async {
    if (!await verifySaferModePassword(context)) return;
    if (!mounted) return;
    final selection = await showDialog<NotesExportSelection>(
      context: context,
      builder: (context) => PersonalNotesExportDialog(
        allNotes: _collectAllNotes(),
        title: 'גיבוי הערות',
        confirmText: 'גבה',
      ),
    );
    if (!mounted) return;
    if (selection == null || selection.notes.isEmpty) return;

    final path = await FilePicker.saveFile(
      dialogTitle: 'בחר מיקום לשמירת קובץ הגיבוי',
      fileName: 'otzaria_notes_backup.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
      lockParentWindow: true,
    );
    if (!mounted) return;
    if (path == null) return;

    await _importExportService.exportToFile(
      path: path,
      notes: selection.notes,
      description: selection.description,
    );

    if (!mounted) return;
    UiSnack.show(NotesMessages.backupCompleted);
  }

  Future<void> _exportNotesToText() async {
    if (!await verifySaferModePassword(context)) return;
    if (!mounted) return;
    final selection = await showDialog<NotesExportSelection>(
      context: context,
      builder: (context) => PersonalNotesExportDialog(
        allNotes: _collectAllNotes(),
        title: 'ייצוא לטקסט',
        confirmText: 'ייצא',
      ),
    );
    if (!mounted) return;
    if (selection == null || selection.notes.isEmpty) return;

    final path = await FilePicker.saveFile(
      dialogTitle: 'בחר מיקום לשמירת קובץ הטקסט',
      fileName: 'otzaria_notes.txt',
      allowedExtensions: ['txt'],
      type: FileType.custom,
      lockParentWindow: true,
    );
    if (!mounted) return;
    if (path == null) return;

    await _importExportService.exportToTextFile(
      path: path,
      notes: selection.notes,
      description: selection.description,
    );

    if (!mounted) return;
    UiSnack.show(NotesMessages.textExportCompleted);
  }

  Future<void> _importNotes() async {
    if (!await verifySaferModePassword(context)) return;
    if (!mounted) return;
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'בחר קובץ ייבוא',
      allowedExtensions: ['json'],
      type: FileType.custom,
      lockParentWindow: true,
    );
    if (!mounted) return;
    if (picked == null || picked.files.isEmpty) return;

    final strategy = await showDialog<NotesImportConflictStrategy>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ייבוא הערות - טיפול בהתנגשויות'),
        content: const Text('כיצד לטפל בהערות קיימות עם אותו מזהה?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(NotesImportConflictStrategy.merge),
            child: const Text('מזג'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(NotesImportConflictStrategy.skip),
            child: const Text('דלג על כפולים'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(NotesImportConflictStrategy.keepBoth),
            child: const Text('שמור גם וגם'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(NotesImportConflictStrategy.overwrite),
            child: const Text('דרוס'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (strategy == null) return;

    final summary = await _importExportService.importFromFile(
      path: picked.files.first.path!,
      strategy: strategy,
    );

    if (!mounted) return;
    UiSnack.show(
      NotesMessages.importCompleted(
        inserted: summary.inserted,
        updated: summary.updated,
        skipped: summary.skipped,
        duplicated: summary.duplicated,
      ),
    );
    _loadBooks();
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

        // שיטוח לרשימת שורות + ListView.builder (בנייה עצלה) — ספריית ההערות
        // דינמית ועלולה להיות ארוכה; בנייה מוקדמת של כל העץ הכבידה.
        final rows = <_NotesNavRow>[_NotesNavRow.root(totalNotesCount)];
        _flattenNotes(rootCategory, 0, rows);
        rows.add(_NotesNavRow.missing());
        // כל הקטגוריות/הספרים הם כרטיס אחד רציף (מעוגל בקצוות, מפריד בין
        // כל השורות). השורש וה"הערות ללא מיקום" נשארים מחוץ לכרטיס.
        int? firstGrouped;
        int? lastGrouped;
        for (var i = 0; i < rows.length; i++) {
          final k = rows[i].kind;
          if (k == _NotesNavRowKind.root || k == _NotesNavRowKind.missing) {
            continue;
          }
          firstGrouped ??= i;
          lastGrouped = i;
        }
        if (firstGrouped != null) {
          rows[firstGrouped].isGroupStart = true;
          rows[lastGrouped!].isGroupEnd = true;
        }

        return ListView.builder(
          // שוליים אופקיים — הכרטיסים לא נוגעים בקצה, וקו הגלילה ברווח.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: rows.length,
          itemBuilder: (context, index) => _buildNotesNavRow(rows[index]),
        );
      },
    );
  }

  void _flattenNotes(Category category, int level, List<_NotesNavRow> rows) {
    for (final sub in category.subCategories) {
      final count = _getNotesCountForCategory(sub);
      if (count <= 0) continue;
      final childLevel = level + 1;
      final isExpanded = _expansionState[sub.path] ?? childLevel <= 1;
      rows.add(_NotesNavRow.category(sub, childLevel, count, isExpanded));
      if (isExpanded) _flattenNotes(sub, childLevel, rows);
    }

    // איחוד ספרים כפולים לפי כותרת (טקסט + PDF של אותו ספר).
    final seenTitles = <String>{};
    for (final book in category.books) {
      if (seenTitles.contains(book.title)) continue;
      final count = _getNotesCountForBook(book.title);
      if (count <= 0) continue;
      seenTitles.add(book.title);
      rows.add(_NotesNavRow.book(book, level + 1, count));
    }
  }

  Widget _buildNotesNavRow(_NotesNavRow row) {
    switch (row.kind) {
      case _NotesNavRowKind.root:
        // שורש "הערות אישיות" — תמיד פתוח וללא כפתור חץ (כמו בחיפוש).
        // שורש — כותרת על רקע החלונית (בלי כרטיס/קופסת-אייקון).
        return NavTreeHeader(
          title: 'הערות אישיות',
          count: row.count > 0 ? row.count : null,
          isSelected: _selectedFilter == null,
          // "נקה סינון" לצד השורש כשקיים סינון פעיל (כמו בתוצאות החיפוש).
          onClearFilter: _selectedFilter != null
              ? () => _onFilterChanged(null)
              : null,
          onTap: () => _onFilterChanged(null),
        );
      case _NotesNavRowKind.category:
        final category = row.category!;
        final isSelected = _selectedFilter == category.path;
        final isExpanded = _expansionState[category.path] ?? row.level <= 1;
        return NavTreeGroupCard(
          isGroupStart: row.isGroupStart,
          isGroupEnd: row.isGroupEnd,
          child: KeyedSubtree(
            key: ValueKey(category.path),
            child: NavTreeTile.category(
              title: category.title,
              // level-1: תיקיות עליונות מתחילות ב-0 (השורש הוא כותרת).
              level: row.level - 1,
              isSelected: isSelected,
              isExpanded: isExpanded,
              hasChildren:
                  category.subCategories.isNotEmpty ||
                  category.books.isNotEmpty,
              count: row.count > 0 ? row.count : null,
              onTap: () => _onFilterChanged(category.path),
              onToggleExpand: () {
                setState(() {
                  _expansionState[category.path] = !isExpanded;
                });
              },
            ),
          ),
        );
      case _NotesNavRowKind.book:
        return NavTreeGroupCard(
          isGroupStart: row.isGroupStart,
          isGroupEnd: row.isGroupEnd,
          child: KeyedSubtree(
            key: ObjectKey(row.book),
            child: _buildBookTile(row.book!, row.count, row.level - 1),
          ),
        );
      case _NotesNavRowKind.missing:
        return _buildMissingNotesTile();
    }
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
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3)
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

  Widget _buildBookTile(Book book, int count, int level) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    final isSelected = _selectedFilter == book.title;

    return NavTreeTile.book(
      title: book.title,
      level: level,
      isSelected: isSelected,
      count: count > 0 ? count : null,
      onTap: () => _onFilterChanged(book.title),
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
            allNotes.add(
              _NoteWithBook(note: note, bookId: book.bookId, isMissing: true),
            );
          }
        }
      }
    }

    // סינון לפי חיפוש
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      allNotes.removeWhere((noteWithBook) {
        final note = noteWithBook.note;
        return !note.contentPlain.toLowerCase().contains(query) &&
            !note.bookId.toLowerCase().contains(query) &&
            !(note.lineNumber?.toString().contains(query) ?? false);
      });
    }

    // סינון לפי טווח תאריכים (לפי תאריך עדכון ההערה, ברמת היום)
    if (_dateRange != null) {
      allNotes.removeWhere(
        (noteWithBook) => !noteWithinDateRange(noteWithBook.note, _dateRange),
      );
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
      filteredNotes = allNotes
          .where((n) => n.bookId == _selectedFilter)
          .toList();
    }

    // Filter missing notes if not showing missing filter
    final displayNotes = _selectedFilter == '__missing__'
        ? filteredNotes
        : filteredNotes;

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
          groupedNotes.add(
            _NotesGroup(bookId: currentBookId!, notes: currentGroup),
          );
        }
        currentBookId = note.bookId;
        currentGroup = [note];
      } else {
        currentGroup.add(note);
      }
    }
    if (currentGroup.isNotEmpty) {
      groupedNotes.add(
        _NotesGroup(bookId: currentBookId!, notes: currentGroup),
      );
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
            FutureBuilder<List<TocEntry>?>(
              future: _tocFor(group.bookId),
              builder: (context, tocSnapshot) {
                final toc = tocSnapshot.data;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    const minCardWidth = 280.0;
                    const maxCardsPerRow = 3;
                    const spacing = 12.0;
                    final availableWidth = constraints.maxWidth;
                    int crossAxisCount =
                        ((availableWidth + spacing) / (minCardWidth + spacing))
                            .floor();
                    crossAxisCount = crossAxisCount.clamp(1, maxCardsPerRow);

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        mainAxisExtent: 170,
                      ),
                      itemCount: group.notes.length,
                      itemBuilder: (context, noteIndex) {
                        final item = group.notes[noteIndex];
                        return _buildNoteCard(
                          item.note,
                          item.isMissing,
                          tableOfContents: toc,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// באנר המציג את טווח התאריכים הפעיל לסינון, עם אפשרות ניקוי.
  Widget _buildDateFilterBanner() {
    final cs = Theme.of(context).colorScheme;
    final range = _dateRange!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        children: [
          RtlIcon(
            FluentIcons.calendar_24_regular,
            size: 18,
            color: cs.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'מציג הערות מ-${_formatDate(range.start)} עד ${_formatDate(range.end)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'נקה סינון תאריך',
            icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
            color: cs.onSecondaryContainer,
            onPressed: _clearDateRange,
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(
    PersonalNote note,
    bool isMissing, {
    List<TocEntry>? tableOfContents,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hebrewDate = getHebrewDateFormattedAsString(note.updatedAt);
    // שם הספר כבר מוצג ככותרת הקבוצה, לכן כאן מציגים רק את הדף/העמוד.
    final locationRef = isMissing
        ? null
        : personalNoteLocationRef(
            note,
            isPdf: false,
            bookTitle: note.bookId,
            tableOfContents: tableOfContents,
            includeBookTitle: false,
          );

    return AppCard(
      onTap: isMissing ? () => _repositionMissing(note) : null,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  isMissing ? 'הערה ללא מיקום' : note.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (locationRef != null) ...[
            const SizedBox(height: 2),
            Text(
              locationRef,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          // תצוגה מקדימה מעוצבת: מרנדרים את ה-Quill Delta במקום טקסט פשוט,
          // כך שהעיצוב (מודגש/נטוי/קו תחתי/קו חוצה וכו') יופיע גם בכרטיס.
          // maxPreviewChars מקצר הערות ארוכות כדי שלא נרנדר אלפי מילים
          // בכל כרטיס (QuillEditor הלא-נגלל מחשב layout לכל הטקסט).
          // הכרטיס בגובה קבוע (mainAxisExtent: 170), לכן עוטפים ב-Expanded +
          // ClipRect + OverflowBox כדי לחתוך את העודף הוויזואלי. maxHeight
          // מוגבל כהגנה כפולה מעל הקיצור התוכני.
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: 200,
                child: IgnorePointer(
                  child: PersonalNoteContentView(
                    note: note,
                    allowSelection: false,
                    maxPreviewChars: 280,
                    textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _InfoChip(
                      icon: FluentIcons.calendar_24_regular,
                      text: hebrewDate,
                      backgroundColor: cs.secondaryContainer,
                      foregroundColor: cs.onSecondaryContainer,
                    ),
                    if (isMissing && note.lastKnownLineNumber != null)
                      _InfoChip(
                        icon: FluentIcons.location_24_regular,
                        text: 'שורה קודמת: ${note.lastKnownLineNumber}',
                        backgroundColor: cs.surfaceContainerHighest,
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  BarButton.icon(
                    tooltip: 'עריכה',
                    icon: FluentIcons.edit_24_regular,
                    onPressed: () => _editNote(note),
                  ),
                  if (isMissing)
                    BarButton.icon(
                      tooltip: 'מיקום מחדש',
                      icon: FluentIcons.location_24_regular,
                      onPressed: () => _repositionMissing(note),
                    ),
                  if (!isMissing)
                    BarButton.icon(
                      tooltip: 'פתח ספר בשורה',
                      icon: FluentIcons.book_open_24_regular,
                      onPressed: () => _openNoteInBook(note),
                    ),
                  BarButton.icon(
                    tooltip: 'מחיקה',
                    icon: FluentIcons.delete_24_regular,
                    onPressed: () => _deleteNote(note),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editNote(PersonalNote note) async {
    final result = await showDialog<PersonalNoteEditorResult>(
      context: context,
      builder: (context) => PersonalNoteEditorDialog(
        title: 'ערוך הערה',
        initialContent: note.content,
        initialContentFormat: note.contentFormat,
        referenceText: note.displayTitle,
        icon: FluentIcons.edit_24_regular,
        bookId: note.bookId,
        linkableNotes: [
          ...context.read<PersonalNotesBloc>().state.locatedNotes,
          ...context.read<PersonalNotesBloc>().state.missingNotes,
        ],
      ),
    );
    if (result == null) return;

    final trimmed = result.contentPlain.trim();
    if (trimmed.isEmpty) {
      UiSnack.show(NotesMessages.emptyNoteNotSaved);
      return;
    }

    if (!mounted) return;
    context.read<PersonalNotesBloc>().add(
      UpdatePersonalNote(
        bookId: note.bookId,
        noteId: note.id,
        content: result.content,
        contentPlain: result.contentPlain,
        contentFormat: result.contentFormat,
      ),
    );
    UiSnack.show(NotesMessages.noteUpdated);
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
      UiSnack.show(NotesMessages.noteDeleted);
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
      UiSnack.show(NotesMessages.noteMovedToLine(newLine));
    }
  }

  Future<void> _openNoteInBook(PersonalNote note) async {
    if (note.lineNumber == null) {
      UiSnack.show(NotesMessages.noteHasNoLocation);
      return;
    }

    final libraryState = context.read<LibraryBloc>().state;
    final library = libraryState.library;
    if (library == null) {
      UiSnack.show(NotesMessages.libraryNotLoadedYet);
      return;
    }

    final book =
        library.findBookByTitle(note.bookId, TextBook) ??
        library.findBookByTitle(note.bookId, null);
    if (book == null) {
      UiSnack.show(NotesMessages.bookNotFound(note.bookId));
      return;
    }

    final lineIndex = (note.lineNumber! - 1).clamp(0, 1 << 30);
    final tabsBloc = context.read<TabsBloc>();
    final previousSidebarTab = Settings.getValue<int>(
      'key-sidebar-tab-index-combined',
    );
    Settings.setValue<int>('key-sidebar-tab-index-combined', 2);
    Settings.setValue<int>('key-sidebar-tab-index-pending', 2);

    openBook(
      context,
      book,
      lineIndex,
      '',
      ignoreHistory: true,
      requiresStableLayout: true,
    );

    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final tabsState = tabsBloc.state;
      if (tabsState.tabs.isEmpty) return;
      final currentTab = tabsState.tabs[tabsState.currentTabIndex];
      if (currentTab is TextBookTab) {
        currentTab.bloc.add(UpdateSelectedIndex(lineIndex));
        currentTab.bloc.add(HighlightLine(lineIndex));
        currentTab.bloc.add(const ToggleSplitView(true));
      }

      if (previousSidebarTab != null) {
        Settings.setValue<int>(
          'key-sidebar-tab-index-combined',
          previousSidebarTab,
        );
      } else {
        Settings.setValue<int>('key-sidebar-tab-index-combined', 0);
      }
    });
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color backgroundColor;
  final Color foregroundColor;

  const _InfoChip({
    required this.icon,
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RtlIcon(icon, size: 12, color: foregroundColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// בודקת אם הערה נכללת בטווח התאריכים שנבחר לסינון.
///
/// הסינון מתבצע לפי תאריך העדכון [PersonalNote.updatedAt] ברמת היום בלבד
/// (מתעלם משעה). [range] של null פירושו שאין סינון פעיל — כל ההערות נכללות.
@visibleForTesting
bool noteWithinDateRange(PersonalNote note, DateTimeRange? range) {
  if (range == null) return true;
  final noteDay = DateUtils.dateOnly(note.updatedAt);
  return !noteDay.isBefore(range.start) && !noteDay.isAfter(range.end);
}

enum _NotesNavRowKind { root, category, book, missing }

/// שורה משוטחת בעץ ההערות (לבנייה עצלה ב-ListView.builder).
class _NotesNavRow {
  final _NotesNavRowKind kind;
  final Category? category;
  final Book? book;
  final int level;
  final int count;
  final bool isExpanded;
  bool isGroupStart = false;
  bool isGroupEnd = false;

  _NotesNavRow._({
    required this.kind,
    this.category,
    this.book,
    this.level = 0,
    this.count = 0,
    this.isExpanded = false,
  });

  _NotesNavRow.root(int count)
    : this._(kind: _NotesNavRowKind.root, count: count);

  _NotesNavRow.missing() : this._(kind: _NotesNavRowKind.missing);

  _NotesNavRow.category(
    Category category,
    int level,
    int count,
    bool isExpanded,
  ) : this._(
        kind: _NotesNavRowKind.category,
        category: category,
        level: level,
        count: count,
        isExpanded: isExpanded,
      );

  _NotesNavRow.book(Book book, int level, int count)
    : this._(
        kind: _NotesNavRowKind.book,
        book: book,
        level: level,
        count: count,
      );
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
