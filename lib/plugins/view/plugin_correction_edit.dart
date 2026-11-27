import 'package:flutter/services.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';
import 'package:otzaria/plugins/view/plugin_correction_projection.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart'
    show TextDiffOp, TextDiffSegment, computeTextDiff;

/// עיצוב תו בעורך: תת-קבוצה של תגיות המקור שהעורך יודע להציג.
typedef CorrectionFormat = ({
  bool bold,
  bool italic,
  bool underline,
  bool strike,
  bool link,
  double scale,
  String? heading,
});

const CorrectionFormat plainCorrectionFormat = (
  bold: false,
  italic: false,
  underline: false,
  strike: false,
  link: false,
  scale: 1,
  heading: null,
);

typedef CorrectionAttributes = ({
  CorrectionFormat format,
  CorrectionHtmlOrigin? origin,
});

const CorrectionAttributes plainCorrectionAttributes = (
  format: plainCorrectionFormat,
  origin: null,
);

CorrectionHtmlOrigin? _inheritedOrigin(CorrectionHtmlOrigin? origin) =>
    origin == null ? null : (slot: origin.slot, spelling: null);

CorrectionAttributes _inheritedAttributes(CorrectionAttributes attributes) => (
  format: attributes.format,
  origin: _inheritedOrigin(attributes.origin),
);

/// הטקסט המלא של פסקה, עיצובו, והטקסט הגלוי ממנו. כל עריכה ממוזגת אליו, וכל ערך
/// בהיסטוריית הביטול נושא אותו.
class EditorState {
  EditorState(this.projection, this.runs);

  factory EditorState.of(
    String full,
    List<CorrectionAttributes> attributes, {
    required bool nikud,
    required bool teamim,
  }) {
    final runs = <({int end, CorrectionAttributes attributes})>[];
    for (var i = 0; i < attributes.length; i++) {
      if (i + 1 == attributes.length || attributes[i] != attributes[i + 1]) {
        runs.add((end: i + 1, attributes: attributes[i]));
      }
    }
    return EditorState(
      CorrectionProjection(full, nikud: nikud, teamim: teamim),
      runs,
    );
  }

  final CorrectionProjection projection;
  final List<({int end, CorrectionAttributes attributes})> runs;

  late final List<CorrectionAttributes> fullAttributes = _expand();
  late final List<CorrectionAttributes> visibleAttributes = [
    for (var i = 0; i < projection.visible.length; i++)
      fullAttributes[projection.fullOffset(i)],
  ];
  late final List<CorrectionFormat> visibleFormats = [
    for (final item in visibleAttributes) item.format,
  ];

  List<CorrectionAttributes> _expand() {
    final result = <CorrectionAttributes>[];
    var start = 0;
    for (final run in runs) {
      result.addAll(List.filled(run.end - start, run.attributes));
      start = run.end;
    }
    return result;
  }

  EditorState withHiding({required bool nikud, required bool teamim}) {
    final next = projection.withHiding(nikud: nikud, teamim: teamim);
    return identical(next, projection) ? this : EditorState(next, runs);
  }
}

/// המצב שאחרי עריכה, והערך שיוצג בשדה.
typedef CorrectionEdit = ({EditorState state, TextEditingValue value});

