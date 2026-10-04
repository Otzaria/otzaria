import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_event.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_state.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_feedback_snapshots.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/repository/semantic_results_source.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show MergedSibling;

export 'semantic_results_event.dart';
export 'semantic_results_state.dart';

/// האם התוצאה מספר אישי (או מקור שאינו הספרייה); בספק — כן.
typedef SemanticUserBookResolver = Future<bool> Function(SemanticResultItem);

/// הפסקה המלאה של התוצאה; `null` כשלא נמצאה.
typedef SemanticPassageResolver = Future<String?> Function(SemanticResultItem);

/// ציבורי רק ספר שפוענח ומקורו הספרייה הרשמית; כל השאר (גם מפתח שלא
/// פוענח — לספר אישי יכול להיות מפתח ext:) נחשב פרטי.
bool semanticResultIsPrivate(Book? book) => !(book?.source.isOfficial ?? false);

/// תלויות הטלמטריה; ברירת המחדל [SearchFeedbackService.instance], בגישה הראשונה.
class SemanticFeedbackPorts {
  SemanticFeedbackPorts({
    SearchFeedbackRecorder Function()? recorder,
    SearchFeedbackConsentStore Function()? consent,
    String Function()? newId,
    Future<void> Function()? whenQueued,
  }) : _recorder = recorder ?? (() => SearchFeedbackService.instance),
       _consent = consent ?? (() => SearchFeedbackService.instance),
       _newId = newId ?? (() => SearchFeedbackService.instance.newId()),
       _whenQueued =
           whenQueued ?? (() => SearchFeedbackService.instance.whenQueued());

  final SearchFeedbackRecorder Function() _recorder;
  final SearchFeedbackConsentStore Function() _consent;
  final String Function() _newId;
  final Future<void> Function() _whenQueued;

  SearchFeedbackRecorder get recorder => _recorder();
  SearchFeedbackConsentStore get consent => _consent();
  String newId() => _newId();

  /// מסתיים כשהאירועים שנרשמו נכתבו לתור.
  Future<void> whenQueued() => _whenQueued();
}

