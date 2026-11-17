import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_divine_names_filter.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/plugins/utils/grapheme_occurrences.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

class ReaderSelectionService {
  static const int contextLength = 30;
  final TextSourceMapService _sourceMapService;

  const ReaderSelectionService({
    this._sourceMapService = const TextSourceMapService(),
  });

  /// מאתר בחירה רק בפסקה שהמשתמש בחר, כדי שמופע בפסקה אחרת לא יחליף אותה.
  ({int start, int end})? locateRenderedRange({
    required String renderedText,
    required String selectedText,
    int? startHint,
  }) {
    if (selectedText.isEmpty) return null;
    final start = _nearestMatchStart(renderedText, selectedText, startHint);
    if (start < 0) return null;
    return (start: start, end: start + selectedText.length);
  }

  Map<String, dynamic> buildPayload({
    required String bookId,
    required String bookTitle,
    required int sectionIndex,
    required String rawText,
    required RenderSettings settings,
    required String selectedText,
    required int? renderedStartUtf16,
    required int? renderedEndUtf16,
    String? currentRef,
    int? bookDbId,
    String? bookType,
    String? bookSource,
    String? bookUid,
  }) {
    final legacy = <String, dynamic>{
      'id': ?bookDbId,
      'type': ?bookType,
      'source': ?bookSource,
      'bookUid': ?bookUid,
      'text': selectedText,
      'start': renderedStartUtf16,
      'end': renderedEndUtf16,
      'currentRef': currentRef,
      'currentBook': bookTitle,
      'currentBookId': bookId,
      'currentIndex': sectionIndex,
    };
    if (renderedStartUtf16 == null || renderedEndUtf16 == null) return legacy;
    final selection = build(
      bookId: bookId,
      bookTitle: bookTitle,
      sectionIndex: sectionIndex,
      rawText: rawText,
      settings: settings,
      renderedStartUtf16: renderedStartUtf16,
      renderedEndUtf16: renderedEndUtf16,
      currentRef: currentRef,
      bookDbId: bookDbId,
      bookType: bookType,
      bookSource: bookSource,
    );
    return selection == null ? legacy : {...legacy, ...selection.toJson()};
  }

  /// בונה payload לבחירה חוצת-פסקאות: שדות legacy ברמה העליונה + מערך
  /// `sections` עם עוגן מלא לכל פסקה. פסקה שלא ניתן לעגן מושמטת; פסקה
  /// יחידה מתמזגת לרמה העליונה — זהה לבחירה רגילה בפסקה אחת.
  Map<String, dynamic> buildMultiSectionPayload({
    required String bookId,
    required String bookTitle,
    required int firstSectionIndex,
    required List<String> rawTexts,
    required List<({int line, int start, int end})> lineRanges,
    required RenderSettings settings,
    required String selectedText,
    String? currentRef,
    int? bookDbId,
    String? bookType,
    String? bookSource,
  }) {
    final sections = <Map<String, dynamic>>[];
    for (final range in lineRanges) {
      if (range.line < 0 || range.line >= rawTexts.length) continue;
      final selection = build(
        bookId: bookId,
        bookTitle: bookTitle,
        sectionIndex: firstSectionIndex + range.line,
        rawText: rawTexts[range.line],
        settings: settings,
        renderedStartUtf16: range.start,
        renderedEndUtf16: range.end,
        currentRef: currentRef,
        bookDbId: bookDbId,
        bookType: bookType,
        bookSource: bookSource,
      );
      if (selection != null) {
        sections.add({
          ...selection.toJson(),
          'currentIndex': selection.sectionIndex,
        });
      }
    }
    final legacy = <String, dynamic>{
      'id': ?bookDbId,
      'type': ?bookType,
      'source': ?bookSource,
      'text': selectedText,
      'start': null,
      'end': null,
      'currentRef': currentRef,
      'currentBook': bookTitle,
      'currentBookId': bookId,
      'currentIndex': firstSectionIndex,
    };
    if (sections.isEmpty) return legacy;
    if (sections.length == 1) return {...legacy, ...sections.single};
    return {...legacy, 'sections': sections};
  }

