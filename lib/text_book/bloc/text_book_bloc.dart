import 'dart:async';
import 'package:otzaria/models/books.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/text_book/editing/repository/overrides_repository.dart';
import 'package:otzaria/text_book/editing/models/section_identifier.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/migration/core/models/category.dart' as db;

class TextBookBloc extends Bloc<TextBookEvent, TextBookState> {
  final TextBookRepository repository;
  final OverridesRepository _overridesRepository;
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;

  Timer? _debounceTimer;
  Timer? _highlightTimer;
  VoidCallback? _positionListenerCallback;

  TextBookBloc({
    required this.repository,
    required OverridesRepository overridesRepository,
    required TextBookInitial initialState,
    required this.scrollController,
    required this.positionsListener,
  })  : _overridesRepository = overridesRepository,
        super(initialState) {
    on<LoadContent>(_onLoadContent);
    on<UpdateFontSize>(_onUpdateFontSize);
    on<ToggleLeftPane>(_onToggleLeftPane);
    on<ToggleSplitView>(_onToggleSplitView);
    on<ToggleTzuratHadafView>(_onToggleTzuratHadafView);
    on<TogglePageShapeView>(_onTogglePageShapeView);
    on<UpdateCommentators>(_onUpdateCommentators);
    on<ToggleNikud>(_onToggleNikud);
    on<UpdateVisibleIndecies>(_onUpdateVisibleIndecies);
    on<UpdateSelectedIndex>(_onUpdateSelectedIndex);
    on<HighlightLine>(_onHighlightLine);
    on<ClearHighlightedLine>(_onClearHighlightedLine);
    on<TogglePinLeftPane>(_onTogglePinLeftPane);
    on<UpdateSearchText>(_onUpdateSearchText);
    on<CreateNoteFromToolbar>(_onCreateNoteFromToolbar);
    on<UpdateSelectedTextForNote>(_onUpdateSelectedTextForNote);

    // Editor events
    on<OpenEditor>(_onOpenEditor);
    on<OpenFullFileEditor>(_onOpenFullFileEditor);
    on<SaveEditedSection>(_onSaveEditedSection);
    on<LoadDraftIfAny>(_onLoadDraftIfAny);
    on<DiscardDraft>(_onDiscardDraft);
    on<CloseEditor>(_onCloseEditor);
    on<UpdateEditorText>(_onUpdateEditorText);
    on<AutoSaveDraft>(_onAutoSaveDraft);
    on<UpdateLinks>(_onUpdateLinks);
    on<UpdateAvailableCommentators>(_onUpdateAvailableCommentators);
  }

