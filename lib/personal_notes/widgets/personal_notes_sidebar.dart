import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/utils/note_location_ref.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_filter.dart';
import 'package:otzaria/personal_notes/utils/open_personal_notes_target.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/notes_search_header.dart';
import 'package:otzaria/personal_notes/widgets/note_tile.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

class PersonalNotesSidebar extends StatefulWidget {
  final String bookId;
  final int? categoryId;
  final PersonalNotesRepository? repository;

  /// [note] — ההערה שאליה מנווטים, לגלילה אל המילים שעליהן נכתבה.
  final void Function(int lineNumber, {PersonalNote? note}) onNavigateToLine;
  final bool isPdf;
  final List<int>? visibleLineIndices;
  final List<int>? visiblePdfPages;
  final String? pdfDocumentId;
  final Set<String> pdfDocumentIds;
  final bool includeUnidentifiedPdfAnchors;
  final int? focusLineNumber;
  final Future<void> Function(PersonalNote)? onReanchorNote;

  /// ה-outline של ה-PDF לחישוב כתובת המיקום של כל הערה. רלוונטי רק כש-[isPdf].
  /// מועבר כ-listenable כי ה-outline עשוי להיטען אחרי בניית הפאנל.
  final ValueListenable<List<PdfOutlineNode>?>? pdfOutline;

  /// מוצג בסוף הרשימה, אחרי הערות הספר (למשל הערות המפרשים בצורת הדף).
  final Widget? footer;

  const PersonalNotesSidebar({
    super.key,
    required this.bookId,
    this.categoryId,
    this.repository,
    required this.onNavigateToLine,
    this.isPdf = false,
    this.visibleLineIndices,
    this.visiblePdfPages,
    this.pdfDocumentId,
    this.pdfDocumentIds = const {},
    this.includeUnidentifiedPdfAnchors = false,
    this.focusLineNumber,
    this.onReanchorNote,
    this.pdfOutline,
    this.footer,
  });

  @override
  State<PersonalNotesSidebar> createState() => PersonalNotesSidebarState();
}

