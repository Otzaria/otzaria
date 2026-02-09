import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:pdfrx/pdfrx.dart';

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  final HistoryRepository _repository;
  String? _currentWorkspaceName;
  Timer? _debounce;
  final Map<String, Bookmark> _pendingSnapshots = {};

  HistoryBloc(this._repository) : super(HistoryInitial()) {
    on<LoadHistory>(_onLoadHistory);
    on<SetCurrentWorkspaceName>(_onSetCurrentWorkspaceName);
    on<AddHistory>(_onAddHistory);
    on<BulkAddHistory>(_onBulkAddHistory);
    on<RemoveHistory>(_onRemoveHistory);
    on<ClearHistory>(_onClearHistory);
    on<CaptureStateForHistory>(_onCaptureStateForHistory);
    on<FlushHistory>(_onFlushHistory);

    add(LoadHistory());
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    if (_pendingSnapshots.isNotEmpty) {
      final snapshots = _pendingSnapshots.values.toList();
      _pendingSnapshots.clear();
      _updateAndSaveHistory(snapshots);
    }
    return super.close();
  }

  Future<List<Bookmark>> _updateAndSaveHistory(List<Bookmark> snapshots) async {
    final updatedHistory = List<Bookmark>.from(state.history);

    for (final bookmark in snapshots) {
      final existingIndex =
          updatedHistory.indexWhere((b) => b.historyKey == bookmark.historyKey);
      if (existingIndex >= 0) {
        updatedHistory.removeAt(existingIndex);
      }
      updatedHistory.insert(0, bookmark);
    }

    const maxHistorySize = 200;
    if (updatedHistory.length > maxHistorySize) {
      updatedHistory.removeRange(maxHistorySize, updatedHistory.length);
    }

    await _repository.saveHistory(updatedHistory);
    return updatedHistory;
  }

  Future<Bookmark?> _bookmarkFromTab(OpenedTab tab) async {
    final workspaceName = _currentWorkspaceName;

    if (tab is SearchingTab) {
      final searchingTab = tab;
      final text = searchingTab.queryController.text;
      if (text.trim().isEmpty) return null;

      final formattedQuery = _buildFormattedQuery(searchingTab);

      return Bookmark(
        ref: formattedQuery,
        book: TextBook(title: text), // Use the original text for the book title
        index: 0, // No specific index for a search
        isSearch: true,
        searchOptions: searchingTab.searchOptions,
        alternativeWords: searchingTab.alternativeWords,
        spacingValues: searchingTab.spacingValues,
        workspaceName: workspaceName,
      );
    }

    if (tab is TextBookTab) {
      final blocState = tab.bloc.state;
      if (blocState is TextBookLoaded && blocState.visibleIndices.isNotEmpty) {
        final index = blocState.visibleIndices.first;
        String ref =
            await refFromIndex(index, Future.value(blocState.tableOfContents));
        // הוספת שם הספר לכותרת
        ref = addBookTitleToRef(ref, blocState.book.title);
        return Bookmark(
          ref: ref,
          book: blocState.book,
          index: index,
          commentatorsToShow: blocState.activeCommentators,
          workspaceName: workspaceName,
        );
      }
    } else if (tab is PdfBookTab) {
      if (!tab.pdfViewerController.isReady) return null;
      final page = tab.pdfViewerController.pageNumber ?? 1;

      // נסה למצוא כותרת מה-outline
      String ref;
      final outline = tab.outline.value;
      if (outline != null && outline.isNotEmpty) {
        final heading = _findHeadingForPage(outline, page);
        if (heading != null) {
          ref = '${tab.title} $heading'; // שם הספר + הכותרת
        } else {
          ref = '${tab.title} עמוד $page'; // אם אין כותרת, הצג עם מספר עמוד
        }
      } else {
        ref = '${tab.title} עמוד $page'; // אם אין outline, הצג עם מספר עמוד
      }

      return Bookmark(
        ref: ref,
        book: tab.book,
        index: page,
        workspaceName: workspaceName,
      );
    }
    return null;
  }

  /// מוצא את הכותרת המתאימה לעמוד מסוים ב-outline
  String? _findHeadingForPage(List<PdfOutlineNode> outline, int page) {
    PdfOutlineNode? bestMatch;

    void searchNodes(List<PdfOutlineNode> nodes) {
      for (final node in nodes) {
        final nodePage = node.dest?.pageNumber;
        if (nodePage != null && nodePage <= page) {
          // אם זה העמוד המדויק או קרוב יותר מהמצא הקודם
          if (bestMatch == null ||
              nodePage > (bestMatch!.dest?.pageNumber ?? 0)) {
            bestMatch = node;
          }
          // חפש גם בילדים
          if (node.children.isNotEmpty) {
            searchNodes(node.children);
          }
        }
      }
    }

    searchNodes(outline);
    return bestMatch?.title;
  }

  String _buildFormattedQuery(SearchingTab tab) {
    final text = tab.queryController.text;
    if (text.trim().isEmpty) return '';

    final words = text.trim().split(RegExp(r'\\s+'));
    final List<String> parts = [];

    const Map<String, String> optionAbbreviations = {
      'קידומות': 'ק',
      'סיומות': 'ס',
      'קידומות דקדוקיות': 'קד',
      'סיומות דקדוקיות': 'סד',
      'כתיב מלא/חסר': 'מח',
      'חלק ממילה': 'חמ',
    };

    const Set<String> suffixOptions = {
      'סיומות',
      'סיומות דקדוקיות',
    };

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final wordKey = '${word}_$i';

      final wordOptions = tab.searchOptions[wordKey];
      final selectedOptions = wordOptions?.entries
              .where((entry) => entry.value)
              .map((entry) => entry.key)
              .toList() ??
          [];

      final alternativeWords = tab.alternativeWords[i] ?? [];

      final prefixes = selectedOptions
          .where((opt) => !suffixOptions.contains(opt))
          .map((opt) => optionAbbreviations[opt] ?? opt)
          .toList();

      final suffixes = selectedOptions
          .where((opt) => suffixOptions.contains(opt))
          .map((opt) => optionAbbreviations[opt] ?? opt)
          .toList();

      String wordPart = '';
      if (prefixes.isNotEmpty) {
        wordPart += '(${prefixes.join(',')})';
      }
      wordPart += word;

      if (alternativeWords.isNotEmpty) {
        wordPart += ' או ${alternativeWords.join(' או ')}';
      }

      if (suffixes.isNotEmpty) {
        wordPart += '(${suffixes.join(',')})';
      }

      parts.add(wordPart);
    }

    String result = '';
    for (int i = 0; i < parts.length; i++) {
      result += parts[i];
      if (i < parts.length - 1) {
        final spacingKey = '$i-${i + 1}';
        final spacingValue = tab.spacingValues[spacingKey];
        if (spacingValue != null && spacingValue.isNotEmpty) {
          result += ' +$spacingValue ';
        } else {
          result += ' + ';
        }
      }
    }

    return result;
  }

  Future<void> _onCaptureStateForHistory(
      CaptureStateForHistory event, Emitter<HistoryState> emit) async {
    _debounce?.cancel();
    final bookmark = await _bookmarkFromTab(event.tab);
    if (bookmark != null) {
      _pendingSnapshots[bookmark.historyKey] = bookmark;
    }
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      if (_pendingSnapshots.isNotEmpty) {
        add(BulkAddHistory(List.from(_pendingSnapshots.values)));
        _pendingSnapshots.clear();
      }
    });
  }

  void _onFlushHistory(FlushHistory event, Emitter<HistoryState> emit) {
    _debounce?.cancel();
    if (_pendingSnapshots.isNotEmpty) {
      add(BulkAddHistory(List.from(_pendingSnapshots.values)));
      _pendingSnapshots.clear();
    }
  }

  Future<void> _onLoadHistory(
      LoadHistory event, Emitter<HistoryState> emit) async {
    try {
      emit(HistoryLoading(state.history));
      final history = await _repository.loadHistory();
      emit(HistoryLoaded(history));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  void _onSetCurrentWorkspaceName(
      SetCurrentWorkspaceName event, Emitter<HistoryState> emit) {
    _currentWorkspaceName = event.workspaceName;
  }

  Future<void> _onAddHistory(
      AddHistory event, Emitter<HistoryState> emit) async {
    try {
      final bookmark = await _bookmarkFromTab(event.tab);
      if (bookmark == null) return;
      add(BulkAddHistory([bookmark]));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  Future<void> _onBulkAddHistory(
      BulkAddHistory event, Emitter<HistoryState> emit) async {
    if (event.snapshots.isEmpty) return;
    try {
      final updatedHistory = await _updateAndSaveHistory(event.snapshots);
      emit(HistoryLoaded(updatedHistory));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  Future<void> _onRemoveHistory(
      RemoveHistory event, Emitter<HistoryState> emit) async {
    try {
      final updatedHistory = List<Bookmark>.from(state.history)
        ..removeAt(event.index);
      await _repository.saveHistory(updatedHistory);
      emit(HistoryLoaded(updatedHistory));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  Future<void> _onClearHistory(
      ClearHistory event, Emitter<HistoryState> emit) async {
    try {
      await _repository.clearHistory();
      emit(HistoryLoaded([]));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }
}
