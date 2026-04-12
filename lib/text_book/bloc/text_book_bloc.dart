import 'dart:async';
import 'dart:isolate';
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
// [EDITING DISABLED] import 'package:otzaria/text_book/editing/repository/overrides_repository.dart';
// [EDITING DISABLED] import 'package:otzaria/text_book/editing/models/section_identifier.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/migration/core/models/category.dart' as db;
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

List<Link> _mergeLinksByIdentity(
  List<Link> existing,
  List<Link> incoming,
) {
  final merged = <String, Link>{
    for (final link in existing) _linkIdentityKey(link): link,
  };

  for (final link in incoming) {
    merged[_linkIdentityKey(link)] = link;
  }

  final links = merged.values.toList();
  links.sort((a, b) {
    final indexCompare = a.index1.compareTo(b.index1);
    if (indexCompare != 0) return indexCompare;

    final pathCompare = a.path2.compareTo(b.path2);
    if (pathCompare != 0) return pathCompare;

    final targetCompare = a.index2.compareTo(b.index2);
    if (targetCompare != 0) return targetCompare;

    return a.connectionType.compareTo(b.connectionType);
  });

  return links;
}

String _linkIdentityKey(Link link) {
  return '${link.index1}|${link.path2}|${link.index2}|${link.connectionType}|${link.start}|${link.end}';
}

Map<int, List<Link>> _buildLinksByLineMap(List<Link> links) {
  final linksByLine = <int, List<Link>>{};
  for (final link in links) {
    final list = linksByLine[link.index1];
    if (list == null) {
      linksByLine[link.index1] = [link];
    } else {
      list.add(link);
    }
  }
  return linksByLine;
}

List<Link> _computeVisibleLinks({
  required List<Link> links,
  required List<int> visibleIndices,
  required int? selectedIndex,
  required Map<int, List<Link>> linksByLine,
}) {
  final targetIndices =
      selectedIndex != null ? [selectedIndex] : visibleIndices;

  final visibleLinks = <Link>[];

  for (final index in targetIndices) {
    final candidates = linksByLine[index + 1] ?? const [];

    for (final link in candidates) {
      if (!LinkTypes.isCommentaryOrTargum(link.connectionType) &&
          link.start == null &&
          link.end == null) {
        visibleLinks.add(link);
      }
    }
  }

  final titles = <Link, String>{};
  final pathCache = <String, String>{};
  for (final link in visibleLinks) {
    titles[link] = pathCache.putIfAbsent(
      link.path2,
      () => utils.getTitleFromPath(link.path2),
    );
  }
  visibleLinks.sort((a, b) => titles[a]!.compareTo(titles[b]!));

  return visibleLinks;
}

Future<({List<Link> links, Map<int, List<Link>> linksByLine, List<Link> visibleLinks})>
    _processLinksForState({
  required List<Link> existingLinks,
  required List<Link> incomingLinks,
  required bool replaceExisting,
  required List<int> visibleIndices,
  required int? selectedIndex,
}) async {
  const asyncProcessingThreshold = 250;
  final estimatedLinkCount =
      (replaceExisting ? 0 : existingLinks.length) + incomingLinks.length;

  if (estimatedLinkCount <= asyncProcessingThreshold) {
    final links = _mergeLinksByIdentity(
      replaceExisting ? const [] : existingLinks,
      incomingLinks,
    );
    final linksByLine = _buildLinksByLineMap(links);
    final visibleLinks = _computeVisibleLinks(
      links: links,
      visibleIndices: visibleIndices,
      selectedIndex: selectedIndex,
      linksByLine: linksByLine,
    );
    return (
      links: links,
      linksByLine: linksByLine,
      visibleLinks: visibleLinks,
    );
  }

  return Isolate.run(() {
    final links = _mergeLinksByIdentity(
      replaceExisting ? const [] : existingLinks,
      incomingLinks,
    );
    final linksByLine = _buildLinksByLineMap(links);
    final visibleLinks = _computeVisibleLinks(
      links: links,
      visibleIndices: visibleIndices,
      selectedIndex: selectedIndex,
      linksByLine: linksByLine,
    );
    return (
      links: links,
      linksByLine: linksByLine,
      visibleLinks: visibleLinks,
    );
  });
}

