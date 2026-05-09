import 'dart:async';
import 'package:otzaria/models/books.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/text_book/utils/he_categories_enricher.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class TextBookBloc extends Bloc<TextBookEvent, TextBookState> {
  static const int _linkLookBehindLines = 25;
  static const int _linkLookAheadLines = 50;
  static const int _linksReloadThresholdLines = 20;
  static const Duration _visibleIndicesDebounceDuration =
      Duration(milliseconds: 160);
  static const String _allTargetBookTitlesSignature =
      '__all_target_book_titles__';

  final TextBookRepository repository;
  final Future<String?> Function(
    String title,
    int currentLine, {
    int? categoryId,
    String? fileType,
  }) _quickPreviewLoader;
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;
  final ScrollOffsetController? scrollOffsetController;

  Timer? _debounceTimer;
  Timer? _highlightTimer;
  VoidCallback? _positionListenerCallback;
  int? _loadedLinksStart;
  int? _loadedLinksEnd;
  String? _loadedLinksBookTitle;
  String? _loadedLinksTargetBookTitlesSignature;
  String? _activeLinksTargetBookTitlesSignature;
  String? _cachedPageShapeTargetBookTitlesKey;
  List<String>? _cachedPageShapeTargetBookTitles;
  bool _isLoadingLinks = false;
  bool _pendingLinksReload = false;
  bool _awaitingInitialPageShapeVisibleSync = false;

  TextBookBloc({
    required this.repository,
    Future<String?> Function(
      String title,
      int currentLine, {
      int? categoryId,
      String? fileType,
    })? quickPreviewLoader,
    required TextBookInitial initialState,
    required this.scrollController,
    required this.positionsListener,
    this.scrollOffsetController,
  })  : _quickPreviewLoader = quickPreviewLoader ??
            SqliteDataProvider.instance.getBookQuickPreview,
        super(initialState) {
    on<LoadContent>(_onLoadContent);
    on<UpdateFontSize>(_onUpdateFontSize);
    on<ToggleLeftPane>(_onToggleLeftPane);
    on<ToggleSplitView>(_onToggleSplitView);
    on<ToggleTzuratHadafView>(_onToggleTzuratHadafView);
    on<TogglePageShapeView>(_onTogglePageShapeView);
    on<UpdateCommentators>(_onUpdateCommentators);
    on<ToggleNikud>(_onToggleNikud);
    on<TogglePunctuation>(_onTogglePunctuation);
    on<UpdateVisibleIndecies>(_onUpdateVisibleIndecies);
    on<UpdateSelectedIndex>(_onUpdateSelectedIndex);
    on<HighlightLine>(_onHighlightLine);
    on<ClearHighlightedLine>(_onClearHighlightedLine);
    on<TogglePinLeftPane>(_onTogglePinLeftPane);
    on<UpdateSearchText>(_onUpdateSearchText);
    on<ApplyFullBookContent>(_onApplyFullBookContent);
    on<CreateNoteFromToolbar>(_onCreateNoteFromToolbar);
    on<UpdateSelectedTextForNote>(_onUpdateSelectedTextForNote);
    on<UpdateLinks>(_onUpdateLinks);
    on<UpdateAvailableCommentators>(_onUpdateAvailableCommentators);
    on<RefreshLinksForCurrentWindow>(_onRefreshLinksForCurrentWindow);
  }

  @visibleForTesting
  static int? expectedInitialPageShapeVisibleIndexForTesting({
    required List<int> visibleIndices,
    required int? selectedIndex,
  }) {
    if (visibleIndices.isNotEmpty) {
      return visibleIndices.first;
    }
    return selectedIndex;
  }

  @visibleForTesting
  static bool isInitialPageShapeVisibleSyncAlignedForTesting({
    required List<int> currentVisibleIndices,
    required int? selectedIndex,
    required List<int> nextVisibleIndices,
  }) {
    final expectedIndex = expectedInitialPageShapeVisibleIndexForTesting(
      visibleIndices: currentVisibleIndices,
      selectedIndex: selectedIndex,
    );
    if (expectedIndex == null || nextVisibleIndices.isEmpty) {
      return true;
    }

    final minVisible = nextVisibleIndices.reduce((a, b) => a < b ? a : b);
    final maxVisible = nextVisibleIndices.reduce((a, b) => a > b ? a : b);
    const tolerance = 2;

    return expectedIndex >= (minVisible - tolerance) &&
        expectedIndex <= (maxVisible + tolerance);
  }

  bool _isInitialPageShapeVisibleSyncAligned(
    TextBookLoaded state,
    List<int> nextVisibleIndices,
  ) {
    return isInitialPageShapeVisibleSyncAlignedForTesting(
      currentVisibleIndices: state.visibleIndices,
      selectedIndex: state.selectedIndex,
      nextVisibleIndices: nextVisibleIndices,
    );
  }

  @visibleForTesting
  static ({bool shouldIgnore, bool shouldDispatchImmediately})
      classifyRawPositionsDuringInitialPageShapeVisibleSyncForTesting({
    required bool awaitingInitialPageShapeVisibleSync,
    required bool showPageShapeView,
    required List<int> currentVisibleIndices,
    required int? selectedIndex,
    required List<int> nextVisibleIndices,
  }) {
    if (!awaitingInitialPageShapeVisibleSync ||
        !showPageShapeView ||
        nextVisibleIndices.isEmpty) {
      return (
        shouldIgnore: false,
        shouldDispatchImmediately: false,
      );
    }

    final isAligned = isInitialPageShapeVisibleSyncAlignedForTesting(
      currentVisibleIndices: currentVisibleIndices,
      selectedIndex: selectedIndex,
      nextVisibleIndices: nextVisibleIndices,
    );
    return (
      shouldIgnore: !isAligned,
      shouldDispatchImmediately: isAligned,
    );
  }

  void _setAwaitingInitialPageShapeVisibleSync(bool value) {
    _awaitingInitialPageShapeVisibleSync = value;
  }

  @visibleForTesting
  static List<Link> mergeLinksForTesting(
          List<Link> existing, List<Link> incoming) =>
      mergeLinksByIdentity(existing, incoming);

  @visibleForTesting
  static List<String> buildPreviewLinesForTesting(
          String previewContent, int previewStartLine) =>
      buildPreviewLines(previewContent, previewStartLine);

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
    int searchDistance = 0;
    bool showLeftPane;
    List<String> commentators;
    late final List<int> visibleIndices;

    bool initialShowPageShapeView = false;

    List<String> existingAvailableCommentators = const [];
    List<CommentatorGroup> existingCommentatorGroups = const [];
    bool? preservedRemoveNikud;
    bool? preservedPinLeftPane;

    if (state is TextBookLoaded && event.preserveState) {
      final currentState = state as TextBookLoaded;
      book = currentState.book;
      searchText = currentState.searchText;
      searchOptions = currentState.searchOptions;
      alternativeWords = currentState.alternativeWords;
      spacingValues = currentState.spacingValues;
      searchMode = currentState.searchMode;
      searchDistance = currentState.searchDistance;
      showLeftPane = currentState.showLeftPane;
      commentators = currentState.activeCommentators;
      visibleIndices = currentState.visibleIndices;
      initialShowPageShapeView = currentState.showPageShapeView;
      existingAvailableCommentators = currentState.availableCommentators;
      existingCommentatorGroups = currentState.commentatorGroups;
      preservedRemoveNikud = currentState.removeNikud;
      preservedPinLeftPane = currentState.pinLeftPane;
    } else if (state is TextBookInitial) {
      final initial = state as TextBookInitial;
      book = initial.book;
      searchText = initial.searchText;
      searchOptions = initial.searchOptions;
      alternativeWords = initial.alternativeWords;
      spacingValues = initial.spacingValues;
      searchMode = initial.searchMode;
      searchDistance = initial.searchDistance;
      showLeftPane = initial.showLeftPane;
      commentators = initial.commentators;
      visibleIndices = [initial.index < 0 ? 0 : initial.index];
      initialShowPageShapeView = initial.showPageShapeView;

      emit(TextBookLoading(
          book, initial.index, initial.showLeftPane, initial.commentators));
    } else if (!event.preserveState) {
      if (state is TextBookLoaded) {
        emit(state);
      }
      return;
    } else {
      return;
    }

    try {
      final tocFuture = repository.getTableOfContents(book);

      String content = await repository.getBookContent(book);
      List<String>? contentLines;
      if (content.isEmpty) {
        final preview = await _quickPreviewLoader(
          book.title,
          visibleIndices.first,
          categoryId: book.categoryId,
          fileType: book.fileType,
        );

        if (preview != null && preview.isNotEmpty) {
          final previewStartLine =
              (visibleIndices.first - 10).clamp(0, visibleIndices.first);
          contentLines = buildPreviewLines(preview, previewStartLine);
          _loadFullBookInBackground(book);
        } else {
          content = await repository.getBookContent(book);
        }
      }

      contentLines ??= await splitContentLines(content);

      final tableOfContents = await tocFuture;

      String? currentTitle;
      if (visibleIndices.isNotEmpty) {
        try {
          currentTitle = await refFromIndex(
              visibleIndices.first, Future.value(tableOfContents));
        } catch (_) {
          currentTitle = null;
        }
      }

      final defaultRemoveNikud =
          Settings.getValue<bool>('key-default-nikud') ?? false;
      final removeNikudFromTanach =
          Settings.getValue<bool>('key-remove-nikud-tanach') ?? false;
      final isTanach = await FileSystemData.instance.isTanachBook(
        book.title,
        categoryId: book.categoryId,
        fileType: book.fileType,
      );
      final removeNikud = shouldRemoveNikudForBook(
        defaultRemoveNikud: defaultRemoveNikud,
        removeNikudFromTanach: removeNikudFromTanach,
        isTanach: isTanach,
      );

      const List<Link> emptyLinks = [];
      const List<Link> emptyVisibleLinks = [];

      if (_positionListenerCallback != null) {
        positionsListener.itemPositions
            .removeListener(_positionListenerCallback!);
      }

      _positionListenerCallback = () {
        final rawPositions = positionsListener.itemPositions.value.toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        final currentState = state;
        if (currentState is! TextBookLoaded) {
          return;
        }

        final visibleIndicesNow = _resolveVisibleSourceIndices(
          currentState,
          rawPositions,
        );
        if (visibleIndicesNow.isEmpty) {
          return;
        }

        if (!_hasMeaningfulVisibleIndicesChange(
          currentState.visibleIndices,
          visibleIndicesNow,
        )) {
          return;
        }

        final initialSyncClassification =
            classifyRawPositionsDuringInitialPageShapeVisibleSyncForTesting(
          awaitingInitialPageShapeVisibleSync:
              _awaitingInitialPageShapeVisibleSync,
          showPageShapeView: currentState.showPageShapeView,
          currentVisibleIndices: currentState.visibleIndices,
          selectedIndex: currentState.selectedIndex,
          nextVisibleIndices: visibleIndicesNow,
        );
        if (initialSyncClassification.shouldIgnore ||
            initialSyncClassification.shouldDispatchImmediately) {
          if (initialSyncClassification.shouldIgnore) {
            return;
          }

          _debounceTimer?.cancel();
          add(UpdateVisibleIndecies(visibleIndicesNow));
          return;
        }

        add(UpdateVisibleIndecies(visibleIndicesNow));
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_visibleIndicesDebounceDuration, () {
          if (isClosed) {
            return;
          }

          final debouncedRawPositions = positionsListener.itemPositions.value
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));
          final latestState = state;
          if (latestState is TextBookLoaded) {
            final visibleIndicesNow = _resolveVisibleSourceIndices(
              latestState,
              debouncedRawPositions,
            );
            if (visibleIndicesNow.isNotEmpty &&
                _hasMeaningfulVisibleIndicesChange(
                  latestState.visibleIndices,
                  visibleIndicesNow,
                )) {
              add(UpdateVisibleIndecies(visibleIndicesNow));
            }
          }
        });
      };

      positionsListener.itemPositions.addListener(_positionListenerCallback!);

      _setAwaitingInitialPageShapeVisibleSync(initialShowPageShapeView);

      emit(TextBookLoaded(
        book: book,
        content: contentLines,
        links: emptyLinks,
        linksByLine: const {},
        availableCommentators: existingAvailableCommentators,
        tableOfContents: tableOfContents,
        fontSize: event.fontSize,
        showLeftPane: event.forceCloseLeftPane
            ? false
            : resolveInitialReadingLeftPaneVisibility(
                explicitOpen: showLeftPane,
                hasSearchText: searchText.isNotEmpty,
              ),
        showSplitView: event.showSplitView,
        showPageShapeView: initialShowPageShapeView,
        activeCommentators: commentators,
        commentatorGroups: existingCommentatorGroups,
        removeNikud: (event.preserveRemoveNikud && preservedRemoveNikud != null)
            ? preservedRemoveNikud
            : removeNikud,
        isTanach: isTanach,
        visibleIndices: visibleIndices,
        pinLeftPane: preservedPinLeftPane ??
            (Settings.getValue<bool>('key-pin-sidebar') ?? false),
        searchText: searchText,
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        searchMode: searchMode,
        searchDistance: searchDistance,
        scrollController: scrollController,
        positionsListener: positionsListener,
        scrollOffsetController: scrollOffsetController,
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

      _resetLoadedLinksWindow(book);

      _loadLinksInBackground(book, visibleIndices);

      if (event.loadCommentators) {
        _loadCommentatorsInBackground(book);
      }

      _enrichHeCategoriesInBackground(book);
    } catch (e, st) {
      debugPrint('Error loading textbook: $e\n$st');
      if (state is TextBookInitial) {
        final initial = state as TextBookInitial;
        emit(TextBookError(e.toString(), initial.book, initial.index,
            initial.showLeftPane, initial.commentators));
      } else if (state is TextBookLoading) {
        final loading = state as TextBookLoading;
        emit(TextBookError(e.toString(), loading.book, loading.index,
            loading.showLeftPane, loading.commentators));
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
      if (currentState.showLeftPane == event.show) {
        return;
      }
      final updatedState = currentState.copyWith(
        showLeftPane: event.show,
        selectedIndex: currentState.selectedIndex,
        visibleLinks: event.show
            ? computeVisibleLinks(
                links: currentState.links,
                visibleIndices: currentState.visibleIndices,
                selectedIndex: currentState.selectedIndex,
                linksByLine: currentState.linksByLine,
              )
            : currentState.visibleLinks,
      );
      emit(updatedState);

      if (event.show && _shouldLoadLinksForState(updatedState)) {
        _loadLinksInBackground(
          updatedState.book,
          updatedState.visibleIndices,
        );
      }
    }
  }

  void _onToggleSplitView(
    ToggleSplitView event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      Settings.setValue<bool>('key-splited-view', event.show);
      final updatedState = currentState.copyWith(
        showSplitView: event.show,
        selectedIndex: currentState.selectedIndex,
      );
      emit(updatedState);
      _loadLinksInBackground(
        updatedState.book,
        updatedState.visibleIndices,
        force: true,
      );
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
        showPageShapeView: false,
        selectedIndex: currentState.selectedIndex,
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

      PageShapeSettingsManager.saveViewModePreference(
        currentState.book.title,
        event.show,
      );

      _setAwaitingInitialPageShapeVisibleSync(event.show);
      final updatedState = currentState.copyWith(
        showPageShapeView: event.show,
        showTzuratHadafView: false,
        selectedIndex: currentState.selectedIndex,
        showLeftPane: event.show ? false : currentState.showLeftPane,
      );
      emit(updatedState);
      _loadLinksInBackground(
        updatedState.book,
        updatedState.visibleIndices,
        force: true,
      );

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

      final updatedState = currentState.copyWith(
        activeCommentators: event.commentators,
        selectedIndex: currentState.selectedIndex,
      );
      emit(updatedState);
      if (_shouldLoadLinksForState(updatedState)) {
        final targetIndices = _targetIndicesForCommentaryRefresh(updatedState);
        _loadLinksInBackground(
          updatedState.book,
          targetIndices,
          targetBookTitlesOverride:
              _normalizeCommentaryTargets(updatedState.activeCommentators),
        );
      }
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

  void _onTogglePunctuation(
    TogglePunctuation event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        removePunctuation: event.remove,
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

      if (_awaitingInitialPageShapeVisibleSync &&
          currentState.showPageShapeView) {
        final isAligned = _isInitialPageShapeVisibleSyncAligned(
          currentState,
          event.visibleIndecies,
        );
        if (!isAligned) {
          return;
        }

        _setAwaitingInitialPageShapeVisibleSync(false);
      }

      if (_listsEqual(currentState.visibleIndices, event.visibleIndecies)) {
        return;
      }

      try {
        String? newTitle = currentState.currentTitle;

        if (event.visibleIndecies.isNotEmpty &&
            (currentState.visibleIndices.isEmpty ||
                currentState.visibleIndices.first !=
                    event.visibleIndecies.first)) {
          newTitle = await refFromIndex(event.visibleIndecies.first,
              Future.value(currentState.tableOfContents));
        }

        int? index = currentState.selectedIndex;
        if (index != null && !event.visibleIndecies.contains(index)) {
          final oldFirst = currentState.visibleIndices.isNotEmpty
              ? currentState.visibleIndices.first
              : 0;
          final newFirst = event.visibleIndecies.isNotEmpty
              ? event.visibleIndecies.first
              : 0;

          if ((oldFirst - newFirst).abs() > 3) {
            index = null;
          }
        }

        final List<Link> visibleLinks;
        if (currentState.showLeftPane || index != null) {
          visibleLinks = computeVisibleLinks(
            links: currentState.links,
            visibleIndices: event.visibleIndecies,
            selectedIndex: index,
            linksByLine: currentState.linksByLine,
          );
        } else {
          visibleLinks = currentState.visibleLinks;
        }

        emit(currentState.copyWith(
          visibleIndices: event.visibleIndecies,
          currentTitle: newTitle,
          selectedIndex: index,
          clearSelectedIndex:
              index == null && currentState.selectedIndex != null,
          visibleLinks: visibleLinks,
        ));

        if (_shouldLoadLinksForVisibleIndicesChange(currentState)) {
          _loadLinksInBackground(
            currentState.book,
            event.visibleIndecies,
          );
        }
      } catch (_) {
        rethrow;
      }
    }
  }

  void _resetLoadedLinksWindow(TextBook book) {
    _loadedLinksBookTitle = book.title;
    _loadedLinksStart = null;
    _loadedLinksEnd = null;
    _loadedLinksTargetBookTitlesSignature = null;
    _activeLinksTargetBookTitlesSignature = null;
    _isLoadingLinks = false;
    _pendingLinksReload = false;
  }

  ({int start, int end}) _calculateLinksWindow(List<int> visibleIndices) {
    if (visibleIndices.isEmpty) {
      return (start: 0, end: _linkLookAheadLines);
    }

    final minVisible = visibleIndices.reduce((a, b) => a < b ? a : b);
    final maxVisible = visibleIndices.reduce((a, b) => a > b ? a : b);

    return (
      start: (minVisible - _linkLookBehindLines).clamp(0, minVisible),
      end: maxVisible + _linkLookAheadLines,
    );
  }

  bool _isLinksWindowSufficient(
    String bookTitle,
    int start,
    int end,
    String targetBookTitlesSignature,
  ) {
    return _loadedLinksBookTitle == bookTitle &&
        _loadedLinksStart != null &&
        _loadedLinksEnd != null &&
        _loadedLinksTargetBookTitlesSignature == targetBookTitlesSignature &&
        start >= (_loadedLinksStart! - _linksReloadThresholdLines) &&
        end <= (_loadedLinksEnd! + _linksReloadThresholdLines);
  }

  List<String>? _normalizeTargetBookTitles(Iterable<String>? targetBookTitles) {
    if (targetBookTitles == null) {
      return null;
    }

    return targetBookTitles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  String _targetBookTitlesSignature(Iterable<String>? targetBookTitles) {
    final normalized = _normalizeTargetBookTitles(targetBookTitles);
    if (normalized == null) {
      return _allTargetBookTitlesSignature;
    }

    return normalized.join('||');
  }

  String _serializePageShapeConfiguration(Map<String, String?>? configuration) {
    if (configuration == null) {
      return '__default__';
    }

    return [
      'left=${configuration['left'] ?? 'null'}',
      'right=${configuration['right'] ?? 'null'}',
      'bottom=${configuration['bottom'] ?? 'null'}',
      'bottomRight=${configuration['bottomRight'] ?? 'null'}',
    ].join('|');
  }

  String _serializeColumnVisibility(Map<String, bool> columnVisibility) {
    return [
      'left=${columnVisibility['left'] ?? true}',
      'right=${columnVisibility['right'] ?? true}',
      'bottom=${columnVisibility['bottom'] ?? true}',
    ].join('|');
  }

  Future<List<String>?> _resolvePageShapeTargetBookTitlesForLinks(
    TextBookLoaded state,
  ) async {
    final candidateCommentators = {
      ...state.availableCommentators,
      ...state.activeCommentators,
    }.where((commentator) => commentator.trim().isNotEmpty).toList()
      ..sort();

    if (candidateCommentators.isEmpty) {
      return null;
    }

    final storedConfiguration = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );
    final columnVisibility =
        PageShapeSettingsManager.getColumnVisibility(state.book.title);
    final cacheKey = [
      state.book.title,
      state.book.heCategories ?? '',
      candidateCommentators.join('||'),
      _serializePageShapeConfiguration(storedConfiguration),
      _serializeColumnVisibility(columnVisibility),
    ].join('::');

    if (_cachedPageShapeTargetBookTitlesKey == cacheKey) {
      return _cachedPageShapeTargetBookTitles;
    }

    final configuration = storedConfiguration ??
        await DefaultCommentators.getDefaults(
          state.book,
          availableCommentators: candidateCommentators,
        );

    final selectedCommentators = resolvePageShapeDisplayedCommentators(
      leftSelection: configuration['left'],
      rightSelection: configuration['right'],
      bottomSelection: configuration['bottom'],
      bottomRightSelection: configuration['bottomRight'],
      availableCommentators: candidateCommentators,
      columnVisibility: columnVisibility,
    );

    _cachedPageShapeTargetBookTitlesKey = cacheKey;
    _cachedPageShapeTargetBookTitles = selectedCommentators;
    return selectedCommentators;
  }

  List<String> _normalizeCommentaryTargets(Iterable<String> titles) {
    return titles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<List<String>?> _resolveTargetBookTitlesForLinks(
    TextBookLoaded state,
  ) async {
    if (state.showPageShapeView) {
      final pageShapeTargets =
          await _resolvePageShapeTargetBookTitlesForLinks(state);
      return pageShapeTargets ?? const <String>[];
    }

    if (state.showSplitView || state.activeCommentators.isNotEmpty) {
      return _normalizeCommentaryTargets(state.activeCommentators);
    }

    return const <String>[];
  }

  bool _isCommentariesBelowMode(TextBookLoaded state) {
    return !state.showSplitView && !state.showPageShapeView;
  }

  bool _shouldLoadLinksForState(TextBookLoaded state) {
    return _isCommentariesBelowMode(state) ||
        state.showSplitView ||
        state.showPageShapeView ||
        state.activeCommentators.isNotEmpty;
  }

  bool _shouldLoadLinksForVisibleIndicesChange(TextBookLoaded state) {
    return _isCommentariesBelowMode(state) ||
        state.showSplitView ||
        state.showPageShapeView ||
        state.showLeftPane;
  }

  List<int> _targetIndicesForCommentaryRefresh(TextBookLoaded state) {
    if (state.showSplitView || state.showPageShapeView) {
      return state.visibleIndices;
    }

    return state.selectedIndex != null
        ? [state.selectedIndex!]
        : state.visibleIndices;
  }

  bool _listsEqual(List<int> list1, List<int> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  bool _hasMeaningfulVisibleIndicesChange(
    List<int> currentIndices,
    List<int> nextIndices,
  ) {
    if (_listsEqual(currentIndices, nextIndices)) {
      return false;
    }

    if (currentIndices.isEmpty || nextIndices.isEmpty) {
      return true;
    }

    return currentIndices.first != nextIndices.first ||
        currentIndices.last != nextIndices.last;
  }

  bool _isContinuousReadingModeEnabled() {
    return Settings.getValue<bool>(
          SettingsRepository.keyContinuousReadingMode,
          defaultValue: false,
        ) ??
        false;
  }

  List<int> _resolveVisibleSourceIndices(
    TextBookLoaded state,
    Iterable<ItemPosition> visibleItemPositions,
  ) {
    final itemPositions = visibleItemPositions.toList();
    if (itemPositions.isEmpty) {
      return const [];
    }

    if (!_isContinuousReadingModeEnabled()) {
      return itemPositions.map((position) => position.index).toSet().toList()
        ..sort();
    }

    final segments = buildReadingSegments(
      state.content,
      continuous: true,
    );
    return sourceLineIndicesForSegmentViewports(
      segments,
      itemPositions.map(
        (position) => ReadingSegmentViewport(
          segmentIndex: position.index,
          leadingEdge: position.itemLeadingEdge,
          trailingEdge: position.itemTrailingEdge,
        ),
      ),
    );
  }

  void _onUpdateSelectedIndex(
    UpdateSelectedIndex event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      final visibleLinks = computeVisibleLinks(
        links: currentState.links,
        visibleIndices: currentState.visibleIndices,
        selectedIndex: event.index,
        linksByLine: currentState.linksByLine,
      );
      emit(currentState.copyWith(
        selectedIndex: event.index,
        clearSelectedIndex: event.index == null,
        visibleLinks: visibleLinks,
      ));
      if (_isCommentariesBelowMode(currentState) &&
          !currentState.showPageShapeView &&
          event.index != null) {
        _loadLinksInBackground(currentState.book, [event.index!]);
      }
    }
  }

  void _onHighlightLine(
    HighlightLine event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    emit(currentState.copyWith(highlightedLine: event.lineIndex));

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
        searchOptions: event.searchOptions,
        alternativeWords: event.alternativeWords,
        spacingValues: event.spacingValues,
        searchMode: event.searchMode,
        searchDistance: event.searchDistance,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onApplyFullBookContent(
    ApplyFullBookContent event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    if (currentState.book.title != event.bookTitle) {
      return;
    }

    if (listEquals(currentState.content, event.content)) {
      return;
    }

    emit(currentState.copyWith(content: event.content));
  }

  void _onCreateNoteFromToolbar(
    CreateNoteFromToolbar event,
    Emitter<TextBookState> emit,
  ) {
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

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();

    if (_positionListenerCallback != null) {
      positionsListener.itemPositions
          .removeListener(_positionListenerCallback!);
    }

    return super.close();
  }

  void _loadFullBookInBackground(TextBook book) async {
    try {
      final fullContent = await repository.getBookContent(book);

      if (fullContent.isEmpty) {
        return;
      }

      if (isClosed || state is! TextBookLoaded) {
        return;
      }

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) {
        return;
      }

      add(ApplyFullBookContent(
        bookTitle: book.title,
        content: await splitContentLines(fullContent),
      ));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ TextBookBloc::loadFullBook failed for ${book.title}: $e');
      }
    }
  }

  void _loadLinksInBackground(
    TextBook book,
    List<int> visibleIndices, {
    bool force = false,
    Iterable<String>? targetBookTitlesOverride,
  }) async {
    final runtimeStateBeforeWindowCheck = state;
    if (!force &&
        runtimeStateBeforeWindowCheck is TextBookLoaded &&
        !_shouldLoadLinksForState(runtimeStateBeforeWindowCheck)) {
      return;
    }

    final window = _calculateLinksWindow(visibleIndices);

    if (_isLoadingLinks) {
      _pendingLinksReload = true;
      return;
    }

    List<String>? targetBookTitles;
    var targetBookTitlesSignature = _allTargetBookTitlesSignature;
    if (targetBookTitlesOverride != null) {
      targetBookTitles = _normalizeTargetBookTitles(targetBookTitlesOverride);
      targetBookTitlesSignature = _targetBookTitlesSignature(targetBookTitles);
    } else {
      final runtimeState = state;
      if (runtimeState is TextBookLoaded) {
        targetBookTitles = await _resolveTargetBookTitlesForLinks(runtimeState);
        targetBookTitlesSignature =
            _targetBookTitlesSignature(targetBookTitles);
      }
    }

    if (!force &&
        _isLinksWindowSufficient(
          book.title,
          window.start,
          window.end,
          targetBookTitlesSignature,
        )) {
      _pendingLinksReload = false;
      return;
    }

    _isLoadingLinks = true;
    _pendingLinksReload = false;

    try {
      final links = await repository.getBookLinksInRange(
        book,
        startIndex: window.start,
        endIndex: window.end,
        targetBookTitles: targetBookTitles,
      );

      if (isClosed || state is! TextBookLoaded) {
        _isLoadingLinks = false;
        return;
      }

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) {
        _isLoadingLinks = false;
        return;
      }

      _loadedLinksBookTitle = book.title;
      _loadedLinksStart = window.start;
      _loadedLinksEnd = window.end;
      _loadedLinksTargetBookTitlesSignature = targetBookTitlesSignature;
      _isLoadingLinks = false;
      final replaceExistingLinks = currentState.links.isNotEmpty &&
          _activeLinksTargetBookTitlesSignature != targetBookTitlesSignature;

      add(UpdateLinks(
        links,
        replaceExisting: replaceExistingLinks,
        targetBookTitlesSignature: targetBookTitlesSignature,
      ));

      if (state is TextBookLoaded) {
        final latestState = state as TextBookLoaded;
        final latestWindow = _calculateLinksWindow(latestState.visibleIndices);
        final windowOutdated = !_isLinksWindowSufficient(
          latestState.book.title,
          latestWindow.start,
          latestWindow.end,
          targetBookTitlesSignature,
        );
        if (_pendingLinksReload || windowOutdated) {
          _loadLinksInBackground(
            latestState.book,
            latestState.visibleIndices,
          );
        }
      }
    } catch (e) {
      _isLoadingLinks = false;
      if (kDebugMode) {
        debugPrint(
          '⚠️ TextBookBloc::loadLinks failed for ${book.title} '
          '(window ${window.start}-${window.end}): $e',
        );
      }
    }
  }

  void _onUpdateLinks(
    UpdateLinks event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;
    final stateBeforeAwait = state as TextBookLoaded;
    final processedLinks = await processLinksForState(
      existingLinks: stateBeforeAwait.links,
      incomingLinks: event.links.cast<Link>(),
      replaceExisting: event.replaceExisting,
      visibleIndices: stateBeforeAwait.visibleIndices,
      selectedIndex: stateBeforeAwait.selectedIndex,
    );

    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    if (currentState.book.title != stateBeforeAwait.book.title) return;

    emit(currentState.copyWith(
      links: processedLinks.links,
      linksByLine: processedLinks.linksByLine,
      visibleLinks: processedLinks.visibleLinks,
    ));
    _activeLinksTargetBookTitlesSignature =
        event.targetBookTitlesSignature ?? _allTargetBookTitlesSignature;
  }

  void _onUpdateAvailableCommentators(
    UpdateAvailableCommentators event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      final updatedState = currentState.copyWith(
        availableCommentators: event.availableCommentators,
        commentatorGroups: event.commentatorGroups.cast<CommentatorGroup>(),
      );
      emit(updatedState);

      if (updatedState.showPageShapeView) {
        _loadLinksInBackground(updatedState.book, updatedState.visibleIndices);
      }
    }
  }

  void _onRefreshLinksForCurrentWindow(
    RefreshLinksForCurrentWindow event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    _loadLinksInBackground(
      currentState.book,
      currentState.visibleIndices,
      force: true,
    );
  }

  void _loadCommentatorsInBackground(TextBook book) async {
    try {
      final availableCommentators =
          await repository.getAvailableCommentators(book);

      final eras = await utils.splitByEra(availableCommentators);
      final groups = buildCommentatorGroups(eras, availableCommentators);

      if (isClosed || state is! TextBookLoaded) {
        return;
      }

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) {
        return;
      }

      add(UpdateAvailableCommentators(availableCommentators, groups));
    } catch (e) {
      debugPrint('⚠️ Failed to load commentators in background: $e');
    }
  }

  void _enrichHeCategoriesInBackground(TextBook book) async {
    await enrichHeCategories(book);
  }
}