  /// [payload] עם הטקסט ו-`renderedRange` לפי [names] במקום השמות של
  /// [settings]; [rawTextOf] — שורת הפסקה עם סמני השמות. המקור לא משתנה.
  Map<String, dynamic> withDivineNames(
    Map<String, dynamic> payload, {
    required PluginDivineNamesDisplay names,
    required RenderSettings settings,
    required String Function(int sectionIndex) rawTextOf,
    bool includeNormalized = true,
  }) {
    final namesChanged = PluginDivineNamesDisplay.ofSettings(settings) != names;
    final shownText = withoutDivineNameJoiners(
      (payload['text'] ?? '').toString(),
    );
    Map<String, dynamic> withNames(Map<String, dynamic> selection) => {
      ...selection,
      ..._textFieldsWithNames(
        selection,
        names,
        settings,
        rawTextOf,
        namesChanged: namesChanged,
        includeNormalized: includeNormalized,
      ),
    };
    final result = Map<String, dynamic>.of(payload);
    final sections = payload['sections'];
    if (sections is List) {
      final resolved = [
        for (final section in sections.cast<Map<String, dynamic>>())
          withNames(section),
      ];
      result['sections'] = resolved;
      final first = resolved.first['sectionIndex'] as int;
      final contiguous = resolved.indexed.every(
        (entry) => entry.$2['sectionIndex'] == first + entry.$1,
      );
      result['text'] = !namesChanged
          ? shownText
          : contiguous
          ? resolved
                .map((section) => section['renderedSelectedText'] as String)
                .join('\n')
          : filterPluginDivineNamesText(shownText, names);
    } else if (payload['sourceRange'] is Map) {
      result.addAll(withNames(payload));
      result['text'] = namesChanged
          ? result['renderedSelectedText']
          : shownText;
    } else {
      result['text'] = filterPluginDivineNamesText(shownText, names);
    }
    return result;
  }

  /// שדות הטקסט של [selection] לפי [names]. מפת מקור נבנית לכל היותר פעם
  /// אחת לכל גרסה, ורק כשהיא נדרשת.
  Map<String, dynamic> _textFieldsWithNames(
    Map<String, dynamic> selection,
    PluginDivineNamesDisplay names,
    RenderSettings settings,
    String Function(int sectionIndex) rawTextOf, {
    required bool namesChanged,
    required bool includeNormalized,
  }) {
    final sectionIndex = selection['sectionIndex'] as int;
    final range = selection['sourceRange'] as Map<String, dynamic>;
    final start = (range['start'] as Map<String, dynamic>)['grapheme'] as int;
    final end = (range['end'] as Map<String, dynamic>)['grapheme'] as int;
    final maps = <RenderSettings, PluginTextSourceMap>{};
    PluginTextSourceMap mapWith(RenderSettings settings) => maps.putIfAbsent(
      settings,
      () => _sourceMapService.build(
        bookId: selection['bookId'] as String,
        sectionIndex: sectionIndex,
        rawText: rawTextOf(sectionIndex),
        settings: settings,
      ),
    );
    ({PluginTextSourceMap map, int start, int end}) rangeIn(
      RenderSettings settings,
    ) {
      final map = mapWith(settings.copyWith(formatParentheses: false));
      return (
        map: map,
        start: _sourceMapService.sourceBoundaryToRendered(map, start),
        end: _sourceMapService.sourceBoundaryToRendered(map, end),
      );
    }

    final fields = <String, dynamic>{};
    if (namesChanged) {
      // אחרת exactText והקשרו היו מוסרים את השמות שעל המסך גם למי שביקש אחרת.
      final shown = rangeIn(names.applyToSettings(settings));
      final anchor = _anchor(
        text: _GraphemeBoundaries(shown.map.renderedText),
        start: shown.start,
        end: shown.end,
        layer: 'rendered',
        renderedTextHash: shown.map.renderedTextHash,
      );
      fields['renderedRange'] = anchor.toJson();
      fields['renderedSelectedText'] = withoutDivineNameJoiners(
        anchor.exactText,
      );
    } else {
      fields['renderedSelectedText'] = withoutDivineNameJoiners(
        selection['renderedSelectedText'] as String,
      );
    }
    if (includeNormalized && names.filters) {
      final plain = rangeIn(
        RenderSettings.fromProfile(names.applyTo(TextDisplayProfile.defaults)),
      );
      fields['normalizedSelectedText'] = _normalize(
        withoutDivineNameJoiners(
          plain.map.renderedText.characters
              .getRange(plain.start, plain.end)
              .toString(),
        ),
      );
    }
    return fields;
  }