List<String> _buildPreviewLines(String previewContent, int previewStartLine) {
  final previewLines = previewContent.split('\n');
  if (previewStartLine <= 0) {
    return previewLines;
  }

  return List<String>.filled(previewStartLine, '', growable: true)
    ..addAll(previewLines);
}

Future<List<String>> _splitContentLines(String content) async {
  if (content.isEmpty) {
    return const [];
  }

  return Isolate.run(() => content.split('\n'));
}

class TextBookBloc extends Bloc<TextBookEvent, TextBookState> {
  static const int _linkLookBehindLines = 25;
  static const int _linkLookAheadLines = 50;
  static const int _linksReloadThresholdLines = 20;
  static const String _allTargetBookTitlesSignature =
      '__all_target_book_titles__';

  final TextBookRepository repository;
  final Future<String?> Function(
    String title,
    int currentLine, {
    int? categoryId,
    String? fileType,
  }) _quickPreviewLoader;
  // [EDITING DISABLED] final OverridesRepository _overridesRepository;
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;

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
  bool _pendingLinksReload = false; // בקשת טעינה שנדחתה בגלל _isLoadingLinks
  bool _awaitingInitialPageShapeVisibleSync = false;

  TextBookBloc({
    required this.repository,
    Future<String?> Function(
      String title,
      int currentLine, {
      int? categoryId,
      String? fileType,
    })? quickPreviewLoader,
    // [EDITING DISABLED] required OverridesRepository overridesRepository,
    required TextBookInitial initialState,
    required this.scrollController,
    required this.positionsListener,
  })  : // [EDITING DISABLED] _overridesRepository = overridesRepository,
        _quickPreviewLoader = quickPreviewLoader ??
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