/// ממזג את [after] אל [base], כש-[before] הוא הערך הגלוי ש-[base] הציג.
///
/// רק הטווח שנערך מוחלף בטקסט המלא, כולל הסימנים המוסתרים שבתוכו; כל השאר
/// נשאר כמות שהוא.
CorrectionEdit mergeEdit(
  EditorState base,
  TextEditingValue before,
  TextEditingValue after,
) {
  final range = _editRange(before, after);
  final delta = after.text.length - before.text.length;
  final removed = before.text.substring(range.start, range.end);
  final added = after.text.substring(range.start, range.end + delta);
  final explicitSelection =
      before.selection.isValid &&
      !before.selection.isCollapsed &&
      before.selection.start == range.start &&
      before.selection.end == range.end;
  final (prefix, suffix) = explicitSelection
      ? (0, 0)
      : commonAffixes(removed, added);
  final inserted = added.substring(prefix, added.length - suffix);
  final projection = base.projection;
  final start = projection.fullOffset(range.start + prefix);
  final end = projection.fullOffset(range.end - suffix);
  final visibleAttributes = base.visibleAttributes;
  final insertedAttributes = _replaceAttributes(
    removed,
    added,
    visibleAttributes.sublist(range.start, range.end),
    fallback: plainCorrectionAttributes,
    inherit: _inheritedAttributes,
    previous: range.start > 0 ? visibleAttributes[range.start - 1] : null,
    next: range.end < visibleAttributes.length
        ? visibleAttributes[range.end]
        : null,
  ).sublist(prefix, added.length - suffix);
  final fullAttributes = base.fullAttributes;
  final state = EditorState.of(
    projection.full.replaceRange(start, end, inserted),
    [
      ...fullAttributes.sublist(0, start),
      ...insertedAttributes,
      ...fullAttributes.sublist(end),
    ],
    nikud: projection.nikud,
    teamim: projection.teamim,
  );
  final projected = state.projection;
  if (after.text == projected.visible) return (state: state, value: after);

  final visibleStart = range.start + prefix;
  final insertedEnd = visibleStart + inserted.length;
  int map(int offset) {
    if (offset < 0) return offset;
    if (offset < visibleStart) {
      return projected.visibleOffset(projection.fullOffset(offset));
    }
    if (offset <= insertedEnd) {
      return projected.visibleOffset(start + offset - visibleStart);
    }
    return projected.visibleOffset(
      projection.fullOffset(offset - delta) + inserted.length - (end - start),
    );
  }

  return (
    state: state,
    value: after.copyWith(
      text: projected.visible,
      selection: after.selection.copyWith(
        baseOffset: map(after.selection.baseOffset),
        extentOffset: map(after.selection.extentOffset),
      ),
      composing: TextRange.empty,
    ),
  );
}

/// מקטעי ההרכבה שומרים טווחי מקור גם כשהמקלדת מזיזה או מרחיבה את ההרכבה.
class CorrectionComposition {
  CorrectionComposition(this.source)
    : pieces = [
        for (var i = 0; i < source.projection.visible.length; i++)
          (start: i, end: i + 1, length: 1),
      ];

  CorrectionComposition._(this.source, this.pieces);

  final EditorState source;
  final List<({int start, int end, int length})> pieces;

  ({CorrectionEdit edit, CorrectionComposition composition}) apply(
    EditorState current,
    TextEditingValue before,
    TextEditingValue after,
  ) {
    if (after.text == source.projection.visible) {
      return (
        edit: (state: source, value: after),
        composition: CorrectionComposition(source),
      );
    }
    final range = _editRange(before, after);
    var first = 0;
    var start = 0;
    while (first < pieces.length &&
        (pieces[first].length == 0
            ? start < range.start
            : start + pieces[first].length <= range.start)) {
      start += pieces[first++].length;
    }
    var last = first;
    var end = start;
    while (last < pieces.length &&
        (end < range.end || (pieces[last].length == 0 && end == range.end))) {
      end += pieces[last++].length;
    }
    final originStart = first < pieces.length
        ? pieces[first].start
        : source.projection.visible.length;
    final originEnd = last > first ? pieces[last - 1].end : originStart;
    final delta = after.text.length - before.text.length;
    final replacement = after.text.substring(start, end + delta);
    final next = CorrectionComposition._(source, [
      ...pieces.take(first),
      (start: originStart, end: originEnd, length: replacement.length),
      ...pieces.skip(last),
    ]);
    var edit = mergeEdit(current, before, after);
    if (replacement ==
        source.projection.visible.substring(originStart, originEnd)) {
      final old = edit.state.projection;
      final fullStart = old.fullOffset(start);
      final fullEnd = old.fullOffset(start + replacement.length);
      final original = source.projection;
      final originalStart = original.fullOffset(originStart);
      final originalEnd = original.fullOffset(originEnd);
      final state = EditorState.of(
        old.full.replaceRange(
          fullStart,
          fullEnd,
          original.full.substring(originalStart, originalEnd),
        ),
        [
          ...edit.state.fullAttributes.take(fullStart),
          ...source.fullAttributes.sublist(originalStart, originalEnd),
          ...edit.state.fullAttributes.skip(fullEnd),
        ],
        nikud: old.nikud,
        teamim: old.teamim,
      );
      edit = (state: state, value: edit.value);
    }
    return (edit: edit, composition: next);
  }
}