  PluginReaderSelection? build({
    required String bookId,
    required String bookTitle,
    required int sectionIndex,
    required String rawText,
    required RenderSettings settings,
    required int renderedStartUtf16,
    required int renderedEndUtf16,
    String? currentRef,
    String? tabId,
    DateTime? createdAt,
    int? bookDbId,
    String? bookType,
    String? bookSource,
  }) {
    final map = _sourceMapService.build(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: rawText,
      settings: settings,
    );
    return _buildFromMap(
      map: map,
      bookId: bookId,
      bookTitle: bookTitle,
      sectionIndex: sectionIndex,
      currentRef: currentRef,
      tabId: tabId,
      createdAt: createdAt,
      bookDbId: bookDbId,
      bookType: bookType,
      bookSource: bookSource,
      renderedStartUtf16: renderedStartUtf16,
      renderedEndUtf16: renderedEndUtf16,
    );
  }

  /// ממפה בחירה מהתצוגה לטווח המקביל במקור בעזרת מפת פסקה אחת.
  PluginReaderSelection? buildFromRenderedSelection({
    required String bookId,
    required String bookTitle,
    required int sectionIndex,
    required String rawText,
    required RenderSettings settings,
    required String selectedText,
    int? startHint,
    String? currentRef,
    int? bookDbId,
    String? bookType,
    String? bookSource,
  }) {
    final map = _sourceMapService.build(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: rawText,
      settings: settings,
    );
    final range = _locateWhitespaceNormalizedRange(
      renderedText: map.renderedText,
      selectedText: selectedText,
      startHint: startHint,
    );
    if (range == null) return null;
    var preciseSourceRange = null as ({int start, int end})?;
    if (settings.replaceHolyNames) {
      final replacementMapping = _sourceRangeForHolyNameReplacement(
        map: map,
        rawText: rawText,
        settings: settings,
        renderedRange: range,
      );
      if (replacementMapping == null ||
          (replacementMapping.hasVisibleReplacements &&
              replacementMapping.range == null)) {
        return null;
      }
      preciseSourceRange = replacementMapping.range;
    }
    return _buildFromMap(
      map: map,
      bookId: bookId,
      bookTitle: bookTitle,
      sectionIndex: sectionIndex,
      currentRef: currentRef,
      bookDbId: bookDbId,
      bookType: bookType,
      bookSource: bookSource,
      renderedStartUtf16: range.start,
      renderedEndUtf16: range.end,
      sourceStartGrapheme: preciseSourceRange?.start,
      sourceEndGrapheme: preciseSourceRange?.end,
    );
  }