  Future<void> _onLoadContent(
    LoadContent event,
    Emitter<TextBookState> emit,
  ) async {
    TextBook book;
    String searchText;
    Map<String, Map<String, bool>> searchOptions = {};
    Map<int, List<String>> alternativeWords = {};
    Map<String, String> spacingValues = {};
    SearchMode searchMode = SearchMode.exact;
    bool showLeftPane;
    List<String> commentators;
    late final List<int> visibleIndices;

    bool initialShowPageShapeView = false;

    // שמירת מפרשים קיימים כדי לא לאבד אותם ב-preserveState reload
    List<String> existingAvailableCommentators = const [];
    List<CommentatorGroup> existingCommentatorGroups = const [];

    if (state is TextBookLoaded && event.preserveState) {
      // Preserve current state when reloading
      final currentState = state as TextBookLoaded;
      book = currentState.book;
      searchText = currentState.searchText;
      searchOptions = currentState.searchOptions;
      alternativeWords = currentState.alternativeWords;
      spacingValues = currentState.spacingValues;
      searchMode = currentState.searchMode;
      showLeftPane = currentState.showLeftPane;
      commentators = currentState.activeCommentators;
      visibleIndices = currentState.visibleIndices;
      initialShowPageShapeView = currentState.showPageShapeView;
      existingAvailableCommentators = currentState.availableCommentators;
      existingCommentatorGroups = currentState.commentatorGroups;
    } else if (state is TextBookInitial) {
      // Normal initial load
      final initial = state as TextBookInitial;
      book = initial.book;
      searchText = initial.searchText;
      searchOptions = initial.searchOptions;
      alternativeWords = initial.alternativeWords;
      spacingValues = initial.spacingValues;
      searchMode = initial.searchMode;
      showLeftPane = initial.showLeftPane;
      commentators = initial.commentators;
      visibleIndices = [initial.index];
      initialShowPageShapeView = initial.showPageShapeView;

      emit(TextBookLoading(
          book, initial.index, initial.showLeftPane, initial.commentators));
    } else if (!event.preserveState) {
      // Not preserving state and not initial, just emit current state
      if (state is TextBookLoaded) {
        emit(state);
      }
      return;
    } else {
      return; // Invalid state combination
    }

    try {
      // ── שלב 1: התחלת טעינות מקבילות ──
      // מתחילים את טעינת TOC במקביל לטעינת התוכן כדי לחסוך זמן
      final tocFuture = repository.getTableOfContents(book);

      // טעינת תוכן הספר (עם fallback ל-preview אם ריק)
      final sqliteProvider = SqliteDataProvider.instance;
      String content = await repository.getBookContent(book);
      if (content.isEmpty) {
        // Load quick preview (40 lines) for instant display
        final preview = await sqliteProvider.getBookQuickPreview(
          book.title,
          visibleIndices.first,
        );

        if (preview != null && preview.isNotEmpty) {
          content = preview;

          // Load full book in background
          _loadFullBookInBackground(book, emit, event, visibleIndices,
              searchText, showLeftPane, commentators);
        } else {
          // Preview failed, load full book normally
          content = await repository.getBookContent(book);
        }
      }

      // ── שלב 2: המתנה ל-TOC (כבר רץ במקביל, צפוי להיות מוכן) ──
      final tableOfContents = await tocFuture;

      // ── שלב 3: חישובים מהירים שלא דורשים I/O כבד ──
      // חישוב כותרת נוכחית (תלוי ב-TOC שכבר מוכן)
      String? currentTitle;
      if (visibleIndices.isNotEmpty) {
        try {
          currentTitle = await refFromIndex(
              visibleIndices.first, Future.value(tableOfContents));
        } catch (_) {
          currentTitle = null;
        }
      }

      // הגדרות ניקוד (קריאות Settings סינכרוניות + בדיקת נתיב קלה)
      final defaultRemoveNikud =
          Settings.getValue<bool>('key-default-nikud') ?? false;
      final removeNikudFromTanach =
          Settings.getValue<bool>('key-remove-nikud-tanach') ?? false;
      final isTanach = await FileSystemData.instance.isTanachBook(book.title);
      final removeNikud =
          defaultRemoveNikud && (removeNikudFromTanach || !isTanach);

      // קישורים מתחילים ריקים - יטענו ברקע אחרי הצגת הספר
      const List<Link> emptyLinks = [];
      const List<Link> emptyVisibleLinks = [];

      // Set up position listener with debouncing to prevent excessive updates
      // Remove old listener if exists
      if (_positionListenerCallback != null) {
        positionsListener.itemPositions
            .removeListener(_positionListenerCallback!);
      }

      _positionListenerCallback = () {
        // Cancel previous timer if exists
        _debounceTimer?.cancel();

        // Set new timer with 100ms delay
        _debounceTimer = Timer(const Duration(milliseconds: 100), () {
          if (isClosed) return;

          final visibleIndicesNow = positionsListener.itemPositions.value
              .map((e) => e.index)
              .toList();
          if (visibleIndicesNow.isNotEmpty) {
            add(UpdateVisibleIndecies(visibleIndicesNow));
          }
        });
      };

      positionsListener.itemPositions.addListener(_positionListenerCallback!);

      // ── שלב 4: EMIT ראשוני - הצגת הספר מיידית! ──
      // בטעינה ראשונית: מפרשים ריקים, ייטענו ברקע
      // ב-preserveState: שימור מפרשים קיימים כדי למנוע הבהוב
      emit(TextBookLoaded(
        book: book,
        content: content.split('\n'),
        links: emptyLinks,
        availableCommentators: existingAvailableCommentators,
        tableOfContents: tableOfContents,
        fontSize: event.fontSize,
        showLeftPane: event.forceCloseLeftPane
            ? false
            : (showLeftPane || searchText.isNotEmpty),
        showSplitView: event.showSplitView,
        showPageShapeView: initialShowPageShapeView,
        activeCommentators: commentators,
        commentatorGroups: existingCommentatorGroups,
        removeNikud: removeNikud,
        visibleIndices: visibleIndices,
        pinLeftPane: Settings.getValue<bool>('key-pin-sidebar') ?? false,
        searchText: searchText,
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        searchMode: searchMode,
        scrollController: scrollController,
        positionsListener: positionsListener,
        currentTitle: currentTitle,
        visibleLinks: emptyVisibleLinks,
        selectedTextForNote: state is TextBookLoaded
            ? (state as TextBookLoaded).selectedTextForNote
            : null,
        selectedTextStart: state is TextBookLoaded
            ? (state as TextBookLoaded).selectedTextStart
            : null,
        selectedTextEnd: state is TextBookLoaded
            ? (state as TextBookLoaded).selectedTextEnd
            : null,
      ));

      // ── שלב 5: טעינות ברקע - לא חוסמות את ה-UI ──
      // טעינת קישורים ברקע אחרי הצגת הספר
      _loadLinksInBackground(book, visibleIndices);

      // טעינת מפרשים ברקע (רשימת מפרשים זמינים + חלוקה לתקופות)
      if (event.loadCommentators) {
        _loadCommentatorsInBackground(book);
      }

      // העשרת heCategories ברקע (אם חסר)
      _enrichHeCategoriesInBackground(book);
    } catch (e) {
      if (state is TextBookInitial) {
        final initial = state as TextBookInitial;
        emit(TextBookError(e.toString(), initial.book, initial.index,
            initial.showLeftPane, initial.commentators));
      } else if (state is TextBookLoaded && event.preserveState) {
        final current = state as TextBookLoaded;
        emit(TextBookError(
            e.toString(),
            current.book,
            current.visibleIndices.isNotEmpty
                ? current.visibleIndices.first
                : 0,
            current.showLeftPane,
            current.activeCommentators));
      }
    }
  }

