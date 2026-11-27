import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';
import 'package:otzaria/plugins/view/plugin_correction_edit.dart';
import 'package:otzaria/plugins/view/plugin_correction_projection.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

export 'package:otzaria/plugins/view/plugin_correction_edit.dart'
    show CorrectionFormat;

typedef CorrectionUndoValue = ({String canonical, TextEditingValue editing});

/// בקר העורך: מסתיר את רווחי תגיות הבלוק בקצוות ואת מה שהקורא מסתיר, ומציג את
/// עיצוב המקור. כל עריכה ממוזגת אל הטקסט המלא לפי הטווח שנערך.
class PluginCorrectionController extends TextEditingController {
  late PluginCorrectionText source;
  String? _sourceText;
  String _prefix = '';
  String _suffix = '';
  bool _removeNikud;
  bool _removeTeamim;
  late EditorState _state;
  late EditorState _sourceState;
  TextEditingValue? _editingValue;
  Object _epoch = Object();
  ({
    TextEditingValue before,
    TextEditingValue after,
    CorrectionEdit result,
    CorrectionComposition composition,
  })?
  _pending;

  CorrectionComposition? _composition;
  final VoidCallback? onEdit;
  ValueNotifier<CorrectionUndoValue>? _undoValue;

  /// כמו בקריאה: טקסט שבין סוגריים מוצג מוקטן (`RenderSettings.formatParentheses`).
  bool formatParentheses = true;