  ({
    bool hasVisibleReplacements,
    ({int start, int end})? range,
  })?
  _sourceRangeForHolyNameReplacement({
    required PluginTextSourceMap map,
    required String rawText,
    required RenderSettings settings,
    required ({int start, int end}) renderedRange,
  }) {
    final intermediateSettings = settings.copyWith(replaceHolyNames: false);
    final intermediateHtml = TextRendererService.processText(
      rawText,
      intermediateSettings,
    );
    final intermediateMap = _sourceMapService.buildFromProcessedHtml(
      bookId: map.bookId,
      sectionIndex: map.sectionIndex,
      rawText: rawText,
      processedHtml: intermediateHtml,
    );
    final replacements = text_utils.findReplaceableHolyNames(
      intermediateHtml,
    );
    final replacedHtml = text_utils.replaceHolyNames(
      intermediateHtml,
      style: settings.holyNameStyle,
    );
    if (TextRendererService.stripHtml(replacedHtml) != map.renderedText) {
      return null;
    }

    final intermediateText = intermediateMap.renderedText;
    final sourceBoundaries = _GraphemeBoundaries(intermediateText);
    final replacementRanges =
        <
          ({int sourceStart, int sourceEnd, int renderedStart, int renderedEnd})
        >[];
    var htmlOffset = 0;
    var htmlScanOffset = 0;
    var insideHtmlTag = false;
    var visibleOffset = 0;
    var delta = 0;
    final projectedText = StringBuffer();
    for (final match in replacements) {
      while (htmlScanOffset < match.start) {
        final code = intermediateHtml.codeUnitAt(htmlScanOffset++);
        if (code == 0x3C) insideHtmlTag = true;
        if (code == 0x3E) insideHtmlTag = false;
      }
      final isInsideTag = insideHtmlTag;
      htmlScanOffset = match.end;
      if (isInsideTag) continue;

      final precedingText = TextRendererService.stripHtml(
        intermediateHtml.substring(htmlOffset, match.start),
      );
      projectedText.write(precedingText);
      visibleOffset += precedingText.length;
      final visibleMatch = TextRendererService.stripHtml(match[0]!);
      projectedText.write(visibleMatch);
      final sourceStart = sourceBoundaries.graphemeAtUtf16(visibleOffset);
      final sourceEnd = sourceBoundaries.graphemeAtUtf16(
        visibleOffset + visibleMatch.length,
      );
      if (sourceStart == null || sourceEnd == null) return null;
      final replacement = text_utils.replaceHolyNames(
        visibleMatch,
        style: settings.holyNameStyle,
      );
      final replacementLength = replacement.characters.length;
      final outputStart = sourceStart - delta;
      replacementRanges.add((
        sourceStart: sourceStart,
        sourceEnd: sourceEnd,
        renderedStart: outputStart,
        renderedEnd: outputStart + replacementLength,
      ));
      delta += (sourceEnd - sourceStart) - replacementLength;
      visibleOffset += visibleMatch.length;
      htmlOffset = match.end;
    }
    final trailingText = TextRendererService.stripHtml(
      intermediateHtml.substring(htmlOffset),
    );
    projectedText.write(trailingText);
    visibleOffset += trailingText.length;
    if (visibleOffset != intermediateText.length ||
        projectedText.toString() != intermediateText) {
      return null;
    }
    if (replacementRanges.isEmpty) {
      return (hasVisibleReplacements: false, range: null);
    }

    final renderedBoundaries = _GraphemeBoundaries(map.renderedText);
    final renderedStart = renderedBoundaries.graphemeAtUtf16(
      renderedRange.start,
    );
    final renderedEnd = renderedBoundaries.graphemeAtUtf16(renderedRange.end);
    if (renderedStart == null || renderedEnd == null) return null;

    int toIntermediate(int boundary, {required bool endBoundary}) {
      var deltaBefore = 0;
      for (final replacement in replacementRanges) {
        if (boundary < replacement.renderedStart) {
          return boundary + deltaBefore;
        }
        if (boundary <= replacement.renderedEnd) {
          if (boundary == replacement.renderedStart) {
            return replacement.sourceStart;
          }
          if (boundary == replacement.renderedEnd) {
            return replacement.sourceEnd;
          }
          if (replacement.renderedEnd - replacement.renderedStart ==
              replacement.sourceEnd - replacement.sourceStart) {
            return replacement.sourceStart +
                (boundary - replacement.renderedStart);
          }
          return endBoundary ? replacement.sourceEnd : replacement.sourceStart;
        }
        deltaBefore +=
            (replacement.sourceEnd - replacement.sourceStart) -
            (replacement.renderedEnd - replacement.renderedStart);
      }
      return boundary + deltaBefore;
    }

    final intermediateStart = toIntermediate(renderedStart, endBoundary: false);
    final intermediateEnd = toIntermediate(renderedEnd, endBoundary: true);
    return (
      hasVisibleReplacements: true,
      range: (
        start: _sourceMapService.renderedBoundaryToSource(
          intermediateMap,
          intermediateStart,
        ),
        end: _sourceMapService.renderedBoundaryToSource(
          intermediateMap,
          intermediateEnd,
        ),
      ),
    );
  }

