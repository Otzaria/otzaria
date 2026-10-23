import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/plugins/services/plugin_correction_text.dart';
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/inline_html_text.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

/// בקר ששומר את סגנון המקור של התווים גם במהלך עריכה רגילה ו-IME.
class PluginCorrectionController extends TextEditingController {
  static final _styleTag = RegExp(
    r'^<(/?)(b|strong|i|em|u|big|small|span|font|a)(?=[\s/>])',
    caseSensitive: false,
  );
  late PluginCorrectionText source;
  List<int> _origins = [];
  String? _styledSource;
  TextStyle? _baseStyle;
  Color? _linkColor;
  Color? _primaryColor;
  List<TextStyle> _styles = [];
  String _prefix = '';
  String _suffix = '';
  TextSpan? _plainSpan;
  TextSpan? _composingSpan;

  void _invalidateSpans() {
    _plainSpan = null;
    _composingSpan = null;
  }

  PluginCorrectionController(String raw) {
    setSource(raw);
  }

  void setSource(String raw) {
    if (_styledSource == raw) return;
    source = PluginCorrectionText(raw);
    _styledSource = raw;
    _baseStyle = null;
    _invalidateSpans();
    final visible = forEditor(source.plain);
    _origins = List.generate(
      visible.length,
      (index) => source.visibleStart + index,
    );
    super.value = TextEditingValue(text: visible);
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
  set value(TextEditingValue next) {
    final previous = text;
    if (previous != next.text || value.composing != next.composing) {
      _invalidateSpans();
    }
    if (previous != next.text) {
      var prefix = 0;
      while (prefix < previous.length &&
          prefix < next.text.length &&
          previous.codeUnitAt(prefix) == next.text.codeUnitAt(prefix)) {
        prefix++;
      }
      var suffix = 0;
      while (suffix < previous.length - prefix &&
          suffix < next.text.length - prefix &&
          previous.codeUnitAt(previous.length - suffix - 1) ==
              next.text.codeUnitAt(next.text.length - suffix - 1)) {
        suffix++;
      }
      final selection = value.selection;
      final insertedLength =
          next.text.length - previous.length + selection.end - selection.start;
      if (selection.isValid &&
          selection.end <= previous.length &&
          insertedLength >= 0 &&
          next.selection.isCollapsed &&
          next.selection.extentOffset == selection.start + insertedLength &&
          previous.substring(0, selection.start) ==
              next.text.substring(0, selection.start) &&
          previous.substring(selection.end) ==
              next.text.substring(selection.start + insertedLength)) {
        prefix = selection.start;
        suffix = previous.length - selection.end;
      }
      final origin = _origins.isEmpty
          ? source.visibleStart
          : _origins[(prefix - 1).clamp(0, _origins.length - 1)];
      _origins = [
        ..._origins.take(prefix),
        ...List.filled(next.text.length - prefix - suffix, origin),
        ..._origins.skip(previous.length - suffix),
      ];
    }
    super.value = next;
  }

  void _styleSource(TextStyle base, ColorScheme colorScheme) {
    final linkColor = InlineHtmlText.readerLinkColor(colorScheme);
    final primaryColor = colorScheme.primary;
    if (_baseStyle == base &&
        _linkColor == linkColor &&
        _primaryColor == primaryColor) {
      return;
    }
    _baseStyle = base;
    _linkColor = linkColor;
    _primaryColor = primaryColor;
    _invalidateSpans();
    TextStyle resolve(InlineHtmlLine line, InlineRun run) => line.style.merge(
      run.resolvedStyle(linkColor: linkColor, primaryColor: primaryColor),
    );

    // כמו הקורא: המסלול המהיר כשהשורה inline, ואחרת סגנון השורה של HtmlWidget.
    final line = InlineHtmlDocument.parseLine(source.source, base);
    if (line != null && _alignToReader(line, resolve)) return;
    final heading =
        line?.style ??
        SimpleInlineHtml.headingStyle(source.source, base) ??
        base;
    final supported = <String, String>{};
    _styles = List.filled(source.plain.length, heading);
    final tags = source.tags.iterator;
    var hasTag = tags.moveNext();
    final open = <({String name, String tag})>[];
    for (final node in source.nodes) {
      final rawStart = node.boundaries[0]!;
      while (hasTag && tags.current.end <= rawStart) {
        final tag = source.source.substring(
          tags.current.start,
          tags.current.end,
        );
        final match = _styleTag.firstMatch(tag);
        if (match != null && !tag.endsWith('/>')) {
          final name = match[2]!.toLowerCase();
          if (match[1] == '/') {
            final index = open.lastIndexWhere((e) => e.name == name);
            if (index >= 0) open.removeRange(index, open.length);
          } else {
            open.add((name: name, tag: tag));
          }
        }
        hasTag = tags.moveNext();
      }
      // התג המקורי, עם המאפיינים שלו, מפוענח בפרסר של הקורא.
      String placeholder(String Function(({String name, String tag})) tag) =>
          '${open.map(tag).join()}x'
          '${open.reversed.map((e) => '</${e.name}>').join()}';
      final parsed =
          InlineHtmlDocument.parseLine(placeholder((e) => e.tag), heading) ??
          InlineHtmlDocument.parseLine(
            placeholder(
              (e) => supported[e.tag] ??= _supportedTag(e.name, e.tag, heading),
            ),
            heading,
          );
      final style = parsed == null || parsed.isHeading
          ? heading
          : resolve(parsed, parsed.document.runs.first);
      _styles.fillRange(node.start, node.end, style);
    }
  }

  /// [tag] רק עם המאפיינים והצהרות ה-CSS שהפרסר של הקורא מקבל, כדי שמאפיין
  /// שאינו נתמך (כמו line-height) לא יבטל את מה שכן נתמך.
  static String _supportedTag(String name, String tag, TextStyle style) {
    bool accepted(String attribute) =>
        InlineHtmlDocument.parseLine('<$name $attribute>x</$name>', style) !=
        null;
    String attribute(String key, String value) =>
        '$key="${const HtmlEscape(HtmlEscapeMode.attribute).convert(value)}"';
    final element = html_parser.parseFragment('$tag</$name>').children.first;
    final kept = <String>[];
    element.attributes.forEach((key, value) {
      if (key is! String) return;
      if (key != 'style') {
        if (accepted(attribute(key, value))) kept.add(attribute(key, value));
        return;
      }
      final declarations = value
          .split(';')
          .where((d) => d.trim().isNotEmpty && accepted(attribute(key, d)));
      if (declarations.isNotEmpty) {
        kept.add(attribute(key, declarations.join(';')));
      }
    });
    return '<${[name, ...kept].join(' ')}>';
  }

  /// מצמיד כל תו גלוי לתו שהקורא מציג. הקורא מכווץ ומקצץ רווחים ומציג
  /// BR/NBSP אחרת, ולכן רק רווחים רשאים להיות בלי בן זוג.
  bool _alignToReader(
    InlineHtmlLine line,
    TextStyle Function(InlineHtmlLine line, InlineRun run) resolve,
  ) {
    final shown = line.document.plainText;
    final shownStyles = [
      for (final run in line.document.runs)
        ...List.filled(run.text.length, resolve(line, run)),
    ];
    final plain = source.plain;
    final aligned = List<TextStyle?>.filled(plain.length, null);
    var j = 0;
    for (var i = source.visibleStart; i < source.visibleEnd; i++) {
      final unit = plain.codeUnitAt(i);
      if (_isSpace(unit)) {
        if (j < shown.length && _isSpace(shown.codeUnitAt(j))) {
          aligned[i] = shownStyles[j++];
        }
        continue;
      }
      while (j < shown.length &&
          shown.codeUnitAt(j) != unit &&
          _isSpace(shown.codeUnitAt(j))) {
        j++;
      }
      if (j >= shown.length || shown.codeUnitAt(j) != unit) return false;
      aligned[i] = shownStyles[j++];
    }
    for (; j < shown.length; j++) {
      if (!_isSpace(shown.codeUnitAt(j))) return false;
    }
    _styles = List.filled(plain.length, line.style);
    TextStyle? previous;
    var i = source.visibleStart;
    while (i < source.visibleEnd) {
      final style = aligned[i];
      if (style != null) {
        _styles[i++] = previous = style;
        continue;
      }
      var next = i + 1;
      while (next < source.visibleEnd && aligned[next] == null) {
        next++;
      }
      // רווח שהקורא כיווץ יורש רק כשמשני צדיו אותו סגנון.
      if (previous != null &&
          next < source.visibleEnd &&
          aligned[next] == previous) {
        _styles.fillRange(i, next, previous);
      }
      i = next;
    }
    return true;
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 ||
      unit == 0xA0 ||
      unit == 0x09 ||
      unit == 0x0A ||
      unit == 0x0C ||
      unit == 0x0D;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    _styleSource(base, Theme.of(context).colorScheme);
    final cached = withComposing ? _composingSpan : _plainSpan;
    if (cached != null) return cached;
    final spans = <TextSpan>[];
    final composing = value.composing;
    TextStyle at(int index) {
      final origin = _origins[index];
      return origin < _styles.length ? _styles[origin] : base;
    }

    void add(int start, int end, TextStyle style) {
      if (start < end) {
        spans.add(TextSpan(text: text.substring(start, end), style: style));
      }
    }

    var start = 0;
    while (start < text.length) {
      final current = at(start);
      var end = start + 1;
      while (end < text.length && at(end) == current) {
        end++;
      }
      final composingStart = composing.start.clamp(start, end);
      final composingEnd = composing.end.clamp(start, end);
      if (withComposing &&
          value.isComposingRangeValid &&
          composingStart < composingEnd) {
        add(start, composingStart, current);
        add(
          composingStart,
          composingEnd,
          current.copyWith(
            decoration: TextDecoration.combine([
              if (current.decoration != null) current.decoration!,
              TextDecoration.underline,
            ]),
          ),
        );
        add(composingEnd, end, current);
      } else {
        add(start, end, current);
      }
      start = end;
    }
    final result = TextSpan(style: base, children: spans);
    if (withComposing) {
      _composingSpan = result;
    } else {
      _plainSpan = result;
    }
    return result;
  }
}