  PluginCorrectionController(
    String raw, {
    this._removeNikud = false,
    this._removeTeamim = false,
    this.onEdit,
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
    _composition = null;
    _setFormattedValue(TextEditingValue(text: _state.projection.visible));
    _resetUndo();
  }

  /// ערכי ביטול שמשתנים גם כשעריכה משנה רק סימנים מוסתרים.
  ValueNotifier<CorrectionUndoValue> get undoValue => _undoValue!;

  CorrectionUndoValue get _snapshot => (canonical: canonical, editing: value);

  void _resetUndo() {
    _undoValue?.dispose();
    _undoValue = ValueNotifier(_snapshot);
  }

  void applyUndoValue(CorrectionUndoValue snapshot) {
    undoValue.value = snapshot;
    value = snapshot.editing;
  }

  @override
  void dispose() {
    undoValue.dispose();
    super.dispose();
  }

  /// מחליף מה מוסתר, בלי לגעת בטקסט המלא; הבחירה עוברת למקומה בטקסט הגלוי.
  void setHiding({required bool nikud, required bool teamim}) {
    if (nikud == _removeNikud && teamim == _removeTeamim) return;
    _removeNikud = nikud;
    _removeTeamim = teamim;
    _sourceState = _sourceState.withHiding(nikud: nikud, teamim: teamim);
    _pending = null;
    _composition = null;
    _showState(_state.withHiding(nikud: nikud, teamim: teamim), value);
  }

  /// עיצוב כל יחידת UTF-16 בטקסט שבעורך.
  List<CorrectionFormat> get formats =>
      List.unmodifiable(_state.visibleFormats);

  /// הטקסט המלא של הפסקה, כפי שהשירות שומר אותו.
  String get canonical => _prefix + _state.projection.full + _suffix;

  /// הטקסט המלא שיתקבל אם [after] יחליף את הערך הנוכחי.
  String canonicalAfter(TextEditingValue after) =>
      _prefix + _editAfter(after).state.projection.full + _suffix;

  /// שחזור טיוטה שאין עמה היסטוריית עריכה: העיצוב נגזר ממקור הפסקה.
  void restoreCanonical(String canonical) {
    final text = _stripMargins(canonical);
    final formats = remapFormats(
      _sourceState.projection.full,
      text,
      _sourceState.fullFormats,
    );
    _pending = null;
    _composition = null;
    _showState(_stateOf(text, formats), value);
    _resetUndo();
  }

  EditorState _stateOf(String full, List<CorrectionFormat> formats) =>
      EditorState.of(full, formats, nikud: _removeNikud, teamim: _removeTeamim);

  /// מציג [state] ומעביר אליו את הבחירה של [from] דרך הטקסט המלא.
  void _showState(EditorState state, TextEditingValue from) {
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
          ? selection.copyWith(
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
    final previous = _state;
    final before = value;
    if (newValue is _FormattedEditingValue &&
        identical(newValue.epoch, _epoch) &&
        !identical(newValue.state, _state)) {
      newValue = _adoptHistoryValue(newValue);
    } else if (newValue.text != text) {
      final edit = _editAfter(newValue);
      // שינוי הטקסט בעיצומה של הרכבה עלול להחזיר את המקלדת לאותו קלט שוב.
      if (!newValue.composing.isCollapsed && newValue.text != edit.value.text) {
        return;
      }
      _state = edit.state;
      newValue = edit.value;
    }
    _commit(newValue, previous: previous, before: before);
  }

  /// ערך מההיסטוריה נושא את המצב שלו; ההסתרה הנוכחית גוברת על זו שבערך.
  TextEditingValue _adoptHistoryValue(_FormattedEditingValue value) {
    _composition = null;
    final state = value.state.withHiding(
      nikud: _removeNikud,
      teamim: _removeTeamim,
    );
    _state = state;
    return identical(state, value.state)
        ? value
        : _shown(value, value.state.projection, state.projection);
  }

  /// מציג את הערך שנקבע, ומעדכן הרכבה, טיוטה והיסטוריה.
  void _commit(
    TextEditingValue newValue, {
    required EditorState previous,
    required TextEditingValue before,
  }) {
    final pending = _pending;
    final composition =
        pending != null &&
            pending.before == before &&
            pending.result.value == newValue
        ? pending.composition
        : null;
    _pending = null;
    _setFormattedValue(newValue);
    _composition = value.composing.isCollapsed
        ? null
        : (composition ?? _composition ?? CorrectionComposition(previous));
    final changed = previous.projection.full != _state.projection.full;
    if (changed) onEdit?.call();
    if (value.composing.isCollapsed &&
        value.selection.isValid &&
        (changed ||
            !before.composing.isCollapsed ||
            !undoValue.value.editing.selection.isValid)) {
      undoValue.value = _snapshot;
    }
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

  /// המצב אחרי ש-[after] מחליף את הערך הנוכחי.
  CorrectionEdit _editAfter(TextEditingValue after) {
    if (after is _FormattedEditingValue && identical(after.epoch, _epoch)) {
      return (state: after.state, value: after);
    }
    if (after.text == text) return (state: _state, value: after);
    if (!after.selection.isValid &&
        after.text == _sourceState.projection.visible) {
      return (state: _sourceState, value: after);
    }
    final pending = _pending;
    if (pending != null && pending.before == value && pending.after == after) {
      return pending.result;
    }
    if (_composition == null && after.composing.isCollapsed) {
      return mergeEdit(_state, value, after);
    }
    final composition = _composition ?? CorrectionComposition(_state);
    final result = composition.apply(_state, value, after);
    _pending = (
      before: value,
      after: after,
      result: result.edit,
      composition: result.composition,
    );
    return result.edit;
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
    final parenthesized = formatParentheses ? _parenthesized(text) : null;
    final visibleFormats = _state.visibleFormats;
    if (parenthesized == null &&
        (visibleFormats.length != text.length ||
            visibleFormats.every(
              (format) => format == plainCorrectionFormat,
            ))) {
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
    final formats = visibleFormats.length == text.length
        ? visibleFormats
        : List.filled(text.length, plainCorrectionFormat);
    final children = <TextSpan>[];
    var start = 0;
    while (start < text.length) {
      final format = formats[start];
      final small = parenthesized?[start] ?? false;
      final inComposing = start >= composing.start && start < composing.end;
      var end = start + 1;
      while (end < text.length &&
          formats[end] == format &&
          (parenthesized?[end] ?? false) == small &&
          end != composing.start &&
          end != composing.end) {
        end++;
      }
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: _resolve(format, base, linkColor, inComposing, small),
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
    bool parenthesized,
  ) {
    if (format == plainCorrectionFormat && !composing && !parenthesized) {
      return null;
    }
    var style = base;
    if (parenthesized) {
      style = style.copyWith(
        fontSize: (style.fontSize ?? 14) * kHtmlSmallerFontScale,
      );
    }
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

  /// תווים בתוך זוג סוגריים סמוך, באותו כלל של `formatTextWithParentheses`;
  /// null כשאין כאלה.
  static List<bool>? _parenthesized(String text) {
    List<bool>? marks;
    var open = -1;
    for (var i = 0; i < text.length; i++) {
      final char = text.codeUnitAt(i);
      if (char == 0x28) {
        open = i;
      } else if (char == 0x29) {
        if (open != -1) {
          marks ??= List.filled(text.length, false);
          marks.fillRange(open, i + 1, true);
        }
        open = -1;
      }
    }
    return marks;
  }

  static final _tagName = RegExp(r'^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)');
  static final _href = RegExp(r'\shref\s*=', caseSensitive: false);
  static const _voidTags = {'br', 'hr', 'img', 'wbr', 'input', 'meta', 'link'};

  /// עיצוב לכל תו ב-[PluginCorrectionText.plain], לפי מחסנית התגיות הפתוחות.
  static List<CorrectionFormat> _sourceFormats(PluginCorrectionText text) {
    final formats = List<CorrectionFormat>.filled(
      text.plain.length,
      plainCorrectionFormat,
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
  final EditorState state;

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