  PluginReaderSelection? _buildFromMap({
    required PluginTextSourceMap map,
    required String bookId,
    required String bookTitle,
    required int sectionIndex,
    required int renderedStartUtf16,
    required int renderedEndUtf16,
    String? currentRef,
    String? tabId,
    DateTime? createdAt,
    int? bookDbId,
    String? bookType,
    String? bookSource,
    int? sourceStartGrapheme,
    int? sourceEndGrapheme,
  }) {
    final rendered = _GraphemeBoundaries(map.renderedText);
    final renderedStart = rendered.graphemeAtUtf16(renderedStartUtf16);
    final renderedEnd = rendered.graphemeAtUtf16(renderedEndUtf16);
    if (renderedStart == null ||
        renderedEnd == null ||
        renderedStart >= renderedEnd) {
      return null;
    }

    final sourceStart =
        sourceStartGrapheme ??
        _sourceMapService.renderedBoundaryToSource(map, renderedStart);
    final sourceEnd =
        sourceEndGrapheme ??
        _sourceMapService.renderedBoundaryToSource(map, renderedEnd);
    if (sourceStart >= sourceEnd) return null;

    final source = _GraphemeBoundaries(map.sourceText);
    final renderedText = rendered.slice(renderedStart, renderedEnd);
    final sourceText = source.slice(sourceStart, sourceEnd);
    final timestamp = createdAt ?? DateTime.now().toUtc();
    final selectionId = sha256
        .convert(
          utf8.encode(
            '$bookId:$sectionIndex:$sourceStart:$sourceEnd:${timestamp.microsecondsSinceEpoch}',
          ),
        )
        .toString()
        .substring(0, 24);

    return PluginReaderSelection(
      selectionId: selectionId,
      bookId: bookId,
      id: bookDbId,
      type: bookType,
      source: bookSource,
      bookTitle: bookTitle,
      tabId: tabId,
      sectionIndex: sectionIndex,
      currentRef: currentRef,
      renderedSelectedText: renderedText,
      sourceSelectedText: sourceText,
      normalizedSelectedText: _normalize(sourceText),
      sourceRange: _anchor(
        text: source,
        start: sourceStart,
        end: sourceEnd,
        layer: 'source',
        sourceTextHash: map.sourceTextHash,
      ),
      renderedRange: _anchor(
        text: rendered,
        start: renderedStart,
        end: renderedEnd,
        layer: 'rendered',
        renderedTextHash: map.renderedTextHash,
      ),
      direction: _direction(renderedText),
      createdAt: timestamp,
    );
  }

  ({int start, int end})? _locateWhitespaceNormalizedRange({
    required String renderedText,
    required String selectedText,
    int? startHint,
  }) {
    final normalized = StringBuffer();
    final offsets = <int>[];
    var pendingWhitespace = false;
    var whitespaceStart = 0;
    for (var i = 0; i < renderedText.length; i++) {
      final character = renderedText[i];
      if (character.trim().isEmpty) {
        if (normalized.isNotEmpty) {
          if (!pendingWhitespace) whitespaceStart = i;
          pendingWhitespace = true;
        }
        continue;
      }
      if (pendingWhitespace) {
        offsets.add(whitespaceStart);
        normalized.write(' ');
        pendingWhitespace = false;
      }
      offsets.add(i);
      normalized.write(character);
    }
    final needle = selectedText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (needle.isEmpty || needle.length > offsets.length) return null;
    final text = normalized.toString();
    final start = _nearestMatchStart(
      text,
      needle,
      startHint,
      sourceOffsets: offsets,
    );
    if (start < 0) return null;
    return (start: offsets[start], end: offsets[start + needle.length - 1] + 1);
  }