class PersonalNotesSidebarState extends State<PersonalNotesSidebar>
    with AutomaticKeepAliveClientMixin<PersonalNotesSidebar> {
  @override
  bool get wantKeepAlive => true;
  final PersonalNoteDraftService _draftService = PersonalNoteDraftService();
  late final PersonalNotesRepository _notesRepository =
      widget.repository ?? PersonalNotesRepository();
  final ValueNotifier<List<int>> _visibleLineIndices = ValueNotifier(const []);
  final ValueNotifier<int> _newNoteCancelRequest = ValueNotifier<int>(0);
  final ItemScrollController _itemScrollController = ItemScrollController();
  (String, int?, int)? _revealedExpansion;
  (String, int?, int)? _revealedDraft;
  int _revealGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadTarget();
      _restorePendingNewNoteDraftIfNeeded();
      _syncVisibleLines();
    });
  }

  bool get _hasTextBookBloc =>
      context.findAncestorWidgetOfExactType<BlocProvider<TextBookBloc>>() !=
      null;

  /// האם ההערות בחלונית הן של הספר שבקורא. הערות מפרש שנפתחו מהמפרשים הן של
  /// ספר אחר, ולכן השורה הנבחרת, השורות הנראות ותוכן העניינים בקורא אינם שלהן.
  bool _isReaderBook(TextBookLoaded state) =>
      personalNotesBookKey(state.book) == widget.bookId;

  ({String bookId, Library? library, Future<List<TocEntry>?> toc})?
  _notesBookToc;

  /// תוכן העניינים של [PersonalNotesSidebar.bookId], כשאינו הספר שבקורא.
  Future<List<TocEntry>?> _tocOfNotesBook(BuildContext context) {
    final library = context.select<LibraryBloc?, Library?>(
      (bloc) => bloc?.state.library,
    );
    final cached = _notesBookToc;
    if (cached != null &&
        cached.bookId == widget.bookId &&
        identical(cached.library, library)) {
      return cached.toc;
    }
    final toc = personalNotesBookToc(library, widget.bookId);
    _notesBookToc = (bookId: widget.bookId, library: library, toc: toc);
    return toc;
  }

  void _syncVisibleLines() {
    final fromWidget = widget.visibleLineIndices;
    if (fromWidget != null) {
      _setVisibleLines(fromWidget);
      return;
    }
    if (!_hasTextBookBloc) return;
    final textBookState = context.read<TextBookBloc>().state;
    if (textBookState is TextBookLoaded) {
      _setReaderVisibleLines(textBookState);
    }
  }

  void _setReaderVisibleLines(TextBookLoaded state) =>
      _setVisibleLines(_isReaderBook(state) ? state.visibleIndices : const []);

  void _setVisibleLines(List<int> lines) {
    if (!listEquals(_visibleLineIndices.value, lines)) {
      _visibleLineIndices.value = List.unmodifiable(lines);
    }
  }

  @override
  void didUpdateWidget(covariant PersonalNotesSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.categoryId != widget.categoryId ||
        oldWidget.isPdf != widget.isPdf ||
        oldWidget.pdfDocumentId != widget.pdfDocumentId ||
        !setEquals(oldWidget.pdfDocumentIds, widget.pdfDocumentIds)) {
      context.read<PersonalNotesBloc>().add(const CancelCreatingPersonalNote());
      _loadTarget();
      _restorePendingNewNoteDraftIfNeeded();
      _syncVisibleLines();
    } else if (oldWidget.focusLineNumber != widget.focusLineNumber &&
        widget.focusLineNumber != null) {
      context.read<PersonalNotesBloc>().add(
        RequestExpandNotesForLine(widget.focusLineNumber!),
      );
    }

    if (!listEquals(oldWidget.visibleLineIndices, widget.visibleLineIndices) &&
        widget.visibleLineIndices != null) {
      _setVisibleLines(widget.visibleLineIndices!);
    }
  }

  @override
  void dispose() {
    _visibleLineIndices.dispose();
    _newNoteCancelRequest.dispose();
    super.dispose();
  }

  void _loadTarget() {
    final bloc = context.read<PersonalNotesBloc>();
    final focusLineNumber = widget.focusLineNumber;
    if (focusLineNumber != null) {
      openPersonalNotesTarget(
        bloc,
        bookId: widget.bookId,
        categoryId: widget.categoryId,
        lineNumber: focusLineNumber,
      );
      return;
    }
    bloc.add(LoadPersonalNotes(widget.bookId, categoryId: widget.categoryId));
  }

  Future<void> _restorePendingNewNoteDraftIfNeeded() async {
    final bloc = context.read<PersonalNotesBloc>();
    final bookId = widget.bookId;
    final categoryId = widget.categoryId;
    final pdfDocumentId = widget.pdfDocumentId;
    final pdfDocumentIds = widget.pdfDocumentIds;
    final includeUnidentifiedPdfAnchors = widget.includeUnidentifiedPdfAnchors;
    final isPdf = widget.isPdf;
    final draft = await _draftService.loadLatestNewNoteDraft(
      bookId: bookId,
      categoryId: categoryId,
      includePdfAnchors: isPdf,
      pdfDocumentId: pdfDocumentId,
      pdfDocumentIds: pdfDocumentIds,
      includeUnidentifiedPdfAnchors: includeUnidentifiedPdfAnchors,
    );
    if (!mounted ||
        widget.bookId != bookId ||
        widget.categoryId != categoryId ||
        widget.pdfDocumentId != pdfDocumentId ||
        !setEquals(widget.pdfDocumentIds, pdfDocumentIds) ||
        widget.includeUnidentifiedPdfAnchors != includeUnidentifiedPdfAnchors ||
        widget.isPdf != isPdf ||
        draft == null ||
        draft.lineNumber == null) {
      return;
    }

    final currentState = bloc.state;
    // ניווט או יצירה מפורשים גוברים על שחזור אוטומטי, גם אם הגיעו בזמן הטעינה.
    if (widget.focusLineNumber != null ||
        currentState.expandRequestLineNumber != null ||
        currentState.isCreatingNewNote) {
      return;
    }

    bloc.add(
      StartCreatingPersonalNote(
        bookId: bookId,
        lineNumber: draft.lineNumber!,
        referenceText: draft.referenceText,
        selectedText: currentState.newNoteSelectedText,
        selectionColumn: currentState.newNoteSelectionColumn,
        sourceSelectedText: currentState.newNoteSourceSelectedText,
        sourceSelectionOffset: currentState.newNoteSourceSelectionOffset,
        punctuationHidden: currentState.newNotePunctuationHidden,
        pdfAnchor: draft.pdfAnchor,
        initialContent: draft.content,
        initialFormat: draft.contentFormat,
      ),
    );
  }

  void _cancelNewNote() {
    if (!mounted) return;
    context.read<PersonalNotesBloc>().add(const CancelCreatingPersonalNote());
  }

  Future<void> _saveNewNote(
    PersonalNoteEditorResult result,
    PersonalNotesState request,
  ) async {
    final bookId = widget.bookId;
    final lineNumber = request.newNoteLineNumber;
    if (lineNumber == null || request.newNoteBookId != bookId) {
      throw StateError('מיקום ההערה אינו זמין');
    }
    await _notesRepository.createNote(
      bookId: bookId,
      lineNumber: lineNumber,
      content: result.content,
      contentPlain: result.contentPlain,
      contentFormat: result.contentFormat,
      selectedText: request.newNoteSelectedText?.trim(),
      selectionColumn: request.newNoteSelectionColumn,
      sourceSelectedText: request.newNoteSourceSelectedText,
      sourceSelectionOffset: request.newNoteSourceSelectionOffset,
      punctuationHidden: request.newNotePunctuationHidden,
      pdfAnchor: request.newNotePdfAnchor,
      categoryId: widget.categoryId,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasTextBookBloc = _hasTextBookBloc;

    final child = BlocConsumer<PersonalNotesBloc, PersonalNotesState>(
      listenWhen: (previous, current) =>
          _isMyDraft(previous) &&
          _isMyDraft(current) &&
          previous.newNoteRequestToken != current.newNoteRequestToken,
      listener: (context, state) {
        if (_itemScrollController.isAttached) {
          // חושפים עורך קיים לפני בנייתו מחדש: Quill מעדכן IME בסוף הפריים,
          // גם כשפריט שמור מחוץ למסך עדיין לא קיבל פריסה חדשה.
          _itemScrollController.jumpTo(index: 0);
        }
      },
      buildWhen: (previous, current) {
        // מעבר ישיר בין טיוטות של ספרים צריך לרענן את שתי החלוניות.
        final wasMyDraft =
            previous.isCreatingNewNote &&
            previous.newNoteBookId == widget.bookId;
        final isMyDraft =
            current.isCreatingNewNote && current.newNoteBookId == widget.bookId;
        if (wasMyDraft || isMyDraft) {
          return true;
        }
        return current.bookId == widget.bookId;
      },
      builder: (context, state) {
        // rebuild מההורה עוקף את buildWhen, ולכן state של ספר אחר (למשל
        // במעבר ספר באותו טאב) עלול להגיע לכאן — לא מציגים הערות זרות.
        if (state.bookId != null && state.bookId != widget.bookId) {
          return const LoadingIndicator();
        }
        if (state.isLoading && state.locatedNotes.isEmpty) {
          return const LoadingIndicator();
        }

        return ValueListenableBuilder<List<int>>(
          valueListenable: _visibleLineIndices,
          builder: (context, visibleLineIndices, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NotesSearchHeader(
                bookId: widget.bookId,
                categoryId: widget.categoryId,
                isPdf: widget.isPdf,
                visibleLineIndices: visibleLineIndices,
                visiblePdfPages: widget.visiblePdfPages,
                pdfDocumentId: widget.pdfDocumentId,
                pdfDocumentIds: widget.pdfDocumentIds,
                includeUnidentifiedPdfAnchors:
                    widget.includeUnidentifiedPdfAnchors,
              ),
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
                          if (textBookState is TextBookLoaded &&
                              !_isReaderBook(textBookState)) {
                            final toc = _tocOfNotesBook(context);
                            return FutureBuilder<List<TocEntry>?>(
                              future: toc,
                              builder: (context, snapshot) => _buildContent(
                                context,
                                state,
                                visibleLineIndices: visibleLineIndices,
                                tableOfContents:
                                    snapshot.connectionState ==
                                        ConnectionState.done
                                    ? snapshot.data
                                    : null,
                              ),
                            );
                          }

                          final selectedLineNumber =
                              textBookState is TextBookLoaded
                              ? (textBookState.selectedIndex != null
                                    ? textBookState.selectedIndex! + 1
                                    : null)
                              : null;

                          return _buildContent(
                            context,
                            state,
                            visibleLineIndices: visibleLineIndices,
                            selectedLineNumber: selectedLineNumber,
                            tableOfContents: textBookState is TextBookLoaded
                                ? textBookState.tableOfContents
                                : null,
                          );
                        },
                      )
                    : widget.isPdf && widget.pdfOutline != null
                    ? ValueListenableBuilder<List<PdfOutlineNode>?>(
                        valueListenable: widget.pdfOutline!,
                        builder: (context, outline, _) => _buildContent(
                          context,
                          state,
                          visibleLineIndices: visibleLineIndices,
                          selectedLineNumber: null,
                          pdfOutline: outline,
                        ),
                      )
                    : _buildContent(
                        context,
                        state,
                        visibleLineIndices: visibleLineIndices,
                        selectedLineNumber: null,
                      ),
              ),
            ],
          ),
        );
      },
    );

    // אם TextBookBloc זמין, נעטוף עם listener
    if (hasTextBookBloc) {
      return MultiBlocListener(
        listeners: [
          BlocListener<TextBookBloc, TextBookState>(
            listener: (context, state) {
              if (state is TextBookLoaded) _setReaderVisibleLines(state);
            },
          ),
        ],
        child: child,
      );
    }

    return child;
  }

  /// כתובת המיקום של ההערה (שם הספר + דף/עמוד) כשורת משנה מתחת לכותרת.
  Widget? _buildLocationSubtitle(
    BuildContext context,
    PersonalNote note, {
    List<TocEntry>? tableOfContents,
    List<PdfOutlineNode>? pdfOutline,
  }) {
    final ref = personalNoteLocationRef(
      note,
      isPdf: widget.isPdf,
      bookTitle: widget.bookId,
      tableOfContents: tableOfContents,
      pdfOutline: pdfOutline,
    );
    if (ref == null) return null;

    return Text(
      ref,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildContent(
    BuildContext context,
    PersonalNotesState state, {
    required List<int> visibleLineIndices,
    int? selectedLineNumber,
    List<TocEntry>? tableOfContents,
    List<PdfOutlineNode>? pdfOutline,
  }) {
    if (state.errorMessage != null) {
      return OtzariaErrorState(
        isCompact: true,
        title: 'לא ניתן לטעון את ההערות',
        details: state.errorMessage,
      );
    }

    final defaultExpanded =
        !(Settings.getValue<bool>(
              SettingsRepository.keyPersonalNotesCollapsedByDefault,
            ) ??
            true);

    final filtered = filterPersonalNotes(
      locatedNotes: state.locatedNotes,
      missingNotes: state.missingNotes,
      searchQuery: state.searchQuery,
      showOnlyVisible: state.showOnlyVisible,
      visibleLineIndices: visibleLineIndices,
      isPdf: widget.isPdf,
      visiblePdfPages: widget.visiblePdfPages,
      pdfDocumentId: widget.pdfDocumentId,
      pdfDocumentIds: widget.pdfDocumentIds,
      includeUnidentifiedPdfAnchors: widget.includeUnidentifiedPdfAnchors,
    );
    // רשימה משותפת לכל הכרטיסים: העתקה לכל כרטיס ריבועית במספר ההערות.
    final linkableNotes = [...state.locatedNotes, ...state.missingNotes];
    // כל הערה כרטיס עדין, ממוקמת וחסרת מיקום כאחת, עם רווח ביניהם ובלי קווים
    // (review-r5, q-notes-cards). רק בחלונית ההערות: הקישורים והמפרשים נשארים
    // שורות שקופות עם מפריד. הקבוצה של חסרות המיקום מזוהה בכותרת שמעליה.
    final cardColor = AppSurfaces.tintedRow(Theme.of(context).colorScheme);
    final items = <Widget>[];

    // הטיוטה מזוהה לפי newNoteBookId; state.bookId הוא הספר האחרון שנטען.
    final hasNewEditor = _isMyDraft(state);
    if (hasNewEditor) {
      items.add(_buildNewNoteEditor(context, state));
    }

    // הערות ממוקמות
    if (filtered.locatedNotes.isNotEmpty) {
      items.addAll(
        filtered.locatedNotes.map(
          (note) => NoteTile(
            key: ValueKey(note.id),
            note: note,
            onTap: () => widget.onNavigateToLine(note.lineNumber!, note: note),
            onSave: (result) => _saveInline(context, note, result),
            onDelete: () => _confirmDelete(context, note),
            onLinkTap: (url) => _handleNoteLinkTap(context, url),
            defaultExpanded: defaultExpanded,
            backgroundColor: cardColor,
            subtitle: _buildLocationSubtitle(
              context,
              note,
              tableOfContents: tableOfContents,
              pdfOutline: pdfOutline,
            ),
            expandToken: _matchesExpansion(note, state)
                ? state.expandRequestToken
                : null,
            bookId: widget.bookId,
            categoryId: widget.categoryId,
            linkableNotes: linkableNotes,
            extraAction: AppIconButton(
              size: AppIconButtonSize.small,
              tooltip: widget.isPdf ? 'שנה מיקום בדף' : 'שנה שיוך לשורה נבחרת',
              icon: const Icon(FluentIcons.pin_24_regular),
              onPressed: () => _reanchorNote(context, note, selectedLineNumber),
            ),
          ),
        ),
      );
    }

    // הערות חסרות מיקום
    if (filtered.missingNotes.isNotEmpty) {
      if (filtered.locatedNotes.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD,
              vertical: AppTokens.spaceSM,
            ),
            child: Text(
              'הערות חסרות מיקום',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      items.addAll(
        filtered.missingNotes.map(
          (note) => NoteTile(
            key: ValueKey(note.id),
            note: note,
            onTap: () => _reposition(context, note),
            onSave: (result) => _saveInline(context, note, result),
            onDelete: () => _confirmDelete(context, note),
            onLinkTap: (url) => _handleNoteLinkTap(context, url),
            defaultExpanded: defaultExpanded,
            expandToken: _matchesExpansion(note, state)
                ? state.expandRequestToken
                : null,
            bookId: widget.bookId,
            categoryId: widget.categoryId,
            linkableNotes: linkableNotes,
            backgroundColor: cardColor,
            subtitle: note.lastKnownLineNumber != null
                ? Text(
                    'שורה קודמת: ${note.lastKnownLineNumber}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : null,
            extraAction: AppIconButton(
              size: AppIconButtonSize.small,
              tooltip: 'מיקום מחדש',
              icon: const Icon(FluentIcons.location_24_regular),
              onPressed: () => _reposition(context, note),
            ),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      final message = state.showOnlyVisible && visibleLineIndices.isNotEmpty
          ? (widget.isPdf
                ? 'אין הערות לעמוד המוצג'
                : 'אין הערות לטקסט הנראה במסך')
          : (state.searchQuery.isNotEmpty
                ? 'לא נמצאו הערות התואמות לחיפוש'
                : 'אין עדיין הערות על ספר זה');
      items.add(
        OtzariaEmptyState(
          isCompact: true,
          icon: FluentIcons.note_24_regular,
          title: message,
        ),
      );
    }

    if (widget.footer case final footer?) items.add(footer);

    if (state.isLoading) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppTokens.spaceMD),
          child: Center(child: LoadingIndicator.inline()),
        ),
      );
    }

    _revealRequestedItem(
      state,
      filtered.locatedNotes,
      filtered.missingNotes,
      hasNewEditor,
    );
    return ScrollablePositionedListScrollbar(
      scrollController: _itemScrollController,
      itemCount: items.length,
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemCount: items.length,
        itemBuilder: (context, index) => items[index],
      ),
    );
  }

  bool _matchesExpansion(PersonalNote note, PersonalNotesState state) {
    if (state.expandRequestPdfAnchor case final anchor?) {
      return note.pdfAnchor == anchor;
    }
    return note.lineNumber == state.expandRequestLineNumber &&
        state.expandRequestLineNumber != null;
  }

  void _revealRequestedItem(
    PersonalNotesState state,
    List<PersonalNote> locatedNotes,
    List<PersonalNote> missingNotes,
    bool hasNewEditor,
  ) {
    final generation = ++_revealGeneration;
    if (state.isLoading) return;
    final expansion = (
      widget.bookId,
      widget.categoryId,
      state.expandRequestToken,
    );
    final draft = hasNewEditor
        ? (widget.bookId, widget.categoryId, state.newNoteRequestToken)
        : null;
    if (draft == null) _revealedDraft = null;
    final revealExpansion =
        state.expandRequestLineNumber != null &&
        expansion != _revealedExpansion;
    final revealDraft =
        !revealExpansion && draft != null && draft != _revealedDraft;
    if (!revealDraft && !revealExpansion) return;
    var noteIndex = locatedNotes.indexWhere(
      (note) => _matchesExpansion(note, state),
    );
    if (noteIndex < 0) {
      final missingIndex = missingNotes.indexWhere(
        (note) => _matchesExpansion(note, state),
      );
      if (missingIndex >= 0) {
        // כשיש גם הערות ממוקמות, כותרת ההערות החסרות תופסת פריט נוסף.
        noteIndex =
            locatedNotes.length +
            (locatedNotes.isNotEmpty ? 1 : 0) +
            missingIndex;
      }
    }
    if (!revealDraft && noteIndex < 0) return;
    final index = revealDraft ? 0 : noteIndex + (hasNewEditor ? 1 : 0);

    // הפריט עשוי להיות מחוץ למסך או להגיע מטעינה אסינכרונית; גוללים אחרי הבנייה.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _revealGeneration ||
          !_itemScrollController.isAttached) {
        return;
      }
      final current = context.read<PersonalNotesBloc>().state;
      if (!identical(current, state) ||
          widget.bookId != expansion.$1 ||
          widget.categoryId != expansion.$2 ||
          (revealDraft
              ? draft == _revealedDraft
              : expansion == _revealedExpansion)) {
        return;
      }
      _itemScrollController.jumpTo(index: index);
      _revealedExpansion = expansion;
      _revealedDraft = draft;
    });
  }

  Widget _buildNewNoteEditor(BuildContext context, PersonalNotesState state) {
    final bloc = context.read<PersonalNotesBloc>();
    return InlineNoteEditorCard(
      icon: FluentIcons.note_add_24_regular,
      title: state.newNoteReferenceText != null
          ? 'הערה חדשה - ${state.newNoteReferenceText}'
          : 'הערה חדשה - שורה ${state.newNoteLineNumber}',
      // דרך העורך, כדי שישאל על שינויים שלא נשמרו (issue #1303).
      onCancelPressed: () => _newNoteCancelRequest.value++,
      editor: InlineNoteEditor(
        key: ValueKey((
          widget.bookId,
          widget.categoryId,
          state.newNoteSessionToken,
          state.newNoteLineNumber,
          state.newNotePdfAnchor,
        )),
        referenceText: state.newNoteReferenceText,
        bookId: widget.bookId,
        categoryId: widget.categoryId,
        initialContent: state.newNoteInitialContent ?? '',
        initialFormat:
            state.newNoteInitialFormat ?? PersonalNoteContentFormat.plain,
        draftLineNumber: state.newNoteLineNumber,
        pdfAnchor: state.newNotePdfAnchor,
        linkableNotes: [...state.locatedNotes, ...state.missingNotes],
        cancelRequest: _newNoteCancelRequest,
        onSave: (result) => _saveNewNote(result, state),
        onSaved: () {
          // ההשלמה שייכת לבקשה שנשמרה, גם אם הפאנל הוסר בזמן הכתיבה.
          if (!bloc.isClosed) {
            bloc.add(
              CancelCreatingPersonalNote(
                sessionToken: state.newNoteSessionToken,
                bookId: state.newNoteBookId,
                lineNumber: state.newNoteLineNumber,
              ),
            );
          }
        },
        onCancel: _cancelNewNote,
      ),
    );
  }

  bool _isMyDraft(PersonalNotesState state) {
    if (!state.isCreatingNewNote || state.newNoteBookId != widget.bookId) {
      return false;
    }
    final anchor = state.newNotePdfAnchor;
    if (anchor == null) return true;
    if (!widget.isPdf) return false;
    if (anchor.documentId == null) return widget.includeUnidentifiedPdfAnchors;
    return anchor.documentId == widget.pdfDocumentId ||
        widget.pdfDocumentIds.contains(anchor.documentId);
  }

  Future<void> _saveInline(
    BuildContext _,
    PersonalNote note,
    PersonalNoteEditorResult result,
  ) async {
    await _notesRepository.persistNote(
      bookId: widget.bookId,
      noteId: note.id,
      content: result.content,
      contentPlain: result.contentPlain,
      contentFormat: result.contentFormat,
      categoryId: widget.categoryId,
    );
  }

  Future<void> _handleNoteLinkTap(BuildContext context, String url) =>
      openNoteLink(context, url, widget.bookId, widget.onNavigateToLine);

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
      bloc.add(DeletePersonalNote(bookId: widget.bookId, noteId: note.id));
    }
  }

  Future<void> _reposition(BuildContext context, PersonalNote note) async {
    if (widget.onReanchorNote case final reanchor?) {
      await reanchor(note);
      return;
    }
    final bloc = context.read<PersonalNotesBloc>();
    final result = await showInputDialog(
      context: context,
      title: 'שחזור מיקום הערה',
      icon: FluentIcons.location_24_regular,
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
          categoryId: widget.categoryId,
        ),
      );
    }
  }

  void _reanchorToSelectedLineWith(
    PersonalNotesBloc bloc,
    PersonalNote note,
    int selectedLineNumber,
  ) {
    bloc.add(
      RepositionPersonalNote(
        bookId: widget.bookId,
        noteId: note.id,
        lineNumber: selectedLineNumber,
        categoryId: widget.categoryId,
      ),
    );
  }

  Future<void> _reanchorNote(
    BuildContext context,
    PersonalNote note,
    int? selectedLineNumber,
  ) async {
    if (widget.onReanchorNote case final reanchor?) {
      await reanchor(note);
      return;
    }
    final bloc = context.read<PersonalNotesBloc>();
    if (selectedLineNumber != null) {
      final choice = await showSelectionDialog<String>(
        context: context,
        title: 'שינוי שיוך הערה',
        icon: FluentIcons.pin_24_regular,
        items: [
          SelectionItem(
            label: 'שייך לשורה נבחרת ($selectedLineNumber)',
            value: 'selected',
          ),
          const SelectionItem(label: 'הקלד מספר שורה', value: 'manual'),
        ],
      );
      if (!mounted) return;
      if (choice == 'selected') {
        _reanchorToSelectedLineWith(bloc, note, selectedLineNumber);
        return;
      }
      if (choice == null) return;
    }

    if (!context.mounted) return;
    final result = await showInputDialog(
      context: context,
      title: 'שנה שיוך הערה',
      icon: FluentIcons.pin_24_regular,
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
      _reanchorToSelectedLineWith(bloc, note, newLine);
    }
  }
}

