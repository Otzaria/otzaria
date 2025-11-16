import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/find_ref/find_ref_event.dart';
import 'package:otzaria/find_ref/find_ref_repository.dart';
import 'package:otzaria/find_ref/find_ref_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:search_engine/search_engine.dart';

class FindRefBloc extends Bloc<FindRefEvent, FindRefState> {
  final FindRefRepository findRefRepository;
  
  // Cache for raw results from Tantivy
  List<ReferenceSearchResult>? _cachedRawResults;
  String? _lastBaseQuery;

  FindRefBloc({required this.findRefRepository}) : super(FindRefInitial()) {
    on<SearchRefRequested>(_onSearchRefRequested);
    on<ClearSearchRequested>(_onClearSearchRequested);
    on<OpenBookRequested>(_onOpenBookRequested);
  }

  Future<void> _onSearchRefRequested(
      SearchRefRequested event, Emitter<FindRefState> emit) async {
    if (event.refText.length < 3) {
      emit(const FindRefSuccess([]));
      _cachedRawResults = null;
      _lastBaseQuery = null;
      return;
    }

    try {
      // Extract the first word (base query) to determine if we need a new search
      final words = event.refText.trim().split(RegExp(r'\s+'));
      final baseQuery = words.isNotEmpty ? words[0] : event.refText;

      // Check if we need to fetch new results from Tantivy
      if (_cachedRawResults == null || _lastBaseQuery != baseQuery) {
        // New base query - fetch from Tantivy
        emit(FindRefLoading());
        debugPrint('🔍 NEW TANTIVY SEARCH: "$baseQuery" (base query changed)');
        _cachedRawResults = await findRefRepository.fetchRawResults(baseQuery);
        _lastBaseQuery = baseQuery;
      } else {
        // Same base query - filter cached results
        debugPrint('🔍 FILTERING CACHED RESULTS for: "${event.refText}"');
      }

      // Apply filtering logic on cached results
      final filtered = await findRefRepository.filterResults(event.refText, _cachedRawResults!);
      emit(FindRefSuccess(filtered));
    } catch (e) {
      emit(FindRefError(e.toString()));
    }
  }

  void _onClearSearchRequested(
      ClearSearchRequested event, Emitter<FindRefState> emit) {
    emit(FindRefInitial());
    _cachedRawResults = null;
    _lastBaseQuery = null;
  }

  void _onOpenBookRequested(
      OpenBookRequested event, Emitter<FindRefState> emit) {
    final book = event.book;
    final index = event.index;
    emit(
        FindRefBookOpening(book: book, index: index)); // Emit BookOpening state
  }
}

class FindRefBookOpening extends FindRefState {
  // Define BookOpening state
  final Book book;
  final int index;

  const FindRefBookOpening({required this.book, required this.index});

  @override
  List<Object> get props => [book, index];
}