  void _onUpdateFontSize(
    UpdateFontSize event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        fontSize: event.fontSize,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onToggleLeftPane(
    ToggleLeftPane event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        showLeftPane: event.show,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onToggleSplitView(
    ToggleSplitView event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      // שמירת ההגדרה ב-Settings כדי שתישמר כברירת מחדל
      Settings.setValue<bool>('key-splited-view', event.show);
      emit(currentState.copyWith(
        showSplitView: event.show,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onToggleTzuratHadafView(
    ToggleTzuratHadafView event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      emit(currentState.copyWith(
        showTzuratHadafView: event.show,
        showPageShapeView: false, // כיבוי התצוגה החדשה
        selectedIndex: currentState.selectedIndex,
        // סגור את חלונית הניווט/חיפוש כשעוברים לצורת הדף
        showLeftPane: event.show ? false : currentState.showLeftPane,
      ));
    }
  }

  void _onTogglePageShapeView(
    TogglePageShapeView event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      // שמירת העדפת התצוגה לספר זה
      PageShapeSettingsManager.saveViewModePreference(
        currentState.book.title,
        event.show,
      );

      // מצב צורת הדף נשמר פר-ספר (ב-toJson של הטאב), לא גלובלית
      emit(currentState.copyWith(
        showPageShapeView: event.show,
        showTzuratHadafView: false, // כיבוי התצוגה הישנה
        selectedIndex: currentState.selectedIndex,
        // סגור את חלונית הניווט/חיפוש כשעוברים לצורת הדף
        showLeftPane: event.show ? false : currentState.showLeftPane,
      ));

      // כשיוצאים ממצב צורת הדף למצב רגיל, גלול למיקום הנוכחי
      if (!event.show && currentState.selectedIndex != null) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (scrollController.isAttached) {
            scrollController.scrollTo(
              index: currentState.selectedIndex!,
              duration: const Duration(milliseconds: 300),
            );
          }
        });
      }
    }
  }

