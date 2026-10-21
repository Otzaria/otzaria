import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

/// בקר ששומר את סגנון המקור של התווים גם במהלך עריכה רגילה ו-IME.
class PluginCorrectionController extends TextEditingController {
  late PluginCorrectionText source;
  List<int> _origins = [];
  String? _styledSource;
  TextStyle? _baseStyle;
  List<TextStyle> _styles = [];

  PluginCorrectionController(String raw) {
    setSource(raw);
  }

  void setSource(String raw) {
    if (_styledSource == raw) return;
    source = PluginCorrectionText(raw);
    _styledSource = raw;
    _baseStyle = null;
    final visible = source.plain.substring(
      source.visibleStart,
      source.visibleEnd,
    );
    super.value = TextEditingValue(text: visible);
    _origins = List.generate(
      visible.length,
      (index) => source.visibleStart + index,
    );
  }

  String forEditor(String canonical) {
    final prefix = source.plain.substring(0, source.visibleStart);
    final suffix = source.plain.substring(source.visibleEnd);
    if (!canonical.startsWith(prefix) ||
        !canonical.endsWith(suffix) ||
        canonical.length < prefix.length + suffix.length) {
      return canonical;
    }
    return canonical.substring(prefix.length, canonical.length - suffix.length);
  }

  String forService(String visible) =>
      source.plain.substring(0, source.visibleStart) +
      visible +
      source.plain.substring(source.visibleEnd);

  @override
  set value(TextEditingValue next) {
    final previous = text;
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
      final origin = _origins.isEmpty
          ? source.visibleStart
          : _origins[prefix.clamp(0, _origins.length - 1)];
      _origins = [
        ..._origins.take(prefix),
        ...List.filled(next.text.length - prefix - suffix, origin),
        ..._origins.skip(previous.length - suffix),
      ];
    }
    super.value = next;
  }

  void _styleSource(TextStyle base) {
    if (_baseStyle == base) return;
    _baseStyle = base;
    final heading = SimpleInlineHtml.headingStyle(source.source, base) ?? base;
    _styles = List.filled(source.plain.length, heading);
    final tags = RegExp(r'<[^>]*>').allMatches(source.source).iterator;
    var hasTag = tags.moveNext();
    final open = <String>[];
    for (final node in source.nodes) {
      final rawStart = node.boundaries[0]!;
      while (hasTag && tags.current.end <= rawStart) {
        final tag = tags.current[0]!;
        final match = RegExp(
          r'^<(/?)(b|strong|i|em|u|big|small)\s*>$',
          caseSensitive: false,
        ).firstMatch(tag);
        if (match != null) {
          final name = match[2]!.toLowerCase();
          if (match[1] == '/') {
            final index = open.lastIndexOf(name);
            if (index >= 0) open.removeRange(index, open.length);
          } else {
            open.add(name);
          }
        }
        hasTag = tags.moveNext();
      }
      final html =
          '${open.map((tag) => '<$tag>').join()}x'
          '${open.reversed.map((tag) => '</$tag>').join()}';
      final parsed = SimpleInlineHtml.tryParse(html, heading);
      TextStyle styleOf(TextSpan span, TextStyle inherited) {
        final style = inherited.merge(span.style);
        if (span.text?.isNotEmpty ?? false) return style;
        final children = span.children;
        return children == null || children.isEmpty
            ? style
            : styleOf(children.first as TextSpan, style);
      }

      final style = parsed == null ? heading : styleOf(parsed, heading);
      _styles.fillRange(node.start, node.end, style);
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    _styleSource(base);
    final spans = <TextSpan>[];
    final composing = value.composing;
    TextStyle at(int index) {
      final origin = _origins[index];
      var result = origin < _styles.length ? _styles[origin] : base;
      if (withComposing &&
          composing.isValid &&
          index >= composing.start &&
          index < composing.end) {
        result = result.copyWith(
          decoration: TextDecoration.combine([
            if (result.decoration != null) result.decoration!,
            TextDecoration.underline,
          ]),
        );
      }
      return result;
    }

    var start = 0;
    while (start < text.length) {
      final current = at(start);
      var end = start + 1;
      while (end < text.length && at(end) == current) {
        end++;
      }
      spans.add(TextSpan(text: text.substring(start, end), style: current));
      start = end;
    }
    return TextSpan(style: base, children: spans);
  }
}
