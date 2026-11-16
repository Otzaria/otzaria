import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';
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

/// בקר העורך: מסתיר את הרווחים שנוצרו מתגיות בלוק בקצוות, ומציג את עיצוב
/// המקור. טקסט שהוקלד יורש את עיצוב התו שלפניו (או של הטקסט שהוחלף).
class PluginCorrectionController extends TextEditingController {
  late PluginCorrectionText source;
  String? _sourceText;
  String _prefix = '';
  String _suffix = '';
  List<CorrectionFormat> _formats = const [];
  String _sourceEditorText = '';
  List<CorrectionFormat> _sourceEditorFormats = const [];
  TextEditingValue? _editingValue;
  Object _formatSource = Object();
  List<({int end, CorrectionFormat format})> _runs = const [];

  PluginCorrectionController(String raw) {
    setSource(raw);
  }

  void setSource(String raw) {
    if (_sourceText == raw) return;
    source = PluginCorrectionText(raw);
    _sourceText = raw;
    final formats = _sourceFormats(source);
    final text = forEditor(source.plain);
    _sourceEditorText = text;
    _sourceEditorFormats = formats.sublist(
      _prefix.length,
      formats.length - _suffix.length,
    );
    _formats = _sourceEditorFormats;
    _formatSource = Object();
    _runs = _formatRuns(_formats);
    _setFormattedValue(TextEditingValue(text: text));
  }

  /// עיצוב כל יחידת UTF-16 בטקסט שבעורך.
  List<CorrectionFormat> get formats => List.unmodifiable(_formats);

  @override
  TextEditingValue get value => _editingValue ?? super.value;

  @override
  set value(TextEditingValue newValue) {
    if (newValue is _FormattedEditingValue &&
        identical(newValue.source, _formatSource)) {
      if (!identical(newValue.runs, _runs)) {
        _formats = newValue.expandFormats();
        _runs = newValue.runs;
      }
    } else if (newValue.text != text) {
      _formats =
          !newValue.selection.isValid && newValue.text == _sourceEditorText
          ? _sourceEditorFormats
          : _editFormats(value, newValue, _formats);
      _runs = _formatRuns(_formats);
    }
    _setFormattedValue(newValue);
  }

  /// שחזור טיוטה שאין עמה היסטוריית עריכה: העיצוב נגזר ממקור הפסקה.
  void restoreDraftValue(TextEditingValue newValue) {
    _formats = _remapFormats(
      _sourceEditorText,
      newValue.text,
      _sourceEditorFormats,
    );
    _runs = _formatRuns(_formats);
    _setFormattedValue(newValue);
  }

  void _setFormattedValue(TextEditingValue value) {
    final previous = this.value;
    final formatted = _formattedValue(value);
    _editingValue = formatted;
    super.value = formatted;
    if (previous == formatted &&
        previous is _FormattedEditingValue &&
        (!identical(previous.source, _formatSource) ||
            !identical(previous.runs, _runs))) {
      notifyListeners();
    }
  }

  _FormattedEditingValue _formattedValue(TextEditingValue value) {
    if (value is _FormattedEditingValue &&
        identical(value.source, _formatSource) &&
        identical(value.runs, _runs)) {
      return value;
    }
    return _FormattedEditingValue(
      value,
      source: _formatSource,
      runs: _runs,
    );
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

  static List<CorrectionFormat> _editFormats(
    TextEditingValue before,
    TextEditingValue after,
    List<CorrectionFormat> formats,
  ) {
    final delta = after.text.length - before.text.length;
    bool replaces(int start, int end) =>
        start >= 0 &&
        end <= before.text.length &&
        end >= start &&
        end - start + delta >= 0 &&
        after.text.startsWith(before.text.substring(0, start)) &&
        after.text.endsWith(before.text.substring(end));

    final selection = before.selection;
    TextRange? range;
    if (selection.isValid && replaces(selection.start, selection.end)) {
      range = selection;
    } else if (before.isComposingRangeValid &&
        !before.composing.isCollapsed &&
        replaces(before.composing.start, before.composing.end)) {
      range = before.composing;
    } else if (selection.isValid && selection.isCollapsed && delta < 0) {
      final caret = selection.extentOffset;
      final nextCaret = after.selection.isValid
          ? after.selection.extentOffset
          : null;
      if ((nextCaret == null || nextCaret == caret + delta) &&
          replaces(caret + delta, caret)) {
        range = TextRange(start: caret + delta, end: caret);
      } else if ((nextCaret == null || nextCaret == caret) &&
          replaces(caret, caret - delta)) {
        range = TextRange(start: caret, end: caret - delta);
      }
    }
    if (range == null) {
      var start = 0;
      while (start < before.text.length &&
          start < after.text.length &&
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
      range = TextRange(start: start, end: end);
    }
    final addedEnd = range.end + delta;
    return [
      ...formats.sublist(0, range.start),
      ..._replaceFormats(
        before.text.substring(range.start, range.end),
        after.text.substring(range.start, addedEnd),
        formats.sublist(range.start, range.end),
        previous: range.start > 0 ? formats[range.start - 1] : null,
        next: range.end < formats.length ? formats[range.end] : null,
      ),
      ...formats.sublist(range.end),
    ];
  }

  String forEditor(String canonical) {
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

  String forService(String visible) => _prefix + visible + _suffix;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_formats.length != text.length ||
        _formats.every((format) => format == _plainFormat)) {
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
      final format = _formats[start];
      final inComposing = start >= composing.start && start < composing.end;
      var end = start + 1;
      while (end < text.length &&
          _formats[end] == format &&
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

// היסטוריית Flutter שומרת את העיצוב עם אותו ערך, גם כשנוסחים זהים נוצרו אחרת.
class _FormattedEditingValue extends TextEditingValue {
  _FormattedEditingValue(
    TextEditingValue value, {
    required this.source,
    required this.runs,
  }) : super(
         text: value.text,
         selection: value.selection,
         composing: value.composing,
       );

  final Object source;
  final List<({int end, CorrectionFormat format})> runs;

  List<CorrectionFormat> expandFormats() {
    final result = <CorrectionFormat>[];
    var start = 0;
    for (final run in runs) {
      result.addAll(List.filled(run.end - start, run.format));
      start = run.end;
    }
    return result;
  }

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
        ? _FormattedEditingValue(result, source: source, runs: runs)
        : result;
  }
}