  void _onUpdateCommentators(
    UpdateCommentators event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      // עדכון המפרשים הפעילים בלבד, ללא שינוי של סוג התצוגה
      emit(currentState.copyWith(
        activeCommentators: event.commentators,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onToggleNikud(
    ToggleNikud event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        removeNikud: event.remove,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onUpdateVisibleIndecies(
    UpdateVisibleIndecies event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      // בדיקה אם האינדקסים באמת השתנו
      if (_listsEqual(currentState.visibleIndices, event.visibleIndecies)) {
        return; // אין שינוי, לא צריך לעדכן
      }

      String? newTitle = currentState.currentTitle;

      // עדכון הכותרת רק אם האינדקס הראשון השתנה
      if (event.visibleIndecies.isNotEmpty &&
          (currentState.visibleIndices.isEmpty ||
              currentState.visibleIndices.first !=
                  event.visibleIndecies.first)) {
        newTitle = await refFromIndex(event.visibleIndecies.first,
            Future.value(currentState.tableOfContents));
      }

      int? index = currentState.selectedIndex;
      // איפוס selectedIndex רק אם היתה גלילה משמעותית (יותר מ-3 שורות)
      // כדי למנוע איפוס כשפשוט עוברים בין tabs
      if (index != null && !event.visibleIndecies.contains(index)) {
        final oldFirst = currentState.visibleIndices.isNotEmpty
            ? currentState.visibleIndices.first
            : 0;
        final newFirst =
            event.visibleIndecies.isNotEmpty ? event.visibleIndecies.first : 0;

        // רק אם גללנו יותר מ-3 שורות, נאפס את הבחירה
        if ((oldFirst - newFirst).abs() > 3) {
          index = null;
        }
      }
      final visibleLinks = _getVisibleLinks(
        links: currentState.links,
        visibleIndices: event.visibleIndecies,
        selectedIndex: index,
      );

      emit(currentState.copyWith(
        visibleIndices: event.visibleIndecies,
        currentTitle: newTitle,
        selectedIndex: index,
        visibleLinks: visibleLinks,
      ));
    }
  }

  /// בדיקה אם שתי רשימות שוות
  bool _listsEqual(List<int> list1, List<int> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  void _onUpdateSelectedIndex(
    UpdateSelectedIndex event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      final visibleLinks = _getVisibleLinks(
        links: currentState.links,
        visibleIndices: currentState.visibleIndices,
        selectedIndex: event.index,
      );
      emit(currentState.copyWith(
        selectedIndex: event.index,
        visibleLinks: visibleLinks,
      ));
    }
  }

  void _onHighlightLine(
    HighlightLine event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    emit(currentState.copyWith(highlightedLine: event.lineIndex));

    // Cancel previous highlight timer if exists
    _highlightTimer?.cancel();

    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (!isClosed) {
        add(ClearHighlightedLine(event.lineIndex));
      }
    });
  }

  void _onClearHighlightedLine(
    ClearHighlightedLine event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    if (currentState.highlightedLine == null) return;
    if (event.lineIndex != null &&
        currentState.highlightedLine != event.lineIndex) {
      return;
    }
    emit(currentState.copyWith(clearHighlight: true));
  }

  void _onTogglePinLeftPane(
    TogglePinLeftPane event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        pinLeftPane: event.pin,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onUpdateSearchText(
    UpdateSearchText event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        searchText: event.text,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onCreateNoteFromToolbar(
    CreateNoteFromToolbar event,
    Emitter<TextBookState> emit,
  ) {
    // כרגע זה רק מציין שהאירוע התקבל
    // הלוגיקה האמיתית תהיה בכפתור בשורת הכלים
  }

  void _onUpdateSelectedTextForNote(
    UpdateSelectedTextForNote event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        selectedTextForNote: event.text,
        selectedTextStart: event.start,
        selectedTextEnd: event.end,
      ));
    }
  }

  List<Link> _getVisibleLinks({
    required List<Link> links,
    required List<int> visibleIndices,
    int? selectedIndex,
  }) {
    final targetIndices =
        selectedIndex != null ? [selectedIndex] : visibleIndices;

    final visibleLinks = <Link>[];

    for (final index in targetIndices) {
      final indexLinks = links
          .where(
            (link) =>
                link.index1 == index + 1 &&
                !LinkTypes.isCommentaryOrTargum(link.connectionType) &&
                // מסנן קישורים מבוססי תווים (inline links) - הם אמורים להופיע רק בתוך הטקסט
                link.start == null &&
                link.end == null,
          )
          .toList();
      visibleLinks.addAll(indexLinks);
    }

    visibleLinks.sort(
      (a, b) => a.path2
          .split(Platform.pathSeparator)
          .last
          .compareTo(b.path2.split(Platform.pathSeparator).last),
    );

    return visibleLinks;
  }

