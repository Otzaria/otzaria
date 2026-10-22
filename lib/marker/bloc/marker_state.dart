import 'package:equatable/equatable.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_query.dart';

enum MarkerListStatus { initial, loading, ready, failure }

class MarkerState extends Equatable {
  final MarkerListStatus status;
  final MarkerQuery query;
  final List<MarkerHighlight> items;
  final bool hasMore;
  final bool loadingMore;
  final MarkerCounts counts;
  final List<MarkerBookCount> books;
  final List<({String tag, int count})> tags;
  final Set<String> selectedIds;

  const MarkerState({
    this.status = MarkerListStatus.initial,
    this.query = const MarkerQuery(),
    this.items = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.counts = const MarkerCounts(),
    this.books = const [],
    this.tags = const [],
    this.selectedIds = const {},
  });

  bool get isSelecting => selectedIds.isNotEmpty;

  MarkerState copyWith({
    MarkerListStatus? status,
    MarkerQuery? query,
    List<MarkerHighlight>? items,
    bool? hasMore,
    bool? loadingMore,
    MarkerCounts? counts,
    List<MarkerBookCount>? books,
    List<({String tag, int count})>? tags,
    Set<String>? selectedIds,
  }) => MarkerState(
    status: status ?? this.status,
    query: query ?? this.query,
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    counts: counts ?? this.counts,
    books: books ?? this.books,
    tags: tags ?? this.tags,
    selectedIds: selectedIds ?? this.selectedIds,
  );

  @override
  List<Object?> get props => [
    status,
    query,
    items,
    hasMore,
    loadingMore,
    counts,
    books,
    tags,
    selectedIds,
  ];
}