    // [EDITING DISABLED] Editor events
    // on<OpenEditor>(_onOpenEditor);
    // on<OpenFullFileEditor>(_onOpenFullFileEditor);
    // on<SaveEditedSection>(_onSaveEditedSection);
    // on<LoadDraftIfAny>(_onLoadDraftIfAny);
    // on<DiscardDraft>(_onDiscardDraft);
    // on<CloseEditor>(_onCloseEditor);
    // on<UpdateEditorText>(_onUpdateEditorText);
    // on<AutoSaveDraft>(_onAutoSaveDraft);
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
      List<Link> existing, List<Link> incoming) {
    return _mergeLinksByIdentity(existing, incoming);
  }

  @visibleForTesting
  static List<String> buildPreviewLinesForTesting(
      String previewContent, int previewStartLine) {
    return _buildPreviewLines(previewContent, previewStartLine);
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
      visibleIndices = [initial.index < 0 ? 0 : initial.index];
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
      String content = await repository.getBookContent(book);
      List<String>? contentLines;
      if (content.isEmpty) {
        // Load quick preview (40 lines) for instant display
        final preview = await _quickPreviewLoader(
          book.title,
          visibleIndices.first,
          categoryId: book.categoryId,
          fileType: book.fileType,
        );

        if (preview != null && preview.isNotEmpty) {
          final previewStartLine =
              (visibleIndices.first - 10).clamp(0, visibleIndices.first);
          contentLines = _buildPreviewLines(preview, previewStartLine);

          // Load full book in background
          _loadFullBookInBackground(book);
        } else {
          // Preview failed, load full book normally
          content = await repository.getBookContent(book);
        }
      }

      contentLines ??= await _splitContentLines(content);

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
        final rawPositions = positionsListener.itemPositions.value.toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        final visibleIndicesNow =
            rawPositions.map((position) => position.index).toList();
        final currentState = state;
        if (currentState is TextBookLoaded) {
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
        }

        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 100), () {
          if (isClosed) {
            return;
          }

          final debouncedRawPositions = positionsListener.itemPositions.value
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));
          final visibleIndicesNow =
              debouncedRawPositions.map((e) => e.index).toList();
          if (visibleIndicesNow.isNotEmpty) {
            add(UpdateVisibleIndecies(visibleIndicesNow));
          }
        });
      };

      positionsListener.itemPositions.addListener(_positionListenerCallback!);

      _setAwaitingInitialPageShapeVisibleSync(initialShowPageShapeView);

      // ── שלב 4: EMIT ראשוני - הצגת הספר מיידית! ──
      // בטעינה ראשונית: מפרשים ריקים, ייטענו ברקע
      // ב-preserveState: שימור מפרשים קיימים כדי למנוע הבהוב
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
            : (showLeftPane || searchText.isNotEmpty),
        showSplitView: event.showSplitView,
        showPageShapeView: initialShowPageShapeView,
        activeCommentators: commentators,
        commentatorGroups: existingCommentatorGroups,
        removeNikud: removeNikud,
        isTanach: isTanach,
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
      _resetLoadedLinksWindow(book);

      // טעינת קישורים ברקע אחרי הצגת הספר
      _loadLinksInBackground(
        book,
        visibleIndices,
      );

      // טעינת מפרשים ברקע (רשימת מפרשים זמינים + חלוקה לתקופות)
      if (event.loadCommentators) {
        _loadCommentatorsInBackground(book);
      }

      // העשרת heCategories ברקע (אם חסר)
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
            ? _computeVisibleLinks(
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
      // שמירת ההגדרה ב-Settings כדי שתישמר כברירת מחדל
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
      _setAwaitingInitialPageShapeVisibleSync(event.show);
      final updatedState = currentState.copyWith(
        showPageShapeView: event.show,
        showTzuratHadafView: false, // כיבוי התצוגה הישנה
        selectedIndex: currentState.selectedIndex,
        // סגור את חלונית הניווט/חיפוש כשעוברים לצורת הדף
        showLeftPane: event.show ? false : currentState.showLeftPane,
      );
      emit(updatedState);
      _loadLinksInBackground(
        updatedState.book,
        updatedState.visibleIndices,
        force: true,
      );

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
      final updatedState = currentState.copyWith(
        activeCommentators: event.commentators,
        selectedIndex: currentState.selectedIndex,
      );
      emit(updatedState);
      if (_shouldLoadLinksForState(updatedState)) {
        final targetIndices =
            _targetIndicesForCommentaryRefresh(updatedState);
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

      // בדיקה אם האינדקסים באמת השתנו
      if (_listsEqual(currentState.visibleIndices, event.visibleIndecies)) {
        return; // אין שינוי, לא צריך לעדכן
      }

      try {
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
          final newFirst = event.visibleIndecies.isNotEmpty
              ? event.visibleIndecies.first
              : 0;

          // רק אם גללנו יותר מ-3 שורות, נאפס את הבחירה
          if ((oldFirst - newFirst).abs() > 3) {
            index = null;
          }
        }

        // אופטימיזציה: חישוב ומיון קישורים נראים רק אם החלונית פתוחה או שיש שורה נבחרת לתפריט ההקשר
        final List<Link> visibleLinks;
        if (currentState.showLeftPane || index != null) {
          visibleLinks = _computeVisibleLinks(
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
          clearSelectedIndex: index == null && currentState.selectedIndex != null,
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

    final normalized = targetBookTitles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return normalized;
  }

  String _targetBookTitlesSignature(Iterable<String>? targetBookTitles) {
    final normalizedTargetBookTitles =
        _normalizeTargetBookTitles(targetBookTitles);
    if (normalizedTargetBookTitles == null) {
      return _allTargetBookTitlesSignature;
    }

    return normalizedTargetBookTitles.join('||');
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

  bool _shouldLoadLinksForState(TextBookLoaded state) {
    return state.showSplitView ||
        state.showPageShapeView ||
        state.activeCommentators.isNotEmpty;
  }

  bool _shouldLoadLinksForVisibleIndicesChange(TextBookLoaded state) {
    return state.showSplitView || state.showPageShapeView || state.showLeftPane;
  }

  List<int> _targetIndicesForCommentaryRefresh(TextBookLoaded state) {
    if (state.showSplitView || state.showPageShapeView) {
      return state.visibleIndices;
    }

    return state.selectedIndex != null
        ? [state.selectedIndex!]
        : state.visibleIndices;
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
      final visibleLinks = _computeVisibleLinks(
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
      // במצב מפרשים מתחת, קישורים לא נטענים ברקע באופן שוטף —
      // נטען עבור הקטע הנבחר כדי להציג expansion tiles
      if (!currentState.showSplitView &&
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

      // שליחת event לפלאגינים רק אם יש טקסט לא-ריק
      final text = event.text;
      if (text != null && text.trim().isNotEmpty) {
        final bookId = currentState.book.title;
        unawaited(PluginRuntimeDispatcher.instance.dispatchEvent(
          'reader.selection_changed',
          {
            'text': text,
            'start': event.start,
            'end': event.end,
            'currentRef': currentState.currentTitle,
            'currentBook': bookId,
            'currentBookId': bookId,
            'currentIndex': currentState.visibleIndices.isNotEmpty
                ? currentState.visibleIndices.first
                : 0,
          },
        ));
      }
    }
  }

  // [EDITING DISABLED] - All editor event handlers commented out
  // Future<void> _onOpenEditor(
  //   OpenEditor event,
  //   Emitter<TextBookState> emit,
  // ) async {
  //   if (state is! TextBookLoaded) return;
  //
  //   final currentState = state as TextBookLoaded;
  //
  //   try {
  //     // Generate section identifier
  //     final content = currentState.content[event.index];
  //     final sectionId = SectionIdentifier.fromContent(
  //       content: content,
  //       index: event.index,
  //     );
  //
  //     // Check if book has links file
  //     final hasLinks =
  //         await _overridesRepository.hasLinksFile(currentState.book.title);
  //
  //     // Load existing override or original content
  //     final override = await _overridesRepository.readOverride(
  //       currentState.book.title,
  //       sectionId.sectionId,
  //     );
  //
  //     final editorText = override?.markdownContent ?? content;
  //
  //     // Check for draft
  //     final hasDraft = await _overridesRepository.hasNewerDraftThanOverride(
  //       currentState.book.title,
  //       sectionId.sectionId,
  //     );
  //
  //     emit(currentState.copyWith(
  //       isEditorOpen: true,
  //       editorIndex: event.index,
  //       editorSectionId: sectionId.sectionId,
  //       editorText: editorText,
  //       hasDraft: hasDraft,
  //       hasLinksFile: hasLinks,
  //     ));
  //   } catch (e) {
  //     // Handle error - could emit error state or show notification
  //   }
  // }
  //
  // Future<void> _onOpenFullFileEditor(
  //   OpenFullFileEditor event,
  //   Emitter<TextBookState> emit,
  // ) async {
  //   if (state is! TextBookLoaded) return;
  //
  //   final currentState = state as TextBookLoaded;
  //
  //   try {
  //     // Combine all content into one string
  //     final fullContent = currentState.content.join('\n\n');
  //
  //     // We don't need section identifier for full file - using fixed ID
  //
  //     // Check if book has links file
  //     final hasLinks =
  //         await _overridesRepository.hasLinksFile(currentState.book.title);
  //
  //     // Load existing override or original content
  //     final override = await _overridesRepository.readOverride(
  //       currentState.book.title,
  //       'full_file',
  //     );
  //
  //     final editorText = override?.markdownContent ?? fullContent;
  //
  //     // Check for draft
  //     final hasDraft = await _overridesRepository.hasNewerDraftThanOverride(
  //       currentState.book.title,
  //       'full_file',
  //     );
  //
  //     emit(currentState.copyWith(
  //       isEditorOpen: true,
  //       editorIndex: -1, // Special index for full file
  //       editorSectionId: 'full_file',
  //       editorText: editorText,
  //       hasDraft: hasDraft,
  //       hasLinksFile: hasLinks,
  //     ));
  //   } catch (e) {
  //     // Debug: Error in _onOpenFullFileEditor: $e
  //     // Handle error - could emit error state or show notification
  //   }
  // }
  //
  // Future<void> _onSaveEditedSection(
  //   SaveEditedSection event,
  //   Emitter<TextBookState> emit,
  // ) async {
  //   if (state is! TextBookLoaded) return;
  //
  //   final currentState = state as TextBookLoaded;
  //
  //   try {
  //     // Handle full file editing differently
  //     if (event.sectionId == 'full_file' && event.index == -1) {
  //       // For full file editing, save the entire content to the original file
  //       await repository.saveBookContent(currentState.book, event.markdown);
  //
  //       // Split the content back into sections for display
  //       final sections = event.markdown
  //           .split('\n\n')
  //           .where((s) => s.trim().isNotEmpty)
  //           .toList();
  //
  //       // If we have fewer sections than before, pad with empty strings
  //       while (sections.length < currentState.content.length) {
  //         sections.add('');
  //       }
  //
  //       // Reload content to ensure we have the latest version
  //       add(LoadContent(
  //         fontSize: currentState.fontSize,
  //         showSplitView: currentState.showSplitView,
  //         removeNikud: currentState.removeNikud,
  //         preserveState: true,
  //       ));
  //
  //       return;
  //     }
  //
  //     // Regular section editing - update the specific section and save the entire file
  //     final updatedContent = List<String>.from(currentState.content);
  //     updatedContent[event.index] = event.markdown;
  //
  //     // Join all sections back together and save to original file
  //     final fullContent = updatedContent.join('\n\n');
  //     await repository.saveBookContent(currentState.book, fullContent);
  //
  //     // Close editor immediately
  //     emit(currentState.copyWith(
  //       isEditorOpen: false,
  //       editorIndex: null,
  //       editorSectionId: null,
  //       editorText: null,
  //       hasDraft: false,
  //     ));
  //
  //     // Reload content to ensure we have the latest version from the file system
  //     add(LoadContent(
  //       fontSize: currentState.fontSize,
  //       showSplitView: currentState.showSplitView,
  //       removeNikud: currentState.removeNikud,
  //       preserveState: true,
  //     ));
  //   } catch (e) {
  //     // Debug: Error in _onSaveEditedSection: $e
  //     // Handle error - could show error message to user
  //   }
  // }
  //
  // Future<void> _onLoadDraftIfAny(
  //   LoadDraftIfAny event,
  //   Emitter<TextBookState> emit,
  // ) async {
  //   if (state is! TextBookLoaded) return;
  //
  //   final currentState = state as TextBookLoaded;
  //
  //   try {
  //     final draft = await _overridesRepository.readDraft(
  //       currentState.book.title,
  //       event.sectionId,
  //     );
  //
  //     if (draft != null) {
  //       emit(currentState.copyWith(
  //         editorText: draft.markdownContent,
  //         hasDraft: false, // Draft is now loaded, so no longer "pending"
  //       ));
  //     }
  //   } catch (e) {
  //     // Handle error
  //   }
  // }
  //
  // Future<void> _onDiscardDraft(
  //   DiscardDraft event,
  //   Emitter<TextBookState> emit,
  // ) async {
  //   if (state is! TextBookLoaded) return;
  //
  //   final currentState = state as TextBookLoaded;
  //
  //   try {
  //     await _overridesRepository.deleteDraft(
  //       currentState.book.title,
  //       event.sectionId,
  //     );
  //
  //     emit(currentState.copyWith(hasDraft: false));
  //   } catch (e) {
  //     // Handle error
  //   }
  // }
  //
  // Future<void> _onCloseEditor(
  //   CloseEditor event,
  //   Emitter<TextBookState> emit,
  // ) async {
  //   if (state is! TextBookLoaded) return;
  //
  //   final currentState = state as TextBookLoaded;
  //
  //   emit(currentState.copyWith(
  //     isEditorOpen: false,
  //     editorIndex: null,
  //     editorSectionId: null,
  //     editorText: null,
  //     hasDraft: false,
  //   ));
  // }
  //
  // Future<void> _onUpdateEditorText(
  //   UpdateEditorText event,
  //   Emitter<TextBookState> emit,
  // ) async {
  //   if (state is! TextBookLoaded) return;
  //
  //   final currentState = state as TextBookLoaded;
  //
  //   emit(currentState.copyWith(editorText: event.text));
  // }
  //
  // Future<void> _onAutoSaveDraft(
  //   AutoSaveDraft event,
  //   Emitter<TextBookState> emit,
  // ) async {
  //   if (state is! TextBookLoaded) return;
  //
  //   final currentState = state as TextBookLoaded;
  //
  //   try {
  //     await _overridesRepository.writeDraft(
  //       currentState.book.title,
  //       event.sectionId,
  //       event.markdown,
  //     );
  //
  //     // Don't emit state change for auto-save to avoid unnecessary rebuilds
  //   } catch (e) {
  //     // Handle error silently for auto-save
  //   }
  // }

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
  ) async {
    try {
      // Load full content
      final fullContent = await repository.getBookContent(book);

      if (fullContent.isEmpty) {
        return;
      }

      // Check if still in the same book (user might have navigated away)
      if (isClosed || state is! TextBookLoaded) {
        return;
      }

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) {
        return;
      }

      add(ApplyFullBookContent(
        bookTitle: book.title,
        content: await _splitContentLines(fullContent),
      ));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ TextBookBloc::loadFullBook failed for ${book.title}: $e');
      }
      // Silent fail - user already has preview
    }
  }

  /// Loads links in the background after the book is displayed
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
      // בקשה חדשה הגיעה בזמן שטעינה אחרת רצה — מסמנים לנסות שוב אחריה
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
      targetBookTitlesSignature = _targetBookTitlesSignature(targetBookTitles);
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

      // Check if still in the same book
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

      // Use event to update links
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
      // Silent fail - user already has the book displayed
    }
  }

  void _onUpdateLinks(
    UpdateLinks event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;
    final stateBeforeAwait = state as TextBookLoaded;
    final processedLinks = await _processLinksForState(
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

  /// Handler for updating available commentators after background loading
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

  /// Loads available commentators in the background after the book is displayed
  void _loadCommentatorsInBackground(TextBook book) async {
    try {
      final availableCommentators =
          await repository.getAvailableCommentators(book);
      final eras = await utils.splitByEra(availableCommentators);
      final groups = _buildCommentatorGroups(eras, availableCommentators);

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
      // Silent fail - user already has the book displayed
    }
  }

  /// Enriches heCategories metadata in the background after the book is displayed
  void _enrichHeCategoriesInBackground(TextBook book) async {
    if (book.heCategories != null && book.heCategories!.isNotEmpty) {
      return;
    }

    try {
      // ניסיון 1: טעינה ממסד הנתונים
      final sqliteProvider = SqliteDataProvider.instance;
      if (await sqliteProvider.databaseExists() &&
          sqliteProvider.isInitialized) {
        final dbRepo = sqliteProvider.repository;
        if (dbRepo != null) {
          final dbBook = book.categoryId != null
              ? await dbRepo.getBookByTitleAndCategory(
                  book.title,
                  book.categoryId!,
                )
              : await dbRepo.getBookByTitle(book.title);
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
          // titleToPath יכול להכיל נתיב קובץ (FS) או נתיב קטגוריה מה-DB.
          if (bookPath.contains(Platform.pathSeparator)) {
            final pathParts = bookPath.split(Platform.pathSeparator);
            final otzariaIndex = pathParts.indexOf('אוצריא');
            if (otzariaIndex >= 0 && otzariaIndex < pathParts.length - 2) {
              final categories =
                  pathParts.sublist(otzariaIndex + 1, pathParts.length - 1);
              book.heCategories = categories.join(', ');
              debugPrint(
                  '📚 Background: נטען heCategories מהנתיב: "${book.heCategories}"');
            }
          } else {
            final normalizedCategories = bookPath
                .split(',')
                .map((part) => part.trim())
                .where((part) => part.isNotEmpty)
                .join(', ');
            if (normalizedCategories.isNotEmpty) {
              book.heCategories = normalizedCategories;
              debugPrint(
                  '📚 Background: נטען heCategories מנתיב קטגוריה: "${book.heCategories}"');
            }
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
