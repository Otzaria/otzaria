import 'package:equatable/equatable.dart';
import 'package:otzaria/search/utils/result_text_status.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show
        MergedSibling,
        SearchResult,
        SemanticResultSource,
        SemanticSearchResult,
        TextStatus;

/// תוצאה אחת במסך החיפוש הסמנטי — משותפת למנוע ולתצוגה המקדימה בפיתוח.
class SemanticResultItem extends Equatable {
  final String title;
  final String reference;

  /// HTML מודגש כמו בשאר החיפושים; התאמה לפי עניין בלבד מגיעה בלי סימון.
  final String snippetHtml;
  final bool isHighlighted;
  final BigInt id;
  final int segment;
  final bool isPdf;

  /// מפתח האינדקס היציב (`id:`/`uid:`/`ext:` או נתיב PDF).
  final String filePath;
  final int mergedCount;
  final List<MergedSibling> merged;
  final double? lexicalScore;
  final double? semanticScore;
  final double fusedScore;
  final SemanticResultSource source;

  const SemanticResultItem({
    required this.title,
    required this.reference,
    required this.snippetHtml,
    required this.isHighlighted,
    required this.id,
    required this.segment,
    required this.isPdf,
    required this.filePath,
    required this.source,
    required this.fusedScore,
    this.mergedCount = 1,
    this.merged = const [],
    this.lexicalScore,
    this.semanticScore,
  });

  /// תוצאה מהמנוע הסמנטי.
  factory SemanticResultItem.fromEngine(SemanticSearchResult result) =>
      SemanticResultItem(
        title: result.title,
        reference: result.reference,
        snippetHtml: switch (result.textStatus) {
          TextStatus.unavailable => unavailableResultText,
          TextStatus.stale when result.snippetHtml.isEmpty =>
            unavailableResultText,
          _ => result.snippetHtml,
        },
        isHighlighted: result.isHighlighted,
        id: result.id,
        segment: result.segment.toInt(),
        isPdf: result.isPdf,
        filePath: result.filePath,
        mergedCount: result.mergedCount,
        merged: result.merged,
        lexicalScore: result.lexicalScore,
        semanticScore: result.semanticScore,
        fusedScore: result.fusedScore,
        source: result.source,
      );

  /// תוצאה מילולית בתצוגה המקדימה; הציון מדומה במכוון (לפי המיקום).
  factory SemanticResultItem.debugFromLexical(SearchResult result, int rank) {
    final fakeScore = 1 / rank;
    return SemanticResultItem(
      title: result.title,
      reference: result.reference,
      snippetHtml: result.text,
      isHighlighted: true,
      id: result.id,
      segment: result.segment.toInt(),
      isPdf: result.isPdf,
      filePath: result.filePath,
      mergedCount: result.mergedCount,
      merged: result.merged,
      lexicalScore: fakeScore,
      fusedScore: fakeScore,
      source: SemanticResultSource.lexical,
    );
  }

  /// האם נמצאה רק לפי עניין, בלי מילה תואמת בשורה.
  bool get isSemanticOnly => source == SemanticResultSource.semantic;

  /// האם לבקש מהמנוע לסמן בה את הקטע הקרוב לשאילתה.
  bool get wantsPassageHighlight =>
      isSemanticOnly &&
      snippetHtml.isNotEmpty &&
      snippetHtml != unavailableResultText;

  /// תוצאה מאוחדת שבכרטיס: מיקום ה-sibling, עם המקור והציונים של הכרטיס.
  SemanticResultItem forSibling(MergedSibling sibling) => SemanticResultItem(
    title: sibling.title,
    reference: sibling.reference,
    snippetHtml: snippetHtml,
    isHighlighted: isHighlighted,
    id: sibling.id,
    segment: sibling.segment.toInt(),
    isPdf: sibling.isPdf,
    filePath: sibling.filePath,
    source: source,
    fusedScore: fusedScore,
    lexicalScore: lexicalScore,
    semanticScore: semanticScore,
  );

  @override
  List<Object?> get props => [id, filePath, segment, isPdf, source];
}

/// עמוד תוצאות אחד מהמקור, עם נתוני התשובה לטלמטריה.
class SemanticResultsPage {
  final List<SemanticResultItem> items;

  /// האם יש עמוד נוסף; לא נגזר מהספירות, שמתארות חלון מועמדים.
  final bool hasMore;

  /// המנוע איבד את סשן הדפדוף; העמוד הוא התחלה חדשה ולא המשך לרשימה.
  final bool sessionRestarted;
  final String executedMode;
  final bool semanticAvailable;
  final String? fallbackReason;
  final String? fallbackKind;
  final int latencyMs;
  final int totalCount;
  final int lexicalTotalCount;
  final int? groupCount;
  final bool countsAreExact;
  final bool truncated;
  final bool candidateWindowTruncated;

  const SemanticResultsPage({
    required this.items,
    required this.hasMore,
    this.sessionRestarted = false,
    required this.executedMode,
    required this.semanticAvailable,
    required this.latencyMs,
    required this.totalCount,
    required this.lexicalTotalCount,
    required this.countsAreExact,
    required this.truncated,
    required this.candidateWindowTruncated,
    this.fallbackReason,
    this.fallbackKind,
    this.groupCount,
  });
}

/// מה המשתמש ביקש: השאילתה, ההיקף והאפשרויות של המצב.
class SemanticQueryOptions extends Equatable {
  final String query;

  /// facets של קטגוריות הספרייה בלבד; `['/']` = כל הספרייה.
  final List<String> facets;

  /// היברידי (גם התאמה מילולית) או לפי עניין בלבד.
  final bool includeLexical;
  final bool groupIdenticalText;

  const SemanticQueryOptions({
    required this.query,
    this.facets = const ['/'],
    this.includeLexical = true,
    this.groupIdenticalText = true,
  });

  bool get allLibrary => facets.isEmpty || facets.contains('/');

  SemanticQueryOptions copyWith({
    String? query,
    List<String>? facets,
    bool? includeLexical,
    bool? groupIdenticalText,
  }) => SemanticQueryOptions(
    query: query ?? this.query,
    facets: facets ?? this.facets,
    includeLexical: includeLexical ?? this.includeLexical,
    groupIdenticalText: groupIdenticalText ?? this.groupIdenticalText,
  );

  Map<String, dynamic> toJson() => {
    'query': query,
    'facets': facets,
    'includeLexical': includeLexical,
    'groupIdenticalText': groupIdenticalText,
  };

  factory SemanticQueryOptions.fromJson(Map<String, dynamic> json) =>
      SemanticQueryOptions(
        query: json['query'] is String ? json['query'] as String : '',
        facets: json['facets'] is List
            ? [for (final facet in json['facets'] as List) '$facet']
            : const ['/'],
        includeLexical: json['includeLexical'] != false,
        groupIdenticalText: json['groupIdenticalText'] != false,
      );

  @override
  List<Object?> get props => [
    query,
    facets,
    includeLexical,
    groupIdenticalText,
  ];
}