  int _nearestMatchStart(
    String text,
    String needle,
    int? startHint, {
    List<int>? sourceOffsets,
  }) {
    var nearest = text.indexOf(needle);
    if (nearest < 0 || startHint == null) return nearest;
    var nearestDistance = ((sourceOffsets?[nearest] ?? nearest) - startHint)
        .abs();
    var found = nearest;
    while (found >= 0) {
      final sourceStart = sourceOffsets?[found] ?? found;
      final distance = (sourceStart - startHint).abs();
      if (distance < nearestDistance) {
        nearest = found;
        nearestDistance = distance;
      }
      if (sourceStart >= startHint) break;
      found = text.indexOf(needle, found + 1);
    }
    return nearest;
  }

  PluginTextRangeAnchor? buildRangeAnchor({
    required String text,
    required int startGrapheme,
    required int endGrapheme,
    required String layer,
    String? sourceTextHash,
    String? renderedTextHash,
    String? normalizationProfile,
  }) => buildRangeAnchors(
    text: text,
    ranges: [(startGrapheme: startGrapheme, endGrapheme: endGrapheme)],
    layer: layer,
    sourceTextHash: sourceTextHash,
    renderedTextHash: renderedTextHash,
    normalizationProfile: normalizationProfile,
  ).single;

  /// בונה קבוצת עוגנים לאותו טקסט תוך שיתוף חישובי הגבולות והמופעים.
  List<PluginTextRangeAnchor?> buildRangeAnchors({
    required String text,
    required List<({int startGrapheme, int endGrapheme})> ranges,
    required String layer,
    String? sourceTextHash,
    String? renderedTextHash,
    String? normalizationProfile,
  }) {
    if (ranges.isEmpty) return const [];
    final boundaries = _GraphemeBoundaries(text);
    final exactByRange = <int, String>{};
    for (final entry in ranges.asMap().entries) {
      final range = entry.value;
      if (range.startGrapheme < 0 ||
          range.endGrapheme > boundaries.length ||
          range.startGrapheme >= range.endGrapheme) {
        continue;
      }
      exactByRange[entry.key] = boundaries.slice(
        range.startGrapheme,
        range.endGrapheme,
      );
    }
    final occurrences = boundaries.occurrencesFor(exactByRange.values);
    final wordIndices = boundaries.wordIndices();
    return [
      for (final entry in ranges.asMap().entries)
        if (exactByRange[entry.key] case final exact?)
          _anchor(
            text: boundaries,
            start: entry.value.startGrapheme,
            end: entry.value.endGrapheme,
            layer: layer,
            sourceTextHash: sourceTextHash,
            renderedTextHash: renderedTextHash,
            normalizationProfile: normalizationProfile ?? 'strict',
            occurrences: occurrences[exact],
            wordIndices: wordIndices,
          )
        else
          null,
    ];
  }

  PluginTextRangeAnchor _anchor({
    required _GraphemeBoundaries text,
    required int start,
    required int end,
    required String layer,
    String? sourceTextHash,
    String? renderedTextHash,
    String? normalizationProfile,
    List<int>? occurrences,
    List<int>? wordIndices,
  }) {
    final exact = text.slice(start, end);
    final exactOccurrences = occurrences ?? text.occurrences(exact);
    return PluginTextRangeAnchor(
      layer: layer,
      sourceTextHash: sourceTextHash,
      renderedTextHash: renderedTextHash,
      start: text.offsetAt(start),
      end: text.offsetAt(end),
      exactText: exact,
      beforeText: _context(
        text,
        (start - contextLength).clamp(0, start).toInt(),
        start,
      ),
      afterText: _context(
        text,
        end,
        (end + contextLength).clamp(end, text.length).toInt(),
      ),
      occurrenceIndexInSection: binarySearch(exactOccurrences, start),
      occurrenceCountInSection: exactOccurrences.length,
      startWordIndex: wordIndices?[start] ?? _wordIndex(text.slice(0, start)),
      endWordIndex: wordIndices?[end] ?? _wordIndex(text.slice(0, end)),
      normalizationProfile: normalizationProfile ?? 'strict',
    );
  }

