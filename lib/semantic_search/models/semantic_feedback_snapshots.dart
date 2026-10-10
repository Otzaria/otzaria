import 'package:flutter/painting.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';

import 'semantic_engine_models.dart';
import 'semantic_result_item.dart';

/// הטקסט הפשוט של הקטע והקטעים המודגשים בו, דרך אותו מפענח של המסך.
({String plain, List<String> matched}) semanticSnippetText(String html) {
  const plainStyle = TextStyle();
  const markStyle = TextStyle(fontWeight: FontWeight.bold);
  final spans = SnippetBuilder.fromHighlightedHtml(
    html: html,
    defaultStyle: plainStyle,
    highlightStyle: markStyle,
  );
  final plain = StringBuffer();
  final matched = <String>[];
  var inMark = false;
  for (final span in spans) {
    if (span is! TextSpan) continue;
    final text = span.text ?? '';
    plain.write(text);
    final isMark = identical(span.style, markStyle);
    if (isMark && inMark) {
      matched.last += text;
    } else if (isMark) {
      matched.add(text);
    }
    inMark = isMark;
  }
  return (
    plain: plain.toString().trim(),
    matched: [
      for (final text in matched)
        if (text.trim().isNotEmpty) text.trim(),
    ],
  );
}

/// המיקום ברשימה כולה, מ-1.
int semanticResultRank(int offset, int index) => offset + index + 1;

/// תמונת תוצאה לטלמטריה; [passageText] רק בפתיחה ובסימון.
SemanticResultSnapshot buildSemanticResultSnapshot(
  SemanticResultItem item, {
  required int rank,
  required bool isUserBook,
  String? passageText,
}) {
  final snippet = semanticSnippetText(item.snippetHtml);
  return SemanticResultSnapshot(
    rank: rank,
    title: item.title,
    reference: item.reference,
    segment: item.segment,
    isPdf: item.isPdf,
    isUserBook: isUserBook,
    source: item.source.name,
    lexicalScore: item.lexicalScore,
    semanticScore: item.semanticScore,
    fusedScore: item.fusedScore,
    mergedCount: item.mergedCount,
    snippetText: snippet.plain,
    matchedText: snippet.matched,
    passageText: passageText,
    passageTextSource: passageText == null ? null : 'line',
  );
}

/// הפרמטרים שנשלחו לחיפוש, כפי שהם נרשמים בטלמטריה.
/// הבקשה ולא מה שבוצע: ביטוי במירכאות נשלח כ-fuzzy והמנוע מריץ אותו כ-exact.
SemanticSearchParamsSnapshot buildSemanticParamsSnapshot(
  SemanticQueryOptions options, {
  required int pageSize,
  SemanticRankingConfig? ranking,
}) => SemanticSearchParamsSnapshot(
  retrievalMode: options.includeLexical ? 'hybrid' : 'semanticOnly',
  lexicalMode: kSmartSearchLexicalMode.name,
  fuzzyMaxDistance: kSmartSearchFuzzyMaxDistance,
  grouping: options.groupIdenticalText ? 'identicalText' : null,
  matchNikud: false,
  matchTaamim: false,
  facets: options.facets,
  allLibrary: options.allLibrary,
  pageSize: pageSize,
  ranking: ranking?.toSnapshotMap(),
);

/// סיכום התשובה של העמוד הראשון.
SemanticSearchResponseSnapshot buildSemanticResponseSnapshot(
  SemanticResultsPage page,
) => SemanticSearchResponseSnapshot(
  executedMode: page.executedMode,
  semanticAvailable: page.semanticAvailable,
  // טקסט המנוע חופשי (נתיבים, שם משתמש) — רק ערך מרשימה סגורה עובר.
  fallbackReason: page.fallbackReason == kSemanticDebugPreviewFallbackReason
      ? kSemanticDebugPreviewFallbackReason
      : null,
  fallbackKind: page.fallbackKind,
  latencyMs: page.latencyMs,
  totalCount: page.totalCount,
  lexicalTotalCount: page.lexicalTotalCount,
  groupCount: page.groupCount,
  countsAreExact: page.countsAreExact,
  truncated: page.truncated,
  candidateWindowTruncated: page.candidateWindowTruncated,
);