  // Editor event handlers
  Future<void> _onOpenEditor(
    OpenEditor event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;

    final currentState = state as TextBookLoaded;

    try {
      // Generate section identifier
      final content = currentState.content[event.index];
      final sectionId = SectionIdentifier.fromContent(
        content: content,
        index: event.index,
      );

      // Check if book has links file
      final hasLinks =
          await _overridesRepository.hasLinksFile(currentState.book.title);

      // Load existing override or original content
      final override = await _overridesRepository.readOverride(
        currentState.book.title,
        sectionId.sectionId,
      );

      final editorText = override?.markdownContent ?? content;

      // Check for draft
      final hasDraft = await _overridesRepository.hasNewerDraftThanOverride(
        currentState.book.title,
        sectionId.sectionId,
      );

      emit(currentState.copyWith(
        isEditorOpen: true,
        editorIndex: event.index,
        editorSectionId: sectionId.sectionId,
        editorText: editorText,
        hasDraft: hasDraft,
        hasLinksFile: hasLinks,
      ));
    } catch (e) {
      // Handle error - could emit error state or show notification
    }
  }

  Future<void> _onOpenFullFileEditor(
    OpenFullFileEditor event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;

    final currentState = state as TextBookLoaded;

    try {
      // Combine all content into one string
      final fullContent = currentState.content.join('\n\n');

      // We don't need section identifier for full file - using fixed ID

      // Check if book has links file
      final hasLinks =
          await _overridesRepository.hasLinksFile(currentState.book.title);

      // Load existing override or original content
      final override = await _overridesRepository.readOverride(
        currentState.book.title,
        'full_file',
      );

      final editorText = override?.markdownContent ?? fullContent;

      // Check for draft
      final hasDraft = await _overridesRepository.hasNewerDraftThanOverride(
        currentState.book.title,
        'full_file',
      );

      emit(currentState.copyWith(
        isEditorOpen: true,
        editorIndex: -1, // Special index for full file
        editorSectionId: 'full_file',
        editorText: editorText,
        hasDraft: hasDraft,
        hasLinksFile: hasLinks,
      ));
    } catch (e) {
      // Debug: Error in _onOpenFullFileEditor: $e
      // Handle error - could emit error state or show notification
    }
  }

  Future<void> _onSaveEditedSection(
    SaveEditedSection event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;

    final currentState = state as TextBookLoaded;

    try {
      // Handle full file editing differently
      if (event.sectionId == 'full_file' && event.index == -1) {
        // For full file editing, save the entire content to the original file
        await repository.saveBookContent(currentState.book, event.markdown);

        // Split the content back into sections for display
        final sections = event.markdown
            .split('\n\n')
            .where((s) => s.trim().isNotEmpty)
            .toList();

        // If we have fewer sections than before, pad with empty strings
        while (sections.length < currentState.content.length) {
          sections.add('');
        }

        // Reload content to ensure we have the latest version
        add(LoadContent(
          fontSize: currentState.fontSize,
          showSplitView: currentState.showSplitView,
          removeNikud: currentState.removeNikud,
          preserveState: true,
        ));

        return;
      }

      // Regular section editing - update the specific section and save the entire file
      final updatedContent = List<String>.from(currentState.content);
      updatedContent[event.index] = event.markdown;

      // Join all sections back together and save to original file
      final fullContent = updatedContent.join('\n\n');
      await repository.saveBookContent(currentState.book, fullContent);

      // Close editor immediately
      emit(currentState.copyWith(
        isEditorOpen: false,
        editorIndex: null,
        editorSectionId: null,
        editorText: null,
        hasDraft: false,
      ));

      // Reload content to ensure we have the latest version from the file system
      add(LoadContent(
        fontSize: currentState.fontSize,
        showSplitView: currentState.showSplitView,
        removeNikud: currentState.removeNikud,
        preserveState: true,
      ));
    } catch (e) {
      // Debug: Error in _onSaveEditedSection: $e
      // Handle error - could show error message to user
    }
  }