/// פותח קישור מהערה אישית של [currentBookId]: פנימי באפליקציה, אינטרנט בדפדפן.
Future<void> openNoteLink(
  BuildContext context,
  String url,
  String currentBookId,
  void Function(int lineNumber, {PersonalNote? note}) onNavigateToLine,
) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) UiSnack.showError(NotesMessages.cannotOpenLink(url));
    return;
  }
  if (uri.scheme != 'otzaria' && uri.scheme != 'zayit') {
    UiSnack.show(NotesMessages.externalLink(url));
    return;
  }

  switch (uri.scheme == 'otzaria' ? uri.host : '') {
    case 'book':
      final bookId = uri.queryParameters['bookId'] ?? '';
      final line = int.tryParse(uri.queryParameters['line'] ?? '');
      if (line == null) return;
      if (bookId.isEmpty || bookId == currentBookId) {
        onNavigateToLine(line);
        return;
      }
      UiSnack.show(NotesMessages.linkToAnotherBook(bookId));
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
        onNavigateToLine(note.lineNumber!, note: note);
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AppDialog.singleAction(
          title: 'הערה מקושרת',
          icon: FluentIcons.link_24_regular,
          confirmText: 'סגור',
          customContent: PersonalNoteContentView(note: note!),
        ),
      );
      return;
    default:
      // קישור עמוק (otzaria://open/... או zayit://) — מנותב למסך הראשי.
      final handled =
          await AppWindowKeys.of(
            context,
          ).mainWindowScreen.currentState?.handleInternalDeepLink(
            url,
          ) ??
          false;
      if (!handled) UiSnack.showError(NotesMessages.unsupportedLink(url));
      return;
  }
}