/// הטווח ב-[before] ש-[after] החליף: לפי הבחירה, ההרכבה או מחיקה בסמן. רק בלי
/// הסבר כזה משווים את הטקסטים, בעוגן בסמן החדש.
TextRange _editRange(TextEditingValue before, TextEditingValue after) {
  final delta = after.text.length - before.text.length;
  bool replaces(int start, int end) =>
      start >= 0 &&
      end <= before.text.length &&
      end >= start &&
      end - start + delta >= 0 &&
      after.text.startsWith(before.text.substring(0, start)) &&
      after.text.endsWith(before.text.substring(end));

  final selection = before.selection;
  if (selection.isValid &&
      !selection.isCollapsed &&
      replaces(selection.start, selection.end)) {
    return selection;
  }
  if (before.isComposingRangeValid &&
      !before.composing.isCollapsed &&
      after.isComposingRangeValid &&
      !after.composing.isCollapsed &&
      (after.composing.end <= before.composing.start ||
          after.composing.start >= before.composing.end)) {
    final start = after.composing.start;
    final end = after.composing.end - delta;
    if (replaces(start, end)) return TextRange(start: start, end: end);
  }
  if (selection.isValid && replaces(selection.start, selection.end)) {
    return selection;
  }
  if (before.isComposingRangeValid &&
      !before.composing.isCollapsed &&
      replaces(before.composing.start, before.composing.end)) {
    return before.composing;
  }
  if (selection.isValid && selection.isCollapsed && delta < 0) {
    final caret = selection.extentOffset;
    final nextCaret = after.selection.isValid
        ? after.selection.extentOffset
        : null;
    if ((nextCaret == null || nextCaret == caret + delta) &&
        replaces(caret + delta, caret)) {
      return TextRange(start: caret + delta, end: caret);
    }
    if ((nextCaret == null || nextCaret == caret) &&
        replaces(caret, caret - delta)) {
      return TextRange(start: caret, end: caret - delta);
    }
  }
  var start = 0;
  final limit = after.selection.isValid
      ? after.selection.extentOffset
      : after.text.length;
  while (start < before.text.length &&
      start < after.text.length &&
      start < limit &&
      before.text.codeUnitAt(start) == after.text.codeUnitAt(start)) {
    start++;
  }
  var end = before.text.length;
  while (end > start &&
      end + delta > start &&
      before.text.codeUnitAt(end - 1) ==
          after.text.codeUnitAt(end + delta - 1)) {
    end--;
  }
  return TextRange(start: start, end: end);
}

/// אורך הרצף המשותף בתחילת [removed] ו-[added], ואורך הרצף המשותף בסופם.
(int, int) commonAffixes(String removed, String added) {
  var prefix = 0;
  while (prefix < removed.length &&
      prefix < added.length &&
      removed.codeUnitAt(prefix) == added.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < removed.length - prefix &&
      suffix < added.length - prefix &&
      removed.codeUnitAt(removed.length - 1 - suffix) ==
          added.codeUnitAt(added.length - 1 - suffix)) {
    suffix++;
  }
  return (prefix, suffix);
}

/// עיצוב הטקסט החדש [added] במקום [removed]: מה שנשאר זהה שומר את עיצובו, והשאר
/// יורש מהטקסט שהוחלף או מהתו שלפניו.
List<T> _replaceAttributes<T>(
  String removed,
  String added,
  List<T> old, {
  required T fallback,
  T Function(T)? inherit,
  T? previous,
  T? next,
}) {
  final (prefix, suffix) = commonAffixes(removed, added);
  final replaced = prefix < removed.length - suffix;
  final inherited = replaced
      ? old[prefix]
      : (prefix > 0 ? old[prefix - 1] : previous) ??
            (prefix < old.length ? old[prefix] : next) ??
            fallback;
  return [
    ...old.sublist(0, prefix),
    ...List.filled(
      added.length - prefix - suffix,
      inherit == null ? inherited : inherit(inherited),
    ),
    ...old.sublist(old.length - suffix),
  ];
}