  Future<void> _onLoadDraftIfAny(
    LoadDraftIfAny event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;

    final currentState = state as TextBookLoaded;

    try {
      final draft = await _overridesRepository.readDraft(
        currentState.book.title,
        event.sectionId,
      );

      if (draft != null) {
        emit(currentState.copyWith(
          editorText: draft.markdownContent,
          hasDraft: false, // Draft is now loaded, so no longer "pending"
        ));
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onDiscardDraft(
    DiscardDraft event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;

    final currentState = state as TextBookLoaded;

    try {
      await _overridesRepository.deleteDraft(
        currentState.book.title,
        event.sectionId,
      );

      emit(currentState.copyWith(hasDraft: false));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onCloseEditor(
    CloseEditor event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;

    final currentState = state as TextBookLoaded;

    emit(currentState.copyWith(
      isEditorOpen: false,
      editorIndex: null,
      editorSectionId: null,
      editorText: null,
      hasDraft: false,
    ));
  }

  Future<void> _onUpdateEditorText(
    UpdateEditorText event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;

    final currentState = state as TextBookLoaded;

    emit(currentState.copyWith(editorText: event.text));
  }

  Future<void> _onAutoSaveDraft(
    AutoSaveDraft event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;

    final currentState = state as TextBookLoaded;

    try {
      await _overridesRepository.writeDraft(
        currentState.book.title,
        event.sectionId,
        event.markdown,
      );

      // Don't emit state change for auto-save to avoid unnecessary rebuilds
    } catch (e) {
      // Handle error silently for auto-save
    }
  }

  @override
  Future<void> close() {
    // Cancel all timers
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();

    // Remove position listener
    if (_positionListenerCallback != null) {
      positionsListener.itemPositions
          .removeListener(_positionListenerCallback!);
    }

    return super.close();
  }

  /// Loads the full book in the background and updates the state
  void _loadFullBookInBackground(
    TextBook book,
    Emitter<TextBookState> emit,
    LoadContent event,
    List<int> visibleIndices,
    String searchText,
    bool showLeftPane,
    List<String> commentators,
  ) async {
    try {
      // Load full content
      final fullContent = await repository.getBookContent(book);

      // Check if still in the same book (user might have navigated away)
      if (isClosed || state is! TextBookLoaded) {
        return;
      }

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) {
        return;
      }

      // Update state with full content
      emit(currentState.copyWith(
        content: fullContent.split('\n'),
      ));
    } catch (e) {
      // Silent fail - user already has preview
    }
  }

  /// Loads links in the background after the book is displayed
  void _loadLinksInBackground(TextBook book, List<int> visibleIndices) async {
    try {
      // Load all links for the book
      final links = await repository.getBookLinks(book);

      // Check if still in the same book
      if (isClosed || state is! TextBookLoaded) {
        return;
      }

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) {
        return;
      }

      // Use event to update links
      add(UpdateLinks(links));
    } catch (e) {
      // Silent fail - user already has the book displayed
    }
  }

  void _onUpdateLinks(
    UpdateLinks event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      final links = event.links.cast<Link>();

      // Calculate visible links
      final visibleLinks = _getVisibleLinks(
        links: links,
        visibleIndices: currentState.visibleIndices,
        selectedIndex: currentState.selectedIndex,
      );

      emit(currentState.copyWith(
        links: links,
        visibleLinks: visibleLinks,
      ));
    }
  }

  /// Handler for updating available commentators after background loading
  void _onUpdateAvailableCommentators(
    UpdateAvailableCommentators event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        availableCommentators: event.availableCommentators,
        commentatorGroups: event.commentatorGroups.cast<CommentatorGroup>(),
      ));
    }
  }

  /// Loads available commentators in the background after the book is displayed
  void _loadCommentatorsInBackground(TextBook book) async {
    try {
      final availableCommentators =
          await repository.getAvailableCommentators(book);
      final eras = await utils.splitByEra(availableCommentators);
      final groups = _buildCommentatorGroups(eras, availableCommentators);

      if (isClosed || state is! TextBookLoaded) return;

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) return;

      add(UpdateAvailableCommentators(availableCommentators, groups));
    } catch (e) {
      debugPrint('⚠️ Failed to load commentators in background: $e');
      // Silent fail - user already has the book displayed
    }
  }

  /// Enriches heCategories metadata in the background after the book is displayed
  void _enrichHeCategoriesInBackground(TextBook book) async {
    if (book.heCategories != null && book.heCategories!.isNotEmpty) return;

    try {
      // ניסיון 1: טעינה ממסד הנתונים
      final sqliteProvider = SqliteDataProvider.instance;
      if (await sqliteProvider.databaseExists() &&
          sqliteProvider.isInitialized) {
        final dbRepo = sqliteProvider.repository;
        if (dbRepo != null) {
          final dbBook = await dbRepo.getBookByTitle(book.title);
          if (dbBook != null) {
            final category = await dbRepo.getCategory(dbBook.categoryId);
            if (category != null) {
              final categoryParts = <String>[];
              db.Category? currentCategory = category;
              while (currentCategory != null) {
                categoryParts.insert(0, currentCategory.title);
                if (currentCategory.parentId != null) {
                  currentCategory =
                      await dbRepo.getCategory(currentCategory.parentId!);
                } else {
                  break;
                }
              }
              book.heCategories = categoryParts.join(', ');
              debugPrint(
                  '📚 Background: נטען heCategories מה-DB: "${book.heCategories}"');
              return;
            }
          }
        }
      }

      // ניסיון 2: טעינה מ-metadata
      if (book.heCategories == null || book.heCategories!.isEmpty) {
        final metadata = await FileSystemData.instance.metadata;
        final bookMetadata = metadata[book.title];
        if (bookMetadata != null) {
          book.heCategories = bookMetadata['heCategories'];
          book.author ??= bookMetadata['author'];
          book.heEra ??= bookMetadata['heEra'];
          if (book.heCategories != null && book.heCategories!.isNotEmpty) {
            debugPrint(
                '📚 Background: נטען heCategories מ-metadata: "${book.heCategories}"');
            return;
          }
        }
      }

      // ניסיון 3: חילוץ מהנתיב
      if (book.heCategories == null || book.heCategories!.isEmpty) {
        final titleToPath = await FileSystemData.instance.titleToPath;
        final bookPath = titleToPath[book.title];
        if (bookPath != null) {
          final pathParts = bookPath.split(Platform.pathSeparator);
          final otzariaIndex = pathParts.indexOf('אוצריא');
          if (otzariaIndex >= 0 && otzariaIndex < pathParts.length - 2) {
            final categories =
                pathParts.sublist(otzariaIndex + 1, pathParts.length - 1);
            book.heCategories = categories.join(', ');
            debugPrint(
                '📚 Background: נטען heCategories מהנתיב: "${book.heCategories}"');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to enrich heCategories in background: $e');
    }
  }

  List<CommentatorGroup> _buildCommentatorGroups(
      Map<String, List<String>> eras, List<String> availableCommentators) {
    final known = <String>{
      ...?eras['תורה שבכתב'],
      ...?eras['חז"ל'],
      ...?eras['ראשונים'],
      ...?eras['אחרונים'],
      ...?eras['מחברי זמננו'],
    };

    final others = (eras['מפרשים נוספים'] ?? [])
        .toSet()
        .union(availableCommentators
            .where((c) => !known.contains(c))
            .toList()
            .toSet())
        .toList();

    return [
      CommentatorGroup(
        title: 'תורה שבכתב',
        commentators: eras['תורה שבכתב'] ?? const [],
      ),
      CommentatorGroup(
        title: 'חז"ל',
        commentators: eras['חז"ל'] ?? const [],
      ),
      CommentatorGroup(
        title: 'ראשונים',
        commentators: eras['ראשונים'] ?? const [],
      ),
      CommentatorGroup(
        title: 'אחרונים',
        commentators: eras['אחרונים'] ?? const [],
      ),
      CommentatorGroup(
        title: 'מחברי זמננו',
        commentators: eras['מחברי זמננו'] ?? const [],
      ),
      CommentatorGroup(
        title: 'שאר מפרשים',
        commentators: others,
      ),
    ];
  }
}
