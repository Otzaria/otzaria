import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';
import 'package:otzaria/plugins/view/plugin_correction_projection.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart'
    show TextDiffOp, computeTextDiff;
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

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

const CorrectionFormat _plainFormat = (
  bold: false,
  italic: false,
  underline: false,
  strike: false,
  link: false,
  scale: 1,
  heading: null,
);

/// הטקסט המלא של הפסקה ועיצובו. כל עריכה ממוזגת אליו, וכל ערך בהיסטוריית
/// הביטול נושא אותו.
class _EditorState {
  _EditorState(this.projection, this.runs);

  final CorrectionProjection projection;
  final List<({int end, CorrectionFormat format})> runs;

  late final List<CorrectionFormat> fullFormats = _expand();
  late final List<CorrectionFormat> visibleFormats = [
    for (var i = 0; i < projection.visible.length; i++)
      fullFormats[projection.fullOffset(i)],
  ];

  List<CorrectionFormat> _expand() {
    final result = <CorrectionFormat>[];
    var start = 0;
    for (final run in runs) {
      result.addAll(List.filled(run.end - start, run.format));
      start = run.end;
    }
    return result;
  }

  _EditorState withHiding({required bool nikud, required bool teamim}) {
    final next = projection.withHiding(nikud: nikud, teamim: teamim);
    return identical(next, projection) ? this : _EditorState(next, runs);
  }
}

/// בקר העורך: מסתיר את רווחי תגיות הבלוק בקצוות ואת מה שהקורא מסתיר, ומציג את
/// עיצוב המקור. כל עריכה ממוזגת אל הטקסט המלא לפי הטווח שנערך.
class PluginCorrectionController extends TextEditingController {
  late PluginCorrectionText source;
  String? _sourceText;
  String _prefix = '';
  String _suffix = '';
  bool _removeNikud;
  bool _removeTeamim;
  late _EditorState _state;
  late _EditorState _sourceState;
  TextEditingValue? _editingValue;
  Object _epoch = Object();
  ({TextEditingValue before, TextEditingValue after, _EditorState result})?
  _pending;

  PluginCorrectionController(
    String raw, {
    this._removeNikud = false,
    this._removeTeamim = false,
  }) {
    setSource(raw);
  }

  void setSource(String raw) {
    if (_sourceText == raw) return;
    source = PluginCorrectionText(raw);
    _sourceText = raw;
    final formats = _sourceFormats(source);
    final text = _stripMargins(source.plain);
    _sourceState = _stateOf(
      text,
      formats.sublist(_prefix.length, formats.length - _suffix.length),
    );
    _state = _sourceState;
    _epoch = Object();
    _pending = null;
    _setFormattedValue(TextEditingValue(text: _state.projection.visible));
  }

  /// מחליף מה מוסתר, בלי לגעת בטקסט המלא; הבחירה עוברת למקומה בטקסט הגלוי.
  void setHiding({required bool nikud, required bool teamim}) {
    if (nikud == _removeNikud && teamim == _removeTeamim) return;
    _removeNikud = nikud;
    _removeTeamim = teamim;
    _sourceState = _sourceState.withHiding(nikud: nikud, teamim: teamim);
    _pending = null;
    _showState(_state.withHiding(nikud: nikud, teamim: teamim), value);
  }

  /// עיצוב כל יחידת UTF-16 בטקסט שבעורך.
  List<CorrectionFormat> get formats =>
      List.unmodifiable(_state.visibleFormats);

  /// הטקסט המלא של הפסקה, כפי שהשירות שומר אותו.
  String get canonical => _prefix + _state.projection.full + _suffix;

  /// הטקסט המלא שיתקבל אם [after] יחליף את הערך הנוכחי.
  String canonicalAfter(TextEditingValue after) =>
      _prefix + _stateAfter(after).projection.full + _suffix;

  /// שחזור טיוטה שאין עמה היסטוריית עריכה: העיצוב נגזר ממקור הפסקה.
  void restoreCanonical(String canonical) {
    final text = _stripMargins(canonical);
    final formats = _remapFormats(
      _sourceState.projection.full,
      text,
      _sourceState.fullFormats,
    );
    _pending = null;
    _showState(_stateOf(text, formats), value);
  }

  _EditorState _stateOf(String full, List<CorrectionFormat> formats) =>
      _EditorState(
        CorrectionProjection(
          full,
          nikud: _removeNikud,
          teamim: _removeTeamim,
        ),
        _formatRuns(formats),
      );