  PluginAnchorContext _context(_GraphemeBoundaries text, int start, int end) {
    final raw = text.slice(start, end);
    return PluginAnchorContext(
      raw: raw,
      normalized: _normalize(raw),
      maxGraphemes: contextLength,
      actualGraphemes: end - start,
      truncatedAtBoundary: start == 0 || end == text.length,
    );
  }

  int _wordIndex(String prefix) {
    // trimLeft בלבד: רווח בסוף ה-prefix הוא המפריד שלפני המילה הנוכחית,
    // ומחיקתו (trim מלא) החזירה את אינדקס המילה הקודמת.
    final trimmed = prefix.trimLeft();
    if (trimmed.isEmpty) return 0;
    return RegExp(r'\s+').allMatches(trimmed).length;
  }

  String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _direction(String value) {
    final hasRtl = RegExp(r'[\u0590-\u08FF]').hasMatch(value);
    final hasLtr = RegExp(r'[A-Za-z]').hasMatch(value);
    if (hasRtl && hasLtr) return 'mixed';
    return hasLtr ? 'ltr' : 'rtl';
  }
}

class _GraphemeBoundaries {
  static final RegExp _whitespace = RegExp(r'^\s+$');

  final List<String> values;
  final List<PluginTextOffset> offsets;

  _GraphemeBoundaries(String text)
    : values = text.characters.toList(growable: false),
      offsets = _offsets(text);

  int get length => values.length;

  PluginTextOffset offsetAt(int index) => offsets[index];

  int? graphemeAtUtf16(int utf16) {
    var low = 0;
    var high = offsets.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      final offset = offsets[mid].utf16;
      if (offset < utf16) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < offsets.length && offsets[low].utf16 == utf16 ? low : null;
  }

  String slice(int start, int end) => values.sublist(start, end).join();

  List<int> occurrences(String query) =>
      findGraphemeOccurrences(values, query.characters.toList(growable: false));

  Map<String, List<int>> occurrencesFor(Iterable<String> queries) {
    final uniqueQueries = queries.toSet();
    if (uniqueQueries.length == 1) {
      final query = uniqueQueries.single;
      return {query: occurrences(query)};
    }
    final result = {for (final query in uniqueQueries) query: <int>[]};
    final root = _GraphemeTrieNode();
    for (final query in uniqueQueries) {
      final needle = query.characters.toList(growable: false);
      if (needle.isEmpty || needle.length > values.length) continue;
      var node = root;
      for (final grapheme in needle) {
        node = node.children.putIfAbsent(grapheme, _GraphemeTrieNode.new);
      }
      node.queries.add(query);
    }
    for (var start = 0; start < values.length; start++) {
      var node = root;
      for (var offset = start; offset < values.length; offset++) {
        final child = node.children[values[offset]];
        if (child == null) break;
        node = child;
        for (final query in node.queries) {
          result[query]!.add(start);
        }
      }
    }
    return result;
  }

  List<int> wordIndices() {
    final result = List<int>.filled(values.length + 1, 0);
    var hasText = false;
    var inWhitespace = false;
    var wordIndex = 0;
    for (var index = 0; index < values.length; index++) {
      final isWhitespace = _whitespace.hasMatch(values[index]);
      if (isWhitespace) {
        if (hasText && !inWhitespace) wordIndex++;
        inWhitespace = true;
      } else {
        hasText = true;
        inWhitespace = false;
      }
      result[index + 1] = wordIndex;
    }
    return result;
  }

  static List<PluginTextOffset> _offsets(String text) {
    final result = <PluginTextOffset>[
      const PluginTextOffset(grapheme: 0, codePoint: 0, utf16: 0),
    ];
    var grapheme = 0;
    var codePoint = 0;
    var utf16 = 0;
    for (final cluster in text.characters) {
      result.add(
        PluginTextOffset(
          grapheme: ++grapheme,
          codePoint: codePoint += cluster.runes.length,
          utf16: utf16 += cluster.length,
        ),
      );
    }
    return result;
  }
}

class _GraphemeTrieNode {
  final Map<String, _GraphemeTrieNode> children = {};
  final List<String> queries = [];
}