/// מעביר עיצוב מ-[before] ל-[after]: טקסט שלא השתנה שומר את עיצובו, וטקסט
/// חדש יורש מהטקסט שהחליף או מהתו שלפניו.
List<T> _remapAttributes<T>(
  String before,
  String after,
  List<T> formats,
  List<TextDiffSegment> diff, {
  required T fallback,
  T Function(T)? inherit,
  bool Function(T, T)? equivalent,
  bool suppressAmbiguousRepeats = false,
}) {
  if (formats.length != before.length) {
    return List.filled(after.length, fallback);
  }
  final result = <T>[];
  var offset = 0;
  bool same(T a, T b) => equivalent?.call(a, b) ?? a == b;
  final removed = StringBuffer();
  final added = StringBuffer();
  void flush() {
    if (removed.isEmpty && added.isEmpty) return;
    final old = formats.sublist(offset, offset + removed.length);
    final end = offset + removed.length;
    result.addAll(
      old.isNotEmpty && old.any((format) => !same(format, old.first))
          ? List.filled(added.length, fallback)
          : _replaceAttributes(
              removed.toString(),
              added.toString(),
              old,
              fallback: fallback,
              inherit: inherit,
              previous: result.isEmpty ? null : result.last,
              next: end < formats.length ? formats[end] : null,
            ),
    );
    offset += removed.length;
    removed.clear();
    added.clear();
  }

  for (final segment in diff) {
    switch (segment.op) {
      case TextDiffOp.removed:
        removed.write(segment.text);
      case TextDiffOp.added:
        added.write(segment.text);
      case TextDiffOp.equal:
        flush();
        result.addAll(formats.sublist(offset, offset + segment.text.length));
        offset += segment.text.length;
    }
  }
  flush();
  if (before == after) return result;
  // כשמשחזרים מנוסח בלבד, אי אפשר לזהות איזה מופע חוזר נמחק.
  final words = <String, ({int count, List<T> formats, bool ambiguous})>{};
  final tokens = RegExp(r'\S+');
  for (final match in tokens.allMatches(before)) {
    final word = match[0]!;
    final previous = words[word];
    final current = formats.sublist(match.start, match.end);
    words[word] = (
      count: (previous?.count ?? 0) + 1,
      formats: previous?.formats ?? current,
      ambiguous:
          previous != null &&
          (previous.ambiguous ||
              Iterable<int>.generate(
                current.length,
              ).any((index) => !same(previous.formats[index], current[index]))),
    );
  }
  final counts = <String, int>{};
  if (!suppressAmbiguousRepeats) {
    for (final match in tokens.allMatches(after)) {
      counts.update(match[0]!, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  for (final match in tokens.allMatches(after)) {
    final original = words[match[0]!];
    if (original != null &&
        original.ambiguous &&
        (suppressAmbiguousRepeats || original.count != counts[match[0]!])) {
      result.fillRange(match.start, match.end, fallback);
    }
  }
  return result;
}

List<CorrectionAttributes> remapCorrectionAttributes(
  String before,
  String after,
  List<CorrectionAttributes> attributes, {
  required bool hasMarkup,
  List<CorrectionHtmlOrigin?>? restoredOrigins,
}) {
  if (before == after) return attributes;
  final diff = computeTextDiff(before, after);
  final formats = _remapAttributes(
    before,
    after,
    [for (final item in attributes) item.format],
    diff,
    fallback: plainCorrectionFormat,
  );
  final origins =
      restoredOrigins ??
      (hasMarkup
          ? _remapAttributes<CorrectionHtmlOrigin?>(
              before,
              after,
              [for (final item in attributes) item.origin],
              diff,
              fallback: ambiguousCorrectionOrigin,
              inherit: _inheritedOrigin,
              equivalent: (a, b) => a?.slot == b?.slot,
              suppressAmbiguousRepeats: true,
            )
          : null);
  final formatsBySlot = {
    if (restoredOrigins != null)
      for (final item in attributes) item.origin?.slot: item.format,
  };
  return [
    for (var i = 0; i < formats.length; i++)
      (
        format: formatsBySlot[origins?[i]?.slot] ?? formats[i],
        origin: origins?[i],
      ),
  ];
}
