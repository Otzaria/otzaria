import 'dart:async';
import 'package:otzaria/models/books.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/text_book/editing/repository/overrides_repository.dart';
import 'package:otzaria/text_book/editing/models/section_identifier.dart';

class TextBookBloc extends Bloc<TextBookEvent, TextBookState> {
  final TextBookRepository _repository;
  final OverridesRepository _overridesRepository;
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;

  TextBookBloc({
    required TextBookRepository repository,
    required OverridesRepository overridesRepository,
    required TextBookInitial initialState,
    required this.scrollController,
    required this.positionsListener,
  })  : _repository = repository,
        _overridesRepository = overridesRepository,
        super(initialState) {
    on<LoadContent>(_onLoadContent);
    on<UpdateFontSize>(_onUpdateFontSize);
    on<ToggleLeftPane>(_onToggleLeftPane);
    on<ToggleSplitView>(_onToggleSplitView);
    on<UpdateCommentators>(_onUpdateCommentators);
    on<ToggleNikud>(_onToggleNikud);
    on<UpdateVisibleIndecies>(_onUpdateVisibleIndecies);
    on<UpdateSelectedIndex>(_onUpdateSelectedIndex);
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
  }

  Future<void> _onLoadContent(
    LoadContent event,
    Emitter<TextBookState> emit,
  ) async {
    TextBook book;
    String searchText;
    bool showLeftPane;
    List<String> commentators;
    late final List<int> visibleIndices;

    if (state is TextBookLoaded && event.preserveState) {
      // Preserve current state when reloading
      final currentState = state as TextBookLoaded;
      book = currentState.book;
      searchText = currentState.searchText;
      showLeftPane = currentState.showLeftPane;
      commentators = currentState.activeCommentators;
      visibleIndices = currentState.visibleIndices;
    } else if (state is TextBookInitial) {
      // Normal initial load
      final initial = state as TextBookInitial;
      book = initial.book;
      searchText = initial.searchText;
      showLeftPane = initial.showLeftPane;
      commentators = initial.commentators;
      visibleIndices = [initial.index];

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
      final content = await _repository.getBookContent(book);
      final links = await _repository.getBookLinks(book);
      final tableOfContents = await _repository.getTableOfContents(book);

      // Update current title if we're preserving state
      String? currentTitle;
      if (visibleIndices.isNotEmpty) {
        try {
          currentTitle = await refFromIndex(
              visibleIndices.first, Future.value(tableOfContents));
        } catch (_) {
          currentTitle = null;
        }
      }

      final availableCommentators =
          await _repository.getAvailableCommentators(links);
      //
      final eras = await utils.splitByEra(availableCommentators);

      final defaultRemoveNikud =
          Settings.getValue<bool>('key-default-nikud') ?? false;
      final removeNikudFromTanach =
          Settings.getValue<bool>('key-remove-nikud-tanach') ?? false;
      final isTanach = await FileSystemData.instance.isTanachBook(book.title);
      final removeNikud =
          defaultRemoveNikud && (removeNikudFromTanach || !isTanach);

      final visibleLinks = _getVisibleLinks(
        links: links,
        visibleIndices: visibleIndices,
        selectedIndex: null,
      );

      // Set up position listener with debouncing to prevent excessive updates
      Timer? debounceTimer;
      positionsListener.itemPositions.addListener(() {
        // Cancel previous timer if exists
        debounceTimer?.cancel();

        // Set new timer with 100ms delay
        debounceTimer = Timer(const Duration(milliseconds: 100), () {
          final visibleIndicesNow = positionsListener.itemPositions.value
              .map((e) => e.index)
              .toList();
          if (visibleIndicesNow.isNotEmpty) {
            add(UpdateVisibleIndecies(visibleIndicesNow));
          }
        });
      });

      emit(TextBookLoaded(
        book: book,
        content: content.split('\n'),
        links: links,
        availableCommentators: availableCommentators,
        tableOfContents: tableOfContents,
        fontSize: event.fontSize,
        showLeftPane: showLeftPane || searchText.isNotEmpty,
        showSplitView: event.showSplitView,
        activeCommentators: commentators,
        commentatorGroups: _buildCommentatorGroups(eras, availableCommentators),
        removeNikud: removeNikud,
        visibleIndices: visibleIndices,
        pinLeftPane: Settings.getValue<bool>('key-pin-sidebar') ?? false,
        searchText: searchText,
        scrollController: scrollController,
        positionsListener: positionsListener,
        currentTitle: currentTitle,
        visibleLinks: visibleLinks,
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
      emit(currentState.copyWith(
        showSplitView: event.show,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onUpdateCommentators(
    UpdateCommentators event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      // אם אין מפרשים פעילים וחלונית הצד פתוחה, סוגר אותה
      final shouldCloseSplitView =
          event.commentators.isEmpty && currentState.showSplitView;

      // אם יש מפרשים חדשים ואין חלונית פתוחה, פותח אותה
      final shouldOpenSplitView = event.commentators.isNotEmpty &&
          currentState.activeCommentators.isEmpty &&
          !currentState.showSplitView;

      emit(currentState.copyWith(
        activeCommentators: event.commentators,
        selectedIndex: currentState.selectedIndex,
        showSplitView: shouldCloseSplitView
            ? false
            : (shouldOpenSplitView ? true : currentState.showSplitView),
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
      if (!event.visibleIndecies.contains(index)) {
        index = null;
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
                link.connectionType != 'commentary' &&
                link.connectionType != 'targum',
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
        await _repository.saveBookContent(currentState.book, event.markdown);

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
      await _repository.saveBookContent(currentState.book, fullContent);

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
