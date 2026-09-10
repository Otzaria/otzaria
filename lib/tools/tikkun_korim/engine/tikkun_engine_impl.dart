/// המימוש הקונקרטי של [TikkunEngine] ו-[TikkunDataSource]. שכבה דקה בלבד
/// מעל הפונקציות שב-`engine/` ו-`data/`, בלי שדות — כדי שאפשר יהיה להעביר
/// את המנוע ל-`Isolate.run`.
library;

import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/aliyot_annotator.dart'
    as annotator;
import 'package:otzaria/tools/tikkun_korim/engine/divine_name.dart' as divine;
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart'
    as paginator;
import 'package:otzaria/tools/tikkun_korim/engine/raw_text_cleaner.dart'
    as cleaner;
import 'package:otzaria/tools/tikkun_korim/engine/special_sections_marker.dart'
    as marker;
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart'
    as processor;
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart' as tokenizer;
import 'package:otzaria/tools/tikkun_korim/engine/verse_range_slicer.dart'
    as slicer;
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';

class TikkunEngineImpl implements TikkunEngine {
  const TikkunEngineImpl();

  @override
  String cleanRawText(String raw) => cleaner.cleanRawText(raw);

  @override
  List<TikkunToken> tokenizeText(String cleaned) =>
      tokenizer.tokenizeText(cleaned);

  @override
  List<TikkunToken> markSpecialSections(
    List<TikkunToken> tokens,
    String bookName,
  ) => marker.markSpecialSections(tokens, bookName);

  @override
  List<TikkunLine> paginateAllTokens(
    List<TikkunToken> tokens,
    StamWidthModel widths,
  ) => paginator.paginateAllTokens(tokens, widths);

  @override
  ProcessedTorah processTorah(
    Map<String, String> rawByBookId,
    StamWidthModel widths, {
    TikkunTradition tradition = TikkunTradition.ashkenazSephard,
    TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
  }) => processor.processTorah(
    rawByBookId,
    widths,
    tradition: tradition,
    decalogueTaam: decalogueTaam,
  );

  @override
  List<TikkunPage> buildPages(ProcessedTorah processed, String methodId) =>
      processor.buildPages(processed, methodId);

  @override
  ProcessedBook processBook(
    String rawText,
    String bookName,
    StamWidthModel widths, {
    TikkunTradition tradition = TikkunTradition.ashkenazSephard,
    TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
  }) => processor.processBook(
    rawText,
    bookName,
    widths,
    tradition: tradition,
    decalogueTaam: decalogueTaam,
  );

  @override
  List<TikkunToken> sliceTokensByVerseRange(
    List<TikkunToken> tokens,
    int fromCh,
    int fromVs,
    int toCh,
    int toVs,
  ) => slicer.sliceTokensByVerseRange(tokens, fromCh, fromVs, toCh, toVs);

  @override
  bool precededBySetuma(List<TikkunToken> tokens, int fromCh, int fromVs) =>
      slicer.precededBySetuma(tokens, fromCh, fromVs);

  @override
  int findWordSequence(
    List<TikkunToken> tokens,
    List<String> words,
    int fromIdx,
  ) => annotator.findWordSequence(tokens, words, fromIdx);

  @override
  int findParashaStart(
    List<TikkunToken> tokens,
    String normalizedParashaName,
    int fromIdx,
  ) => annotator.findParashaStart(tokens, normalizedParashaName, fromIdx);

  @override
  String maskDivineName(String text) => divine.maskDivineName(text);

  @override
  List<VerseRange> computeContinuousSegments(List<ReadingAliya> aliyot) =>
      slicer.computeContinuousSegments(aliyot);
}

class TikkunDataSourceImpl implements TikkunDataSource {
  const TikkunDataSourceImpl();

  @override
  List<TanachBook> get chumashim => [
    for (final id in TikkunData.booksOrder)
      if (TikkunData.torahBooks[id] != null) TikkunData.torahBooks[id]!,
  ];

  @override
  List<TanachBook> booksOfSection(TikkunSection section) => switch (section) {
    TikkunSection.neviim => TikkunData.neviim,
    TikkunSection.ketuvim => TikkunData.ketuvim,
    TikkunSection.torah => chumashim,
    _ => const [],
  };

  @override
  List<TorahLayoutMethod> get methods =>
      TikkunData.torahLayouts.values.toList(growable: false);

  @override
  List<Haftarah> get haftarot => TikkunData.haftarot;

  @override
  List<TorahReading> get torahReadings => TikkunData.torahReadings;

  @override
  Map<String, String> get readingCategoryNames =>
      TikkunData.torahReadingsCategories;

  @override
  List<ParashaAliya> aliyotOf(String bookName, String parashaName) {
    final byBook = TikkunData.aliyotIndex[bookName];
    if (byBook == null) return const [];
    return byBook[parashaName] ??
        byBook[normalizeParashaName(parashaName)] ??
        const [];
  }

  @override
  String normalizeParashaName(String uiName) =>
      TikkunData.normalizeParashaName(uiName);

  @override
  String aliyaDisplayName(String aliyaKey) =>
      TikkunData.aliyaDisplayNames[aliyaKey] ?? aliyaKey;

  @override
  String? combinedParashaOf(String parashaName) {
    final info =
        TikkunData.combinedParashaMap[parashaName] ??
        TikkunData.combinedParashaMap[normalizeParashaName(parashaName)];
    if (info == null) return null;
    return (info as Map)['combined'] as String?;
  }

  @override
  ({String bookId, String parashaName})? resolveParasha(String calendarName) {
    final stripped = calendarName.replaceAll(RegExp('[֑-ׇ]'), '').trim();
    final firstName = stripped.split(RegExp('[-–]')).first.trim();

    final reverseMap = <String, String>{
      for (final e in TikkunData.parashaNameMapping.entries) e.value: e.key,
    };

    for (final candidate in [firstName, stripped]) {
      for (final bookId in TikkunData.booksOrder) {
        final book = TikkunData.torahBooks[bookId];
        if (book?.parashot.contains(candidate) ?? false) {
          return (bookId: bookId, parashaName: candidate);
        }
      }
      final uiName = reverseMap[candidate];
      if (uiName == null) continue;
      for (final bookId in TikkunData.booksOrder) {
        final book = TikkunData.torahBooks[bookId];
        if (book?.parashot.contains(uiName) ?? false) {
          return (bookId: bookId, parashaName: uiName);
        }
      }
    }
    return null;
  }
}