/// תוצאות החיפוש הסמנטי של כרטיסייה אחת, והטלמטריה שלהן.
class SemanticResultsBloc
    extends Bloc<SemanticResultsEvent, SemanticResultsState> {
  SemanticResultsBloc({
    SemanticSourceResolver? resolveSource,
    SemanticFeedbackPorts? feedback,
    SemanticUserBookResolver? isUserBook,
    SemanticPassageResolver? resolvePassage,
    DateTime Function()? clock,
    this.pageSize = 30,
  }) : _resolveSource = resolveSource ?? resolveSemanticResultsSource,
       _feedback = feedback ?? SemanticFeedbackPorts(),
       _isUserBook = isUserBook ?? ((item) async => true),
       _resolvePassage = resolvePassage ?? resolveSemanticPassage,
       _clock = clock ?? DateTime.now,
       super(const SemanticResultsState()) {
    on<SemanticSearchSubmitted>(_onSubmitted);
    on<SemanticMoreResultsRequested>(_onMoreRequested);
    on<SemanticSearchCancelRequested>(_onCancelRequested);
    on<SemanticVoteToggled>(_onVoteToggled);
  }

  final int pageSize;
  final SemanticSourceResolver _resolveSource;
  final SemanticFeedbackPorts _feedback;
  final SemanticUserBookResolver _isUserBook;
  final SemanticPassageResolver _resolvePassage;
  final DateTime Function() _clock;

  SemanticResultsSource? _source;
  SemanticSearchContext? _context;
  final List<bool> _userBookFlags = [];
  int _generation = 0;

  /// ההקשר של החיפוש האחרון שהוצג; `null` לפני חיפוש.
  SemanticSearchContext? get searchContext => _context;

  /// האם התוצאה במיקום [index] מספר אישי (בספק — כן).
  bool isUserBookAt(int index) =>
      index < 0 || index >= _userBookFlags.length || _userBookFlags[index];

  bool get _isCollecting {
    try {
      return _feedback.consent.consent == SearchFeedbackConsent.granted &&
          _feedback.recorder.isCollecting;
    } catch (error) {
      debugPrint('[SemanticResults] consent: $error');
      return false;
    }
  }

  Future<void> _onSubmitted(
    SemanticSearchSubmitted event,
    Emitter<SemanticResultsState> emit,
  ) async {
    final generation = ++_generation;
    _source?.cancel();
    _context = null;
    _userBookFlags.clear();
    final options = event.options;
    emit(
      SemanticResultsState(
        status: SemanticResultsStatus.loading,
        options: options,
        searchId: generation,
      ),
    );
    if (_feedback.consent.consent != SearchFeedbackConsent.granted) {
      emit(
        state.copyWith(
          status: SemanticResultsStatus.unavailable,
          message: SemanticSearchMessages.consentRequired,
        ),
      );
      return;
    }
    SemanticResultsSource? source;
    try {
      source = await _resolveSource();
    } catch (error, stackTrace) {
      debugPrint('[SemanticResults] source: $error\n$stackTrace');
    }
    if (generation != _generation) return;
    if (source == null) {
      emit(
        state.copyWith(
          status: SemanticResultsStatus.unavailable,
          message: SemanticSearchMessages.notReady,
        ),
      );
      return;
    }
    _source = source;
    final startedAt = _clock();
    final page = await _fetch(source, options, 0, generation, emit);
    if (page == null || generation != _generation) return;

    final engine = await _engineSnapshot(source);
    final flags = await _userFlags(page.items);
    if (generation != _generation) return;
    final context = _context = SemanticSearchContext(
      searchSessionId: _feedback.newId(),
      query: options.query,
      startedAt: startedAt,
      params: buildSemanticParamsSnapshot(
        options,
        pageSize: pageSize,
        ranking: source.ranking,
      ),
      response: buildSemanticResponseSnapshot(page),
      engine: engine,
    );
    _userBookFlags.addAll(flags);
    emit(
      state.copyWith(
        status: SemanticResultsStatus.loaded,
        items: page.items,
        pageableTotal: page.pageableTotal,
        isDebugPreview: source.isDebugPreview,
      ),
    );
    if (_isCollecting) {
      _feedback.recorder.recordSearch(context);
      _recordShown(context, 0, page.items);
    }
  }

  Future<void> _onMoreRequested(
    SemanticMoreResultsRequested event,
    Emitter<SemanticResultsState> emit,
  ) async {
    final source = _source;
    final options = state.options;
    if (source == null ||
        options == null ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }
    final generation = _generation;
    final offset = state.items.length;
    emit(state.copyWith(isLoadingMore: true));
    final page = await _fetch(source, options, offset, generation, emit);
    if (generation != _generation) return;
    if (page == null) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }
    final flags = await _userFlags(page.items);
    if (generation != _generation) return;
    _userBookFlags.addAll(flags);
    emit(
      state.copyWith(
        isLoadingMore: false,
        items: [...state.items, ...page.items],
        // עמוד ריק אומר שאין עוד, גם כשהספירה מקורבת.
        pageableTotal: page.items.isEmpty
            ? state.items.length
            : page.pageableTotal,
      ),
    );
    final context = _context;
    if (context != null && _isCollecting && page.items.isNotEmpty) {
      _recordShown(context, offset, page.items);
    }
  }

  void _onCancelRequested(
    SemanticSearchCancelRequested event,
    Emitter<SemanticResultsState> emit,
  ) {
    if (state.status != SemanticResultsStatus.loading && !state.isLoadingMore) {
      return;
    }
    _generation++;
    _source?.cancel();
    emit(
      state.status == SemanticResultsStatus.loading
          ? state.copyWith(status: SemanticResultsStatus.cancelled)
          : state.copyWith(isLoadingMore: false),
    );
  }

  void _onVoteToggled(
    SemanticVoteToggled event,
    Emitter<SemanticResultsState> emit,
  ) {
    final index = event.index;
    if (index < 0 || index >= state.items.length) return;
    final votes = Map<int, SearchFeedbackVote>.of(state.votes);
    final SearchFeedbackVote recorded;
    if (votes[index] == event.vote) {
      votes.remove(index);
      recorded = SearchFeedbackVote.cleared;
    } else {
      votes[index] = event.vote;
      recorded = event.vote;
    }
    emit(state.copyWith(votes: votes));
    final context = _context;
    if (context == null || isUserBookAt(index) || !_isCollecting) return;
    unawaited(
      _fullSnapshot(
        state.items[index],
        index,
        isUserBook: false,
      ).then(
        (snapshot) =>
            _feedback.recorder.recordVote(context, snapshot, recorded),
      ),
    );
  }

  /// רושם פתיחה של התוצאה [index] (או של [sibling] שבכרטיס שלה) ומחזיר את
  /// ה-openId למעקב העיון; `null` כשאין מה לרשום (ספר אישי, אין הסכמה).
  Future<String?> recordOpen(
    int index,
    SearchFeedbackOpenVia via, {
    MergedSibling? sibling,
  }) async {
    final context = _context;
    if (context == null ||
        index < 0 ||
        index >= state.items.length ||
        !_isCollecting) {
      return null;
    }
    final parent = state.items[index];
    final item = sibling == null ? parent : parent.forSibling(sibling);
    final isUserBook = sibling == null
        ? isUserBookAt(index)
        : await _isUserBook(item).catchError((Object _) => true);
    if (isUserBook) return null;
    final snapshot = await _fullSnapshot(item, index, isUserBook: false);
    if (!identical(context, _context) || !_isCollecting) return null;
    return _feedback.recorder.recordOpen(context, snapshot, via);
  }

  /// מדווח על זמן העיון בתוצאה שנפתחה ב-[recordOpen]; מסתיים כשנכתב לתור.
  Future<void> recordDwell(
    SemanticSearchContext context,
    String openId,
    Duration dwell,
    SearchFeedbackDwellEnd end,
  ) async {
    if (!_isCollecting) return;
    _feedback.recorder.recordDwell(context, openId, dwell, end);
    await _feedback.whenQueued();
  }

  Future<SemanticResultsPage?> _fetch(
    SemanticResultsSource source,
    SemanticQueryOptions options,
    int offset,
    int generation,
    Emitter<SemanticResultsState> emit,
  ) async {
    String? failure;
    try {
      final page = await source.fetch(
        options,
        offset: offset,
        limit: pageSize,
      );
      if (page != null || generation != _generation) return page;
      // הוחלף בלי חיפוש חדש — כלומר בוטל.
      if (offset == 0) {
        emit(state.copyWith(status: SemanticResultsStatus.cancelled));
      }
      return null;
    } on SemanticFailure catch (error) {
      failure = SemanticSearchMessages.failure(error.kind);
    } catch (error, stackTrace) {
      debugPrint('[SemanticResults] fetch: $error\n$stackTrace');
      failure = SemanticSearchMessages.internal;
    }
    if (generation != _generation) return null;
    emit(
      offset == 0
          ? state.copyWith(
              status: SemanticResultsStatus.failed,
              message: failure,
            )
          : state.copyWith(isLoadingMore: false, message: failure),
    );
    return null;
  }

  Future<SemanticEngineSnapshot> _engineSnapshot(
    SemanticResultsSource source,
  ) async {
    try {
      return await source.engineSnapshot();
    } catch (error) {
      debugPrint('[SemanticResults] engineSnapshot: $error');
      return const SemanticEngineSnapshot();
    }
  }

  Future<List<bool>> _userFlags(List<SemanticResultItem> items) => Future.wait([
    for (final item in items) _isUserBook(item).catchError((Object _) => true),
  ]);

  void _recordShown(
    SemanticSearchContext context,
    int offset,
    List<SemanticResultItem> items,
  ) {
    _feedback.recorder.recordResultsShown(context, offset, [
      for (var i = 0; i < items.length; i++)
        buildSemanticResultSnapshot(
          items[i],
          rank: semanticResultRank(offset, i),
          isUserBook: isUserBookAt(offset + i),
        ),
    ]);
  }

  Future<SemanticResultSnapshot> _fullSnapshot(
    SemanticResultItem item,
    int index, {
    required bool isUserBook,
  }) async {
    String? passage;
    try {
      passage = await _resolvePassage(item);
    } catch (error) {
      debugPrint('[SemanticResults] passage: $error');
    }
    return buildSemanticResultSnapshot(
      item,
      rank: semanticResultRank(0, index),
      isUserBook: isUserBook,
      passageText: passage == null || passage.trim().isEmpty ? null : passage,
    );
  }

  @override
  Future<void> close() {
    _generation++;
    _source?.cancel();
    return super.close();
  }
}