  /// מציג [state] ומעביר אליו את הבחירה של [from] דרך הטקסט המלא.
  void _showState(_EditorState state, TextEditingValue from) {
    final shown = _shown(from, _state.projection, state.projection);
    _state = state;
    _setFormattedValue(shown);
  }

  static TextEditingValue _shown(
    TextEditingValue from,
    CorrectionProjection previous,
    CorrectionProjection next,
  ) {
    int map(int offset) => offset < 0
        ? offset
        : next.visibleOffset(
            previous.fullOffset(offset.clamp(0, previous.visible.length)),
          );
    final selection = from.selection;
    return TextEditingValue(
      text: next.visible,
      selection: selection.isValid
          ? TextSelection(
              baseOffset: map(selection.baseOffset),
              extentOffset: map(selection.extentOffset),
            )
          : selection,
    );
  }

  @override
  TextEditingValue get value => _editingValue ?? super.value;

  @override
  set value(TextEditingValue newValue) {
    if (newValue is _FormattedEditingValue &&
        identical(newValue.epoch, _epoch)) {
      final state = newValue.state.withHiding(
        nikud: _removeNikud,
        teamim: _removeTeamim,
      );
      // ערך מההיסטוריה שנוצר לפני שהוחלף מה שמוסתר.
      if (!identical(state, newValue.state)) {
        newValue = _shown(
          newValue,
          newValue.state.projection,
          state.projection,
        );
      }
      _state = state;
    } else if (newValue.text != text) {
      _state =
          !newValue.selection.isValid &&
              newValue.text == _sourceState.projection.visible
          ? _sourceState
          : _stateAfter(newValue);
    }
    _setFormattedValue(newValue);
  }

  void _setFormattedValue(TextEditingValue value) {
    final previous = this.value;
    final formatted = _formattedValue(value);
    _editingValue = formatted;
    super.value = formatted;
    if (previous == formatted &&
        previous is _FormattedEditingValue &&
        (!identical(previous.epoch, _epoch) ||
            !identical(previous.state, _state))) {
      notifyListeners();
    }
  }

  _FormattedEditingValue _formattedValue(TextEditingValue value) {
    if (value is _FormattedEditingValue &&
        identical(value.epoch, _epoch) &&
        identical(value.state, _state)) {
      return value;
    }
    return _FormattedEditingValue(value, epoch: _epoch, state: _state);
  }

  static List<({int end, CorrectionFormat format})> _formatRuns(
    List<CorrectionFormat> formats,
  ) {
    final runs = <({int end, CorrectionFormat format})>[];
    for (var i = 0; i < formats.length; i++) {
      if (i + 1 == formats.length || formats[i] != formats[i + 1]) {
        runs.add((end: i + 1, format: formats[i]));
      }
    }
    return runs;
  }

  /// המצב אחרי ש-[after] מחליף את הערך הנוכחי.
  _EditorState _stateAfter(TextEditingValue after) {
    if (after.text == text) return _state;
    final before = value;
    final pending = _pending;
    if (pending != null && pending.before == before && pending.after == after) {
      return pending.result;
    }
    final result = _edit(before, after);
    _pending = (before: before, after: after, result: result);
    return result;
  }

  /// הטווח ב-[before] ש-[after] החליף: לפי הבחירה, ההרכבה או מחיקה בסמן. רק בלי
  /// הסבר כזה משווים את הטקסטים, בעוגן בסמן החדש.
  static TextRange _editRange(TextEditingValue before, TextEditingValue after) {
    final delta = after.text.length - before.text.length;
    bool replaces(int start, int end) =>
        start >= 0 &&
        end <= before.text.length &&
        end >= start &&
        end - start + delta >= 0 &&
        after.text.startsWith(before.text.substring(0, start)) &&
        after.text.endsWith(before.text.substring(end));

    final selection = before.selection;
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

  /// ממזג את העריכה אל הטקסט המלא: רק הטווח שנערך מוחלף, כולל הסימנים
  /// המוסתרים שבתוכו, וכל השאר נשאר כמות שהוא.
  _EditorState _edit(TextEditingValue before, TextEditingValue after) {
    final range = _editRange(before, after);
    final delta = after.text.length - before.text.length;
    final removed = before.text.substring(range.start, range.end);
    final added = after.text.substring(range.start, range.end + delta);
    final (prefix, suffix) = _commonAffixes(removed, added);
    final inserted = added.substring(prefix, added.length - suffix);
    final projection = _state.projection;
    final start = projection.fullOffset(range.start + prefix);
    final end = projection.fullOffset(range.end - suffix);
    final visibleFormats = _state.visibleFormats;
    final insertedFormats = _replaceFormats(
      removed,
      added,
      visibleFormats.sublist(range.start, range.end),
      previous: range.start > 0 ? visibleFormats[range.start - 1] : null,
      next: range.end < visibleFormats.length
          ? visibleFormats[range.end]
          : null,
    ).sublist(prefix, added.length - suffix);
    final fullFormats = _state.fullFormats;
    return _stateOf(projection.full.replaceRange(start, end, inserted), [
      ...fullFormats.sublist(0, start),
      ...insertedFormats,
      ...fullFormats.sublist(end),
    ]);
  }

  /// אורך הרצף המשותף בתחילת [removed] ו-[added], ואורך הרצף המשותף בסופם.
  static (int, int) _commonAffixes(String removed, String added) {
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

  String _stripMargins(String canonical) {
    final prefix = source.plain.substring(0, source.visibleStart);
    final suffix = source.plain.substring(source.visibleEnd);
    _prefix = '';
    _suffix = '';
    if (!canonical.startsWith(prefix) ||
        !canonical.endsWith(suffix) ||
        canonical.length < prefix.length + suffix.length) {
      return canonical;
    }
    _prefix = prefix;
    _suffix = suffix;
    return canonical.substring(prefix.length, canonical.length - suffix.length);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final formats = _state.visibleFormats;
    if (formats.length != text.length ||
        formats.every((format) => format == _plainFormat)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final base = style ?? const TextStyle();
    final linkColor = Theme.of(context).colorScheme.primary;
    final children = <TextSpan>[];
    var start = 0;
    while (start < text.length) {
      final format = formats[start];
      final inComposing = start >= composing.start && start < composing.end;
      var end = start + 1;
      while (end < text.length &&
          formats[end] == format &&
          end != composing.start &&
          end != composing.end) {
        end++;
      }
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: _resolve(format, base, linkColor, inComposing),
        ),
      );
      start = end;
    }
    return TextSpan(style: style, children: children);
  }

  static TextStyle? _resolve(
    CorrectionFormat format,
    TextStyle base,
    Color linkColor,
    bool composing,
  ) {
    if (format == _plainFormat && !composing) return null;
    var style = base;
    if (format.heading != null) {
      style =
          SimpleInlineHtml.headingStyleForTag(format.heading!, style) ?? style;
    }
    if (format.scale != 1) {
      style = style.copyWith(fontSize: (style.fontSize ?? 14) * format.scale);
    }
    if (format.bold) {
      style = style.copyWith(
        fontWeight: FontWeight.bold,
        fontVariations: AppFonts.boldFontVariations(style.fontFamily),
      );
    }
    if (format.italic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (format.link) style = style.copyWith(color: linkColor);
    final decorations = [
      if (format.underline || format.link || composing)
        TextDecoration.underline,
      if (format.strike) TextDecoration.lineThrough,
    ];
    if (decorations.isNotEmpty) {
      style = style.copyWith(
        decoration: decorations.length == 1
            ? decorations.single
            : TextDecoration.combine(decorations),
      );
    }
    return style;
  }

  static final _tagName = RegExp(r'^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)');
  static final _href = RegExp(r'\shref\s*=', caseSensitive: false);
  static const _voidTags = {'br', 'hr', 'img', 'wbr', 'input', 'meta', 'link'};

  /// עיצוב לכל תו ב-[PluginCorrectionText.plain], לפי מחסנית התגיות הפתוחות.
  static List<CorrectionFormat> _sourceFormats(PluginCorrectionText text) {
    final formats = List<CorrectionFormat>.filled(
      text.plain.length,
      _plainFormat,
    );
    final open = <({String name, bool href})>[];
    var tagIndex = 0;
    var filled = 0;
    for (final node in text.nodes) {
      final rawStart = node.boundaries[0]!;
      while (tagIndex < text.tags.length &&
          text.tags[tagIndex].end <= rawStart) {
        final tag = text.tags[tagIndex++];
        final raw = text.source.substring(tag.start, tag.end);
        final match = _tagName.firstMatch(raw);
        if (match == null) continue;
        final name = match[2]!.toLowerCase();
        if (match[1]!.isNotEmpty) {
          final index = open.lastIndexWhere((tag) => tag.name == name);
          if (index >= 0) open.removeAt(index);
        } else if (!_voidTags.contains(name) && !raw.endsWith('/>')) {
          open.add((name: name, href: name == 'a' && _href.hasMatch(raw)));
        }
      }
      final format = _formatOf(open);
      formats.fillRange(filled, node.end, format);
      filled = node.end;
    }
    return formats;
  }

  static CorrectionFormat _formatOf(List<({String name, bool href})> open) {
    var bold = false;
    var italic = false;
    var underline = false;
    var strike = false;
    var link = false;
    var scale = 1.0;
    String? heading;
    for (final tag in open) {
      switch (tag.name) {
        case 'b' || 'strong':
          bold = true;
        case 'i' || 'em' || 'cite' || 'dfn' || 'var':
          italic = true;
        case 'u' || 'ins':
          underline = true;
        case 's' || 'strike' || 'del':
          strike = true;
        case 'big':
          scale *= kHtmlLargerFontScale;
        case 'small' || 'sup' || 'sub':
          scale *= kHtmlSmallerFontScale;
        case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
          heading = tag.name;
        case 'a' when tag.href:
          link = true;
      }
    }
    return (
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      link: link,
      scale: scale,
      heading: heading,
    );
  }

  /// מעביר עיצוב מ-[before] ל-[after]: טקסט שלא השתנה שומר את עיצובו, וטקסט
  /// חדש יורש מהטקסט שהחליף או מהתו שלפניו.
  static List<CorrectionFormat> _remapFormats(
    String before,
    String after,
    List<CorrectionFormat> formats,
  ) {
    if (formats.length != before.length) {
      return List.filled(after.length, _plainFormat);
    }
    final result = <CorrectionFormat>[];
    var offset = 0;
    final removed = StringBuffer();
    final added = StringBuffer();
    void flush() {
      if (removed.isEmpty && added.isEmpty) return;
      final old = formats.sublist(offset, offset + removed.length);
      final end = offset + removed.length;
      result.addAll(
        old.isNotEmpty && old.any((format) => format != old.first)
            ? List.filled(added.length, _plainFormat)
            : _replaceFormats(
                removed.toString(),
                added.toString(),
                old,
                previous: result.isEmpty ? null : result.last,
                next: end < formats.length ? formats[end] : null,
              ),
      );
      offset += removed.length;
      removed.clear();
      added.clear();
    }

    for (final segment in computeTextDiff(before, after)) {
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
    // טיוטה שומרת נוסח בלבד; אין דרך לזהות איזה מופע חוזר נמחק.
    final words =
        <
          String,
          ({int count, List<CorrectionFormat> formats, bool ambiguous})
        >{};
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
                Iterable<int>.generate(current.length).any(
                  (index) => previous.formats[index] != current[index],
                )),
      );
    }
    final counts = <String, int>{};
    for (final match in tokens.allMatches(after)) {
      counts.update(match[0]!, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final match in tokens.allMatches(after)) {
      final original = words[match[0]!];
      if (original != null &&
          original.ambiguous &&
          original.count != counts[match[0]!]) {
        result.fillRange(match.start, match.end, _plainFormat);
      }
    }
    return result;
  }

  static List<CorrectionFormat> _replaceFormats(
    String removed,
    String added,
    List<CorrectionFormat> old, {
    CorrectionFormat? previous,
    CorrectionFormat? next,
  }) {
    final (prefix, suffix) = _commonAffixes(removed, added);
    final replaced = prefix < removed.length - suffix;
    final inherited = replaced
        ? old[prefix]
        : (prefix > 0 ? old[prefix - 1] : previous) ??
              (prefix < old.length ? old[prefix] : next) ??
              _plainFormat;
    return [
      ...old.sublist(0, prefix),
      ...List.filled(added.length - prefix - suffix, inherited),
      ...old.sublist(old.length - suffix),
    ];
  }
}

// היסטוריית Flutter שומרת את המצב המלא עם אותו ערך, גם כשנוסחים זהים נוצרו
// אחרת.
class _FormattedEditingValue extends TextEditingValue {
  _FormattedEditingValue(
    TextEditingValue value, {
    required this.epoch,
    required this.state,
  }) : super(
         text: value.text,
         selection: value.selection,
         composing: value.composing,
       );

  final Object epoch;
  final _EditorState state;

  @override
  TextEditingValue copyWith({
    String? text,
    TextSelection? selection,
    TextRange? composing,
  }) {
    final result = super.copyWith(
      text: text,
      selection: selection,
      composing: composing,
    );
    return text == null || text == this.text
        ? _FormattedEditingValue(result, epoch: epoch, state: state)
        : result;
  }
}
